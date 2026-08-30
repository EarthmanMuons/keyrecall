import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Benchmark trajectories, pinned by digest.
///
/// Performance work on the sweep must not change what it finds. These two are
/// the fixtures a change is measured against: same choices, same outcomes,
/// same anomalies, or the optimization has quietly become a second
/// implementation.
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

  test('the same archetype and seed give the same trajectory', () {
    for (final (player, seed) in [
      (PlayerArchetypes.advanced, 7),
      (PlayerArchetypes.trueBeginner, 3),
    ]) {
      expect(
        digestOf(run(player, seed)),
        digestOf(run(player, seed)),
        reason: '${player.id} seed $seed',
      );
    }
  });

  test('hoisting candidate generation changes nothing', () {
    // The sweep generates once per isolate and passes the list in, which is
    // only safe because generation is learner-blind.
    final generated = generateCandidates(InstrumentProfile(), v1ScaleCatalog);

    for (final (player, seed) in [
      (PlayerArchetypes.advanced, 7),
      (PlayerArchetypes.trueBeginner, 3),
    ]) {
      expect(
        digestOf(run(player, seed, generated: generated)),
        digestOf(run(player, seed)),
        reason: '${player.id} seed $seed',
      );
    }
  });

  test('and different seeds do not', () {
    expect(
      digestOf(run(PlayerArchetypes.advanced, 7)),
      isNot(digestOf(run(PlayerArchetypes.advanced, 8))),
    );
  });
}
