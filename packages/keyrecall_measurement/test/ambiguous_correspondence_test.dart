import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// What timing can and cannot change about a two-hand reading.
///
/// Correspondence is settled before any channel is read, and where the pitches
/// alone leave two readings equally good, grouping settles it with a bounded
/// contribution from timing. The channels then follow the correspondence that
/// was chosen, which is the one way timing reaches a pitch-derived reading.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  /// Two moments whose right hand and left hand ask for the same pitch.
  ///
  /// A lone arrival of that pitch belongs to either one, and the notes say
  /// nothing about which.
  final realization = ExerciseRealization([
    for (final (position, (left, right)) in const [(48, 60), (60, 72)].indexed)
      RealizationMoment(
        position: position,
        metricOffset: position.toDouble(),
        notes: [
          RealizedNote(hand: Hand.left, pitch: pitch(left)),
          RealizedNote(hand: Hand.right, pitch: pitch(right)),
        ],
      ),
  ]);

  /// The same three pitches, with the shared one arriving at [middleMs].
  PerformanceMeasurement playedWithMiddleAt(int middleMs) {
    var transcript = PerformanceTranscript.empty;
    for (final (midiNote, at) in [(48, 0), (60, middleMs), (72, 1000)]) {
      transcript = transcript.appending(
        pitch: pitch(midiNote),
        timestampMs: at,
      );
    }
    return measure(realization: realization, transcript: transcript);
  }

  test('timing settles a correspondence the pitches leave open', () {
    final early = playedWithMiddleAt(100);
    final late = playedWithMiddleAt(900);

    expect(
      early.handAsynchronies.single.position,
      0,
      reason: 'arriving beside the first note, it played the first moment',
    );
    expect(
      late.handAsynchronies.single.position,
      1,
      reason: 'arriving beside the last note, it played the second',
    );
  });

  test('and the channels read the correspondence it settled on', () {
    final early = playedWithMiddleAt(100);
    final late = playedWithMiddleAt(940);

    expect(early.widestAsynchronyAtPosition, 0);
    expect(late.widestAsynchronyAtPosition, 1);
    expect(
      late.coordination,
      greaterThan(early.coordination!),
      reason: 'it landed nearer the note it was read against',
    );
  });

  test('unambiguous pitches correspond the same way however they sat', () {
    final realization = ExerciseRealization([
      for (final (position, (left, right)) in const [
        (48, 60),
        (50, 62),
        (52, 64),
      ].indexed)
        RealizationMoment(
          position: position,
          metricOffset: position.toDouble(),
          notes: [
            RealizedNote(hand: Hand.left, pitch: pitch(left)),
            RealizedNote(hand: Hand.right, pitch: pitch(right)),
          ],
        ),
    ]);
    PerformanceMeasurement played(int secondRightAt) {
      var transcript = PerformanceTranscript.empty;
      for (final (midiNote, at) in [
        (48, 0),
        (60, 10),
        (50, 1000),
        (62, secondRightAt),
        (52, 2000),
        (64, 2010),
      ]) {
        transcript = transcript.appending(
          pitch: pitch(midiNote),
          timestampMs: at,
        );
      }
      return measure(realization: realization, transcript: transcript);
    }

    final together = played(1010);
    final apart = played(1800);

    expect(apart.alignment.noteEdits, together.alignment.noteEdits);
    expect(apart.degreesCorrect, together.degreesCorrect);
    expect(apart.soundedCorrectly, together.soundedCorrectly);
    expect(
      apart.coordination,
      lessThan(together.coordination!),
      reason: 'the hands were further apart, which is what coordination reads',
    );
  });
}
