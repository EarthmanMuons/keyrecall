import 'package:meta/meta.dart';

const int _maximumExactJsonInteger = 9007199254740991;

void _requireNote(int note, String name) {
  if (note < 0 || note > 127) {
    throw RangeError.range(note, 0, 127, name);
  }
}

void _requireNotes(Iterable<int> notes, String name) {
  for (final note in notes) {
    _requireNote(note, name);
  }
}

/// Exactly what is sounding at a boundary in the input stream.
///
/// Pressed and sustained are disjoint: a key is either held down or being held
/// by the pedal, never both. Sustained notes require the pedal to be down,
/// because nothing else can be holding them.
@immutable
class InputTemporalSnapshot {
  /// Notes whose keys are physically held.
  final Set<int> pressedNoteNumbers;

  /// Notes released but still sounding under the pedal.
  final Set<int> sustainedNoteNumbers;

  /// Whether the sustain pedal is down.
  final bool pedalDown;

  /// Throws [ArgumentError] or [RangeError] for a state an instrument cannot
  /// be in.
  InputTemporalSnapshot({
    Iterable<int> pressedNoteNumbers = const [],
    Iterable<int> sustainedNoteNumbers = const [],
    required this.pedalDown,
  }) : pressedNoteNumbers = Set.unmodifiable(pressedNoteNumbers),
       sustainedNoteNumbers = Set.unmodifiable(sustainedNoteNumbers) {
    _requireNotes(this.pressedNoteNumbers, 'pressedNoteNumbers');
    _requireNotes(this.sustainedNoteNumbers, 'sustainedNoteNumbers');

    final overlap = this.pressedNoteNumbers.intersection(
      this.sustainedNoteNumbers,
    );
    if (overlap.isNotEmpty) {
      throw ArgumentError.value(
        overlap,
        'pressedNoteNumbers/sustainedNoteNumbers',
        'a note cannot be both held and sustained',
      );
    }
    if (this.sustainedNoteNumbers.isNotEmpty && !pedalDown) {
      throw ArgumentError.value(
        this.sustainedNoteNumbers,
        'sustainedNoteNumbers',
        'nothing is holding these notes with the pedal up',
      );
    }
  }

  /// Nothing sounding, pedal up.
  static final InputTemporalSnapshot silent = InputTemporalSnapshot(
    pedalDown: false,
  );

  /// Every note currently sounding, however it is being held.
  Set<int> get soundingNoteNumbers => {
    ...pressedNoteNumbers,
    ...sustainedNoteNumbers,
  };

  /// Whether nothing is sounding.
  bool get isSilent =>
      pressedNoteNumbers.isEmpty && sustainedNoteNumbers.isEmpty;

  @override
  String toString() =>
      'InputTemporalSnapshot(pressed: $pressedNoteNumbers, '
      'sustained: $sustainedNoteNumbers, pedal: $pedalDown)';
}

/// One normalized, monotonically timestamped observation of live playing.
///
/// The stream is already cleaned up by the time it reaches this form: a
/// repeated note-on for a held key is not an event, while a note-on after the
/// pedal released a note is.
@immutable
sealed class InputTemporalEvent {
  /// Milliseconds since the input clock started.
  final int timestampMs;

  /// Throws [RangeError] for a timestamp that cannot be represented exactly.
  InputTemporalEvent({required this.timestampMs}) {
    if (timestampMs < 0 || timestampMs > _maximumExactJsonInteger) {
      throw RangeError.range(
        timestampMs,
        0,
        _maximumExactJsonInteger,
        'timestampMs',
      );
    }
  }
}

/// A key was struck.
final class InputTemporalNoteOnEvent extends InputTemporalEvent {
  /// Which note, as a MIDI note number.
  final int noteNumber;

  /// How hard it was struck, from 1 to 127.
  ///
  /// Zero is not a note-on: instruments express a release that way, and the
  /// normalization has already turned those into note-offs.
  final int velocity;

  InputTemporalNoteOnEvent({
    required super.timestampMs,
    required this.noteNumber,
    required this.velocity,
  }) {
    _requireNote(noteNumber, 'noteNumber');
    if (velocity < 1 || velocity > 127) {
      throw RangeError.range(velocity, 1, 127, 'velocity');
    }
  }

  @override
  String toString() =>
      'NoteOn($noteNumber, velocity: $velocity, at: ${timestampMs}ms)';
}

/// A key was released.
///
/// The note may still be sounding if the pedal is down. What ends is the
/// physical hold, not necessarily the sound.
final class InputTemporalNoteOffEvent extends InputTemporalEvent {
  /// Which note, as a MIDI note number.
  final int noteNumber;

  /// How fast it was released, from 0 to 127. Most instruments report zero.
  final int velocity;

  InputTemporalNoteOffEvent({
    required super.timestampMs,
    required this.noteNumber,
    required this.velocity,
  }) {
    _requireNote(noteNumber, 'noteNumber');
    if (velocity < 0 || velocity > 127) {
      throw RangeError.range(velocity, 0, 127, 'velocity');
    }
  }

  @override
  String toString() =>
      'NoteOff($noteNumber, velocity: $velocity, at: ${timestampMs}ms)';
}

/// The sustain pedal moved.
final class InputTemporalPedalEvent extends InputTemporalEvent {
  /// Whether the pedal is now down.
  final bool down;

  InputTemporalPedalEvent({required super.timestampMs, required this.down});

  @override
  String toString() => 'Pedal(${down ? 'down' : 'up'}, at: ${timestampMs}ms)';
}

/// The stream restarted, and this is what was sounding when it did.
///
/// An administrative boundary rather than something anybody played: a source
/// swap, a disconnect, an all-notes-off, or a repair of drifted state. The
/// snapshot lets a consumer resynchronize what it believes is held, and a reset
/// mid-attempt marks that observation as incomplete.
final class InputTemporalResetEvent extends InputTemporalEvent {
  /// What was sounding at the boundary.
  final InputTemporalSnapshot snapshot;

  InputTemporalResetEvent({required super.timestampMs, required this.snapshot});

  @override
  String toString() => 'Reset($snapshot, at: ${timestampMs}ms)';
}
