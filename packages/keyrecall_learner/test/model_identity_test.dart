import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// A model version names one transition function.
///
/// It is what an attempt records and what replay refuses to reinterpret under,
/// so two models that learn differently must not share one. Storing the
/// semantics beside the version would let them disagree; reading them out of
/// it is what makes the disagreement unrepresentable.
void main() {
  final at = t0.plusDays(1);

  Exercise atTempo(double bpm) => Exercise.linear(
    material: cMajor,
    hands: HandConfiguration.together,
    tempoBpm: bpm,
  );

  /// One slow but clean attempt, which the two models attribute differently.
  Outcome played(double tempoRatio) => Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 1.0,
    pitchIntegrity: 1.0,
    continuity: 1.0,
    temporalStability: 1.0,
    achievedTempoRatio: tempoRatio,
    topologyAccuracy: 1.0,
    coordination: 0.4,
  );

  double executionAfter(LearnerModel model) {
    final exercise = atTempo(120);
    final outcome = played(0.5);
    final state = model.placementState(PlacementTier.someExperience, at: t0);
    model.propagate(state, at);
    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: model.predict(state, exercise, at: at),
      at: at,
    );
    return state.competency(Competency.rhScaleExecution).mean;
  }

  test('one version is one set of semantics', () {
    const named = LearnerModel.v1Prototype();
    const byParams = LearnerModel(params: v1PrototypeLearnerParams);

    expect(byParams.params.modelVersion, named.params.modelVersion);
    expect(
      byParams.attributesDemonstratedDifficulty,
      named.attributesDemonstratedDifficulty,
    );
    expect(
      byParams.includesCoordinationInChallenge,
      named.includesCoordinationInChallenge,
    );
    expect(executionAfter(byParams), executionAfter(named));
  });

  test('models that learn differently carry different versions', () {
    const live = LearnerModel();
    const prototype = LearnerModel.v1Prototype();

    expect(
      executionAfter(live),
      isNot(executionAfter(prototype)),
      reason: 'the two attribute a slow performance differently',
    );
    expect(live.params.modelVersion, isNot(prototype.params.modelVersion));
  });

  test('the live version is not the prototype under another name', () {
    expect(const LearnerModel().attributesDemonstratedDifficulty, isTrue);
    expect(const LearnerModel().includesCoordinationInChallenge, isTrue);
  });
}
