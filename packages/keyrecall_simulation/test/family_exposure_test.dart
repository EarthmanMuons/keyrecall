import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The exposure reading agrees with the run it summarizes.
void main() {
  final trajectory = runSittings(
    player: PlayerArchetypes.coordinationLimited,
    seed: 2,
    materials: v1ScaleCatalog,
    sittings: LongitudinalSchedules.named('normal_month', slots: 12),
  );
  final exposures = familyExposures(trajectory);

  FamilyExposure of(String family) =>
      exposures.firstWhere((exposure) => exposure.family == family);

  test('every family the run touched is reported once', () {
    final touched = {
      for (final slot in trajectory.slots) ...handMotionFamilies(slot.chosen),
    };

    expect({for (final exposure in exposures) exposure.family}, touched);
    expect(exposures.length, touched.length);
  });

  test('attempts and first slot come from the run', () {
    for (final exposure in exposures) {
      final held = [
        for (final (position, slot) in trajectory.slots.indexed)
          if (handMotionFamilies(slot.chosen).contains(exposure.family))
            position,
      ];

      expect(exposure.attempts, held.length);
      expect(exposure.firstSlot, held.first);
    }
  });

  test('share is of the run after the family first appeared', () {
    final exposure = of('hands:right');
    expect(
      exposure.share,
      exposure.attempts / (trajectory.slots.length - exposure.firstSlot),
    );
  });

  test('a family that always yields has no unproductive run', () {
    for (final exposure in exposures) {
      if (exposure.managedYield < 1) continue;
      expect(exposure.longestUnproductiveStreak, 0);
      expect(exposure.streaks, 0);
    }
  });

  test('a longest streak below the length asked about opens no window', () {
    for (final exposure in familyExposures(trajectory, streakLength: 5)) {
      if (exposure.longestUnproductiveStreak >= 5) continue;
      expect(exposure.streaks, 0);
      expect(exposure.shareAfterStreaks, 0);
      expect(exposure.slotsToNextManaged, isNull);
    }
  });

  group('whether a failing family can be contracted at all', () {
    final latencies = {
      for (final latency in doseLatencies(trajectory)) latency.family: latency,
    };

    test('every family the run touched is answered once', () {
      expect(latencies.keys.toSet(), {
        for (final exposure in exposures) exposure.family,
      });
    });

    test('a family that never fails is never asked about', () {
      for (final exposure in exposures) {
        if (exposure.longestUnproductiveStreak >= 3) continue;
        expect(
          latencies[exposure.family]!.reachability,
          DoseReachability.neverFailed,
        );
      }
    });

    test('reaching the minimum is dated, and not reaching it is not', () {
      for (final latency in latencies.values) {
        switch (latency.reachability) {
          case DoseReachability.reached:
          case DoseReachability.recoveredFirst:
            expect(latency.slots, isNotNull);
            expect(latency.attempts, isNotNull);
          case DoseReachability.neverEnoughEvidence:
            expect(latency.slots, isNotNull);
          case DoseReachability.neverFailed:
            expect(latency.slots, isNull);
        }
      }
    });

    test('an evidence minimum it cannot reach answers never', () {
      // Nothing holds thirteen of the last twelve selections, so no family can
      // ever be contracted and every failing one says so.
      final unreachable = doseLatencies(
        trajectory,
        config: const DoseConfig(window: 12, minAttempts: 12),
      );

      expect(
        unreachable.where(
          (latency) => latency.reachability == DoseReachability.reached,
        ),
        isEmpty,
      );
    });
  });
}
