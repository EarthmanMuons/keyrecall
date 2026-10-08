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
  final sessions = LongitudinalSchedules.named('normal_month', slots: 12);

  Trajectory run(
    SyntheticPlayer player,
    SchedulerPipeline pipeline, {
    int seed = 4,
    void Function(int slot, DoseDecision dose)? observeDose,
  }) => runTrajectorySessions(
    player: player,
    seed: seed,
    materials: v1ScaleCatalog,
    sessions: sessions,
    pipeline: pipeline,
    observeDose: observeDose,
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

  test('a learner whose coordination never yields is held back from it', () {
    // The contraction is asserted directly, because it can hold back hands
    // together without changing the run: a slot whose winner was never going
    // to be hands together chooses the same thing either way. How often it
    // does change the run is a characterization of these ten seeds, not a
    // guarantee; seven of them change under the current scheduler.
    final player = PlayerArchetypes.coordinationLimited;
    var changed = 0;
    for (var seed = 0; seed < 10; seed++) {
      bool heldBack(SchedulerPipeline pipeline, List<Exercise> into) {
        var contracted = false;
        into.addAll(
          chosen(
            run(
              player,
              pipeline,
              seed: seed,
              observeDose: (_, dose) => contracted |=
                  dose.disposition == DoseDisposition.contracted &&
                  dose.contracted.containsKey('hands:together'),
            ),
          ),
        );
        return contracted;
      }

      final dosed = <Exercise>[];
      final undosed = <Exercise>[];
      expect(heldBack(dosing, dosed), isTrue, reason: 'seed $seed');
      expect(heldBack(baseline, undosed), isFalse, reason: 'seed $seed');
      if (dosed.length != undosed.length ||
          [
            for (var i = 0; i < dosed.length; i++) dosed[i] == undosed[i],
          ].contains(false)) {
        changed++;
      }
    }

    expect(changed, greaterThanOrEqualTo(5));
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
