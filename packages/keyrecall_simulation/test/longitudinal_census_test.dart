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

  test('every slot is counted as exactly one kind of work', () {
    for (final sitting in census.sittings) {
      expect(
        sitting.advancing +
            sitting.introductions +
            sitting.preFrontier +
            sitting.reacquiring +
            sitting.consolidating,
        sitting.slots,
      );
    }
  });

  test('every slot that moved nothing lands on one side of the split', () {
    for (final sitting in census.sittings) {
      expect(
        sitting.progressionPassedOver + sitting.noProgressionSelectable,
        sitting.preFrontier + sitting.reacquiring + sitting.consolidating,
      );
    }
  });

  test('work with no frontier yet is not reacquisition', () {
    for (final slot in trajectory.slots) {
      if (slot.frontierBefore.isNotEmpty || slot.frontierAdvanced) continue;
      expect(
        workOf(slot, known: true),
        SlotWork.preFrontier,
        reason: 'slot ${slot.index} has nothing demonstrated to reacquire',
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

  test('a milestone shock needs a full window either side', () {
    final shocks = milestoneShocks(trajectory, window: 15);

    for (final shock in shocks) {
      expect(shock.slot, greaterThanOrEqualTo(15));
      expect(shock.slot + 15, lessThan(trajectory.slots.length));
      expect(shock.delta, shock.after - shock.before);
    }
  });

  test('a shock is measured at the slot the milestone first appeared', () {
    for (final shock in milestoneShocks(trajectory, window: 15)) {
      expect(
        trajectory.slots.indexWhere(shock.milestone.reachedBy),
        shock.slot,
      );
    }
  });
}
