import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// Execution evidence is attributed at the difficulty an attempt actually
/// demonstrated. Everything else is attributed to the exercise that was asked
/// for.
void main() {
  const model = LearnerModel();
  final at = t0.add(const Duration(days: 1));

  Exercise atTempo(double bpm) => Exercise.linear(
    material: cMajor,
    hands: HandConfiguration.right,
    tempoBpm: bpm,
  );

  Outcome cleanAt(double tempoRatio) => Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 1.0,
    pitchIntegrity: 1.0,
    continuity: 1.0,
    temporalStability: 1.0,
    achievedTempoRatio: tempoRatio,
    topologyAccuracy: 1.0,
  );

  /// Runs one attempt and returns the execution competency afterwards.
  double executionAfter(Exercise exercise, Outcome outcome) {
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

  group('the tempo an attempt demonstrated', () {
    test('is the requested one when it was played at that tempo', () {
      final exercise = atTempo(120);
      expect(model.demonstratedTempoBpm(exercise, cleanAt(1.0)), 120);
    });

    test('is the achieved one when it was played slower', () {
      final exercise = atTempo(120);
      expect(model.demonstratedTempoBpm(exercise, cleanAt(0.5)), 60);
    });

    test('is capped at the requested one when it was played faster', () {
      final exercise = atTempo(120);
      expect(
        model.demonstratedTempoBpm(exercise, cleanAt(2.0)),
        120,
        reason:
            'the scheduler chose the challenge, and a sprint through one '
            'attempt is not an unscheduled harder probe',
      );
    });

    test('falls back to the requested one when there was no pace to read', () {
      final exercise = atTempo(120);
      expect(model.demonstratedTempoBpm(exercise, cleanAt(0.0)), 120);
    });
  });

  group('what that changes', () {
    test('a clean run at the requested tempo behaves as it always did', () {
      final exercise = atTempo(120);
      final outcome = cleanAt(1.0);
      final state = model.placementState(PlacementTier.someExperience, at: t0);
      model.propagate(state, at);

      expect(
        model.demonstratedExecutionProbability(state, exercise, outcome),
        model.executionProbability(state, exercise),
      );
    });

    test('a clean run at half tempo credits less', () {
      final exercise = atTempo(120);

      expect(
        executionAfter(exercise, cleanAt(0.5)),
        lessThan(executionAfter(exercise, cleanAt(1.0))),
        reason:
            'the easier task was the one demonstrated, so the surprise at '
            'succeeding is smaller',
      );
    });

    test('playing faster credits no more than the tempo asked for', () {
      final exercise = atTempo(120);

      expect(
        executionAfter(exercise, cleanAt(2.0)),
        executionAfter(exercise, cleanAt(1.0)),
      );
    });

    test('the same motor quality at different tempos lands differently', () {
      final exercise = atTempo(120);
      final slow = executionAfter(exercise, cleanAt(0.5));
      final asked = executionAfter(exercise, cleanAt(1.0));

      expect(slow, isNot(asked));
      expect(
        slow,
        lessThan(asked),
        reason: 'identical scores, different difficulty coordinates',
      );
    });

    test('leaves memory evidence alone', () {
      final exercise = atTempo(120);

      double durabilityAfter(double ratio) {
        final state = model.placementState(
          PlacementTier.someExperience,
          at: t0,
        );
        model.propagate(state, at);
        final outcome = cleanAt(ratio);
        model.applyOutcome(
          state: state,
          exercise: exercise,
          outcome: outcome,
          weights: evidenceWeightsFor(exercise, outcome),
          prediction: model.predict(state, exercise, at: at),
          at: at,
        );
        return state.materialMemory[cMajor.materialId]!.currentHalfLifeDays;
      }

      expect(
        durabilityAfter(0.5),
        durabilityAfter(1.0),
        reason: 'playing C major slowly is still recalling C major',
      );
    });
  });

  test('the prototype model records achieved tempo without consuming it', () {
    const prototype = LearnerModel.v1Prototype();
    final exercise = atTempo(120);

    expect(prototype.demonstratedTempoBpm(exercise, cleanAt(0.5)), 120);
  });
}
