import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// Parallel and contrary hands-together work keep separate execution records.
///
/// The two are different coordination patterns, so a frontier reached one way
/// must not say the learner has demonstrated the other. Contrary motion is not
/// generated yet, and this is the state semantics that has to hold before it
/// can be.
void main() {
  const model = LearnerModel();
  final material = v1ScaleCatalog.first;

  Exercise together(HandMotion handMotion) => Exercise.linear(
    material: material,
    hands: HandConfiguration.together,
    octaves: 1,
    handMotion: handMotion,
    tempoBpm: 60,
  );

  /// A performance clean enough to move the frontier.
  final managed = Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 1.0,
    pitchIntegrity: 1.0,
    continuity: 1.0,
    temporalStability: 1.0,
    achievedTempoRatio: 1.0,
    topologyAccuracy: 1.0,
  );

  LearnerState afterPlaying(HandMotion handMotion) {
    final state = model.placementState(PlacementTier.someExperience, at: t0);
    final exercise = together(handMotion);
    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: managed,
      weights: evidenceWeightsFor(exercise, managed),
      prediction: model.predict(state, exercise, at: t0),
      at: t0,
    );
    return state;
  }

  MaterialExecutionState? recordOf(LearnerState state, HandMotion handMotion) =>
      state.materialExecution[(
        material.materialId,
        HandConfiguration.together,
        handMotion,
      )];

  test('a contrary attempt moves only the contrary frontier', () {
    final state = afterPlaying(HandMotion.contrary);

    expect(recordOf(state, HandMotion.contrary)!.demonstratedTempoAt(1), 60);
    expect(
      recordOf(state, HandMotion.parallel),
      isNull,
      reason:
          'playing the hands apart says nothing about playing them in '
          'parallel, which the learner has never been asked for',
    );
  });

  test('a parallel attempt moves only the parallel frontier', () {
    final state = afterPlaying(HandMotion.parallel);

    expect(recordOf(state, HandMotion.parallel)!.demonstratedTempoAt(1), 60);
    expect(recordOf(state, HandMotion.contrary), isNull);
  });

  test('the two accumulate independently', () {
    final state = afterPlaying(HandMotion.parallel);
    final contrary = together(HandMotion.contrary);
    model.applyOutcome(
      state: state,
      exercise: contrary,
      outcome: managed,
      weights: evidenceWeightsFor(contrary, managed),
      prediction: model.predict(state, contrary, at: t0),
      at: t0,
    );

    expect(recordOf(state, HandMotion.parallel)!.demonstratedTempoAt(1), 60);
    expect(recordOf(state, HandMotion.contrary)!.demonstratedTempoAt(1), 60);
    expect(
      state.materialExecution.keys
          .where((key) => key.$2 == HandConfiguration.together)
          .length,
      2,
    );
  });

  test('either one answers whether the material has been played together', () {
    // Motion-agnostic on purpose: the coordination transition is once per
    // material, so meeting the scale with both hands either way spends it.
    expect(
      afterPlaying(
        HandMotion.contrary,
      ).hasPlayed(material.materialId, HandConfiguration.together),
      isTrue,
    );
  });
}
