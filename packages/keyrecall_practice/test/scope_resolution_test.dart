import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final resolver = PracticeScopeResolver();

  test('resolves requirement identity separately from material identity', () {
    final material = fixtureMaterials.first;
    final goal = PracticeGoal(
      id: 'EXAM',
      curriculum: Curriculum(
        id: 'PSEUDO_EXAM',
        version: '2026',
        requirements: [
          CurriculumRequirement(
            id: 'C_MAJOR_HT_TWO_OCTAVES',
            familyId: material.familyId,
            materialId: material.materialId,
            constraints: const ExerciseConstraints(
              hands: HandConfiguration.together,
              octaves: 2,
            ),
          ),
        ],
      ),
    );

    final result =
        resolver.resolve(
              goal: goal,
              focus: PracticeFocus.unrestricted,
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;

    expect(
      result.scope.requirements.single.requirement.id,
      isNot(material.materialId),
    );
    expect(
      result.scope.requirements.single.candidates,
      everyElement(
        predicate<Exercise>(
          (exercise) =>
              exercise.conditions.hands == HandConfiguration.together &&
              exercise.conditions.octaves == 2,
        ),
      ),
    );
  });

  test('rejects an unknown identity without returning a partial scope', () {
    final goal = PracticeGoal(
      id: 'BROKEN',
      targetMaterialIds: {'NOT_INSTALLED', fixtureMaterials.first.materialId},
    );

    final result = resolver.resolve(
      goal: goal,
      focus: PracticeFocus.unrestricted,
      catalog: fixtureMaterials,
      instrument: InstrumentProfile(),
    );

    expect(result, isA<InvalidPracticeScope>());
    expect(
      (result as InvalidPracticeScope).failures.map((failure) => failure.code),
      contains(ScopeResolutionFailureCode.unknownMaterial),
    );
  });

  test('rejects a family that does not own the resolved material', () {
    final material = fixtureMaterials.first;
    final result = resolver.resolve(
      goal: PracticeGoal(
        id: 'WRONG_FAMILY',
        curriculum: Curriculum(
          id: 'WRONG_FAMILY',
          version: '1',
          requirements: [
            CurriculumRequirement(
              id: 'ARPEGGIO_SHAPED_SCALE',
              familyId: 'ARPEGGIO',
              materialId: material.materialId,
            ),
          ],
        ),
      ),
      focus: PracticeFocus.unrestricted,
      catalog: fixtureMaterials,
      instrument: InstrumentProfile(),
    );

    expect(
      (result as InvalidPracticeScope).failures.single.code,
      ScopeResolutionFailureCode.unknownFamily,
    );
  });

  test('rejects conditions the installed instrument cannot realize', () {
    final material = fixtureMaterials.first;
    final result = resolver.resolve(
      goal: PracticeGoal(
        id: 'TOO_WIDE',
        curriculum: Curriculum(
          id: 'TOO_WIDE',
          version: '1',
          requirements: [
            CurriculumRequirement(
              id: 'THREE_OCTAVES',
              familyId: material.familyId,
              materialId: material.materialId,
              constraints: const ExerciseConstraints(octaves: 3),
            ),
          ],
        ),
      ),
      focus: PracticeFocus.unrestricted,
      catalog: fixtureMaterials,
      instrument: InstrumentProfile(),
    );

    expect(
      (result as InvalidPracticeScope).failures.single.code,
      ScopeResolutionFailureCode.unrealizableRequirement,
    );
  });

  test('rejects a curriculum version outside its registered editions', () {
    final material = fixtureMaterials.first;
    final versionedResolver = PracticeScopeResolver(
      supportedVersionsByCurriculumId: {
        'EXAM': {'2025'},
      },
    );
    final result = versionedResolver.resolve(
      goal: PracticeGoal(
        id: 'EXAM_GOAL',
        curriculum: Curriculum(
          id: 'EXAM',
          version: '2024',
          requirements: [
            CurriculumRequirement(
              id: 'SCALE',
              familyId: material.familyId,
              materialId: material.materialId,
            ),
          ],
        ),
      ),
      focus: PracticeFocus.unrestricted,
      catalog: fixtureMaterials,
      instrument: InstrumentProfile(),
    );

    expect(
      (result as InvalidPracticeScope).failures.single.code,
      ScopeResolutionFailureCode.unsupportedCurriculumVersion,
    );
  });

  test('rejects support that names an absent target', () {
    final material = fixtureMaterials.first;
    final result = resolver.resolve(
      goal: PracticeGoal(
        id: 'DANGLING_SUPPORT',
        curriculum: Curriculum(
          id: 'DANGLING_SUPPORT',
          version: '1',
          requirements: [
            CurriculumRequirement(
              id: 'SUPPORT',
              familyId: material.familyId,
              materialId: material.materialId,
              role: CurriculumRequirementRole.support,
              supportsRequirementIds: {'ABSENT'},
            ),
          ],
        ),
      ),
      focus: PracticeFocus.unrestricted,
      catalog: fixtureMaterials,
      instrument: InstrumentProfile(),
    );

    expect(
      (result as InvalidPracticeScope).failures.map((failure) => failure.code),
      contains(ScopeResolutionFailureCode.unresolvedSupport),
    );
  });

  test('rejects an exclusive focus with no targets', () {
    final material = fixtureMaterials.first;
    final goal = PracticeGoal(
      id: 'ONE_SCALE',
      targetMaterialIds: {material.materialId},
    );

    final result = resolver.resolve(
      goal: goal,
      focus: PracticeFocus(exclusiveRequirementIds: const {}),
      catalog: fixtureMaterials,
      instrument: InstrumentProfile(),
    );

    expect(result, isA<InvalidPracticeScope>());
    expect(
      (result as InvalidPracticeScope).failures.map((failure) => failure.code),
      contains(ScopeResolutionFailureCode.emptyExclusiveFocus),
    );
  });

  test('an exclusive focus retains support for selected targets', () {
    final material = fixtureMaterials.first;
    final curriculum = Curriculum(
      id: 'WITH_SUPPORT',
      version: '1',
      requirements: [
        CurriculumRequirement(
          id: 'TARGET',
          familyId: material.familyId,
          materialId: material.materialId,
        ),
        CurriculumRequirement(
          id: 'SUPPORT',
          familyId: material.familyId,
          materialId: material.materialId,
          role: CurriculumRequirementRole.support,
          supportsRequirementIds: {'TARGET'},
          constraints: const ExerciseConstraints(
            hands: HandConfiguration.right,
            octaves: 1,
          ),
        ),
      ],
    );

    final result =
        resolver.resolve(
              goal: PracticeGoal(id: 'GOAL', curriculum: curriculum),
              focus: PracticeFocus(exclusiveRequirementIds: {'TARGET'}),
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;

    expect(
      result.scope.requirements.map((resolved) => resolved.requirement.id),
      containsAll(['TARGET', 'SUPPORT']),
    );
  });
}
