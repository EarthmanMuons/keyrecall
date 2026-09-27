import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/goal_progress.dart';
import 'package:keyrecall/features/practice/goal_progress_screen.dart';

void main() {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];

  ResolvedPracticeScope resolved(
    String goalId, {
    PracticeFocus focus = PracticeFocus.unrestricted,
  }) => (PracticeScopeResolver().resolve(
    goal: supportedGoals[goalId]!,
    focus: focus,
    catalog: catalog,
    instrument: InstrumentProfile(),
  ) as ValidPracticeScope).scope;

  Set<String> targetIdsOf(ResolvedPracticeScope scope) => {
    for (final requirement in scope.requirements)
      if (requirement.isTarget) requirement.requirement.id,
  };

  test('Foundations reads as its ten scales, each hand a cell', () {
    final scope = resolved('FOUNDATIONS');
    final progress = goalProgressOf(
      scope,
      ScopeCoverage(coveredTargetIds: const {}, targetCount: 20),
    );

    final [scales] = progress.sections;
    expect(scales.familyId, TechnicalMaterial.scaleFamilyId);
    expect(scales.rows, hasLength(10));
    expect(scales.rows.first.material, ScaleMaterial('C', ScaleForm.major));
    expect(
      [for (final cell in scales.rows.first.cells) cell.hands],
      [HandConfiguration.right, HandConfiguration.left],
    );
    expect(progress.total, 20);
    expect(progress.covered, 0);
  });

  test('24-key fluency reads as scales and arpeggios, one cell each', () {
    final scope = resolved('KEY_FLUENCY_24');
    final progress = goalProgressOf(
      scope,
      ScopeCoverage(coveredTargetIds: const {}, targetCount: 48),
    );

    expect(
      [for (final section in progress.sections) section.familyId],
      [TechnicalMaterial.scaleFamilyId, TechnicalMaterial.arpeggioFamilyId],
    );
    for (final section in progress.sections) {
      expect(section.rows, hasLength(24));
      expect(
        section.rows.every(
          (row) =>
              row.cells.length == 1 &&
              row.cells.single.hands == HandConfiguration.together,
        ),
        isTrue,
      );
    }
  });

  test('a covered target fills its own cell and nothing else', () {
    final scope = resolved('FOUNDATIONS');
    final cMajorRight = scope.requirements
        .firstWhere(
          (requirement) =>
              requirement.material == ScaleMaterial('C', ScaleForm.major) &&
              requirement.requirement.constraints.hands ==
                  HandConfiguration.right,
        )
        .requirement
        .id;
    final progress = goalProgressOf(
      scope,
      ScopeCoverage(coveredTargetIds: {cMajorRight}, targetCount: 20),
    );

    final cMajor = progress.sections.single.rows.first;
    expect([for (final cell in cMajor.cells) cell.covered], [true, false]);
    expect(cMajor.isComplete, isFalse);
    expect(progress.covered, 1);
  });

  test('counts only targets, so it agrees with the coverage it reads', () {
    final scope = resolved('KEY_FLUENCY_24');
    final everything = targetIdsOf(scope);
    final progress = goalProgressOf(
      scope,
      ScopeCoverage(coveredTargetIds: everything, targetCount: 48),
    );

    expect(progress.covered, everything.length);
    expect(progress.total, everything.length);
  });

  test('under an exclusive focus, only what the focus holds', () {
    final general = PracticeGoal.generalFluency;
    final focus = PracticeFocus(
      exclusiveRequirementIds: {
        catalogRequirementId(
          general.id,
          ScaleMaterial('D', ScaleForm.harmonicMinor).materialId,
        ),
      },
    );
    final scope = (PracticeScopeResolver().resolve(
      goal: general,
      focus: focus,
      catalog: catalog,
      instrument: InstrumentProfile(),
    ) as ValidPracticeScope).scope;

    final progress = goalProgressOf(
      scope,
      ScopeCoverage(coveredTargetIds: const {}, targetCount: 1),
    );

    expect(progress.total, 1);
    expect(
      progress.sections.single.rows.single.material,
      ScaleMaterial('D', ScaleForm.harmonicMinor),
    );
  });

  group('how a grid names its keys', () {
    test('a major by its tonic, a minor with m, both families alike', () {
      expect(keyLabel(ScaleMaterial('Bb', ScaleForm.major)), 'B♭');
      expect(keyLabel(ScaleMaterial('F#', ScaleForm.naturalMinor)), 'F♯m');
      expect(keyLabel(ArpeggioMaterial('C', ArpeggioQuality.minor)), 'Cm');
    });

    test('an altered form in full, never shortened to look like a major', () {
      expect(
        keyLabel(ScaleMaterial('D', ScaleForm.harmonicMinor)),
        'D harmonic minor',
      );
      expect(isMinorKey(ScaleMaterial('D', ScaleForm.harmonicMinor)), isTrue);
    });

    test('sections and hand marks read as a learner would say them', () {
      final progress = goalProgressOf(
        resolved('KEY_FLUENCY_24'),
        ScopeCoverage(coveredTargetIds: const {}, targetCount: 48),
      );

      expect(
        [for (final section in progress.sections) sectionName(section)],
        ['Scales', 'Arpeggios'],
      );
      expect(handsMark(HandConfiguration.left), 'LH');
    });
  });
}
