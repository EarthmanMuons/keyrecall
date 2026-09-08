import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What one success withdraws, and what it does not.
///
/// The relaxed floor ends when the candidate's own execution context has
/// demonstrated something, which is the scope execution progression already
/// reads. A wider one withdrew acquisition from work the model had learned
/// nothing new about and had given no step to.
void main() {
  final earned = materials[0];
  final untouched = materials[1];

  Exercise cued(TechnicalMaterial material, HandConfiguration hands) =>
      Exercise.linear(
        material: material,
        hands: hands,
        octaves: 1,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );

  /// Both materials met in both hands, and nothing demonstrated anywhere.
  LearnerState metNothingShown() {
    final state = stateAt(PlacementTier.someExperience);
    for (final material in [earned, untouched]) {
      state.materialMemoryFor(material.materialId, learnerParams)
        ..factualLastRetrievalAt = t0
        ..lastRetrievalAttemptAt = t0;
      for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
        state
                .materialExecutionFor(
                  (material.materialId, hands, HandMotion.parallel),
                  t0,
                  learnerParams,
                  familyId: material.familyId,
                )
                .lastEvidenceAt =
            t0;
      }
    }
    return state;
  }

  CandidateTrace traceOf(LearnerState state, Exercise exercise) => pipeline
      .evaluate(
        state: state,
        session: SessionState(),
        candidates: [exercise],
        at: t0,
      )
      .singleWhere((trace) => trace.exercise == exercise);

  final probes = {
    'the hand and material that earned it': cued(
      earned,
      HandConfiguration.right,
    ),
    'the other hand of the same material': cued(earned, HandConfiguration.left),
    'the same hand of another material': cued(
      untouched,
      HandConfiguration.right,
    ),
    'neither the hand nor the material': cued(
      untouched,
      HandConfiguration.left,
    ),
  };

  test('a frontier elsewhere leaves the rest of the family acquiring', () {
    final after = metNothingShown()
      ..materialExecutionFor(
        (earned.materialId, HandConfiguration.right, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: earned.familyId,
      ).demonstrate(octaves: 1, tempoBpm: 60);

    for (final probe in [
      'the other hand of the same material',
      'the same hand of another material',
      'neither the hand nor the material',
    ]) {
      final trace = traceOf(after, probes[probe]!);
      expect(
        trace.challengeFloorReason,
        ChallengeFloorReason.executionBootstrap,
        reason: 'nothing was demonstrated here, so $probe is still acquiring',
      );
      expect(
        trace.isRanked,
        isTrue,
        reason: 'and remains offerable, for $probe',
      );
      expect(
        trace.prediction.overallP,
        inExclusiveRange(
          config.challenge.pIntroductionMin,
          config.challenge.pMin,
        ),
        reason: 'at a prediction the ordinary floor would refuse, for $probe',
      );
    }
  });

  test('and the context that earned it is held to the ordinary floor', () {
    final before = metNothingShown();
    final after = metNothingShown()
      ..materialExecutionFor(
        (earned.materialId, HandConfiguration.right, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: earned.familyId,
      ).demonstrate(octaves: 1, tempoBpm: 60);
    final earnedIt = probes['the hand and material that earned it']!;

    expect(
      traceOf(before, earnedIt).challengeFloorReason,
      ChallengeFloorReason.executionBootstrap,
    );
    expect(
      traceOf(after, earnedIt).challengeFloorReason,
      ChallengeFloorReason.ordinary,
      reason: 'this context has shown something, so it is no longer acquiring',
    );
    expect(
      executionAdvanceFor(after, earnedIt.atTempo(tempoAfter(60))),
      ExecutionAdvance.tempo,
      reason: 'and what it showed is somewhere to go from',
    );
  });

  test('the withdrawal follows the motion too', () {
    final after = metNothingShown()
      ..materialExecutionFor(
        (earned.materialId, HandConfiguration.together, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: earned.familyId,
      ).demonstrate(octaves: 1, tempoBpm: 60);

    expect(
      pipeline.needsExecutionBootstrap(
        after,
        probes['the hand and material that earned it']!,
      ),
      isTrue,
      reason:
          'hands together parallel is not the single-hand context, so it does '
          'not speak for it',
    );
  });
}
