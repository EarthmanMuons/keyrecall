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

  group('over shapes', () {
    final byShape = SchedulerPipeline(
      learner: const LearnerModel(),
      config: v1SchedulerConfig.withProgress(
        ProgressPreference.targetAndShapeFrontier,
      ),
    );
    final oneOctave = _trace(retention: 0.9);
    final twoOctaves = _trace(octaves: 2);
    final shown = {
      materials[0].materialId: {shapeOf(oneOctave.exercise)},
    };

    test('a demonstrated shape gives way to the next one on it', () {
      expect(
        byShape.chooseFrom(
          [oneOctave, twoOctaves],
          SessionState(),
          demonstratedShapes: shown,
        ),
        twoOctaves,
      );
    });

    test('which ignores the execution frontier', () {
      expect(
        byShape.chooseFrom(
          [
            oneOctave,
            _trace(
              direction: ExerciseDirection.upDown,
              realization: RealizationRank.advancing,
            ),
            twoOctaves,
          ],
          SessionState(),
          demonstratedShapes: {
            materials[0].materialId: {
              ...shown[materials[0].materialId]!,
              (
                hands: HandConfiguration.right,
                octaves: 1,
                direction: ExerciseDirection.upDown,
              ),
            },
          },
        ),
        twoOctaves,
      );
    });

    test('never in place of a pick made for a reason', () {
      final recovering = _trace(bypass: ChallengeBypass.recovery);

      expect(
        byShape.chooseFrom(
          [recovering, twoOctaves],
          SessionState(),
          demonstratedShapes: shown,
        ),
        recovering,
      );
    });

    test('in place of execution progression, which is ordinary work', () {
      final progressing = _trace(
        retention: 0.9,
        bypass: ChallengeBypass.executionProgression,
      );
      final step = _trace(
        octaves: 2,
        bypass: ChallengeBypass.executionProgression,
      );

      expect(
        byShape.chooseFrom(
          [progressing, step],
          SessionState(),
          demonstratedShapes: shown,
        ),
        step,
      );
    });

    test('nor with a step progression did not admit', () {
      expect(
        byShape.chooseFrom(
          [oneOctave, _trace(octaves: 2, bypass: ChallengeBypass.tempoProbe)],
          SessionState(),
          demonstratedShapes: shown,
        ),
        oneOctave,
      );
    });

    test('and nothing demonstrated leaves ranking alone', () {
      expect(
        byShape.chooseFrom([oneOctave, twoOctaves], SessionState()),
        oneOctave,
      );
    });
  });

  test('the execution frontier is inert under every other preference', () {
    final holding = _trace(retention: 0.9);
    final deeper = _trace(octaves: 2, realization: RealizationRank.advancing);

    for (final progress in ProgressPreference.values) {
      if (progress == ProgressPreference.targetAndFrontierInMaterial) continue;
      expect(
        SchedulerPipeline(
          learner: const LearnerModel(),
          config: v1SchedulerConfig.withProgress(progress),
        ).chooseFrom([holding, deeper], SessionState()),
        holding,
        reason: progress.name,
      );
    }
  });
}

CandidateTrace _trace({
  int material = 0,
  int octaves = 1,
  ExerciseDirection direction = ExerciseDirection.up,
  ChallengeBypass? bypass,
  GuidanceContext guidance = GuidanceContext.unguided,
  double retention = 0,
  RealizationRank realization = RealizationRank.holding,
}) => CandidateTrace(
  exercise: Exercise.linear(
    material: materials[material],
    hands: HandConfiguration.right,
    octaves: octaves,
    direction: direction,
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
  challengeBypass: bypass,
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
