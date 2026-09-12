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

  void expectRejected(
    String what, {
    required Exercise exercise,
    required Outcome outcome,
    EvidenceWeights? weights,
    DateTime? at,
  }) {
    final state = freshState();
    final attemptAt = at ?? t0;
    final before = learnerStateHash(state);
    expect(
      () => model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: weights ?? evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: t0),
        at: attemptAt,
      ),
      throwsArgumentError,
      reason: what,
    );
    expect(learnerStateHash(state), before, reason: '$what wrote something');
  }

  group('a rejected transition writes nothing', () {
    test('an attempt the state has not been propagated to', () {
      expectRejected(
        'a day-one attempt against a day-zero state',
        exercise: unguided,
        outcome: outcomeOf(),
        at: t0.plusDays(1),
      );
    });

    test('a cued attempt claiming a retrieval', () {
      expectRejected(
        'a continuously cued success',
        exercise: cued,
        outcome: outcomeOf(),
      );
      expectRejected(
        'a continuously cued failure',
        exercise: cued,
        outcome: outcomeOf(retrieval: FactualRetrieval.failed),
      );
    });

    test('a retrieval-testing attempt claiming it tested nothing', () {
      expectRejected(
        'an unguided attempt that reports no retrieval',
        exercise: unguided,
        outcome: outcomeOf(retrieval: FactualRetrieval.notTested),
      );
    });

    test('an attempt that never began but produced something', () {
      expectRejected(
        'unstarted and completed',
        exercise: unguided,
        outcome: outcomeOf(started: false),
      );
      expectRejected(
        'unstarted and retrieved',
        exercise: unguided,
        outcome: outcomeOf(started: false, completed: false),
      );
    });

    test('memory evidence from an attempt that tested no retrieval', () {
      final outcome = outcomeOf(retrieval: FactualRetrieval.notTested);
      expectRejected(
        'a cued attempt carrying memory weight',
        exercise: cued,
        outcome: outcome,
        weights: EvidenceWeights(
          competencies: const {},
          materialExecution: 0.0,
          materialMemory: 0.4,
        ),
      );
    });

    test('a tempo ratio that derives no finite pace', () {
      expectRejected(
        'an absurd achieved tempo',
        exercise: unguided,
        outcome: outcomeOf(tempoRatio: 1e308),
      );
    });
  });

  test('an accepted transition leaves a state its own decoder reads', () {
    final state = freshState();
    final trajectory = [
      (unguided, outcomeOf()),
      (cued, outcomeOf(retrieval: FactualRetrieval.notTested)),
      (unguided, outcomeOf(retrieval: FactualRetrieval.failed, quality: 0.2)),
      (unguided, outcomeOf(tempoRatio: 0.0, completed: false, quality: 0.4)),
      (unguided, outcomeOf(quality: 0.99, tempoRatio: 2.4)),
    ];

    for (var index = 0; index < trajectory.length; index++) {
      final (exercise, outcome) = trajectory[index];
      final at = t0.plusDays(1.0 * (index + 1));
      model.propagate(state, at);
      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );

      final reread = decodeLearnerState(
        encodeLearnerState(state),
        params: params,
      );
      expect(learnerStateHash(reread), learnerStateHash(state));
    }
  });
}
