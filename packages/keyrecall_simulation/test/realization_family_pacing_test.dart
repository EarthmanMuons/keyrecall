import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

const int seeds = 4;
const int slots = 40;

/// The shipped policy, which paces behind the readiness gate.
const SchedulerPipeline paced = SchedulerPipeline(learner: LearnerModel());

final SchedulerPipeline unpaced = SchedulerPipeline(
  learner: const LearnerModel(),
  config: v1SchedulerConfig.withPacing(null),
);

void main() {
  group('trajectory invariants', () {
    for (final player in PlayerArchetypes.all) {
      test('${player.id} keeps pacing inside admission', () {
        for (var seed = 0; seed < seeds; seed++) {
          final log = PacingLog();
          final trajectory = _run(seed, player, paced, log: log);
          for (final slot in trajectory.slots) {
            expect(
              slot.winner.isRanked,
              isTrue,
              reason: 'slot ${slot.index} chose an unadmitted exercise',
            );
            expect(
              slot.candidates.selectable,
              greaterThan(0),
              reason: 'slot ${slot.index} was left with nothing selectable',
            );
          }
          for (final setAside in log.setAsides) {
            expect(setAside.isRelievable, isTrue);
            expect(setAside.pressured.isRanked, isTrue);
            expect(setAside.relieving.isRanked, isTrue);
          }
          if (log.setAsides.isEmpty) {
            expect(
              [for (final slot in trajectory.slots) slot.chosen],
              [
                for (final slot in _run(seed, player, unpaced).slots)
                  slot.chosen,
              ],
              reason: 'seed $seed formed no pressure',
            );
          }
        }
      });
    }
  });
}

Trajectory _run(
  int seed,
  SyntheticPlayer player,
  SchedulerPipeline pipeline, {
  PacingLog? log,
}) => runTrajectory(
  player: player,
  seed: seed,
  materials: v1ScaleCatalog,
  slots: slots,
  pipeline: pipeline,
  observePacing: log == null ? null : (_, decision) => log.record(decision),
);
