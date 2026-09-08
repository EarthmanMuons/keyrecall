import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('production selection and outcome updates share their predictor', () {
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 1,
    );
    final agent = SchedulerAgent(
      pipeline: SchedulerPipeline(learner: simulation.learner),
      instrument: InstrumentProfile(),
      materials: v1ScaleCatalog,
    );
    final traces = runSessions(
      simulation,
      agent,
      sessionCount: 1,
      attemptsPerSession: 4,
    );
    expect(simulation.learner.includesCoordinationInChallenge, isTrue);
    expect(simulation.learner.attributesDemonstratedDifficulty, isTrue);
    expect(traces[1].at.difference(traces[0].at), const Duration(minutes: 1));
    for (final (i, trace) in traces.indexed) {
      expect(agent.records[i].selected!.prediction, trace.prediction);
    }
    final history = [...agent.session.recentMaterialIds];
    final families = [...agent.session.recentFamilies];
    agent.startNewSession();
    expect(agent.session.recentMaterialIds, history);
    expect(
      agent.session.recentFamilies.map((f) => f.at),
      families.map((f) => f.at),
    );
    expect(agent.session.attemptsThisSession, 0);
    expect(agent.session.lastFailedExercise, isNull);
    expect(agent.session.tempoProbe, isNull);
  });

  test('a hybrid simulation is rejected before running an attempt', () {
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 1,
      learner: const LearnerModel.v1Prototype(),
    );
    final agent = SchedulerAgent(
      pipeline: const SchedulerPipeline(learner: LearnerModel()),
      instrument: InstrumentProfile(),
      materials: v1ScaleCatalog,
    );
    expect(
      () => runSessions(
        simulation,
        agent,
        sessionCount: 1,
        attemptsPerSession: 1,
      ),
      throwsArgumentError,
    );
    expect(simulation.attemptCount, 0);
    expect(simulation.at, simulation.epoch);
    expect(agent.records, isEmpty);
  });

  test('terminal decisions reserve their own indices across sittings', () {
    final trajectory = runSittings(
      player: PlayerArchetypes.advanced,
      seed: 0,
      materials: [],
      generated: [],
      sittings: sittingsOnDays([0, 1, 2], slots: 2),
    );
    expect(trajectory.terminals.map((t) => t.index), [0, 1, 2]);
    expect(trajectory.terminals.map((t) => t.sitting), [0, 1, 2]);
  });
}
