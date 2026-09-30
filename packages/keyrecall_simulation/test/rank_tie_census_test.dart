import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  RankTieCensus census() => censusRankTies(
    player: PlayerArchetypes.advanced,
    seed: 0,
    materials: v1ScaleCatalog,
    slots: 30,
  );

  test('every tie it reports is one candidate order decided', () {
    final found = census();

    expect(found.ties, isNotEmpty);
    for (final tie in found.ties) {
      expect(
        v1SchedulerConfig.rankTolerances.compare(
          tie.winner.rankKey!,
          tie.reversed.rankKey!,
        ),
        0,
        reason: 'slot ${tie.slot} is tied on every rank term',
      );
      expect(identical(tie.winner, tie.reversed), isFalse);
      expect(tie.tied, greaterThanOrEqualTo(2));
    }
  });

  test('observes without changing what was chosen', () {
    final plain = runTrajectory(
      player: PlayerArchetypes.advanced,
      seed: 0,
      materials: v1ScaleCatalog,
      slots: 30,
    );

    expect(
      [for (final slot in census().trajectory.slots) slot.chosen],
      [for (final slot in plain.slots) slot.chosen],
    );
  });
}
