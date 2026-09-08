import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What one success withdraws from the rest of its family.
///
/// The relaxed floor ends at the family's first execution frontier, which is
/// deliberately broad: the entry condition was family-wide because there was no
/// evidence anywhere, and the exit matches it. This is what that costs.
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

  test('one frontier withdraws the floor from work it says nothing about', () {
    final before = metNothingShown();
    final after = metNothingShown()
      ..materialExecutionFor(
        (earned.materialId, HandConfiguration.right, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: earned.familyId,
      ).demonstrate(octaves: 1, tempoBpm: 60);

    for (final probe in probes.entries) {
      final was = traceOf(before, probe.value);
      final now = traceOf(after, probe.value);

      expect(
        now.prediction.overallP,
        was.prediction.overallP,
        reason: 'the model expects exactly what it did of ${probe.key}',
      );
      expect(was.challengeFloorReason, ChallengeFloorReason.familyBootstrap);
      expect(
        now.challengeFloorReason,
        ChallengeFloorReason.ordinary,
        reason: 'and yet the regime changed for ${probe.key}',
      );
      expect(was.isRanked, isTrue);
      expect(
        now.isRanked,
        isFalse,
        reason: 'from offerable to not, for ${probe.key}',
      );
      expect(
        now.prediction.overallP,
        inExclusiveRange(
          config.challenge.pIntroductionMin,
          config.challenge.pMin,
        ),
        reason:
            'landing back in the gap the relaxed floor exists to cover, for '
            '${probe.key}',
      );
    }
  });

  test('and only the context that earned it has somewhere to go', () {
    final after = metNothingShown()
      ..materialExecutionFor(
        (earned.materialId, HandConfiguration.right, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: earned.familyId,
      ).demonstrate(octaves: 1, tempoBpm: 60);

    expect(
      executionAdvanceFor(
        after,
        cued(earned, HandConfiguration.right).atTempo(tempoAfter(60)),
      ),
      ExecutionAdvance.tempo,
      reason: 'a frontier is a place to progress from',
    );
    for (final probe in [
      probes['the other hand of the same material']!,
      probes['the same hand of another material']!,
      probes['neither the hand nor the material']!,
    ]) {
      expect(
        executionAdvanceFor(after, probe.atTempo(tempoAfter(60))),
        ExecutionAdvance.none,
        reason:
            'while the rest of the family has neither the relaxed floor nor a '
            'step of its own',
      );
    }
  });
}
