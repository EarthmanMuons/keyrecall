import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];

  test('every census scope resolves to a practice scope', () {
    for (final scope in GoalTrajectoryScope.values) {
      final plan = scope.plan.resolve(catalog) as ResolvedPlan;
      expect(
        PracticeScopeResolver().resolve(
          goal: plan.goal,
          focus: plan.focus,
          catalog: catalog,
          instrument: InstrumentProfile(),
        ),
        isA<ValidPracticeScope>(),
        reason: scope.name,
      );
      expect(scope.plan.isFocused, scope.name.contains('Focused'));
    }
  });

  test('a run sits once a day and reads coverage back from history', () async {
    final run = await runGoalTrajectory(
      scope: GoalTrajectoryScope.foundations,
      player: PlayerArchetypes.intermediate,
      seed: 0,
      sittings: 2,
      slotsPerSitting: 10,
    );

    expect(run.targetCount, 20);
    expect(run.sittings, hasLength(2));
    expect({for (final pick in run.selections) pick.sitting}, {0, 1});
    expect(run.selections.every((pick) => pick.isTarget), isTrue);
  });
}
