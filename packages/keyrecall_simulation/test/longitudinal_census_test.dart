import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The per-session summary agrees with the slots it summarizes.
///
/// Checked against a real run rather than a constructed one: the census exists
/// to be read instead of the trajectory, so what matters is that the two say
/// the same thing about the same run.
void main() {
  final sessions = LongitudinalSchedules.named('interrupted', slots: 10);
  final trajectory = runTrajectorySessions(
    player: PlayerArchetypes.intermediate,
    seed: 3,
    materials: v1ScaleCatalog,
    sessions: sessions,
  );
  final census = censusOfRun(trajectory);

  test('every session is summarized once, in order', () {
    expect(census.sessions.length, sessions.length);
    expect(
      census.sessions.map((session) => session.index),
      List.generate(sessions.length, (index) => index),
    );
    for (final session in census.sessions) {
      expect(session.slots, trajectory.slotsOf(session.index).length);
    }
  });

  test('coverage counts the materials the run has met', () {
    final seen = <String>{};
    for (final session in census.sessions) {
      seen.addAll(
        trajectory
            .slotsOf(session.index)
            .map((slot) => slot.chosen.material.materialId),
      );
      expect(session.coverage, seen.length);
    }
  });

  test('every slot is counted as exactly one kind of work', () {
    for (final session in census.sessions) {
      expect(
        session.advancing +
            session.introductions +
            session.preFrontier +
            session.reacquiring +
            session.consolidating,
        session.slots,
      );
    }
  });

  test('every slot that moved nothing lands on one side of the split', () {
    for (final session in census.sessions) {
      expect(
        session.progressionPassedOver + session.noProgressionSelectable,
        session.preFrontier + session.reacquiring + session.consolidating,
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

  test('the gap is the time since the last attempt, not the last session', () {
    for (final session in census.sessions.skip(1)) {
      final previous = trajectory.slotsOf(session.index - 1).last;
      final first = trajectory.slotsOf(session.index).first;
      expect(session.away, first.at.difference(previous.at));
    }
  });

  test('a recovery is reported for every real break', () {
    final breaks = census.sessions
        .where(
          (session) =>
              session.index > 0 && session.away >= const Duration(days: 2),
        )
        .map((session) => session.index);

    expect(census.recoveries().map((r) => r.session), breaks);
  });

  test('resuming counts sessions until something moved forward', () {
    for (final recovery in census.recoveries()) {
      final after = census.sessions.skip(recovery.session);
      final resumed = after.where((session) => session.progressed);
      expect(
        recovery.sessionsToProgress,
        resumed.isEmpty ? isNull : resumed.first.index - recovery.session,
      );
    }
  });

  test('a milestone is dated to the session it first appears in', () {
    for (final milestone in Milestone.values) {
      final first = trajectory.slots
          .where(milestone.reachedBy)
          .map((slot) => slot.session);
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
