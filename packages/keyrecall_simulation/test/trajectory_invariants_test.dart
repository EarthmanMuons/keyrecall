import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

import 'support/seed_budget.dart';

/// Properties the scheduler must hold for every kind of player.
///
/// Invariants only. The observational detectors are counts against thresholds
/// nobody has calibrated, and asserting one would freeze today's behavior as
/// the definition of healthy practice; they are reported by `bin/sweep.dart`
/// and read, not enforced.
///
/// A handful of seeds on the small catalog, because this runs on every commit.
/// `KEYRECALL_SEED_SCALE` widens it on demand; the widest search is the
/// sweep's job.
void main() {
  final seeds = seedBudget(6);
  const slots = 40;

  Iterable<String> invariantsBroken(
    Trajectory trajectory, {
    required int requestedSlots,
  }) => [
    for (final anomaly in detectAnomalies(
      trajectory,
      requestedSlots: requestedSlots,
    ))
      if (anomaly.severity == AnomalySeverity.invariant)
        'seed ${trajectory.seed}: ${anomaly.summary}\n${anomaly.census}',
  ];

  for (final player in PlayerArchetypes.all) {
    test('${player.id} trips no structural invariant', () {
      final found = <String>[];
      for (var seed = 0; seed < seeds; seed++) {
        final pacing = PacingLog();
        final trajectory = runTrajectory(
          player: player,
          seed: seed,
          materials: v1ScaleCatalog,
          slots: slots,
          observePacing: (_, decision) => pacing.record(decision),
        );
        found.addAll(invariantsBroken(trajectory, requestedSlots: slots));
        for (final slot in trajectory.slots) {
          expect(
            slot.winner.isRanked,
            isTrue,
            reason:
                'seed $seed slot ${slot.index} chose an unadmitted exercise',
          );
          expect(
            slot.candidates.selectable,
            greaterThan(0),
            reason: 'seed $seed slot ${slot.index} had nothing selectable',
          );
        }
        for (final setAside in pacing.setAsides) {
          expect(setAside.isRelievable, isTrue, reason: 'seed $seed');
          expect(setAside.pressured.isRanked, isTrue, reason: 'seed $seed');
          expect(setAside.relieving.isRanked, isTrue, reason: 'seed $seed');
        }
      }

      expect(found, isEmpty, reason: found.join('\n\n'));
    });

    test('${player.id} trips no structural invariant across months', () {
      // The same properties, over sessions spread across a calendar rather
      // than one unbroken run: what decays between them is the only
      // difference, and nothing about a break makes a defect acceptable. The
      // month of short sessions is where dose control contracts a family, and
      // seed 4 is where that contraction was first checked.
      final found = <String>[];
      for (final (sessions, firstSeed, seeds) in [
        (sessionsOnDays([0, 2, 9, 30, 90], slots: 8), 0, seedBudget(3)),
        (
          LongitudinalSchedules.named('normal_month', slots: 12),
          4,
          seedBudget(1),
        ),
      ]) {
        for (var seed = firstSeed; seed < firstSeed + seeds; seed++) {
          found.addAll(
            invariantsBroken(
              runTrajectorySessions(
                player: player,
                seed: seed,
                materials: v1ScaleCatalog,
                sessions: sessions,
              ),
              requestedSlots: sessions.fold<int>(
                0,
                (sum, session) => sum + session.slots,
              ),
            ),
          );
        }
      }

      expect(found, isEmpty, reason: found.join('\n\n'));
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
