import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test(
    'a supported attempt says why the unguided one was not chosen',
    () async {
      final slots = await traceGuidanceLadder(
        scope: GoalTrajectoryScope.foundations,
        player: PlayerArchetypes.trueBeginner,
        seed: 0,
        sittings: 2,
        slotsPerSitting: 10,
      );

      expect(slots, isNotEmpty);
      for (final slot in slots) {
        expect(
          slot.unguidedFate == null,
          slot.rung == Rung.unguided,
          reason:
              'only a supported attempt has an unguided version passed over',
        );
      }
    },
  );
}
