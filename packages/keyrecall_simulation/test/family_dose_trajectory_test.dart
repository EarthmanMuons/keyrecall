import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What dose control does to a whole trajectory.
///
/// The strength of a contraction is not asserted anywhere; these are the
/// properties that hold whatever it is set to.
void main() {
  const learner = LearnerModel();
  // The V1 policy carries dose control, so the arm without it is the one that
  // has to be built.
  final baseline = SchedulerPipeline(
    learner: learner,
    config: v1SchedulerConfig.withDose(null),
  );
  const dosing = SchedulerPipeline(learner: learner);
  final sittings = LongitudinalSchedules.named('normal_month', slots: 12);

  Trajectory run(SyntheticPlayer player, SchedulerPipeline pipeline) =>
      runSittings(
        player: player,
        seed: 4,
        materials: v1ScaleCatalog,
        sittings: sittings,
        pipeline: pipeline,
      );

  List<Exercise> chosen(Trajectory trajectory) => [
    for (final slot in trajectory.slots) slot.chosen,
  ];

  test('a learner whose families all yield practises the same run', () {
    // The mechanism reads yield, so a learner who produces managed execution
    // almost every attempt must never meet it. Anything else is dose control
    // perturbing learners it has nothing to say about.
    final player = PlayerArchetypes.advanced;

    expect(chosen(run(player, dosing)), chosen(run(player, baseline)));
  });

  test(
    'a learner whose coordination never yields practises a different one',
    () {
      final player = PlayerArchetypes.coordinationLimited;

      expect(chosen(run(player, dosing)), isNot(chosen(run(player, baseline))));
    },
  );

  test('contraction never empties a slot', () {
    for (final player in PlayerArchetypes.all) {
      final trajectory = run(player, dosing);

      expect(
        trajectory.terminals,
        isEmpty,
        reason: '${player.id} was left with nothing to practise',
      );
    }
  });

  test('a contracted family is asked for less, never never', () {
    final trajectory = run(PlayerArchetypes.coordinationLimited, dosing);
    final exposures = familyExposures(trajectory);
    final together = exposures.firstWhere(
      (exposure) => exposure.family == 'hands:together',
    );

    expect(together.attempts, greaterThan(0));
  });
}
