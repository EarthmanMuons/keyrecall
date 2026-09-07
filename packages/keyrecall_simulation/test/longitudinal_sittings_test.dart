import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// A run spread across simulated calendar time, and what crosses its breaks.
///
/// The scheduler question a single sitting cannot ask. Everything here is
/// about the boundary: the learner keeps decaying through a gap, and the
/// sitting's own context is rebuilt on the far side the way a restart rebuilds
/// it, so a mechanism cannot outlive the sitting it belongs to just because
/// the harness held the object.
void main() {
  final weekly = sittingsOnDays([0, 3, 10, 24], slots: 12);

  Trajectory run({int seed = 0, List<Sitting>? sittings}) => runSittings(
    player: PlayerArchetypes.developing,
    seed: seed,
    materials: v1ScaleCatalog,
    sittings: sittings ?? weekly,
  );

  test('slots carry the sitting they were played in', () {
    final trajectory = run();

    expect(trajectory.slots.length, 48);
    for (var sitting = 0; sitting < weekly.length; sitting++) {
      final slots = trajectory.slotsOf(sitting).toList();
      expect(slots.length, 12);
      expect(slots.first.at, weekly[sitting].at);
      expect(
        slots.map((slot) => slot.index),
        List.generate(slots.length, (i) => sitting * 12 + i),
      );
    }
  });

  test('the schedule is the only clock', () {
    final trajectory = run();
    final days = [
      for (var sitting = 0; sitting < weekly.length; sitting++)
        trajectory.slotsOf(sitting).first.at.difference(weekly.first.at).inDays,
    ];

    expect(days, [0, 3, 10, 24]);
  });

  test('a schedule reproduces itself exactly', () {
    final chosen = [for (final slot in run().slots) slot.chosen];

    expect([for (final slot in run().slots) slot.chosen], chosen);
  });

  test('no sitting starts owed a probe or a recovery', () {
    final trajectory = run();

    for (var sitting = 1; sitting < weekly.length; sitting++) {
      final first = trajectory.slotsOf(sitting).first;
      expect(first.probe.pendingBefore, isNull);
      expect(first.probe.freshBefore, isFalse);
    }
  });

  test('a break changes the trajectory it comes before', () {
    final together = runSittings(
      player: PlayerArchetypes.developing,
      seed: 0,
      materials: v1ScaleCatalog,
      sittings: sittingsOnDays([0, 1, 2, 3], slots: 12),
    );
    final apart = run(sittings: sittingsOnDays([0, 30, 60, 90], slots: 12));

    expect([
      for (final slot in apart.slots) slot.chosen,
    ], isNot([for (final slot in together.slots) slot.chosen]));
  });
}
