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
}
