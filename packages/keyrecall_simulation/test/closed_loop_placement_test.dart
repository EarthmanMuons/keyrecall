import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test(
    'each placement runs the same player and is compared at checkpoints',
    () async {
      final group = await runClosedLoopPlacement(
        scope: GoalTrajectoryScope.foundations,
        player: PlayerArchetypes.intermediate,
        seed: 0,
        checkpoints: const [1, 2],
        slotsPerSession: 8,
      );

      expect(group.checkpoints.map((point) => point.sessions), [1, 2]);
      for (final point in group.checkpoints) {
        expect(point.covered, hasLength(3));
        expect(point.eligibleOverlap, inInclusiveRange(0, 1));
        expect(point.mixDistance.values, everyElement(inInclusiveRange(0, 1)));
      }
      expect(group.milestones['first_unguided'], hasLength(3));

      final read = ClosedLoopGroup.fromJson(group.toJson());
      expect(read.toJson(), group.toJson());
    },
  );
}
