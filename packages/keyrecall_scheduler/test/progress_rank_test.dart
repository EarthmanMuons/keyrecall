import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

void main() {
  RankKey key({
    double retention = 0,
    double information = 0,
    bool targetShaped = false,
    bool advancesFrontier = false,
    bool targetShapedGoal = false,
    EligibilityTier tier = EligibilityTier.fullyEligible,
  }) => RankKey(
    tier: tier,
    retention: retention,
    information: information,
    diversity: 0,
    goals: 0,
    targetShaped: targetShaped,
    advancesFrontier: advancesFrontier,
    targetShapedGoal: targetShapedGoal,
  );

  test('above retention, arriving outranks a more urgent precursor', () {
    expect(
      key(targetShaped: true).compareTo(key(retention: 0.9)),
      greaterThan(0),
    );
  });

  test('but never a better eligibility tier', () {
    expect(
      key(
        targetShaped: true,
        tier: EligibilityTier.provisionallyEligible,
      ).compareTo(key()),
      lessThan(0),
    );
  });

  test('beside goal relevance, it decides only what the terms above tie', () {
    expect(
      key(targetShapedGoal: true).compareTo(key(information: 0.001)),
      lessThan(0),
      reason: 'continuous terms above it almost never tie',
    );
    expect(key(targetShapedGoal: true).compareTo(key()), greaterThan(0));
  });

  test('a step past the frontier outranks retention, and not a target', () {
    expect(
      key(advancesFrontier: true).compareTo(key(retention: 0.9)),
      greaterThan(0),
    );
    expect(
      key(advancesFrontier: true).compareTo(key(targetShaped: true)),
      lessThan(0),
      reason: 'a goal\'s destination before a step toward what it does not ask',
    );
  });

  test('a target at a tempo generation never offered is still arriving', () {
    const learner = LearnerModel();
    final pipeline = SchedulerPipeline(
      learner: learner,
      config: v1SchedulerConfig.withProgress(ProgressPreference.target),
    );
    final at = DateTime.utc(2026);
    final learned = Exercise.linear(
      material: ScaleMaterial('C', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.upDown,
      tempoBpm: 63,
    );
    final traces = pipeline.evaluate(
      state: learner.placementState(PlacementTier.advanced, at: at),
      session: SessionState(),
      candidates: [learned],
      at: at,
      overrides: {learned: ChallengeBypass.override},
      uncoveredTargets: UncoveredTargets([
        UncoveredTarget(
          material: learned.material,
          constraints: const ExerciseConstraints(
            hands: HandConfiguration.right,
            octaves: 1,
            direction: ExerciseDirection.upDown,
          ),
          retrieval: CoverageRetrieval.unguided,
        ),
      ]),
    );

    expect(
      traces
          .firstWhere((trace) => trace.exercise == learned)
          .rankKey!
          .targetShaped,
      isTrue,
    );
  });
}
