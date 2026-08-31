import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final together = Exercise.linear(
    material: materials.first,
    hands: HandConfiguration.together,
    octaves: 1,
    direction: ScaleDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );
  final right = Exercise.linear(
    material: materials.first,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ScaleDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );

  LearnerState readyState() {
    final state = learner.newState(at: t0);
    for (final competency in motorCompetencies) {
      state.competency(competency).mean = 2.0;
    }
    state.competency(Competency.handsTogetherCoordination).mean = 2.0;
    return state;
  }

  test('coordination changes only hands-together challenge probability', () {
    final state = readyState();
    final rightBefore = learner.predict(state, right, at: t0);
    final togetherBefore = learner.predict(state, together, at: t0);

    state.competency(Competency.handsTogetherCoordination).mean = -2.0;
    final rightAfter = learner.predict(state, right, at: t0);
    final togetherAfter = learner.predict(state, together, at: t0);

    expect(rightBefore.coordinationP, 1.0);
    expect(rightAfter.overallP, rightBefore.overallP);
    expect(togetherAfter.coordinationP, lessThan(togetherBefore.coordinationP));
    expect(togetherAfter.overallP, lessThan(togetherBefore.overallP));
    expect(togetherAfter.executionP, togetherBefore.executionP);
    expect(togetherAfter.materialAvailableP, togetherBefore.materialAvailableP);
  });

  test('motor execution and coordination remain separate factors', () {
    final state = readyState();
    final before = learner.predict(state, together, at: t0);

    for (final competency in motorCompetencies) {
      state.competency(competency).mean = 1.0;
    }
    final after = learner.predict(state, together, at: t0);

    expect(after.executionP, lessThan(before.executionP));
    expect(after.coordinationP, before.coordinationP);
    expect(
      before.overallP,
      closeTo(
        before.materialAvailableP *
            math.min(before.executionP, before.coordinationP),
        1e-12,
      ),
    );
  });

  test('direct evidence can move HT work out of and back into the band', () {
    final state = readyState();
    final adverse = _coordinationOutcome(0.0);
    final favorable = _coordinationOutcome(1.0);

    expect(
      pipeline.isWithinChallengeBand(learner.predict(state, together, at: t0)),
      isTrue,
    );

    var attempts = 0;
    while (pipeline.isWithinChallengeBand(
      learner.predict(state, together, at: t0),
    )) {
      _applyCoordination(state, together, adverse);
      expect(++attempts, lessThan(100));
    }

    while (!pipeline.isWithinChallengeBand(
      learner.predict(state, together, at: t0),
    )) {
      _applyCoordination(state, together, favorable);
      expect(++attempts, lessThan(200));
    }
  });
}

Outcome _coordinationOutcome(double coordination) => Outcome(
  started: true,
  retrieval: FactualRetrieval.notTested,
  completed: true,
  materialRetrieval: 1.0,
  pitchIntegrity: 1.0,
  continuity: 1.0,
  temporalStability: 1.0,
  achievedTempoRatio: 1.0,
  topologyAccuracy: 1.0,
  coordination: coordination,
);

void _applyCoordination(
  LearnerState state,
  Exercise exercise,
  Outcome outcome,
) {
  learner.applyOutcome(
    state: state,
    exercise: exercise,
    outcome: outcome,
    weights: EvidenceWeights(
      competencies: {Competency.handsTogetherCoordination: 1.0},
      materialExecution: 0.0,
      materialMemory: 0.0,
    ),
    prediction: learner.predict(state, exercise, at: t0),
    at: t0,
  );
}
