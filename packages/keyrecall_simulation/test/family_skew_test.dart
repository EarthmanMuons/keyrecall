import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final catalog = <TechnicalMaterial>[
    ...v1ScaleCatalog.take(3),
    ...proofArpeggios.take(3),
  ];
  final set = standardAssessment(catalog, repetitions: 2);
  const scales = TechnicalMaterial.scaleFamilyId;
  const arpeggios = TechnicalMaterial.arpeggioFamilyId;

  /// Each skew, keyed by the family the player is weak in.
  final weakIn = {
    scales: PlayerArchetypes.arpeggioStrongScaleWeak,
    arpeggios: PlayerArchetypes.scaleStrongArpeggioWeak,
  };
  const seeds = [2, 4];

  // Run once and ask several questions of the same trajectories, because each
  // is eighty slots against the real pipeline.
  final runs = {
    for (final weak in weakIn.keys)
      for (final seed in seeds)
        (weak, seed): runSittings(
          player: weakIn[weak]!,
          seed: seed,
          materials: catalog,
          sittings: sittingsOnDays([0, 1, 2, 3], slots: 20),
          assessment: set,
        ),
  };

  String otherThan(String family) => family == scales ? arpeggios : scales;

  double shareOf(Trajectory trajectory, String family) =>
      trajectory.slots
          .where((slot) => slot.chosen.material.familyId == family)
          .length /
      trajectory.slots.length;

  Iterable<TrajectorySlot> slotsIn(Trajectory trajectory, String family) =>
      trajectory.slots.where((slot) => slot.chosen.material.familyId == family);

  test('a reading reports each family that was asked about', () {
    final reading = runs[(arpeggios, 2)]!.assessments.first;

    expect(reading.families.keys, unorderedEquals([scales, arpeggios]));
    expect(
      reading.families.values.map((r) => r.attempts).reduce((a, b) => a + b),
      reading.attempts,
    );
    expect(
      reading.families[scales]!.managed,
      greaterThan(reading.families[arpeggios]!.managed),
      reason: 'the skew is there before any practice happens',
    );
    expect(
      reading.families[scales]!.families,
      isEmpty,
      reason: 'a family reading does not divide itself again',
    );
  });

  test('the sitting spends itself on the family already going well', () {
    for (final entry in runs.entries) {
      final (weak, seed) = entry.key;
      expect(
        shareOf(entry.value, otherThan(weak)),
        greaterThan(shareOf(entry.value, weak)),
        reason:
            'allocation went to the strong family for a player weak in $weak '
            'at seed $seed, so the weaker one is not what gets practised',
      );
    }
  });

  test('the weak family does not improve while the strong one does', () {
    for (final entry in runs.entries) {
      final (weak, seed) = entry.key;
      final before = entry.value.assessments.first.families;
      final after = entry.value.assessments.last.families;
      final where = 'weak in $weak at seed $seed';

      expect(
        after[weak]!.managed,
        lessThanOrEqualTo(before[weak]!.managed),
        reason: 'eighty slots left held-out $weak no better, $where',
      );
      expect(
        after[otherThan(weak)]!.managed,
        greaterThan(before[otherThan(weak)]!.managed),
        reason: 'while the strong family improved, $where',
      );
    }
  });

  test('a family is asked past its own evidence at the other one\'s pace', () {
    for (final entry in runs.entries) {
      final (weak, seed) = entry.key;
      final where = 'weak in $weak at seed $seed';
      // Slots where this family has demonstrated nothing at all at the span
      // being asked for, so nothing it has earned can explain the tempo.
      final unearned = [
        for (final slot in slotsIn(entry.value, weak))
          if (slot.frontierAtSpan == 0 && slot.chosen.conditions.tempoBpm > 60)
            slot,
      ];

      expect(
        unearned,
        isNotEmpty,
        reason:
            '$weak was asked for above the gentle entry tempo while having '
            'demonstrated nothing at that span, $where',
      );
      for (final slot in unearned) {
        expect(
          slot.chosen.conditions.tempoBpm,
          lessThanOrEqualTo(slot.transferableBefore),
          reason:
              'and what made that rung reachable is the median this hand '
              'shows on material it owns, which counts ${otherThan(weak)} as '
              'evidence about $weak, at slot ${slot.index}, $where',
        );
      }
    }
  });
}
