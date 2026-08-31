import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// What makes a hand ready for the other one to join it.
///
/// A different claim from the execution frontier beside it, on a different
/// channel and at a different tempo, and the distinctions are the point.
void main() {
  const model = LearnerModel();
  final material = v1ScaleCatalog.first;

  Exercise at(double tempoBpm) => Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    octaves: 1,
    tempoBpm: tempoBpm,
  );

  MaterialExecutionState after(Exercise exercise, Outcome outcome) {
    final state = model.placementState(PlacementTier.someExperience, at: t0);
    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: model.predict(state, exercise, at: t0),
      at: t0,
    );
    return state.materialExecution[(
      material.materialId,
      HandConfiguration.right,
      HandMotion.parallel,
    )]!;
  }

  Outcome played({
    required double pitchIntegrity,
    required double motorScore,
    required double tempoRatio,
    bool completed = true,
  }) => Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: completed,
    materialRetrieval: pitchIntegrity,
    pitchIntegrity: pitchIntegrity,
    continuity: motorScore,
    temporalStability: motorScore,
    achievedTempoRatio: tempoRatio,
    topologyAccuracy: pitchIntegrity,
  );

  test('right notes played unevenly are ready', () {
    // The learner the separation exists for. Below the frontier's motor bar,
    // so nothing about progression moves, and the notes are known.
    final residual = after(
      at(60),
      played(pitchIntegrity: 1.0, motorScore: 0.3, tempoRatio: 1.0),
    );

    expect(residual.coordinationReadyTempoAt(1), greaterThan(0));
    expect(
      residual.demonstratedTempoAt(1),
      0,
      reason: 'and the frontier is untouched, which is the whole point',
    );
  });

  test('wrong notes played smoothly are not', () {
    final residual = after(
      at(60),
      played(pitchIntegrity: 0.4, motorScore: 1.0, tempoRatio: 1.0),
    );

    expect(residual.coordinationReadyTempoAt(1), 0);
  });

  test('and neither is an attempt that never got through', () {
    // `completed` carries the minimum execution requirement, which is why no
    // second motor threshold is needed beside the pitch one.
    final residual = after(
      at(60),
      played(
        pitchIntegrity: 1.0,
        motorScore: 0.9,
        tempoRatio: 1.0,
        completed: false,
      ),
    );

    expect(residual.coordinationReadyTempoAt(1), 0);
  });

  group('the tempo it records', () {
    test('is what was played, not what was asked', () {
      // Asked for sixty, played at about a hundred and twenty. Recording the
      // request would start coordination work below sixty for somebody
      // demonstrably twice that.
      final residual = after(
        at(60),
        played(pitchIntegrity: 1.0, motorScore: 0.9, tempoRatio: 2.0),
      );

      expect(residual.coordinationReadyTempoAt(1), 120);
    });

    test('including when that is slower than the request', () {
      final residual = after(
        at(120),
        played(pitchIntegrity: 1.0, motorScore: 0.9, tempoRatio: 0.5),
      );

      expect(residual.coordinationReadyTempoAt(1), 60);
    });

    test('while the frontier still records the request', () {
      // The two rules are opposite on purpose: a rung is earned by being asked
      // for it, and coordination begins where the hand actually is.
      final residual = after(
        at(60),
        played(pitchIntegrity: 1.0, motorScore: 1.0, tempoRatio: 2.0),
      );

      expect(residual.demonstratedTempoAt(1), 60);
      expect(residual.coordinationReadyTempoAt(1), 120);
    });
  });
}
