import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// A pulse the app supplied while the attempt ran narrows what its timing
/// says: execution was still managed, and the learner did not keep time alone.
void main() {
  const model = LearnerModel();
  final at = t0.add(const Duration(days: 1));
  final exercise = Exercise.linear(
    material: cMajor,
    hands: HandConfiguration.right,
    tempoBpm: 100,
  );

  Outcome played({
    required PulseMaintenance pulse,
    double temporalStability = 1.0,
    double tempoRatio = 1.0,
  }) => Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 1.0,
    pitchIntegrity: 1.0,
    continuity: 1.0,
    temporalStability: temporalStability,
    achievedTempoRatio: tempoRatio,
    topologyAccuracy: 1.0,
    pulseMaintenance: pulse,
  );

  MaterialExecutionState residualAfter(Outcome outcome) {
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
    return state.materialExecution[executionContextOf(exercise)]!;
  }

  group('the motor score', () {
    test('reads steadiness the learner kept', () {
      final outcome = played(
        pulse: PulseMaintenance.tested,
        temporalStability: 0.2,
      );

      expect(outcome.motorScore, closeTo(0.6, 1e-12));
    });

    test('leaves out steadiness a supplied pulse lent', () {
      final outcome = played(
        pulse: PulseMaintenance.notTested,
        temporalStability: 0.2,
      );

      expect(outcome.motorScore, 1.0);
      expect(outcome.temporalStability, 0.2);
    });
  });

  test('practice quality counts steadiness either way', () {
    expect(
      played(
        pulse: PulseMaintenance.notTested,
        temporalStability: 0.2,
      ).practiceQuality,
      played(
        pulse: PulseMaintenance.tested,
        temporalStability: 0.2,
      ).practiceQuality,
    );
  });

  group('the pace the learner chose', () {
    test('is the measured one when they held the pulse', () {
      expect(
        played(
          pulse: PulseMaintenance.tested,
          tempoRatio: 1.3,
        ).chosenTempoRatio,
        1.3,
      );
    });

    test('is absent under a supplied pulse, which set the pace', () {
      final outcome = played(
        pulse: PulseMaintenance.notTested,
        tempoRatio: 1.3,
      );

      expect(outcome.chosenTempoRatio, isNull);
      expect(outcome.measuredTempoRatio, 1.3);
    });
  });

  group('a managed attempt under a supplied pulse', () {
    test('still moves the execution frontier', () {
      final residual = residualAfter(played(pulse: PulseMaintenance.notTested));

      expect(residual.demonstratedTempoAt(1), 100);
    });

    test('records no pace for unseen material to start near', () {
      final supplied = residualAfter(
        played(pulse: PulseMaintenance.notTested, tempoRatio: 1.3),
      );
      final held = residualAfter(
        played(pulse: PulseMaintenance.tested, tempoRatio: 1.3),
      );

      expect(supplied.pacedTempoBpm, 0);
      expect(held.pacedTempoBpm, greaterThan(100));
    });
  });
}
