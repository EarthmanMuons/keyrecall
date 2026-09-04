import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final scaleC = v1ScaleCatalog.firstWhere(
    (material) => material.tonic == 'C' && material.form == ScaleForm.major,
  );
  final scaleG = v1ScaleCatalog.firstWhere(
    (material) => material.tonic == 'G' && material.form == ScaleForm.major,
  );
  final arpeggioC = proofArpeggios.firstWhere(
    (material) => material.tonic == 'C',
  );
  final arpeggioG = proofArpeggios.firstWhere(
    (material) => material.tonic == 'G',
  );
  final arpeggioCMinor = proofArpeggios.firstWhere(
    (material) => material.quality == ArpeggioQuality.minor,
  );
  final materials = <TechnicalMaterial>[scaleC, scaleG, arpeggioC, arpeggioG];
  final curriculum = Curriculum(
    id: 'PSEUDO_TECHNIQUE_1',
    version: '1',
    requirements: [
      _requirement('C_SCALE_RH', scaleC),
      _requirement('G_SCALE_RH', scaleG),
      _requirement('C_ARPEGGIO_RH', arpeggioC),
      _requirement('G_ARPEGGIO_RH', arpeggioG),
    ],
  );
  final goal = PracticeGoal(id: 'TECHNIQUE_1', curriculum: curriculum);
  final resolver = PracticeScopeResolver();

  test('one structural scope resolves both material families', () {
    final resolution = resolver.resolve(
      goal: goal,
      focus: PracticeFocus.unrestricted,
      catalog: materials,
      instrument: InstrumentProfile(),
    );

    final scope = (resolution as ValidPracticeScope).scope;
    expect(
      scope.requirements.map((resolved) => resolved.material.familyId).toSet(),
      {TechnicalMaterial.scaleFamilyId, TechnicalMaterial.arpeggioFamilyId},
    );
    expect(
      scope.requirements.map((resolved) => resolved.requirement.id).toSet(),
      {'C_SCALE_RH', 'G_SCALE_RH', 'C_ARPEGGIO_RH', 'G_ARPEGGIO_RH'},
    );
  });

  test('a focus can retain one scale and one arpeggio', () {
    final resolution = resolver.resolve(
      goal: goal,
      focus: PracticeFocus(
        exclusiveRequirementIds: {'C_SCALE_RH', 'G_ARPEGGIO_RH'},
      ),
      catalog: materials,
      instrument: InstrumentProfile(),
    );

    final scope = (resolution as ValidPracticeScope).scope;
    expect(
      scope.requirements.map((resolved) => resolved.requirement.id).toSet(),
      {'C_SCALE_RH', 'G_ARPEGGIO_RH'},
    );
    expect(scope.requirements.map((resolved) => resolved.material).toSet(), {
      scaleC,
      arpeggioG,
    });
  });

  test('families provide requirement-directed acquisition entries', () {
    final scope =
        (resolver.resolve(
                  goal: goal,
                  focus: PracticeFocus.unrestricted,
                  catalog: materials,
                  instrument: InstrumentProfile(),
                )
                as ValidPracticeScope)
            .scope;

    final entries = resolver.acquisitionFloorFor(scope.requirements).entries;
    final byRequirement = <String, List<Exercise>>{};
    for (final entry in entries) {
      byRequirement
          .putIfAbsent(entry.requirementId, () => [])
          .add(entry.exercise);
    }

    expect(byRequirement['C_SCALE_RH'], hasLength(2));
    expect(byRequirement['C_ARPEGGIO_RH'], hasLength(1));
    expect(
      byRequirement['C_ARPEGGIO_RH']!.single.conditions.hands,
      HandConfiguration.right,
    );
  });

  test('the generic evaluator aggregates mixed requirement state', () {
    final scope =
        (resolver.resolve(
                  goal: goal,
                  focus: PracticeFocus.unrestricted,
                  catalog: materials,
                  instrument: InstrumentProfile(),
                )
                as ValidPracticeScope)
            .scope;

    final evaluated = const PracticeScopeEvaluator().evaluate(
      scope: scope,
      state: learner.newState(at: t0),
      journal: AttemptJournal(
        JournalHeader(profileId: alice.id, createdAt: t0),
      ),
      learner: learner,
      at: t0,
    );

    expect(evaluated.requirements, hasLength(4));
    expect(
      evaluated.requirements,
      everyElement(
        predicate<RequirementState>((state) => !state.isCovered && state.isDue),
      ),
    );
    expect(evaluated.coverage.targetCount, 4);
    expect(evaluated.coverage.coveredTargets, 0);
  });

  for (final placement in PlacementTier.values) {
    test(
      'the common scheduler presents mixed work for ${placement.name}',
      () async {
        final session = await PracticeSession.open(
          store: InMemoryPracticeStore(createdAt: t0),
          profile: alicePlacedAt(placement),
          materials: materials,
          goal: goal,
          sessionId: 'mixed-${placement.name}',
          nextId: countingIds(placement.name),
        );

        final decision = await session.decideOutcome(at: t0.plusDays(0.5));

        expect(decision, isA<PresentedAttempt>());
        expect(
          (decision as PresentedAttempt).exercise.material.familyId,
          isIn({
            TechnicalMaterial.scaleFamilyId,
            TechnicalMaterial.arpeggioFamilyId,
          }),
        );
      },
    );
  }

  test(
    'a direct material goal derives the arpeggio family from the catalog',
    () {
      final resolution = resolver.resolve(
        goal: PracticeGoal(
          id: 'ARPEGGIO_ONLY',
          targetMaterialIds: {arpeggioC.materialId},
        ),
        focus: PracticeFocus.unrestricted,
        catalog: materials,
        instrument: InstrumentProfile(),
      );

      final requirement =
          (resolution as ValidPracticeScope).scope.requirements.single;
      expect(requirement.requirement.familyId, arpeggioC.familyId);
      expect(requirement.material, arpeggioC);
    },
  );

  test('the sourced family generates one, two, and four-octave shapes', () {
    final candidates = const ArpeggioPracticeMaterialFamily().generate(
      InstrumentProfile(),
      arpeggioCMinor,
    );

    expect(candidates.map((exercise) => exercise.conditions.octaves).toSet(), {
      1,
      2,
      4,
    });
    expect(
      candidates.map((exercise) => exercise.conditions.hands).toSet(),
      HandConfiguration.values.toSet(),
    );
  });

  test('catalog and fingering availability alone determine candidates', () {
    const family = ArpeggioPracticeMaterialFamily();
    final instrument = InstrumentProfile();
    final shapesByMaterial = {
      for (final material in allRootPositionArpeggios)
        material.materialId: {
          for (final exercise in family.generate(instrument, material))
            exercise.conditions,
        },
    };

    expect(shapesByMaterial, hasLength(allRootPositionArpeggios.length));
    expect(shapesByMaterial.values, everyElement(isNotEmpty));
    final expectedShapes = shapesByMaterial.values.first;
    for (final shapes in shapesByMaterial.values.skip(1)) {
      expect(shapes, expectedShapes);
    }

    final unsupported = ArpeggioMaterial(
      'C',
      ArpeggioQuality.major,
      inversion: ArpeggioInversion.first,
    );
    expect(family.generate(instrument, unsupported), isEmpty);
  });

  test('counterfactual policy changes entry tempo without changing spans', () {
    final candidates = const ArpeggioPracticeMaterialFamily(
      policy: ArpeggioPracticePolicy(initialTempoBpm: 72),
    ).generate(InstrumentProfile(), arpeggioC);

    expect(candidates.map((exercise) => exercise.conditions.tempoBpm).toSet(), {
      72,
    });
    expect(candidates.map((exercise) => exercise.conditions.octaves).toSet(), {
      1,
      2,
      4,
    });
  });

  test('scope resolution carries each family entry tempo', () {
    final resolution =
        PracticeScopeResolver(
              families: const [
                ScalePracticeMaterialFamily(),
                ArpeggioPracticeMaterialFamily(
                  policy: ArpeggioPracticePolicy(initialTempoBpm: 72),
                ),
              ],
            ).resolve(
              goal: goal,
              focus: PracticeFocus.unrestricted,
              catalog: materials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;

    expect(resolution.entryPolicy.tempoFor(scaleC), generatedTempi.first);
    expect(resolution.entryPolicy.tempoFor(arpeggioC), 72);
  });

  test('counterfactual floor can offer both separate hands', () {
    const family = ArpeggioPracticeMaterialFamily(
      policy: ArpeggioPracticePolicy(
        acquisitionFloorShape:
            ArpeggioAcquisitionFloorShape.separateHandsAscending,
      ),
    );
    final candidates = family.generate(InstrumentProfile(), arpeggioC);
    final floor = family.acquisitionFloorFor([
      AcquisitionFloorRequest(
        requirementId: 'C_MAJOR_ARPEGGIO',
        candidates: candidates,
      ),
    ]);

    expect(
      floor.entries.map((entry) => entry.exercise.conditions.hands).toSet(),
      {HandConfiguration.right, HandConfiguration.left},
    );
  });

  test('counterfactual floor can use ascending and descending traversal', () {
    const family = ArpeggioPracticeMaterialFamily(
      policy: ArpeggioPracticePolicy(
        acquisitionFloorShape:
            ArpeggioAcquisitionFloorShape.rightHandAscendingAndDescending,
      ),
    );
    final candidates = family.generate(InstrumentProfile(), arpeggioC);
    final floor = family.acquisitionFloorFor([
      AcquisitionFloorRequest(
        requirementId: 'C_MAJOR_ARPEGGIO',
        candidates: candidates,
      ),
    ]);

    expect(
      candidates.map((exercise) => exercise.conditions.direction).toSet(),
      ExerciseDirection.values.toSet(),
    );
    expect(
      floor.entries.map((entry) => entry.exercise.conditions.direction).toSet(),
      {ExerciseDirection.upDown},
    );
    expect(
      floor.entries.map((entry) => entry.exercise.conditions.hands).toSet(),
      {HandConfiguration.right},
    );
  });

  test('topology without canonical fingering is not a practice candidate', () {
    final inversion = ArpeggioMaterial(
      'C',
      ArpeggioQuality.major,
      inversion: ArpeggioInversion.first,
    );
    final resolution = resolver.resolve(
      goal: PracticeGoal(
        id: 'UNSUPPORTED_INVERSION',
        targetMaterialIds: {inversion.materialId},
      ),
      focus: PracticeFocus.unrestricted,
      catalog: [inversion],
      instrument: InstrumentProfile(),
    );

    expect(resolution, isA<InvalidPracticeScope>());
    expect(
      (resolution as InvalidPracticeScope).failures.single.code,
      ScopeResolutionFailureCode.unrealizableRequirement,
    );
  });
}

CurriculumRequirement _requirement(String id, TechnicalMaterial material) =>
    CurriculumRequirement(
      id: id,
      familyId: material.familyId,
      materialId: material.materialId,
      constraints: const ExerciseConstraints(
        hands: HandConfiguration.right,
        octaves: 1,
        direction: ExerciseDirection.up,
      ),
    );
