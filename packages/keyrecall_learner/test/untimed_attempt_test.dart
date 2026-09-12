import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// The motor competencies an unguided right-hand scale can teach.
Iterable<Competency> motorCompetenciesOf(Exercise exercise) => [
  for (final competency in exercise.structuralQ)
    if (!competency.isTopology &&
        !coordinationCompetencies.contains(competency))
      competency,
];

/// An attempt played as badly as the timing scores can read.
Outcome timedPoorly() => Outcome(
  started: true,
  retrieval: FactualRetrieval.succeeded,
  completed: true,
  materialRetrieval: 1.0,
  pitchIntegrity: 1.0,
  continuity: 0.0,
  temporalStability: 0.0,
  achievedTempoRatio: 1.0,
  topologyAccuracy: 1.0,
);

void main() {
  final exercise = exerciseFor(cMajor);

  group('an attempt that measured no timing', () {
    test('carries no motor score rather than a zero one', () {
      expect(untimedOutcome().motorScore, isNull);
      expect(timedPoorly().motorScore, 0.0);
    });

    test('carries no motor evidence', () {
      final weights = evidenceWeightsFor(exercise, untimedOutcome());
      expect(weights.materialExecution, 0.0);
      for (final competency in motorCompetenciesOf(exercise)) {
        expect(weights[competency], 0.0);
      }
    });

    test('still carries topology and memory evidence', () {
      final weights = evidenceWeightsFor(exercise, untimedOutcome());
      expect(weights.materialMemory, greaterThan(0.0));
      expect(weights[Competency.majorScaleTopology], greaterThan(0.0));
    });

    test('moves no motor competency and no execution residual', () {
      final state = model.newState(at: t0);
      final before = {
        for (final competency in motorCompetenciesOf(exercise))
          competency: state.competency(competency).mean,
      };
      MaterialExecutionState residual() => state.materialExecutionFor(
        executionContextOf(exercise),
        t0,
        params,
        familyId: TechnicalMaterial.scaleFamilyId,
      );
      final residualBefore = residual().residualMean;

      applyAttempt(state, exercise, untimedOutcome(), at: t0.plusDays(1));

      for (final MapEntry(key: competency, value: mean) in before.entries) {
        expect(state.competency(competency).mean, mean);
      }
      expect(residual().residualMean, residualBefore);
    });

    test('demonstrates no execution frontier', () {
      expect(model.executionWasManaged(untimedOutcome()), isFalse);
    });

    test('is rejected as motor evidence it never was', () {
      final state = model.newState(at: t0);
      final outcome = untimedOutcome();
      expect(
        () => model.validateTransition(
          state: state,
          exercise: exercise,
          outcome: outcome,
          weights: evidenceWeightsFor(exercise, perfectOutcome()),
          at: t0.plusDays(1),
        ),
        throwsArgumentError,
      );
    });

    test('is read on its pitches alone as practice', () {
      expect(untimedOutcome().practiceQuality, 1.0);
      expect(timedPoorly().practiceQuality, closeTo(1 / 3, 1e-12));
    });
  });

  group('an attempt whose timing was measured and poor', () {
    test('carries motor evidence at full weight', () {
      final weights = evidenceWeightsFor(exercise, timedPoorly());
      expect(weights.materialExecution, greaterThan(0.0));
      for (final competency in motorCompetenciesOf(exercise)) {
        expect(weights[competency], greaterThan(0.0));
      }
    });

    test('moves the motor competencies down', () {
      final state = model.newState(at: t0);
      final competency = motorCompetenciesOf(exercise).first;
      final before = state.competency(competency).mean;

      applyAttempt(state, exercise, timedPoorly(), at: t0.plusDays(1));

      expect(state.competency(competency).mean, lessThan(before));
    });
  });
}
