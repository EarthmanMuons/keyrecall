import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// What a rejected transition must leave behind, and what an accepted one must
/// produce.
///
/// Validation that runs partway through an update is worse than none: the
/// caller sees a throw and the state keeps the half of the write that landed
/// before it. Both properties here are asked through the state codec, because
/// the hash is what replay compares and the decoder is what a resumed install
/// has to get past.
void main() {
  final unguided = exerciseFor(v1ScaleCatalogFirst);
  final cued = exerciseFor(
    v1ScaleCatalogFirst,
    guidance: GuidanceContext.continuouslyCued,
  );

  LearnerState freshState() =>
      model.placementState(PlacementTier.someExperience, at: t0);

  Outcome declined() => outcomeOf(
    retrieval: FactualRetrieval.failed,
    started: false,
    completed: false,
    quality: 0.0,
  );

  /// Every way an attempt can be inadmissible, buildable at any instant.
  final inadmissible =
      <
        String,
        ({Exercise exercise, Outcome outcome, EvidenceWeights? weights})
      >{
        'a cued attempt claiming a success': (
          exercise: cued,
          outcome: outcomeOf(),
          weights: null,
        ),
        'a cued attempt claiming a failure': (
          exercise: cued,
          outcome: outcomeOf(retrieval: FactualRetrieval.failed),
          weights: null,
        ),
        'an unguided attempt reporting no retrieval': (
          exercise: unguided,
          outcome: outcomeOf(retrieval: FactualRetrieval.notTested),
          weights: null,
        ),
        'an attempt that never began but completed': (
          exercise: unguided,
          outcome: outcomeOf(started: false),
          weights: null,
        ),
        'an attempt that never began but retrieved': (
          exercise: unguided,
          outcome: outcomeOf(started: false, completed: false),
          weights: null,
        ),
        'memory evidence from an untested retrieval': (
          exercise: cued,
          outcome: outcomeOf(retrieval: FactualRetrieval.notTested),
          weights: EvidenceWeights(
            competencies: const {},
            materialExecution: 0.0,
            materialMemory: 0.4,
          ),
        ),
        'execution evidence from an attempt that never began': (
          exercise: unguided,
          outcome: declined(),
          weights: EvidenceWeights(
            competencies: const {},
            materialExecution: 0.4,
            materialMemory: 0.8,
          ),
        ),
        'competency evidence from an attempt that never began': (
          exercise: unguided,
          outcome: declined(),
          weights: EvidenceWeights(
            competencies: const {Competency.rhScaleExecution: 0.4},
            materialExecution: 0.0,
            materialMemory: 0.8,
          ),
        ),
        'a tempo ratio deriving no finite pace': (
          exercise: unguided,
          outcome: outcomeOf(tempoRatio: 1e308),
          weights: null,
        ),
      };

  group('a rejected transition writes nothing', () {
    for (final entry in inadmissible.entries) {
      final (:exercise, :outcome, :weights) = entry.value;

      test('applyOutcome refuses ${entry.key}', () {
        final state = freshState();
        final before = learnerStateHash(state);

        expect(
          () => model.applyOutcome(
            state: state,
            exercise: exercise,
            outcome: outcome,
            weights: weights ?? evidenceWeightsFor(exercise, outcome),
            prediction: model.predict(state, exercise, at: t0),
            at: t0,
          ),
          throwsArgumentError,
        );
        expect(learnerStateHash(state), before);
      });

      test('propagateAndApplyOutcome refuses ${entry.key}', () {
        // A day later, so propagation would really move every layer's
        // timestamp and variance if it ran against the state itself.
        final at = t0.plusDays(1);
        final state = freshState();
        final before = learnerStateHash(state);

        expect(
          () => model.propagateAndApplyOutcome(
            state: state,
            exercise: exercise,
            outcome: outcome,
            weights: weights ?? evidenceWeightsFor(exercise, outcome),
            prediction: model.predict(
              state.copy()..propagateTo(at, params),
              exercise,
              at: at,
            ),
            at: at,
          ),
          throwsArgumentError,
        );
        expect(
          learnerStateHash(state),
          before,
          reason: 'propagation landed before the attempt was refused',
        );
      });
    }

    test('applyOutcome refuses an attempt the state has not reached', () {
      final state = freshState();
      final before = learnerStateHash(state);
      final at = t0.plusDays(1);

      expect(
        () => model.applyOutcome(
          state: state,
          exercise: unguided,
          outcome: outcomeOf(),
          weights: evidenceWeightsFor(unguided, outcomeOf()),
          prediction: model.predict(state, unguided, at: at),
          at: at,
        ),
        throwsArgumentError,
      );
      expect(learnerStateHash(state), before);
    });
  });

  /// A maximum timestamp says nothing is ahead of the attempt. It says nothing
  /// about a layer left behind, and a layer behind its own evidence is what a
  /// state codec refuses to read back.
  group('one layer out of step is not an aligned state', () {
    final at = t0.plusDays(1);

    void expectRefusedWith(LearnerState state) {
      final before = learnerStateHash(state);
      expect(
        () => model.applyOutcome(
          state: state,
          exercise: unguided,
          outcome: outcomeOf(),
          weights: evidenceWeightsFor(unguided, outcomeOf()),
          prediction: model.predict(state, unguided, at: at),
          at: at,
        ),
        throwsArgumentError,
      );
      expect(learnerStateHash(state), before);
    }

    /// The residual for [unguided], created at [createdAt].
    MaterialExecutionState residualOf(LearnerState state, DateTime createdAt) =>
        state.materialExecutionFor(
          executionContextOf(unguided),
          createdAt,
          params,
          familyId: unguided.material.familyId,
        );

    test('any one competency the others have not caught up with', () {
      for (final competency in Competency.values) {
        final state = freshState();
        state.competency(competency).updatedAt = at;
        expectRefusedWith(state);
      }
    });

    test('an execution residual the competencies have moved past', () {
      final state = freshState();
      model.propagate(state, at);
      residualOf(state, at).updatedAt = t0;
      expectRefusedWith(state);
    });

    test('an execution residual ahead of everything', () {
      final state = freshState();
      model.propagate(state, at);
      residualOf(state, at).updatedAt = at.plusDays(1);
      expectRefusedWith(state);
    });
  });

  test('an attempt that never began leaves execution untouched', () {
    final state = freshState();
    final outcome = declined();
    final before = state.competency(Competency.rhScaleExecution).mean;

    model.applyOutcome(
      state: state,
      exercise: unguided,
      outcome: outcome,
      weights: evidenceWeightsFor(unguided, outcome),
      prediction: model.predict(state, unguided, at: t0),
      at: t0,
    );

    expect(state.competency(Competency.rhScaleExecution).mean, before);
    expect(
      state.hasPlayed(v1ScaleCatalogFirst.materialId, HandConfiguration.right),
      isFalse,
      reason: 'nothing was played, so this hand has not met this material',
    );
    expect(
      state
          .materialMemory[v1ScaleCatalogFirst.materialId]
          ?.lastRetrievalAttemptAt,
      t0,
      reason: 'failing to begin is still a retrieval the learner attempted',
    );
  });

  test('an accepted transition leaves a state its own decoder reads', () {
    final state = freshState();
    final trajectory = [
      (unguided, outcomeOf()),
      (cued, outcomeOf(retrieval: FactualRetrieval.notTested)),
      (unguided, outcomeOf(retrieval: FactualRetrieval.failed, quality: 0.2)),
      (unguided, outcomeOf(tempoRatio: 0.0, completed: false, quality: 0.4)),
      (unguided, declined()),
      (unguided, outcomeOf(quality: 0.99, tempoRatio: 2.4)),
    ];

    for (var index = 0; index < trajectory.length; index++) {
      final (exercise, outcome) = trajectory[index];
      final at = t0.plusDays(1.0 * (index + 1));
      final decidedFrom = state.copy()..propagateTo(at, params);
      model.propagateAndApplyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(decidedFrom, exercise, at: at),
        at: at,
      );

      final reread = decodeLearnerState(
        encodeLearnerState(state),
        params: params,
      );
      expect(learnerStateHash(reread), learnerStateHash(state));
    }
  });

  test('the composite lands exactly what the two halves would', () {
    final separately = freshState();
    final together = freshState();
    final at = t0.plusDays(3);
    final outcome = outcomeOf(quality: 0.7);

    model.propagate(separately, at);
    final prediction = model.predict(separately, unguided, at: at);
    final weights = evidenceWeightsFor(unguided, outcome);
    model.applyOutcome(
      state: separately,
      exercise: unguided,
      outcome: outcome,
      weights: weights,
      prediction: prediction,
      at: at,
    );

    model.propagateAndApplyOutcome(
      state: together,
      exercise: unguided,
      outcome: outcome,
      weights: weights,
      prediction: prediction,
      at: at,
    );

    expect(learnerStateHash(together), learnerStateHash(separately));
  });
}
