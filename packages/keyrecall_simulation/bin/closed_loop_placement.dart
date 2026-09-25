import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether the same player ends up practicing alike from every starting level.
///
/// Each group is appended to [--out] when it finishes, and a rerun over the
/// same file runs only the groups it does not hold yet.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '2')
    ..addOption('jobs', defaultsTo: '4')
    ..addOption('out', defaultsTo: 'closed_loop_placement.jsonl');
  final options = parser.parse(arguments);
  final out = File(options.option('out')!);

  final previous = [
    if (out.existsSync())
      for (final line in out.readAsLinesSync())
        if (line.trim().isNotEmpty)
          ClosedLoopGroup.fromJson(jsonDecode(line) as Map<String, Object?>),
  ];
  final stopwatch = Stopwatch()..start();
  final fresh = await runClosedLoopPlacementMatrix(
    seeds: int.parse(options.option('seeds')!),
    parallelism: int.parse(options.option('jobs')!),
    done: {for (final group in previous) group.identity},
    onGroup: (group) => out.writeAsStringSync(
      '${jsonEncode(group.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    ),
    onProgress: (completed, total) => stderr.writeln(
      'completed $completed/$total (${stopwatch.elapsed.inSeconds}s)',
    ),
  );

  final facets = ['guidance', 'hands', 'octaves', 'direction', 'family'];
  stdout
    ..writeln(
      'closed-loop placement: ${previous.length} resumed, ${fresh.length} '
      'run in ${stopwatch.elapsed.inSeconds}s',
    )
    ..writeln(
      [
        'scope',
        'player',
        'seed',
        'sittings',
        'covered',
        ...facets,
        'overlap',
        'same_pick',
      ].join('\t'),
    );
  for (final group in [...previous, ...fresh]) {
    for (final point in group.checkpoints) {
      stdout.writeln(
        [
          group.scope.name,
          group.playerId,
          '${group.seed}',
          '${point.sittings}',
          point.covered.map((value) => value.toStringAsFixed(2)).join('/'),
          for (final facet in facets)
            point.mixDistance[facet]!.toStringAsFixed(3),
          point.eligibleOverlap.toStringAsFixed(3),
          '${point.samePick}',
        ].join('\t'),
      );
    }
  }
}
