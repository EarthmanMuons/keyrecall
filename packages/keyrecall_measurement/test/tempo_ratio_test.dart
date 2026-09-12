import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// What the achieved tempo ratio is a ratio of.
///
/// The requested beat over the median wait between the learner's own notes, so
/// it says how fast they played and nothing about when they started.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  const requestedBpm = 104.0;

  Exercise exerciseFor(ExerciseDirection direction) => Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: direction,
    tempoBpm: requestedBpm,
  );

  /// The exercise played correctly, every wait [gapMs] long, starting [startMs]
  /// in.
  PerformanceMeasurement playedAt({
    required Exercise exercise,
    required double gapMs,
    double startMs = 0,
  }) {
    final realization = realize(exercise);
    var transcript = PerformanceTranscript.empty;
    for (final (index, moment) in realization.moments.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(
          moment.notes.single.midiNote,
          material: material,
        ),
        timestampMs: (startMs + index * gapMs).round(),
      );
    }
    return measure(realization: realization, transcript: transcript);
  }

  final onTheBeatMs = 60000 / requestedBpm;

  for (final direction in ExerciseDirection.values) {
    final exercise = exerciseFor(direction);

    test('${direction.id}: playing on the beat reads as the tempo asked', () {
      final measurement = playedAt(exercise: exercise, gapMs: onTheBeatMs);

      expect(measurement.medianIntervalMs, onTheBeatMs.round());
      expect(
        measurement.achievedTempoRatioFor(exercise.conditions),
        closeTo(1.0, 0.01),
        reason: 'rounding each arrival to the millisecond is the only error',
      );
    });

    test('${direction.id}: starting late costs nothing', () {
      expect(
        playedAt(
          exercise: exercise,
          gapMs: onTheBeatMs,
          startMs: 5000,
        ).achievedTempoRatioFor(exercise.conditions),
        playedAt(
          exercise: exercise,
          gapMs: onTheBeatMs,
        ).achievedTempoRatioFor(exercise.conditions),
      );
    });
  }

  final exercise = exerciseFor(ExerciseDirection.up);

  test('playing twice as slowly halves the ratio', () {
    expect(
      playedAt(
        exercise: exercise,
        gapMs: 2 * onTheBeatMs,
      ).achievedTempoRatioFor(exercise.conditions),
      closeTo(0.5, 0.01),
    );
  });

  test('playing faster than asked overshoots it', () {
    expect(
      playedAt(
        exercise: exercise,
        gapMs: onTheBeatMs / 2,
      ).achievedTempoRatioFor(exercise.conditions),
      closeTo(2.0, 0.01),
    );
  });

  test('a performance with no waits established no pace', () {
    final realization = realize(exercise);
    final measurement = measure(
      realization: realization,
      transcript: PerformanceTranscript.empty,
    );

    expect(measurement.medianIntervalMs, isNull);
    expect(measurement.achievedTempoRatioFor(exercise.conditions), 0);
  });
}
