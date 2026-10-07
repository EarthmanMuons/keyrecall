import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/goal_progress.dart';
import 'package:keyrecall/features/practice/goal_progress_screen.dart';
import 'package:keyrecall/features/practice/goal_feedback.dart';

void main() {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];

  List<GoalTarget> resolved(
    String goalId, {
    PracticeFocus focus = PracticeFocus.unrestricted,
  }) => PracticeScopeResolver().targetsOf(
    goal: goalId == PracticeGoal.generalFluency.id
        ? PracticeGoal.generalFluency
        : supportedGoals[goalId]!,
    focus: focus,
    catalog: catalog,
  )!;

  Set<String> targetIdsOf(List<GoalTarget> targets) => {
    for (final target in targets) target.requirement.id,
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
    final cMajorRight = scope
        .firstWhere(
          (target) =>
              target.material == ScaleMaterial('C', ScaleForm.major) &&
              target.requirement.constraints.hands == HandConfiguration.right,
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
    final scope = resolved(general.id, focus: focus);

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

  group('choosing a layout', () {
    GoalProgressCell cell(
      HandConfiguration? hands, {
      int octaves = 1,
      bool covered = false,
    }) => GoalProgressCell(
      constraints: ExerciseConstraints(
        hands: hands,
        octaves: octaves,
        direction: ExerciseDirection.upDown,
      ),
      covered: covered,
    );

    GoalProgressSection sectionOf(List<GoalProgressCell> cells) =>
        GoalProgressSection(
          familyId: TechnicalMaterial.scaleFamilyId,
          rows: [
            GoalProgressRow(
              material: ScaleMaterial('C', ScaleForm.major),
              cells: cells,
            ),
          ],
        );

    test('the production goals keep their compact layouts', () {
      GoalProgressLayout only(String goalId, int targets) => layoutOf(
        goalProgressOf(
          resolved(goalId),
          ScopeCoverage(coveredTargetIds: const {}, targetCount: targets),
        ).sections.first,
      );

      expect(only('FOUNDATIONS', 20), GoalProgressLayout.handRows);
      expect(only('KEY_FLUENCY_24', 48), GoalProgressLayout.keyGrid);
    });

    test('hands that do not tell targets apart fall back to naming them', () {
      final section = sectionOf([
        cell(HandConfiguration.right),
        cell(HandConfiguration.right, octaves: 2),
      ]);

      expect(layoutOf(section), GoalProgressLayout.targetList);
      expect(
        [
          for (final c in section.rows.single.cells)
            targetShapeName(c.constraints),
        ],
        [
          'Right hand, 1 octave, up and down',
          'Right hand, 2 octaves, up and down',
        ],
      );
    });

    test('a target naming no hands falls back as well', () {
      expect(
        layoutOf(sectionOf([cell(null), cell(HandConfiguration.left)])),
        GoalProgressLayout.targetList,
      );
    });

    test('a family this build cannot name is called by its id', () {
      expect(
        sectionName(GoalProgressSection(familyId: 'CHORD', rows: const [])),
        'CHORD',
      );
    });
  });

  group('what counts, as the page says it', () {
    test('from memory only where every target asks for it', () {
      final foundations = goalProgressOf(
        resolved('FOUNDATIONS'),
        ScopeCoverage(coveredTargetIds: const {}, targetCount: 20),
      );
      final general = goalProgressOf(
        resolved(
          PracticeGoal.generalFluency.id,
          focus: PracticeFocus(
            exclusiveRequirementIds: {
              catalogRequirementId(
                PracticeGoal.generalFluency.id,
                ScaleMaterial('C', ScaleForm.major).materialId,
              ),
            },
          ),
        ),
        ScopeCoverage(coveredTargetIds: const {}, targetCount: 1),
      );

      expect(foundations.fromMemory, isTrue);
      expect(progressExplanation(foundations), contains('from memory'));
      expect(general.fromMemory, isFalse);
      expect(progressExplanation(general), isNot(contains('from memory')));
    });
  });

  testWidgets('the key grid puts several keys on a row at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scales = goalProgressOf(
      resolved('KEY_FLUENCY_24'),
      ScopeCoverage(coveredTargetIds: const {}, targetCount: 48),
    ).sections.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GoalProgressSectionView(scales),
          ),
        ),
      ),
    );

    final [first, second, ...] = [
      for (final row in scales.rows)
        if (!isMinorKey(row.material)) keyLabel(row.material),
    ];
    final a = tester.getRect(find.text(first));
    final b = tester.getRect(find.text(second));
    expect(b.top, a.top, reason: 'neighboring keys share a run');
    expect(b.left, greaterThan(a.right), reason: 'side by side, not stacked');
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text(first),
                  matching: find.byType(Container),
                )
                .first,
          )
          .width,
      lessThan(100),
      reason: 'a mark is the size of its label, not of the run',
    );
  });
}
