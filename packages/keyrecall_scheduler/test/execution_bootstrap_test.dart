import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final material = materials.first;

  Exercise cued({
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
    GuidanceContext guidance = GuidanceContext.continuouslyCued,
    double tempoBpm = 60,
  }) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    tempoBpm: tempoBpm,
    guidance: guidance,
  );

  /// A learner who has met this material and demonstrated nothing in it.
  LearnerState metButUnproven() {
    final state = stateAt(PlacementTier.beginner);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0;
    state
            .materialExecutionFor(
              executionContextOf(cued()),
              t0,
              learnerParams,
              familyId: material.familyId,
            )
            .lastEvidenceAt =
        t0;
    return state;
  }

  bool admits(LearnerState state, Exercise exercise) => pipeline
      .evaluate(
        state: state,
        session: SessionState(),
        candidates: [exercise],
        at: t0,
      )
      .singleWhere((trace) => trace.exercise == exercise)
      .isRanked;

  test('a later exposure of the bootstrap shape is still admitted', () {
    final state = metButUnproven();
    final exercise = cued();
    final prediction = learner.predict(state, exercise, at: t0);

    expect(
      pipeline.isIntroduction(state, exercise),
      isFalse,
      reason: 'the material has been met, so nothing here is an introduction',
    );
    expect(
      prediction.overallP,
      inInclusiveRange(
        config.challenge.pIntroductionMin,
        config.challenge.pMin,
      ),
      reason: 'and it predicts in the gap between the two floors',
    );
    expect(pipeline.needsExecutionBootstrap(state, exercise), isTrue);
    expect(admits(state, exercise), isTrue);
    expect(
      pipeline
          .evaluate(
            state: state,
            session: SessionState(),
            candidates: [exercise],
            at: t0,
          )
          .singleWhere((trace) => trace.exercise == exercise)
          .challengeFloorReason,
      ChallengeFloorReason.executionBootstrap,
      reason: 'and the trace says which regime admitted it',
    );
  });

  test('and stops being once this context has a frontier', () {
    final state = metButUnproven();
    final exercise = cued();
    expect(admits(state, exercise), isTrue);

    state
        .materialExecutionFor(
          (material.materialId, HandConfiguration.left, HandMotion.parallel),
          t0,
          learnerParams,
          familyId: material.familyId,
        )
        .demonstrate(octaves: 1, tempoBpm: 60);
    expect(
      pipeline.needsExecutionBootstrap(state, exercise),
      isTrue,
      reason: 'the other hand has shown something and this one has not',
    );

    state
        .materialExecutionFor(
          executionContextOf(exercise),
          t0,
          learnerParams,
          familyId: material.familyId,
        )
        .demonstrate(octaves: 1, tempoBpm: 60);

    expect(
      pipeline.needsExecutionBootstrap(state, exercise),
      isFalse,
      reason: 'its own context has, which is what ends the bootstrap',
    );
    expect(
      admits(state, exercise),
      isFalse,
      reason:
          'so the ordinary floor applies again, on evidence rather than on the '
          'material having stopped being new',
    );
  });

  test('and nothing else in the family inherits it', () {
    final state = metButUnproven();

    for (final harder in [
      cued(octaves: 2),
      cued(hands: HandConfiguration.together),
      cued(guidance: GuidanceContext.notesPreviewedOnly),
      cued(guidance: GuidanceContext.unguided),
    ]) {
      expect(
        pipeline.isBootstrapShape(harder),
        isFalse,
        reason: '${harder.conditions} ${harder.guidance} is not the shape',
      );
      expect(
        pipeline.challengeFloorFor(state, harder),
        (config.challenge.pMin, ChallengeFloorReason.ordinary),
        reason: 'so it is held to the ordinary floor while the family is weak',
      );
    }
    expect(pipeline.challengeFloorFor(state, cued()), (
      config.challenge.pIntroductionMin,
      ChallengeFloorReason.executionBootstrap,
    ));
  });

  test('this is ordinary admission, not the fallback', () {
    final state = metButUnproven();
    final result = pipeline.decide(
      state: state,
      session: SessionState(),
      candidates: [cued()],
      at: t0,
    );

    expect(result, isA<CandidateSelected>());
    expect(
      (result as CandidateSelected).candidate.challengeBypass,
      isNull,
      reason:
          'the work competes on the ordinary path, so a learner whose other '
          'family keeps admission alive still reaches it',
    );
  });
}
