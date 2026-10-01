import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// Waits too short to be playing are the clock's resolution, and every
/// channel read from the pace says so together.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  final exercise = Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    tempoBpm: 120,
  );
  final realization = realize(exercise);
  final floorMs = MeasurementPolicy.standard.minimumTimedIntervalMs;

  /// The exercise played correctly, the instrument stamping the moments
  /// [gapsUs] apart, one wait after another.
  PerformanceMeasurement stampedApart(List<int> gapsUs) {
    var transcript = PerformanceTranscript.empty;
    var at = 1000000;
    for (final (index, moment) in realization.moments.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(
          moment.notes.single.midiNote,
          material: material,
        ),
        timestampMs: 1000 + 500 * index,
        performanceTimeUs: at,
      );
      if (index < gapsUs.length) at += gapsUs[index];
    }
    return measure(realization: realization, transcript: transcript);
  }

  List<int> steady(int gapUs) => [
    for (var i = 1; i < realization.moments.length; i++) gapUs,
  ];

  test('just below the floor, nothing is read from the pace', () {
    final measurement = stampedApart(steady((floorMs * 1000).round() - 1));
    final outcome = outcomeFor(measurement: measurement, exercise: exercise);

    expect(measurement.timing.gaps, hasLength(realization.moments.length - 1));
    expect(measurement.timing.paceMs, isNull);
    expect(measurement.dispersion, isNull);
    expect(measurement.worstIntervalRatio, isNull);
    expect(outcome.continuity, isNull);
    expect(outcome.temporalStability, isNull);
    expect(outcome.measuredTempoRatio, isNull);
  });

  for (final (name, gapUs) in [
    ('exactly at', (floorMs * 1000).round()),
    ('just above', (floorMs * 1000).round() + 1),
  ]) {
    test('$name the floor, the pace is read', () {
      final measurement = stampedApart(steady(gapUs));
      final outcome = outcomeFor(measurement: measurement, exercise: exercise);

      expect(measurement.timing.paceMs, gapUs / 1000);
      expect(outcome.continuity, 1);
      expect(outcome.temporalStability, 1);
      expect(outcome.measuredTempoRatio, isNotNull);
    });
  }

  test('one pair stamped together among ordinary waits leaves the rest', () {
    final gaps = steady(500000)..[3] = 100;
    final measurement = stampedApart(gaps);

    expect(measurement.timing.paceMs, 500);
    expect(measurement.continuity, isNotNull);
    expect(measurement.temporalStability, isNotNull);
  });
}
