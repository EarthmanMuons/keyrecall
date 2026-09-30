import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Benchmark trajectories, pinned by digest.
///
/// Performance work on the sweep must not change what it finds. These are the
/// fixtures a change is measured against: same choices, same outcomes, same
/// anomalies, or the optimization has quietly become a second implementation.
/// A deliberate change to scheduling regenerates them in the same step.
const pinned = [
  (
    player: 'advanced',
    seed: 7,
    digest: '1142158a0a2d297c1c73f786968660cc8516e9ecf641d5ee00bf0d511e61a80e',
  ),
  (
    player: 'true_beginner',
    seed: 3,
    digest: 'eb474cbeff02fe809082394dd678b66898a2c98c5bd48fa85043813ed569b1d9',
  ),
];

void main() {
  String digestOf(Trajectory trajectory) {
    final lines = [
      for (final slot in trajectory.slots)
        [
          slot.index,
          slot.chosen.material.materialId,
          slot.chosen.conditions.hands.id,
          slot.chosen.conditions.octaves,
          slot.chosen.conditions.direction.name,
          slot.chosen.conditions.tempoBpm,
          slot.chosen.guidance.independence,
          slot.winner.challengeBypass?.id ?? 'in-band',
          slot.winner.rankKey!.realization.id,
          slot.outcome.completed,
          slot.outcome.pulseMaintenance.name,
          slot.outcome.pitchIntegrity.toStringAsFixed(6),
          slot.performedTempoBpm.toStringAsFixed(6),
          slot.frontierBefore.toString(),
          slot.handsTogether.fullyEligibleSelectable.toList()..sort(),
        ].join('|'),
    ];
    return sha256.convert(utf8.encode(lines.join('\n'))).toString();
  }

  Trajectory run(
    SyntheticPlayer player,
    int seed, {
    List<Exercise>? generated,
  }) => runTrajectory(
    player: player,
    seed: seed,
    materials: v1ScaleCatalog,
    slots: 50,
    generated: generated,
  );

  SyntheticPlayer playerNamed(String id) =>
      PlayerArchetypes.all.firstWhere((player) => player.id == id);

  for (final (:player, :seed, :digest) in pinned) {
    test('$player at seed $seed is pinned', () {
      expect(digestOf(run(playerNamed(player), seed)), digest);
    });
  }

  test('hoisting candidate generation changes nothing', () {
    // The sweep generates once per isolate and passes the list in, which is
    // only safe because generation is learner-blind.
    final generated = generateCandidates(InstrumentProfile(), v1ScaleCatalog);

    for (final (:player, :seed, :digest) in pinned) {
      expect(
        digestOf(run(playerNamed(player), seed, generated: generated)),
        digest,
        reason: '$player seed $seed',
      );
    }
  });

  test('and different seeds do not', () {
    final (:player, :seed, :digest) = pinned.first;

    expect(digestOf(run(playerNamed(player), seed + 1)), isNot(digest));
  });
}
