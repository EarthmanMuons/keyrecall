import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

void main() {
  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final at = DateTime.utc(2026);
  final root = ArpeggioMaterial('C', ArpeggioQuality.major);
  final first = ArpeggioMaterial(
    'C',
    ArpeggioQuality.major,
    inversion: ArpeggioInversion.first,
  );

  Exercise exercise(
    TechnicalMaterial material, {
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
  }) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );

  LearnerState advanced() =>
      learner.placementState(PlacementTier.advanced, at: at);

  void demonstrate(
    LearnerState state,
    String materialId,
    HandConfiguration hands,
    int octaves, {
    bool coordinationReady = false,
  }) {
    final residual = state.materialExecutionFor(
      (materialId, hands, HandMotion.parallel),
      at,
      v1LearnerParams,
    )..demonstrate(octaves: octaves, tempoBpm: 60);
    if (coordinationReady) {
      residual.readyForHandsTogether(octaves: octaves, tempoBpm: 60);
    }
    residual.lastEvidenceAt = at;
  }

  test('root-position evidence unlocks its inversion in the same hand', () {
    final state = advanced();
    final candidate = exercise(first);

    expect(
      pipeline.eligibilityFor(state, candidate).code,
      EligibilityReason.materialProgressionPrerequisite,
    );

    demonstrate(state, root.materialId, HandConfiguration.right, 1);

    expect(
      pipeline.eligibilityFor(state, candidate).tier,
      EligibilityTier.fullyEligible,
    );
    expect(
      pipeline
          .eligibilityFor(state, exercise(first, hands: HandConfiguration.left))
          .code,
      EligibilityReason.materialProgressionPrerequisite,
    );
  });

  test('scale mastery cannot unlock an inversion or wider arpeggio', () {
    final state = advanced();
    state.competency(Competency.rhScaleExecution).mean = 20;
    demonstrate(state, 'C_MAJOR', HandConfiguration.right, 1);
    demonstrate(state, 'C_MAJOR', HandConfiguration.right, 2);

    expect(
      pipeline.eligibilityFor(state, exercise(first)).code,
      EligibilityReason.materialProgressionPrerequisite,
    );
    expect(
      pipeline.eligibilityFor(state, exercise(root, octaves: 2)).code,
      EligibilityReason.octaveSpanPrerequisite,
    );
  });

  test('span progression follows one, then two, then four octaves', () {
    final state = advanced();
    final two = exercise(root, octaves: 2);
    final four = exercise(root, octaves: 4);

    expect(
      pipeline.eligibilityFor(state, two).code,
      EligibilityReason.octaveSpanPrerequisite,
    );
    demonstrate(state, root.materialId, HandConfiguration.right, 1);
    expect(
      pipeline.eligibilityFor(state, two).tier,
      EligibilityTier.fullyEligible,
    );
    expect(
      pipeline.eligibilityFor(state, four).code,
      EligibilityReason.octaveSpanPrerequisite,
    );
    demonstrate(state, root.materialId, HandConfiguration.right, 2);
    expect(
      pipeline.eligibilityFor(state, four).tier,
      EligibilityTier.fullyEligible,
    );
  });

  test('hands together requires both arpeggio hands at the same span', () {
    final state = advanced();
    final together = exercise(root, hands: HandConfiguration.together);
    demonstrate(
      state,
      'C_MAJOR',
      HandConfiguration.right,
      1,
      coordinationReady: true,
    );
    demonstrate(
      state,
      'C_MAJOR',
      HandConfiguration.left,
      1,
      coordinationReady: true,
    );

    expect(
      pipeline.eligibilityFor(state, together).code,
      EligibilityReason.handsTogetherPrerequisite,
    );

    demonstrate(
      state,
      root.materialId,
      HandConfiguration.right,
      1,
      coordinationReady: true,
    );
    expect(
      pipeline.eligibilityFor(state, together).code,
      EligibilityReason.handsTogetherPrerequisite,
    );
    demonstrate(
      state,
      root.materialId,
      HandConfiguration.left,
      1,
      coordinationReady: true,
    );

    expect(
      pipeline.eligibilityFor(state, together).tier,
      EligibilityTier.fullyEligible,
    );
  });
}
