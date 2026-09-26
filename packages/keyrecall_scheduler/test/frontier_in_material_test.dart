import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final pipeline = SchedulerPipeline(
    learner: const LearnerModel(),
    config: v1SchedulerConfig.withProgress(
      ProgressPreference.targetAndFrontierInMaterial,
    ),
  );

  test('ranking chooses the material, and the frontier how far in', () {
    final holding = _trace(retention: 0.9);
    final deeper = _trace(octaves: 2, realization: RealizationRank.advancing);
    final elsewhere = _trace(
      material: 1,
      retention: 0.5,
      realization: RealizationRank.advancing,
    );

    expect(
      pipeline.chooseFrom([holding, deeper, elsewhere], SessionState()),
      deeper,
    );
  });

  test('never at another rung', () {
    final holding = _trace(retention: 0.9);
    final cued = _trace(
      octaves: 2,
      guidance: GuidanceContext.continuouslyCued,
      realization: RealizationRank.advancing,
    );

    expect(pipeline.chooseFrom([holding, cued], SessionState()), holding);
  });

  test('inert under every other preference', () {
    final holding = _trace(retention: 0.9);
    final deeper = _trace(octaves: 2, realization: RealizationRank.advancing);

    expect(
      const SchedulerPipeline(
        learner: LearnerModel(),
      ).chooseFrom([holding, deeper], SessionState()),
      holding,
    );
  });
}

CandidateTrace _trace({
  int material = 0,
  int octaves = 1,
  GuidanceContext guidance = GuidanceContext.unguided,
  double retention = 0,
  RealizationRank realization = RealizationRank.holding,
}) => CandidateTrace(
  exercise: Exercise.linear(
    material: materials[material],
    hands: HandConfiguration.right,
    octaves: octaves,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: guidance,
  ),
  eligibility: const EligibilityDecision(
    EligibilityTier.fullyEligible,
    'eligible',
  ),
  safety: const SafetyDecision(true, 'safe'),
  challengeStatus: StageStatus.reached,
  prediction: Prediction(
    independentRetrievalP: 1,
    materialAvailableP: 1,
    executionP: 0.8,
    coordinationP: 1,
    topologyP: 1,
  ),
  isWithinChallengeBand: true,
  challengeBypass: null,
  challengeSurvived: true,
  priorityStatus: StageStatus.reached,
  rankKey: RankKey(
    tier: EligibilityTier.fullyEligible,
    retention: retention,
    information: 0,
    diversity: 0,
    goals: 0,
    realization: realization,
  ),
);
