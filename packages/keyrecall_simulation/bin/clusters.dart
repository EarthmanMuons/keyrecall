import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What is happening inside a run of slots on one material.
///
/// Replaces a diagnostic written against the mislabelled cycle detector, whose
/// predicate counted a solid run as an alternation. Kept as a separate command
/// rather than folded into a detector, because run length is not the question:
/// six slots on one scale can be a learner working through it hand by hand and
/// then together, or it can be somebody held at full cueing while nothing
/// improves, and those want different answers.
///
/// So each cluster is described by the evidence inside it rather than by how
/// long it is.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '25')
    ..addOption('slots', defaultsTo: '50')
    ..addOption('examples', defaultsTo: '2');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final exampleLimit = int.parse(options.option('examples')!);

  const kinds = [
    'improving',
    'finding support',
    'oscillating support',
    'stuck at the floor',
    'coordination phase',
    'other',
  ];

  final byArchetype = <String, Map<String, int>>{};
  final examples = <String, List<String>>{};

  for (final player in PlayerArchetypes.all) {
    final counts = {for (final kind in kinds) kind: 0};

    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      );

      for (final cluster in _clustersIn(trajectory)) {
        final kind = _describe(cluster);
        counts[kind] = counts[kind]! + 1;
        final held = examples.putIfAbsent('${player.id}/$kind', () => []);
        if (held.length < exampleLimit) {
          held.add(_render(player.id, seed, cluster));
        }
      }
    }
    byArchetype[player.id] = counts;
  }

  stdout
    ..writeln(
      'clusters of six or more slots on one material, '
      '$seeds seeds x $slots slots\n',
    )
    ..writeln(
      '${'archetype'.padRight(22)}'
      '${kinds.map((k) => k.split(' ').first.padLeft(13)).join()}',
    );
  for (final entry in byArchetype.entries) {
    stdout.writeln(
      '${entry.key.padRight(22)}'
      '${kinds.map((k) => entry.value[k].toString().padLeft(13)).join()}',
    );
  }
  stdout.writeln('\nlegend: ${kinds.join(' | ')}\n');

  for (final key in examples.keys.toList()..sort()) {
    for (final rendered in examples[key]!) {
      stdout.writeln('$rendered\n');
    }
  }
}

/// Every run of six or more consecutive slots on one material.
List<List<TrajectorySlot>> _clustersIn(Trajectory trajectory) {
  final found = <List<TrajectorySlot>>[];
  var start = 0;
  for (var i = 1; i <= trajectory.slots.length; i++) {
    final ended =
        i == trajectory.slots.length ||
        trajectory.slots[i].chosen.material.materialId !=
            trajectory.slots[start].chosen.material.materialId;
    if (!ended) continue;
    if (i - start >= 6) found.add(trajectory.slots.sublist(start, i));
    start = i;
  }
  return found;
}

/// Which kind of cluster this is, read from what changed inside it.
String _describe(List<TrajectorySlot> cluster) {
  final motor = [for (final slot in cluster) slot.outcome.motorScore];
  final independence = [
    for (final slot in cluster) slot.chosen.guidance.independence,
  ];
  final hands = {for (final slot in cluster) slot.chosen.conditions.hands};

  if (hands.contains(HandConfiguration.together) && hands.length > 1) {
    return 'coordination phase';
  }
  // Monotone or oscillating, which the ends alone cannot tell apart. A run of
  // introduce, recover, introduce, recover ends lower than it started and is
  // not a learner settling on the support they need.
  var descents = 0;
  var climbs = 0;
  for (var i = 1; i < independence.length; i++) {
    if (independence[i] < independence[i - 1]) descents++;
    if (independence[i] > independence[i - 1]) climbs++;
  }
  if (descents > 0 && climbs > 0) return 'oscillating support';
  if (descents > 0) return 'finding support';

  final firstHalf = motor.take(motor.length ~/ 2);
  final secondHalf = motor.skip(motor.length ~/ 2);
  double mean(Iterable<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  final movement = mean(secondHalf) - mean(firstHalf);

  if (movement > 0.1) return 'improving';
  // At the most supportive rung the ladder has, and going nowhere.
  if (independence.every((rung) => rung == 0) && mean(motor) < 0.4) {
    return 'stuck at the floor';
  }
  return 'other';
}

String _render(String archetype, int seed, List<TrajectorySlot> cluster) => [
  '  $archetype seed $seed, '
      '${cluster.first.chosen.material.materialId}, '
      '${cluster.length} slots  [${_describe(cluster)}]',
  for (final slot in cluster)
    '    ${slot.index.toString().padLeft(3)} '
        '${slot.chosen.conditions.hands.id.padRight(9)}'
        'g=${slot.chosen.guidance.independence} '
        '${slot.chosen.conditions.tempoBpm.toStringAsFixed(0).padLeft(3)}bpm '
        '${(slot.winner.challengeBypass?.id ?? 'in-band').padRight(22)}'
        'motor=${slot.outcome.motorScore.toStringAsFixed(2)} '
        'pitch=${slot.outcome.pitchIntegrity.toStringAsFixed(2)} '
        'started=${slot.outcome.started} done=${slot.outcome.completed}',
].join('\n');
