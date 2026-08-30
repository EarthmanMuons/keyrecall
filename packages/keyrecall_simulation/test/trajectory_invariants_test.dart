import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Properties the scheduler must hold for every kind of player.
///
/// Invariants only. The observational detectors are counts against thresholds
/// nobody has calibrated, and asserting one would freeze today's behavior as
/// the definition of healthy practice; they are reported by `bin/sweep.dart`
/// and read, not enforced.
///
/// A handful of seeds on the small catalog, because this runs on every commit.
/// The wide search is the sweep's job.
void main() {
  const seeds = 6;
  const slots = 40;

  /// Invariant failures the sweep found and nothing has fixed yet.
  ///
  /// Named and pinned rather than deleted or quietly tolerated. Each is a real
  /// defect with a deterministic reproduction, and the reason says what it is,
  /// so removing an entry is the visible act of claiming it is fixed.
  const known = {
    'true_beginner':
        'sitting_ran_dry on the narrow catalog only, and reachable in '
        'production through a goal that scopes it. Pinned in '
        'sitting_ran_dry_test.dart',
  };

  for (final player in PlayerArchetypes.all) {
    test(
      '${player.id} trips no structural invariant',
      skip: known[player.id],
      () {
        final found = <Anomaly>[];
        for (var seed = 0; seed < seeds; seed++) {
          final trajectory = runTrajectory(
            player: player,
            seed: seed,
            materials: v1ScaleCatalog,
            slots: slots,
          );
          found.addAll(
            detectAnomalies(
              trajectory,
              requestedSlots: slots,
            ).where((a) => a.severity == AnomalySeverity.invariant),
          );
        }

        expect(
          found,
          isEmpty,
          reason: found.map((a) => '${a.summary}\n${a.census}').join('\n\n'),
        );
      },
    );
  }

  test('a detector reads the census it reports from', () {
    // The census is the deliverable. Three wrong diagnoses came from
    // reconstructing this by hand after the fact, so an anomaly that cannot
    // show its working is not worth raising.
    final trajectory = runTrajectory(
      player: PlayerArchetypes.fastButPlacedLow,
      seed: 0,
      materials: v1ScaleCatalog,
      slots: 30,
    );
    final census = censusOf(trajectory.slots.last);

    expect(census, contains('chosen:'));
    expect(census, contains('frontier for'));
    expect(census, contains('best alternatives:'));
    expect(census, contains('RankKey('));
  });
}
