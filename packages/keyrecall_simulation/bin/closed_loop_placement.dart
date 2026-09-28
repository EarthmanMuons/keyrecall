import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

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

  final out = ResumableOutput(File(options.option('out')!), {
    'experiment': 'closed_loop_placement',
    'format': 1,
    'scopes': [
      GoalTrajectoryScope.general.name,
      GoalTrajectoryScope.foundations.name,
    ],
    'checkpoints': closedLoopCheckpoints,
    'slots_per_session': 20,
    ...modelConfiguration(
      schedulerModelVersion: v1SchedulerConfig.modelVersion,
    ),
  });
  final previous = [
    for (final record in out.resume()) ClosedLoopGroup.fromJson(record),
  ];
  final stopwatch = Stopwatch()..start();
  final fresh = await runClosedLoopPlacementMatrix(
    seeds: int.parse(options.option('seeds')!),
    parallelism: int.parse(options.option('jobs')!),
    done: {for (final group in previous) group.identity},
    onGroup: (group) => out.append(group.toJson()),
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
        'sessions',
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
          '${point.sessions}',
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
