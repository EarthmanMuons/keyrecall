import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

void main() {
  test('realization keys partition the catalog exactly as exercises did', () {
    final candidates = generateCandidates(InstrumentProfile(), v1ScaleCatalog);

    final byKey = <RealizationKey, List<int>>{};
    final byExercise = <Exercise, List<int>>{};
    for (final (index, exercise) in candidates.indexed) {
      byKey.putIfAbsent(realizationKeyOf(exercise), () => []).add(index);
      byExercise
          .putIfAbsent(
            exercise.withGuidance(GuidanceContext.unguided),
            () => [],
          )
          .add(index);
    }

    expect(byKey.values.toSet(), byExercise.values.toSet());
  });

  test('the key separates every generated realization axis', () {
    final material = v1ScaleCatalog.first;
    final exercise = Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
    );

    expect(
      realizationKeyOf(exercise),
      realizationKeyOf(exercise.withGuidance(GuidanceContext.continuouslyCued)),
    );
    expect(
      realizationKeyOf(exercise),
      isNot(realizationKeyOf(exercise.atTempo(80))),
    );
    expect(
      realizationKeyOf(exercise),
      isNot(
        realizationKeyOf(
          Exercise.linear(
            material: material,
            hands: HandConfiguration.left,
            octaves: 1,
            direction: ExerciseDirection.up,
            tempoBpm: 60,
          ),
        ),
      ),
    );
    expect(
      realizationKeyOf(exercise),
      isNot(
        realizationKeyOf(
          Exercise.linear(
            material: v1ScaleCatalog[1],
            hands: HandConfiguration.right,
            octaves: 1,
            direction: ExerciseDirection.up,
            tempoBpm: 60,
          ),
        ),
      ),
    );
  });
}
