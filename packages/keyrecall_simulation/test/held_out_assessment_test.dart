import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final catalog = v1ScaleCatalog.take(4).toList();
  final set = standardAssessment(catalog, repetitions: 2);

  List<TrajectorySlot> slotsOf(Trajectory trajectory) => trajectory.slots;

  test('taking a reading cannot change the run it measures', () {
    Trajectory run({AssessmentSet? assessment}) => runSittings(
      player: PlayerArchetypes.developing,
      seed: 3,
      materials: catalog,
      sittings: sittingsOnDays([0, 3, 21], slots: 10),
      assessment: assessment,
    );

    final measured = run(assessment: set);
    final unmeasured = run();

    expect(measured.assessments, hasLength(6));
    expect(unmeasured.assessments, isEmpty);
    expect(
      slotsOf(measured).map((s) => s.chosen),
      slotsOf(unmeasured).map((s) => s.chosen),
    );
    expect(
      slotsOf(measured).map((s) => s.outcome.motorScore),
      slotsOf(unmeasured).map((s) => s.outcome.motorScore),
    );
    expect(
      slotsOf(measured).map((s) => s.performedTempoBpm),
      slotsOf(unmeasured).map((s) => s.performedTempoBpm),
    );
  });

  test('a reading answers about the player, not about the questions asked', () {
    final unchanging = PlayerArchetypes.advanced.copyWith(learningRate: 0);
    final trajectory = runSittings(
      player: unchanging,
      seed: 1,
      materials: catalog,
      sittings: sittingsOnDays([0, 1], slots: 8),
      assessment: set,
    );

    final readings = trajectory.assessments;
    expect(readings, hasLength(4));
    expect(readings.first.attempts, set.attempts);
    expect(
      readings.map((r) => r.managed).toSet(),
      hasLength(1),
      reason: 'the same set and the same draws of a player who cannot change',
    );
    expect(readings.map((r) => r.retrieval).toSet(), hasLength(1));
    expect(readings.first.coordination, isNotNull);
  });

  test('practice the run chose moves what the held-out set finds', () {
    final learning = PlayerArchetypes.developing.copyWith(learningRate: 0.2);
    final readings = runSittings(
      player: learning,
      seed: 4,
      materials: catalog,
      sittings: sittingsOnDays([0, 1, 2, 3], slots: 25),
      assessment: set,
    ).assessments;

    expect(
      readings.last.managed,
      greaterThan(readings.first.managed),
      reason: 'held-out execution improves when the person does',
    );
    expect(readings.map((r) => r.afterSlots), [
      0,
      25,
      25,
      50,
      50,
      75,
      75,
      100,
    ], reason: 'a reading says how much practice preceded it');
  });

  test('a break moves belief without moving the person', () {
    final unchanging = PlayerArchetypes.developing.copyWith(learningRate: 0);
    final readings = runSittings(
      player: unchanging,
      seed: 2,
      materials: catalog,
      sittings: sittingsOnDays([0, 240], slots: 6),
      assessment: set,
    ).assessments;

    final beforeBreak = readings[1];
    final afterBreak = readings[2];
    expect(beforeBreak.afterSlots, afterBreak.afterSlots);

    expect(afterBreak.managed, beforeBreak.managed);
    expect(afterBreak.retrieval, beforeBreak.retrieval);
    expect(
      afterBreak.predicted!,
      lessThan(beforeBreak.predicted!),
      reason: 'the model decays across the gap',
    );
    expect(
      afterBreak.beliefGap!,
      lessThan(beforeBreak.beliefGap!),
      reason:
          'the gap between what the model expects and what the player does '
          'is the quantity a forgetting run has to be judged on',
    );
  });

  test('two policies are compared on the same questions', () {
    Trajectory under(SchedulerPipeline pipeline) => runTrajectory(
      player: PlayerArchetypes.developing.copyWith(learningRate: 0.2),
      seed: 5,
      materials: catalog,
      slots: 60,
      pipeline: pipeline,
      assessment: set,
    );

    const production = SchedulerPipeline(learner: LearnerModel());
    final paced = under(production);
    final undosed = under(
      SchedulerPipeline(
        learner: production.learner,
        config: production.config.withDose(null),
      ),
    );

    expect(
      paced.slots.map((s) => s.chosen),
      isNot(undosed.slots.map((s) => s.chosen)),
      reason: 'the two policies practise different things',
    );
    final first = [paced, undosed].map((t) => t.assessments.first);
    expect(
      first.map((r) => r.managed).toSet(),
      hasLength(1),
      reason: 'both start from the same person answering the same questions',
    );
    expect(first.map((r) => r.setId).toSet(), {set.id});
    expect(first.map((r) => r.attempts).toSet(), {set.attempts});
    for (final trajectory in [paced, undosed]) {
      final gained =
          trajectory.assessments.last.managed -
          trajectory.assessments.first.managed;
      expect(
        gained,
        greaterThan(0),
        reason: 'each policy left the person better at the held-out set',
      );
    }
  });
}
