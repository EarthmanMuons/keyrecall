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

  const kinds = ClusterKind.values;

  final byArchetype = <String, Map<ClusterKind, int>>{};
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

      for (final cluster in clustersIn(trajectory)) {
        final kind = describeCluster(cluster);
        counts[kind] = counts[kind]! + 1;
        final held = examples.putIfAbsent('${player.id}/${kind.id}', () => []);
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
      '${kinds.map((k) => k.id.split('_').first.padLeft(14)).join()}',
    );
  for (final entry in byArchetype.entries) {
    stdout.writeln(
      '${entry.key.padRight(22)}'
      '${kinds.map((k) => entry.value[k].toString().padLeft(13)).join()}',
    );
  }
  stdout.writeln('\nlegend: ${kinds.map((k) => k.id).join(' | ')}\n');

  for (final key in examples.keys.toList()..sort()) {
    for (final rendered in examples[key]!) {
      stdout.writeln('$rendered\n');
    }
  }
}

String _render(String archetype, int seed, List<TrajectorySlot> cluster) => [
  '  $archetype seed $seed, '
      '${cluster.first.chosen.material.materialId}, '
      '${cluster.length} slots  [${describeCluster(cluster).id}]',
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
