import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// How a two-hand performance sits in time.
///
/// The hands of one moment do not arrive together, and that spread is
/// coordination rather than tempo. Timing reads moments, so it never sees it.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  /// An octave of a C major scale, both hands an octave apart.
  ///
  /// Long enough to establish a timing baseline, since the claims below are
  /// about what the timing scores read.
  final realization = ExerciseRealization([
    for (final (position, (left, right)) in const [
      (48, 60),
      (50, 62),
      (52, 64),
      (53, 65),
      (55, 67),
      (57, 69),
      (59, 71),
      (60, 72),
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

  PerformanceTranscript played(List<(int, int)> arrivals) {
    var transcript = PerformanceTranscript.empty;
    for (final (midiNote, timestampMs) in arrivals) {
      transcript = transcript.appending(
        pitch: pitch(midiNote),
        timestampMs: timestampMs,
      );
    }
    return transcript;
  }

  /// The scale played on the beat, with the hands [spreadMs] apart.
  PerformanceMeasurement measuredWithSpread(int spreadMs) {
    var at = 1000;
    final arrivals = <(int, int)>[];
    for (final moment in realization.moments) {
      arrivals.add((moment.noteFor(Hand.left)!.midiNote, at));
      arrivals.add((moment.noteFor(Hand.right)!.midiNote, at + spreadMs));
      at += 500;
    }
    return measure(realization: realization, transcript: played(arrivals));
  }

  test('the gap between the hands is not an interval', () {
    final measurement = measuredWithSpread(40);

    expect(measurement.medianIntervalMs, 500);
    expect(measurement.temporalStability, 1.0);
    expect(measurement.continuity, 1.0);
  });

  test('a wider spread does not read as a less steady tempo', () {
    expect(
      measuredWithSpread(120).temporalStability,
      measuredWithSpread(0).temporalStability,
    );
    expect(
      measuredWithSpread(120).medianIntervalMs,
      measuredWithSpread(0).medianIntervalMs,
    );
  });

  test('what is counted, and against what', () {
    final measurement = measuredWithSpread(20);

    expect(measurement.expectedNotes, 16);
    expect(measurement.expectedMoments, 8);
    expect(measurement.correspondedTwoHandMoments, 8);
    expect(measurement.materialAppeared, 1.0);
  });

  test('a moment only one hand played is not evidence about coordination', () {
    final measurement = measure(
      realization: realization,
      transcript: played([
        (48, 1000),
        (60, 1020),
        (50, 1500),
        (52, 2000),
        (64, 2020),
        (53, 2500),
        (65, 2520),
        (55, 3000),
        (67, 3020),
        (57, 3500),
        (69, 3520),
        (59, 4000),
        (71, 4020),
        (60, 4500),
        (72, 4520),
      ]),
    );

    expect(measurement.correspondedTwoHandMoments, 7);
    expect(measurement.expectedMoments, 8);
    expect(
      measurement.materialProduced,
      15,
      reason:
          'the note that never arrived is missing material, and the '
          'moment it belonged to still happened',
    );
    expect(measurement.medianIntervalMs, 500);
  });
}
