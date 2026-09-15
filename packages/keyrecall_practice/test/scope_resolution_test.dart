import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
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
      result.scope.requirements.single.targetCandidates,
      everyElement(
        predicate<Exercise>(
          (exercise) =>
              exercise.conditions.hands == HandConfiguration.together &&
              exercise.conditions.octaves == 2,
        ),
      ),
    );
    expect(
      result.scope.requirements.single.candidates,
      contains(
        predicate<Exercise>(
          (exercise) =>
              exercise.conditions.hands == HandConfiguration.right &&
              exercise.conditions.octaves == 1,
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
    expect(result.scope.targetRequirementIds, {'TARGET'});
    expect(result.scope.supportRequirementIds, {'SUPPORT'});
  });

  test('a target retained as support is not a completion target', () {
    final material = fixtureMaterials.first;
    final result =
        resolver.resolve(
              goal: PracticeGoal(
                id: 'GOAL',
                curriculum: _pairCurriculum(material),
              ),
              focus: PracticeFocus(exclusiveRequirementIds: {'A'}),
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;

    expect(
      result.scope.requirements.map((resolved) => resolved.requirement.id),
      containsAll(['A', 'B']),
      reason: 'B still prepares A, so it stays available to schedule',
    );
    expect(result.scope.targetRequirementIds, {'A'});
    expect(result.scope.supportRequirementIds, {'B'});
  });

  test('both hold where both were selected', () {
    final material = fixtureMaterials.first;
    final result =
        resolver.resolve(
              goal: PracticeGoal(
                id: 'GOAL',
                curriculum: _pairCurriculum(material),
              ),
              focus: PracticeFocus.unrestricted,
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;

    expect(result.scope.targetRequirementIds, {'A', 'B'});
    expect(result.scope.supportRequirementIds, {
      'B',
    }, reason: 'roles are not exclusive: B is a target that also prepares one');
  });

  test('one material is realized once, however many requirements name it', () {
    final material = fixtureMaterials.first;
    final family = _CountingFamily();
    final result =
        PracticeScopeResolver(families: [family]).resolve(
              goal: PracticeGoal(
                id: 'GOAL',
                curriculum: _pairCurriculum(material),
              ),
              focus: PracticeFocus.unrestricted,
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;

    expect(family.generated, 1);
    final [first, second] = result.scope.requirements;
    expect(first.candidates, second.candidates);
  });
}

/// The scale family, counting how often it is asked to realize material.
class _CountingFamily implements PracticeMaterialFamily {
  final PracticeMaterialFamily _scales = const ScalePracticeMaterialFamily();
  int generated = 0;

  @override
  String get familyId => _scales.familyId;

  @override
  double get entryTempoBpm => _scales.entryTempoBpm;

  @override
  List<Exercise> generate(
    InstrumentProfile instrument,
    TechnicalMaterial material,
  ) {
    generated++;
    return _scales.generate(instrument, material);
  }

  @override
  AcquisitionFloor acquisitionFloorFor(
    Iterable<AcquisitionFloorRequest> requests,
  ) => _scales.acquisitionFloorFor(requests);
}

/// Two targets over one material, the second declaring it prepares the first.
Curriculum _pairCurriculum(TechnicalMaterial material) => Curriculum(
  id: 'PAIR',
  version: '1',
  requirements: [
    CurriculumRequirement(
      id: 'A',
      familyId: material.familyId,
      materialId: material.materialId,
      constraints: const ExerciseConstraints(octaves: 2),
    ),
    CurriculumRequirement(
      id: 'B',
      familyId: material.familyId,
      materialId: material.materialId,
      constraints: const ExerciseConstraints(octaves: 1),
      supportsRequirementIds: {'A'},
    ),
  ],
);
