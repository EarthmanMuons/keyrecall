import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The per-sitting summary agrees with the slots it summarizes.
///
/// Checked against a real run rather than a constructed one: the census exists
/// to be read instead of the trajectory, so what matters is that the two say
/// the same thing about the same run.
void main() {
  final sittings = LongitudinalSchedules.named('interrupted', slots: 10);
  final trajectory = runSittings(
    player: PlayerArchetypes.intermediate,
    seed: 3,
    materials: v1ScaleCatalog,
    sittings: sittings,
  );
  final census = censusOfRun(trajectory);

  test('every sitting is summarized once, in order', () {
    expect(census.sittings.length, sittings.length);
    expect(
      census.sittings.map((sitting) => sitting.index),
      List.generate(sittings.length, (index) => index),
    );
    for (final sitting in census.sittings) {
      expect(sitting.slots, trajectory.slotsOf(sitting.index).length);
    }
  });

  test('coverage counts the materials the run has met', () {
    final seen = <String>{};
    for (final sitting in census.sittings) {
      seen.addAll(
        trajectory
            .slotsOf(sitting.index)
            .map((slot) => slot.chosen.material.materialId),
      );
      expect(sitting.coverage, seen.length);
    }
  });

  test('advancing and reacquiring slots are disjoint', () {
    for (final sitting in census.sittings) {
      expect(
        sitting.advancing + sitting.reacquiring,
        lessThanOrEqualTo(sitting.slots),
      );
    }
  });

  test('every reacquiring slot lands on one side of the split', () {
    for (final sitting in census.sittings) {
      expect(
        sitting.progressionPassedOver + sitting.noProgressionSelectable,
        sitting.reacquiring,
      );
    }
  });

  test('the gap is the time since the last attempt, not the last sitting', () {
    for (final sitting in census.sittings.skip(1)) {
      final previous = trajectory.slotsOf(sitting.index - 1).last;
      final first = trajectory.slotsOf(sitting.index).first;
      expect(sitting.away, first.at.difference(previous.at));
    }
  });

  test('a recovery is reported for every real break', () {
    final breaks = census.sittings
        .where(
          (sitting) =>
              sitting.index > 0 && sitting.away >= const Duration(days: 2),
        )
        .map((sitting) => sitting.index);

    expect(census.recoveries().map((r) => r.sitting), breaks);
  });

  test('resuming counts sittings until something moved forward', () {
    for (final recovery in census.recoveries()) {
      final after = census.sittings.skip(recovery.sitting);
      final resumed = after.where((sitting) => sitting.progressed);
      expect(
        recovery.sittingsToProgress,
        resumed.isEmpty ? isNull : resumed.first.index - recovery.sitting,
      );
    }
  });

  test('a milestone is dated to the sitting it first appears in', () {
    for (final milestone in Milestone.values) {
      final first = trajectory.slots
          .where(milestone.reachedBy)
          .map((slot) => slot.sitting);
      expect(
        census.milestones[milestone],
        first.isEmpty ? isNull : first.first,
      );
    }
  });
}
