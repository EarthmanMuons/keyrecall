import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final material = TechnicalMaterial('D', ScaleForm.major);
  final entry = exerciseFor(
    material,
    tempoBpm: 72,
    guidance: GuidanceContext.continuouslyCued,
  );
  final policy = PracticeEntryPolicy.byFamily({
    material.familyId: 72,
  }, defaultTempoBpm: 60);

  test('a family entry tempo is the cold-start realization', () {
    final state = stateAt(PlacementTier.beginner);

    expect(
      pipeline.entryTempoFor(state, entry, practiceEntryPolicy: policy),
      72,
    );
    expect(unmeasuredEntryTempo(state, entry, practiceEntryPolicy: policy), 72);
    expect(realizationFitFor(state, entry, practiceEntryPolicy: policy), 0);
  });

  test('introduction does not require the global entry tempo', () {
    final result = pipeline.decide(
      state: stateAt(PlacementTier.beginner),
      session: SessionState(),
      candidates: [entry],
      at: t0,
      practiceEntryPolicy: policy,
    );

    expect(result, isA<CandidateSelected>());
    expect(
      (result as CandidateSelected).candidate.challengeBypass,
      ChallengeBypass.newMaterial,
    );
    expect(result.candidate.exercise.conditions.tempoBpm, 72);
  });

  test('gentle admission follows the family entry tempo', () {
    final state = stateAt(PlacementTier.beginner);
    final decision = pipeline.eligibilityFor(
      state,
      entry,
      practiceEntryPolicy: policy,
    );

    expect(decision.tier, EligibilityTier.fullyEligible);
  });
}
