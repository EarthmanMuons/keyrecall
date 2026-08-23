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
/// The vocabulary every input source reduces to, whatever it is underneath: a
/// MIDI instrument, a synthetic source for demos and tests, or anything added
/// later. Normalizing here is what keeps the rest of the app from reasoning
/// about transports.
///
/// The stream is already cleaned up by the time it reaches this form. A
/// repeated note-on for a key that is already held is not an event, because
/// nothing changed; a note-on after the pedal released a note is, because a
/// reattack is real playing. Timestamps come from a monotonic clock rather than
/// a wall clock, so a clock correction mid-performance cannot reorder what was
/// played.
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
/// swap, a disconnect, an all-notes-off, or a repair of state that drifted.
///
/// It carries a snapshot because a consumer that tracked notes across the
/// boundary would otherwise be left believing keys are held that nobody is
/// holding. For anything measuring a performance, a reset mid-attempt is also
/// the signal that the observation is incomplete: what follows cannot be
/// compared against what came before as though it were continuous.
final class InputTemporalResetEvent extends InputTemporalEvent {
  /// What was sounding at the boundary.
  final InputTemporalSnapshot snapshot;

  InputTemporalResetEvent({required super.timestampMs, required this.snapshot});

  @override
  String toString() => 'Reset($snapshot, at: ${timestampMs}ms)';
}
