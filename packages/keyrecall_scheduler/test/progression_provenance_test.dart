import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final material = materials.first;

  Exercise together({double tempoBpm = 56}) => Exercise.linear(
    material: material,
    hands: HandConfiguration.together,
    tempoBpm: tempoBpm,
    guidance: GuidanceContext.unguided,
  );

  LearnerState readyButUnproven() {
    final state = stateAt(PlacementTier.someExperience);
    for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
      state.materialExecutionFor(
          (material.materialId, hands, HandMotion.parallel),
          t0,
          learnerParams,
          familyId: material.familyId,
        )
        ..readyForHandsTogether(octaves: 1, tempoBpm: 60)
        ..lastEvidenceAt = t0;
    }
    return state;
  }

  test('a hands-together step reads readiness, not a frontier', () {
    final state = readyButUnproven();
    final entry = handsTogetherEntryTempo(state, material.materialId, 1);

    expect(entry, tempoBefore(60));
    for (final hands in HandConfiguration.values) {
      for (final motion in HandMotion.values) {
        expect(
          state
              .materialExecution[(material.materialId, hands, motion)]
              ?.demonstratedTempoByOctaves,
          anyOf(isNull, isEmpty),
          reason: 'nothing has been demonstrated anywhere in this material',
        );
      }
    }
    expect(
      executionAdvanceFor(state, together(tempoBpm: entry)),
      ExecutionAdvance.handsTogether,
      reason:
          'so an adjacent step exists on evidence a frontier census cannot '
          'see, which is what the two families and the returner had in common',
    );
  });

  test('and the trace says which rule made a candidate reachable', () {
    final state = readyButUnproven();
    state.materialMemoryFor(material.materialId, learnerParams)
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0;
    final entry = handsTogetherEntryTempo(state, material.materialId, 1);

    final supported = Exercise.linear(
      material: material,
      hands: HandConfiguration.together,
      tempoBpm: entry,
      guidance: GuidanceContext.continuouslyCued,
    );
    final traces = pipeline.evaluate(
      state: state,
      session: SessionState(),
      candidates: [supported],
      at: t0,
    );
    final trace = traces.singleWhere((t) => t.exercise == supported);

    expect(trace.challengeBypass, ChallengeBypass.executionProgression);
    expect(trace.executionAdvance, ExecutionAdvance.handsTogether);
    expect(
      trace.isWithinChallengeBand,
      isFalse,
      reason: 'the bypass is what made it reachable, not the band',
    );
  });

  test('motor-ready and retrieval-unproven enters with support', () {
    final state = readyButUnproven();
    state.materialMemoryFor(material.materialId, learnerParams)
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0;
    final entry = handsTogetherEntryTempo(state, material.materialId, 1);

    final admitted = pipeline
        .evaluate(
          state: state,
          session: SessionState(),
          candidates: [
            for (final guidance in GuidanceContext.ladder)
              Exercise.linear(
                material: material,
                hands: HandConfiguration.together,
                tempoBpm: entry,
                guidance: guidance,
              ),
          ],
          at: t0,
        )
        .where(
          (t) => t.challengeBypass == ChallengeBypass.executionProgression,
        );

    expect(
      admitted.map((t) => t.exercise.guidance.independence),
      everyElement(0),
      reason:
          'the hands are ready to coordinate and the notes have never come '
          'unaided, so the step is offered with the notes in front of them',
    );
    expect(admitted, isNotEmpty, reason: 'the foothold is still there');
    expect(
      admitted.map((t) => t.executionAdvance),
      everyElement(ExecutionAdvance.handsTogether),
    );
  });

  test('motor-ready and retrieval-proven keeps the independent rung', () {
    final state = readyButUnproven();
    state.materialMemoryFor(material.materialId, learnerParams)
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0
      ..establishedIndependence = 2
      ..establishedIndependenceAt = t0;
    final entry = handsTogetherEntryTempo(state, material.materialId, 1);

    final admitted = pipeline
        .evaluate(
          state: state,
          session: SessionState(),
          candidates: [
            for (final guidance in GuidanceContext.ladder)
              Exercise.linear(
                material: material,
                hands: HandConfiguration.together,
                tempoBpm: entry,
                guidance: guidance,
              ),
          ],
          at: t0,
        )
        .where(
          (t) => t.challengeBypass == ChallengeBypass.executionProgression,
        );

    expect(
      admitted.map((t) => t.exercise.guidance),
      contains(GuidanceContext.unguided),
      reason:
          'somebody who retrieves this material alone is not sent back to full '
          'cueing because coordination is the new part',
    );
  });

  test('a tempo step is the other kind, and does read a frontier', () {
    final state = stateAt(PlacementTier.someExperience);
    final at1 = state.materialExecutionFor(
      (material.materialId, HandConfiguration.right, HandMotion.parallel),
      t0,
      learnerParams,
      familyId: material.familyId,
    )..demonstrate(octaves: 1, tempoBpm: 60);
    at1.lastEvidenceAt = t0;

    expect(
      executionAdvanceFor(
        state,
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          tempoBpm: tempoAfter(60),
        ),
      ),
      ExecutionAdvance.tempo,
    );
  });
}
