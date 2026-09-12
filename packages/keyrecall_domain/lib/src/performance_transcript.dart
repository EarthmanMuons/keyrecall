import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'spelled_pitch.dart';

/// One note somebody played.
///
/// An observation and nothing else: which key, when it arrived, and how it is
/// written. No expected position, no beat, and no verdict, since all three
/// relate the performance to the exercise.
@immutable
class PlayedNote {
  /// Where it fell in the order things were played, from zero.
  final int sequence;

  /// The note as it is written.
  final SpelledPitch pitch;

  /// When the note arrived, on the input stream's clock.
  ///
  /// Kept, not interpreted: nothing here turns it into a beat, an onset error,
  /// or a tempo.
  final int timestampMs;

  PlayedNote({
    required this.sequence,
    required this.pitch,
    required this.timestampMs,
  }) {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'must not be negative');
    }
    if (timestampMs < 0) {
      throw ArgumentError.value(
        timestampMs,
        'timestampMs',
        'must not be negative',
      );
    }
  }

  /// Which key it was.
  int get midiNote => pitch.midiNote;

  @override
  bool operator ==(Object other) =>
      other is PlayedNote &&
      other.sequence == sequence &&
      other.pitch == pitch &&
      other.timestampMs == timestampMs;

  @override
  int get hashCode => Object.hash(sequence, pitch, timestampMs);

  @override
  String toString() => 'PlayedNote($sequence, $pitch, ${timestampMs}ms)';
}

const _playedNoteEquality = ListEquality<PlayedNote>();

/// What was played, in the order it was played.
///
/// Append-only: every note that arrives goes on the end, including repeats,
/// stumbles, and notes nobody asked for. Nothing is dropped, moved to where it
/// was expected, or marked.
///
/// Those omissions make it safe to show during an unguided attempt, since
/// placing an observation into an expected position would tell the learner
/// their note was right. They also keep a repaired error distinguishable from a
/// first-pass one for every later reading.
@immutable
class PerformanceTranscript {
  /// The notes, in arrival order.
  final List<PlayedNote> notes;

  PerformanceTranscript(List<PlayedNote> notes)
    : notes = List.unmodifiable(notes) {
    for (final (index, note) in this.notes.indexed) {
      if (note.sequence != index) {
        throw ArgumentError.value(
          notes,
          'notes',
          'sequence must be contiguous from zero',
        );
      }
      if (index > 0 && note.timestampMs < this.notes[index - 1].timestampMs) {
        throw ArgumentError.value(
          notes,
          'notes',
          'timestamps must be in arrival order',
        );
      }
    }
  }

  /// Nothing played yet.
  static final PerformanceTranscript empty = PerformanceTranscript(const []);

  /// This transcript with one more note on the end.
  PerformanceTranscript appending({
    required SpelledPitch pitch,
    required int timestampMs,
  }) => PerformanceTranscript([
    ...notes,
    PlayedNote(sequence: notes.length, pitch: pitch, timestampMs: timestampMs),
  ]);

  /// How many notes were played.
  int get length => notes.length;

  /// Whether nothing has been played.
  bool get isEmpty => notes.isEmpty;

  /// Whether anything has been played.
  bool get isNotEmpty => notes.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is PerformanceTranscript &&
      _playedNoteEquality.equals(other.notes, notes);

  @override
  int get hashCode => _playedNoteEquality.hash(notes);

  @override
  String toString() => 'PerformanceTranscript(${notes.length} notes)';
}
