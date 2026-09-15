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

  group('storing a plan', () {
    test('a plan survives being written and read back', () {
      final plan = PracticePlan.normal.focusedOn(_minorMaterial);

      expect(PracticePlan.fromJson(plan.toJson()), plan);
    });

    test('a plan from a later build is refused rather than guessed at', () {
      final json = PracticePlan.normal.toJson()
        ..['schema_version'] = practicePlanSchemaVersion + 1;

      expect(
        () => PracticePlan.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a focus missing a facet is refused rather than read as empty', () {
      final json = PracticePlan.normal
          .focusedOn(
            ActiveFocus(
              label: 'C major only',
              strength: FocusStrength.exclusive,
              material: MaterialFocus(tonics: {'C'}),
            ),
          )
          .toJson();
      (json['focus']! as Map<String, Object?>)['material'] =
          <String, Object?>{};

      expect(
        () => PracticePlan.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a focus that narrows nothing is refused', () {
      final json = PracticePlan.normal
          .focusedOn(
            ActiveFocus(
              label: 'Everything',
              strength: FocusStrength.exclusive,
              material: MaterialFocus(tonics: {'C'}),
            ),
          )
          .toJson();
      final material =
          (json['focus']! as Map<String, Object?>)['material']!
              as Map<String, Object?>;
      material['tonics'] = <String>[];

      expect(
        () => PracticePlan.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('erasing a profile takes its plan with it', () async {
      final store = InMemoryPracticeStore();
      await store.savePracticePlan('learner', PracticePlan.normal);

      await store.erase('learner');

      expect(await store.loadPracticePlan('learner'), isNull);
    });
  });
}
