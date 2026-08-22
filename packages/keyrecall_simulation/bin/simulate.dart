/// Runs a synthetic learner through practice attempts and emits a JSON-lines
/// trace of predictions, outcomes, evidence, and state.
///
/// The Dart counterpart of `analysis/learner-model/simulate.py`, emitting the
/// same records so the two can be diffed directly:
///
/// ```console
/// dart run keyrecall_simulation:simulate --profile advanced --attempts 60 --seed 0
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main(List<String> arguments) {
  final profileIds = SyntheticProfile.values.map((p) => p.id).toList()..sort();
  final parser = ArgParser()
    ..addOption('profile', allowed: profileIds, mandatory: true)
    ..addOption('attempts', defaultsTo: '100')
    ..addOption('seed', defaultsTo: '0')
    ..addOption('out', help: 'Output file; defaults to stdout.')
    ..addFlag('help', negatable: false, help: 'Show this usage information.');

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final profile = SyntheticProfile.values.firstWhere(
    (candidate) => candidate.id == options.option('profile'),
  );
  final simulation = PracticeSimulation.of(
    profile,
    seed: int.parse(options.option('seed')!),
  );
  final traces = simulation.run(int.parse(options.option('attempts')!));

  final lines = traces
      .map(
        (trace) =>
            jsonEncode(attemptTraceToJson(trace, epoch: simulation.epoch)),
      )
      .join('\n');

  final out = options.option('out');
  if (out == null) {
    stdout.writeln(lines);
  } else {
    File(out).writeAsStringSync('$lines\n');
  }
}
