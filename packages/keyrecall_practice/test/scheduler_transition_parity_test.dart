import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('the direct transition and practice session stay in parity', () async {
    final practice = await openSession(InMemoryPracticeStore(createdAt: t0));
    final directState = practice.state.copy();
    final directSession = SessionState();
    final at = t0.plusDays(0.5);
    learner.propagate(directState, at);

    final direct = practice.pipeline.decide(
      state: directState,
      session: directSession,
      candidates: practice.candidates,
      at: at,
    );
    final presented = await practice.decide(at: at);

    expect(presented?.exercise, direct.selected?.exercise);
    expect(
      practice.session.attemptsThisSession,
      directSession.attemptsThisSession,
    );
    expect(
      practice.session.unservedGuidanceProbeSelections,
      directSession.unservedGuidanceProbeSelections,
    );

    final exercise = direct.selected!.exercise;
    final outcome = outcomeOf(
      retrieval: exercise.guidance.isRetrievalObserved
          ? FactualRetrieval.succeeded
          : FactualRetrieval.notTested,
      quality: 1,
      tempoRatio: 2,
    );
    final prediction = learner.predict(directState, exercise, at: at);
    learner.applyOutcome(
      state: directState,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: prediction,
      at: at,
    );
    practice.pipeline.recordOutcome(directSession, exercise, outcome);
    await practice.closeWithOutcome(outcome);

    expect(learnerStateHash(practice.state), learnerStateHash(directState));
    expect(
      practice.session.lastFailedExercise,
      directSession.lastFailedExercise,
    );
    expect(practice.session.tempoProbe, directSession.tempoProbe);
    expect(
      practice.session.supportedAttemptsSinceObservation,
      directSession.supportedAttemptsSinceObservation,
    );
    expect(practice.session.recentMaterialIds, directSession.recentMaterialIds);
  });
}
