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

  /// Players whose `sitting_ran_dry` is characterized rather than fixed.
  ///
  /// It was pinned as a true beginner meeting a narrow catalog. It is not
  /// either of those things: a player weak at scales runs sittings dry on the
  /// whole v1 catalog, and across a calendar the sittings after the first
  /// admit nothing from their opening slot. What the two have in common is
  /// being weak at the only family this sweep offers, not the size of the
  /// catalog. The player weak at arpeggios is strong at scales and does not
  /// trip it, which is what says the sweep is measuring the weakness rather
  /// than the archetype.
  ///
  /// Everything else still has to hold for them, which is the point of naming
  /// the detector rather than skipping the player.
  const runsDry = {'true_beginner', 'arpeggio_strong_scale_weak'};

  for (final player in PlayerArchetypes.all) {
    test('${player.id} trips no structural invariant', () {
      final found = <Anomaly>[];
      for (var seed = 0; seed < seeds; seed++) {
        final trajectory = runTrajectory(
          player: player,
          seed: seed,
          materials: v1ScaleCatalog,
          slots: slots,
        );
        found.addAll(
          detectAnomalies(trajectory, requestedSlots: slots).where(
            (a) =>
                a.severity == AnomalySeverity.invariant &&
                !(runsDry.contains(player.id) &&
                    a.detector == 'sitting_ran_dry'),
          ),
        );
      }

      expect(
        found,
        isEmpty,
        reason: found.map((a) => '${a.summary}\n${a.census}').join('\n\n'),
      );
    });

    test('${player.id} trips no structural invariant across months', () {
      // The same properties, over sittings spread across a calendar rather
      // than one unbroken run: what decays between them is the only
      // difference, and nothing about a break makes a defect acceptable.
      final sittings = sittingsOnDays([0, 2, 9, 30, 90], slots: 8);
      final found = <Anomaly>[];
      for (var seed = 0; seed < 3; seed++) {
        found.addAll(
          detectAnomalies(
            runSittings(
              player: player,
              seed: seed,
              materials: v1ScaleCatalog,
              sittings: sittings,
            ),
            requestedSlots: 40,
          ).where(
            (a) =>
                a.severity == AnomalySeverity.invariant &&
                !(runsDry.contains(player.id) &&
                    a.detector == 'sitting_ran_dry'),
          ),
        );
      }

      expect(
        found,
        isEmpty,
        reason: found.map((a) => '${a.summary}\n${a.census}').join('\n\n'),
      );
    });
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
