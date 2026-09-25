import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether identical evidence washes out the starting placement.
///
/// Each history is appended to [--out] as one line when it finishes, and a
/// rerun over the same file runs only the histories it does not hold yet.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '2')
    ..addOption('jobs', defaultsTo: '4')
    ..addOption('out', defaultsTo: 'placement_convergence.jsonl');
  final options = parser.parse(arguments);
  final out = File(options.option('out')!);

  final previous = [
    if (out.existsSync())
      for (final line in out.readAsLinesSync())
        if (line.trim().isNotEmpty)
          PlacementConvergenceRun.fromJson(
            jsonDecode(line) as Map<String, Object?>,
          ),
  ];
  final stopwatch = Stopwatch()..start();
  final fresh = await runPlacementConvergenceMatrix(
    seeds: int.parse(options.option('seeds')!),
    parallelism: int.parse(options.option('jobs')!),
    done: {for (final run in previous) run.identity},
    onRun: (run) => out.writeAsStringSync(
      '${jsonEncode(run.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    ),
    onProgress: (completed, total) => stderr.writeln(
      'completed $completed/$total (${stopwatch.elapsed.inSeconds}s)',
    ),
  );

  stdout
    ..writeln(
      'placement convergence: ${previous.length} resumed, ${fresh.length} '
      'run in ${stopwatch.elapsed.inSeconds}s',
    )
    ..writeln(
      [
        'player',
        'seed',
        'attempts',
        'observed',
        'unobserved',
        'pred_mean',
        'pred_max',
        'band_diff',
        'elig_diff',
        'same_pick',
      ].join('\t'),
    );
  for (final run in [...previous, ...fresh]) {
    for (final point in run.checkpoints) {
      stdout.writeln(
        [
          run.playerId,
          '${run.seed}',
          '${point.attempts}',
          point.observedCompetency.toStringAsFixed(3),
          point.unobservedCompetency.toStringAsFixed(3),
          point.meanPrediction.toStringAsFixed(4),
          point.maxPrediction.toStringAsFixed(3),
          point.bandDisagreement.toStringAsFixed(4),
          point.eligibilityDisagreement.toStringAsFixed(4),
          '${point.sameSelection}',
        ].join('\t'),
      );
    }
  }
}
