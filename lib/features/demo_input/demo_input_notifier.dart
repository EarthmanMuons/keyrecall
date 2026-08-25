import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cancelable_timer_sequence.dart';

/// What the synthetic instrument is doing right now.
///
/// Pressed and sustained are kept apart for the same reason a real instrument
/// distinguishes them: releasing a key with the pedal down ends the hold but
/// not the sound. Collapsing the two into "what is sounding" would make an
/// ordinary release look like a note vanishing, which is not a transition any
/// keyboard can produce.
@immutable
class DemoInputState {
  /// Notes whose keys are held down.
  final Set<int> pressedNoteNumbers;

  /// Notes released but still ringing under the pedal.
  final Set<int> sustainedNoteNumbers;

  /// Whether the sustain pedal is down.
  final bool isPedalDown;

  const DemoInputState({
    this.pressedNoteNumbers = const {},
    this.sustainedNoteNumbers = const {},
    this.isPedalDown = false,
  });

  /// Nothing sounding, pedal up.
  static const DemoInputState silent = DemoInputState();

  /// Every note currently making sound, however it is being held.
  Set<int> get soundingNoteNumbers => {
    ...pressedNoteNumbers,
    ...sustainedNoteNumbers,
  };

  /// Whether nothing is sounding.
  bool get isSilent =>
      pressedNoteNumbers.isEmpty && sustainedNoteNumbers.isEmpty;
}

/// How quickly a played sequence unfolds.
@immutable
class DemoInputTempo {
  /// Gap between lifting the hands and the first note of a sequence.
  final Duration releaseGap;

  /// Gap between consecutive notes.
  final Duration noteSpacing;

  const DemoInputTempo({
    this.releaseGap = const Duration(milliseconds: 50),
    this.noteSpacing = const Duration(milliseconds: 200),
  });

  /// Fast enough to watch, slow enough to see.
  static const DemoInputTempo normal = DemoInputTempo();

  /// Quick, for tests and for driving many attempts without waiting.
  static const DemoInputTempo brisk = DemoInputTempo(
    releaseGap: Duration(milliseconds: 5),
    noteSpacing: Duration(milliseconds: 10),
  );
}

/// The synthetic instrument's current state.
final demoInputProvider = NotifierProvider<DemoInputNotifier, DemoInputState>(
  DemoInputNotifier.new,
);

/// An instrument nobody has to be holding.
///
/// It plays whatever it is told to play and knows nothing about scales,
/// exercises, or whether what it played was correct; deciding those is the
/// practice loop's job, and a synthetic instrument that knew them would be
/// simulating the answer rather than the playing.
///
/// The point is that the rest of the app cannot tell the difference between
/// this and a real keyboard: both reduce to the same normalized event stream,
/// through the same transitions. That is what makes the whole practice loop
/// runnable with nothing plugged in, and it only holds if the transitions are
/// ones a keyboard could actually produce.
///
/// Adapted from WhatChord's demo input source, which drove an authored product
/// tour. The sequencing and timing carry over; what gets played does not.
class DemoInputNotifier extends Notifier<DemoInputState> {
  final CancelableTimerSequence _sequence = CancelableTimerSequence();

  Set<int> _pressed = const <int>{};
  Set<int> _sustained = const <int>{};
  bool _pedalDown = false;

  @override
  DemoInputState build() {
    ref.onDispose(_sequence.dispose);
    return DemoInputState.silent;
  }

