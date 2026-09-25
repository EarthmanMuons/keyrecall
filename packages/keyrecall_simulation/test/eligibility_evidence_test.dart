import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The two readings of the execution floors, compared where they must agree.
void main() {
  const learner = LearnerModel();
  final raw = SchedulerPipeline(
    learner: learner,
    config: v1SchedulerConfig.withEligibility(
      v1SchedulerConfig.eligibility.withEvidence(
        EligibilityEvidence.rawCompetency,
      ),
    ),
  );
  final reference = SchedulerPipeline(learner: learner);

  test('the shipped floors read the predicted reference', () {
    expect(
      v1SchedulerConfig.eligibility.evidence,
      EligibilityEvidence.predictedReference,
    );
  });
  final candidates = productionCandidates(InstrumentProfile());

  test('a placement alone decides every candidate the same either way', () {
    for (final tier in PlacementTier.values) {
      final state = learner.placementState(tier, at: DateTime.utc(2026));
      for (final exercise in candidates) {
        state.materialMemoryFor(exercise.material.materialId, learner.params);
        final before = raw.eligibilityFor(state, exercise);
        final after = reference.eligibilityFor(state, exercise);
        expect(
          (after.tier, after.code),
          (before.tier, before.code),
          reason: '${tier.name} $exercise',
        );
      }
    }
  });

  test('the reference reads what the evidence identifies', () {
    // Execution low and crossing high: the split a beginner placement leaves
    // after evidence has corrected the sum. The raw floor reads the low part;
    // the reference reads the prediction the two make together.
    final state = learner.placementState(
      PlacementTier.beginner,
      at: DateTime.utc(2026),
    );
    state.competency(Competency.scalarCrossing).mean = 3;
    state.competency(Competency.multiOctaveContinuation).mean = 3;
    state.competency(Competency.directionReversal).mean = 3;
    final dMajor = Exercise.linear(
      material: TechnicalMaterial('D', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 2,
      guidance: GuidanceContext.notesPreviewedOnly,
    );
    state.materialMemoryFor(dMajor.material.materialId, learner.params);

    expect(
      raw.eligibilityFor(state, dMajor).tier,
      EligibilityTier.provisionallyEligible,
    );
    expect(
      reference.eligibilityFor(state, dMajor).tier,
      EligibilityTier.fullyEligible,
    );
  });
}
