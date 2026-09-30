import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  RankTieCensus census() => censusRankTies(
    player: PlayerArchetypes.advanced,
    seed: 0,
    materials: v1ScaleCatalog,
    slots: 30,
  );

  test('every tie it reports is one candidate order decided', () {
    final found = census();

    expect(found.ties, isNotEmpty);
    for (final tie in found.ties) {
      expect(
        v1SchedulerConfig.rankTolerances.compare(
          tie.winner.rankKey!,
          tie.reversed.rankKey!,
        ),
        0,
        reason: 'slot ${tie.slot} is tied on every rank term',
      );
      expect(identical(tie.winner, tie.reversed), isFalse);
      expect(tie.tied, greaterThanOrEqualTo(2));
    }
  });

  test('observes without changing what was chosen', () {
    final plain = runTrajectory(
      player: PlayerArchetypes.advanced,
      seed: 0,
      materials: v1ScaleCatalog,
      slots: 30,
    );

    expect(
      [for (final slot in census().trajectory!.slots) slot.chosen],
      [for (final slot in plain.slots) slot.chosen],
    );
  });

  group('under a goal', () {
    test(
      'reports ties the goal left to order, with each side\'s role',
      () async {
        final found = await censusGoalRankTies(
          scope: GoalTrajectoryScope.foundations,
          player: PlayerArchetypes.developing,
          seed: 0,
          sessions: 2,
          slotsPerSession: 10,
        );

        expect(found.ties, isNotEmpty);
        for (final tie in found.ties) {
          expect(
            v1SchedulerConfig.rankTolerances.compare(
              tie.winner.rankKey!,
              tie.reversed.rankKey!,
            ),
            0,
          );
          expect({
            tie.winnerRole,
            tie.reversedRole,
          }, everyElement(isIn(['target', 'in scope'])));
        }
      },
    );

    test('observing a goal trajectory changes nothing it chooses', () async {
      List<(String, HandConfiguration, int, ExerciseDirection)> chosen(
        GoalTrajectoryRun run,
      ) => [
        for (final selection in run.selections)
          (
            selection.materialId,
            selection.hands,
            selection.octaves,
            selection.direction,
          ),
      ];
      Future<GoalTrajectoryRun> run({bool observed = false}) =>
          runGoalTrajectory(
            scope: GoalTrajectoryScope.foundations,
            player: PlayerArchetypes.developing,
            seed: 0,
            sessions: 2,
            slotsPerSession: 10,
            observeSlot: observed ? (_, _, _, _) {} : null,
          );

      expect(chosen(await run(observed: true)), chosen(await run()));
    });
  });
}