  /// Plays [noteNumbers] one at a time, in the order given.
  ///
  /// The order is the caller's and is never normalized: what arrives on the
  /// stream is evidence about a performance, so an instrument that tidied a
  /// descending scale into an ascending one would be inventing one. A note
  /// repeated back to back is struck twice, with the key coming up in between,
  /// the way a real re-attack sounds.
  ///
  /// Each note is released as the next one is struck, the way a scale is
  /// played rather than a chord accumulated. The last note stays held until
  /// something else plays or [releaseAll] lifts the hands.
  ///
  /// Anything still held is released first, so a sequence starts from a clean
  /// hand position. With the pedal down those notes keep ringing, exactly as
  /// they would on a real instrument. Playing again interrupts whatever was in
  /// progress rather than overlapping with it.
  ///
  /// Throws [RangeError] for a note outside the keyboard, which the normalized
  /// stream would refuse anyway.
  void playSequence(
    Iterable<int> noteNumbers, {
    DemoInputTempo tempo = DemoInputTempo.normal,
  }) {
    final notes = noteNumbers.toList();
    for (final note in notes) {
      if (note < 0 || note > 127) {
        throw RangeError.range(note, 0, 127, 'noteNumbers');
      }
    }

    final generation = _sequence.restart();
    _liftHands();
    if (notes.isEmpty) return;

    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      _sequence.schedule(
        tempo.releaseGap + tempo.noteSpacing * index,
        (_) => _strike(note),
        generation: generation,
      );
    }
  }

  /// Strikes [noteNumbers] together, as a chord.
  ///
  /// The order notes within one instant reach the stream is deliberately
  /// unspecified: they happened at the same time, and nothing downstream may
  /// read meaning into their sequence. Use [playSequence] when the order is
  /// the point.
  ///
  /// Throws [RangeError] for a note outside the keyboard.
  void playChord(Set<int> noteNumbers) {
    for (final note in noteNumbers) {
      if (note < 0 || note > 127) {
        throw RangeError.range(note, 0, 127, 'noteNumbers');
      }
    }

    _sequence.restart();
    _liftHands();
    if (noteNumbers.isEmpty) return;

    _sustained = Set.unmodifiable(
      _sustained.where((note) => !noteNumbers.contains(note)),
    );
    _pressed = Set.unmodifiable(noteNumbers);
    _commit();
  }

  /// Plays [noteNumbers] in order and completes once the last one has sounded.
  ///
  /// For a caller that wants to wait for a performance rather than watch for
  /// it, which is most tests.
  Future<void> playSequenceAndSettle(
    Iterable<int> noteNumbers, {
    DemoInputTempo tempo = DemoInputTempo.normal,
  }) async {
    final notes = noteNumbers.toList();
    playSequence(notes, tempo: tempo);
    if (notes.isEmpty) return;
    await Future<void>.delayed(
      tempo.releaseGap + tempo.noteSpacing * notes.length,
    );
  }

  /// Presses or releases the sustain pedal.
  ///
  /// Lifting it damps everything the pedal was holding. That produces no
  /// note-offs, because the keys were already released; the pedal event is the
  /// whole story, which is what a real instrument reports too.
  void setPedalDown(bool down) {
    if (down == _pedalDown) return;
    _pedalDown = down;
    if (!down) _sustained = const <int>{};
    _commit();
  }

  /// Lifts the hands and abandons any sequence in progress.
  ///
  /// Notes caught by the pedal keep ringing until it comes up, which is the
  /// physical truth and the reason this is not called "silence".
  void releaseAll() {
    _sequence.cancel();
    _liftHands();
  }

  /// Strikes [note], releasing whatever was held.
  void _strike(int note) {
    if (_pressed.contains(note)) {
      // A re-attack: the key comes up before it goes down again, so the same
      // note twice reaches the stream as two notes rather than one held one.
      _pressed = Set.unmodifiable(_pressed.difference({note}));
      _commit();
    }

    final released = _pressed.difference({note});
    _pressed = Set.unmodifiable({note});
    _sustained = Set.unmodifiable(
      {if (_pedalDown) ..._sustained, if (_pedalDown) ...released}
        ..remove(note),
    );
    _commit();
  }

  /// Releases every held key, sustaining what the pedal catches.
  void _liftHands() {
    _sustained = Set.unmodifiable({..._sustained, if (_pedalDown) ..._pressed});
    _pressed = const <int>{};
    _commit();
  }

  void _commit() {
    state = DemoInputState(
      pressedNoteNumbers: _pressed,
      sustainedNoteNumbers: _sustained,
      isPedalDown: _pedalDown,
    );
  }
}
