import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

void main() {
  test('ratio', () {
    final material = TechnicalMaterial('C', ScaleForm.major);
    for (final direction in ExerciseDirection.values) {
      final exercise = Exercise.linear(
        material: material,
        hands: HandConfiguration.right,
        octaves: 1,
        direction: direction,
        tempoBpm: 104,
      );
      final realization = realize(exercise);
      final notes = [
        for (final m in realization.moments) m.notes.single.midiNote,
      ];
      // Played exactly on the requested beat.
      var transcript = PerformanceTranscript.empty;
      for (final (i, n) in notes.indexed) {
        transcript = transcript.appending(
          pitch: spellObservedPitch(n, material: material),
          timestampMs: (i * 60000 / 104).round(),
        );
      }
      final m = measure(realization: realization, transcript: transcript);
      print(
        '--- ${direction.id}: notes=${notes.length} '
        'median=${m.medianIntervalMs} '
        'ratio=${m.achievedTempoRatioFor(exercise.conditions).toStringAsFixed(3)}',
      );
    }
  });
}
