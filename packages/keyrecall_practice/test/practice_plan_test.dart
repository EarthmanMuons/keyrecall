import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

final _catalog = <TechnicalMaterial>[
  ScaleMaterial('C', ScaleForm.major),
  ScaleMaterial('A', ScaleForm.naturalMinor),
  ScaleMaterial('D', ScaleForm.harmonicMinor),
  ArpeggioMaterial('C', ArpeggioQuality.major),
  ArpeggioMaterial('A', ArpeggioQuality.minor),
];

final _minorMaterial = ActiveFocus(
  label: 'Minor material',
  strength: FocusStrength.emphasis,
  material: MaterialFocus(
    scaleFormIds: {
      ScaleForm.naturalMinor.id,
      ScaleForm.harmonicMinor.id,
      ScaleForm.melodicMinor.id,
    },
    arpeggioQualityIds: {ArpeggioQuality.minor.id},
  ),
);

void main() {
  group('material focus', () {
    test('an unnamed facet says nothing', () {
      expect(MaterialFocus().selectionOf(_catalog), _catalog);
    });

    test('a family facet reaches every material in that family', () {
      final arpeggios = MaterialFocus(
        familyIds: {TechnicalMaterial.arpeggioFamilyId},
      ).selectionOf(_catalog);

      expect(arpeggios, hasLength(2));
      expect(
        arpeggios.every(
          (material) => material.familyId == TechnicalMaterial.arpeggioFamilyId,
        ),
        isTrue,
        reason: 'both arpeggios and neither scale',
      );
    });

    test('form and quality facets combine across families', () {
      final minor = MaterialFocus(
        scaleFormIds: {
          ScaleForm.naturalMinor.id,
          ScaleForm.harmonicMinor.id,
          ScaleForm.melodicMinor.id,
        },
        arpeggioQualityIds: {ArpeggioQuality.minor.id},
      ).selectionOf(_catalog);

      expect(minor, hasLength(3));
      expect(
        minor.any(
          (material) => material.familyId == TechnicalMaterial.arpeggioFamilyId,
        ),
        isTrue,
        reason: 'minor material is not only minor scales',
      );
    });

    test('a key facet narrows whatever family facet is in force', () {
      final selection = MaterialFocus(
        familyIds: {TechnicalMaterial.scaleFamilyId},
        tonics: {'C'},
      ).selectionOf(_catalog);

      expect(
        selection.single.materialId,
        ScaleMaterial('C', ScaleForm.major).materialId,
      );
    });
  });

  group('resolving a plan', () {
    test('practicing normally narrows and emphasizes nothing', () {
      final resolved = PracticePlan.normal.resolve(_catalog) as ResolvedPlan;

      expect(resolved.goal.isScoped, isFalse);
      expect(resolved.focus.exclusiveRequirementIds, isNull);
      expect(resolved.focus.emphasisByRequirementId, isEmpty);
    });

    test('an emphasis focus weights its material and excludes nothing', () {
      final resolved =
          PracticePlan.normal.focusedOn(_minorMaterial).resolve(_catalog)
              as ResolvedPlan;

      expect(resolved.focus.exclusiveRequirementIds, isNull);
      expect(resolved.focus.emphasisByRequirementId, hasLength(3));
      expect(
        resolved.focus.emphasisByRequirementId.values,
        everyElement(greaterThan(GoalEmphasis.unemphasized)),
      );
    });

    test('an exclusive focus names what may be generated at all', () {
      final resolved =
          PracticePlan.normal
                  .focusedOn(
                    ActiveFocus(
                      label: '1 material',
                      strength: FocusStrength.exclusive,
                      material: MaterialFocus(tonics: {'D'}),
                    ),
                  )
                  .resolve(_catalog)
              as ResolvedPlan;

      expect(resolved.focus.exclusiveRequirementIds, hasLength(1));
      expect(resolved.focus.emphasisByRequirementId, isEmpty);
    });

    test('a focus names requirements the goal actually generated', () {
      final plan = PracticePlan.normal.focusedOn(_minorMaterial);
      final resolved = plan.resolve(_catalog) as ResolvedPlan;

      final resolution = PracticeScopeResolver().resolve(
        goal: resolved.goal,
        focus: resolved.focus,
        catalog: _catalog,
        instrument: InstrumentProfile(),
      );

      expect(
        resolution,
        isA<ValidPracticeScope>(),
        reason: 'a focus that named an unknown requirement fails resolution',
      );
    });
  });

  group('a focus carried across goals', () {
    final production = <TechnicalMaterial>[
      ...allScales,
      ...allRootPositionArpeggios,
    ];
    ActiveFocus majorsIn(Set<String> tonics, FocusStrength strength) =>
        ActiveFocus(
          label: 'Majors',
          strength: strength,
          material: MaterialFocus(
            scaleFormIds: {ScaleForm.major.id},
            tonics: tonics,
          ),
        );

    ResolvedPlan under(String goalId, ActiveFocus focus) =>
        PracticePlan(goalId: goalId, focus: focus).resolve(production)
            as ResolvedPlan;

    test('names every requirement the new goal holds over its material', () {
      final focus = majorsIn({'C'}, FocusStrength.exclusive);

      expect(under('FOUNDATIONS', focus).focus.exclusiveRequirementIds, {
        'C_MAJOR:RIGHT:1',
        'C_MAJOR:LEFT:1',
      });
      expect(under('KEY_FLUENCY_24', focus).focus.exclusiveRequirementIds, {
        'C_MAJOR:TOGETHER:2',
      });
    });

    test('and resolves to a scope there', () {
      for (final goalId in supportedGoals.keys) {
        final resolved = under(
          goalId,
          majorsIn({'C'}, FocusStrength.exclusive),
        );
        expect(
          PracticeScopeResolver().resolve(
            goal: resolved.goal,
            focus: resolved.focus,
            catalog: production,
            instrument: InstrumentProfile(),
          ),
          isA<ValidPracticeScope>(),
          reason: goalId,
        );
      }
    });

    test('emphasis moves the same way', () {
      expect(
        under(
          'FOUNDATIONS',
          majorsIn({'C'}, FocusStrength.emphasis),
        ).focus.emphasisByRequirementId.keys,
        {'C_MAJOR:RIGHT:1', 'C_MAJOR:LEFT:1'},
      );
    });

    test('drops material the new goal does not hold', () {
      expect(
        under(
          'FOUNDATIONS',
          majorsIn({'C', 'E'}, FocusStrength.exclusive),
        ).focus.exclusiveRequirementIds,
        {'C_MAJOR:RIGHT:1', 'C_MAJOR:LEFT:1'},
      );
    });

    test('and is no focus there when it holds none of it', () {
      final resolved = under(
        'FOUNDATIONS',
        majorsIn({'E', 'B'}, FocusStrength.exclusive),
      );

      expect(resolved.focus.exclusiveRequirementIds, isNull);
      expect(resolved.focus.emphasisByRequirementId, isEmpty);
    });

    test('but still fails when the catalog holds none of it', () {
      final resolved =
          PracticePlan(
                goalId: 'FOUNDATIONS',
                focus: majorsIn({'C'}, FocusStrength.exclusive),
              ).resolve(allRootPositionArpeggios)
              as ResolvedPlan;

      expect(
        PracticeScopeResolver().resolve(
          goal: resolved.goal,
          focus: resolved.focus,
          catalog: allRootPositionArpeggios,
          instrument: InstrumentProfile(),
        ),
        isA<InvalidPracticeScope>(),
        reason: 'a focus nothing can satisfy is not a request for everything',
      );
    });
  });

  group('a plan this build cannot read', () {
    test('an unknown goal resolves to nothing rather than to everything', () {
      final resolution = PracticePlan(goalId: 'UNKNOWN_EXAM').resolve(_catalog);

      expect(
        (resolution as UnresolvablePlan).failures.single.code,
        ScopeResolutionFailureCode.unknownGoal,
      );
    });

    test('a focus naming vocabulary this build lacks fails the plan', () {
      final resolution = PracticePlan.normal
          .focusedOn(
            ActiveFocus(
              label: 'Blues',
              strength: FocusStrength.emphasis,
              material: MaterialFocus(scaleFormIds: {'BLUES'}),
            ),
          )
          .resolve(_catalog);

      expect(
        (resolution as UnresolvablePlan).failures.single.reference,
        'BLUES',
      );
    });

    test('one unreadable name fails a selection the rest of which reads', () {
      final resolution = PracticePlan.normal
          .focusedOn(
            ActiveFocus(
              label: 'Two keys',
              strength: FocusStrength.exclusive,
              material: MaterialFocus(tonics: {'C', 'H'}),
            ),
          )
          .resolve(_catalog);

      expect(
        (resolution as UnresolvablePlan).failures.map(
          (failure) => failure.reference,
        ),
        ['H'],
        reason: 'the readable half is not what the learner asked for',
      );
    });

    test('a form this catalog lacks is still a form this build reads', () {
      final resolution = PracticePlan.normal
          .focusedOn(_minorMaterial)
          .resolve(_catalog);

      expect(
        resolution,
        isA<ResolvedPlan>(),
        reason: 'melodic minor is stocked nowhere here and is still meaningful',
      );
    });
  });

  group('a focus that narrows nothing', () {
    test('is not a focus, it is practicing normally', () {
      final plan = PracticePlan.normal.focusedOn(
        ActiveFocus(
          label: 'Nothing selected',
          strength: FocusStrength.exclusive,
          material: MaterialFocus(),
        ),
      );

      expect(plan.isFocused, isFalse);
      expect(plan, PracticePlan.normal);
    });

    test('keeps the goal it was asked under', () {
      final plan = PracticePlan(goalId: 'OTHER_GOAL').focusedOn(
        ActiveFocus(
          label: 'Nothing selected',
          strength: FocusStrength.emphasis,
          material: MaterialFocus(),
        ),
      );

      expect(plan.goalId, 'OTHER_GOAL');
      expect(plan.isFocused, isFalse);
    });
  });

  group('storing a plan', () {
    test('only the goal is stored', () {
      final json = practiceGoalToJson('FOUNDATIONS');

      expect(json.keys, {'schema_version', 'goal_id'});
      expect(practiceGoalFromJson(json), 'FOUNDATIONS');
    });

    test('a goal from a later build is refused rather than guessed at', () {
      final json = practiceGoalToJson('FOUNDATIONS')
        ..['schema_version'] = practiceGoalSchemaVersion + 1;

      expect(
        () => practiceGoalFromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a focus is carried to a goal that holds some of it', () {
      final focus = ActiveFocus(
        label: 'C major',
        strength: FocusStrength.exclusive,
        material: MaterialFocus(
          scaleFormIds: {ScaleForm.major.id},
          tonics: {'C'},
        ),
      );
      final plan = PracticePlan.normal.focusedOn(focus);
      final catalog = <TechnicalMaterial>[...allScales];

      expect(plan.withGoal('FOUNDATIONS', catalog).focus, focus);
    });

    test('and dropped for one that holds none of it', () {
      final plan = PracticePlan.normal.focusedOn(
        ActiveFocus(
          label: 'E major',
          strength: FocusStrength.exclusive,
          material: MaterialFocus(
            scaleFormIds: {ScaleForm.major.id},
            tonics: {'E'},
          ),
        ),
      );

      expect(
        plan.withGoal('FOUNDATIONS', [...allScales]),
        const PracticePlan(goalId: 'FOUNDATIONS'),
      );
    });

    test('erasing a profile takes its goal with it', () async {
      final store = InMemoryPracticeStore();
      await store.saveGoalId('learner', PracticePlan.normal.goalId);

      await store.erase('learner');

      expect(await store.loadGoalId('learner'), isNull);
    });
  });
}
