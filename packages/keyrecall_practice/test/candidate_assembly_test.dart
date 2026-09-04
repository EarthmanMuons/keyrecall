import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

void main() {
  test('material-keyed assembly matches exercise-keyed deduplication', () {
    final scope = _resolveFullCatalog();

    final byMaterial = distinctCandidatesOf(scope.requirements);
    final byExercise = <Exercise>{
      for (final requirement in scope.requirements) ...requirement.candidates,
    }.toList();

    expect(byMaterial, byExercise);
  });

  test('every requirement material contributes its candidates once', () {
    final scope = _resolveFullCatalog();

    final assembled = distinctCandidatesOf(scope.requirements);

    expect(
      {for (final exercise in assembled) exercise.material.materialId},
      {
        for (final requirement in scope.requirements)
          requirement.material.materialId,
      },
    );
    expect(assembled.toSet(), hasLength(assembled.length));
  });
}

ResolvedPracticeScope _resolveFullCatalog() {
  final catalog = v1ScaleCatalog;
  final goal = PracticeGoal(
    id: 'ASSEMBLY',
    curriculum: Curriculum(
      id: 'ASSEMBLY',
      version: '1',
      requirements: [
        for (final material in catalog)
          for (final hands in [HandConfiguration.right, HandConfiguration.left])
            CurriculumRequirement(
              id: '${material.materialId}:${hands.id}',
              familyId: material.familyId,
              materialId: material.materialId,
              constraints: ExerciseConstraints(hands: hands, octaves: 1),
            ),
      ],
    ),
  );

  final resolved =
      PracticeScopeResolver(
        families: const [ScalePracticeMaterialFamily()],
      ).resolve(
        goal: goal,
        focus: PracticeFocus.unrestricted,
        catalog: catalog,
        instrument: InstrumentProfile(),
      );
  return (resolved as ValidPracticeScope).scope;
}
