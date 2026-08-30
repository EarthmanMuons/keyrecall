import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Sweeps every archetype over many seeds and reports what went wrong.
///
/// Deliberately a command rather than a test. A full sweep is minutes of work
/// and answers a question about the scheduler's behavior over a space, which
/// is not the question a check on every commit should be asking; the tests
/// that run every time pin the invariants on a handful of known seeds.
///
/// Reports incidence by archetype and detector rather than individual
/// failures, because the useful finding is almost never one seed. Three
/// archetypes tripping the same detector is one defect, and a report that
/// lists eight hundred trajectories hides that.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '100', help: 'Seeds per archetype.')
    ..addOption('slots', defaultsTo: '50', help: 'Attempts per sitting.')
    ..addOption(
      'census',
      defaultsTo: '3',
      help: 'How many worked examples to print per detector.',
    )
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final censusLimit = int.parse(options.option('census')!);

  final incidence = <String, Map<String, int>>{};
  final severities = <String, AnomalySeverity>{};
  final worked = <String, List<(String, int, Anomaly)>>{};

  final stopwatch = Stopwatch()..start();
  for (final player in PlayerArchetypes.all) {
    final counts = <String, int>{};
    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      );
      for (final anomaly in detectAnomalies(
        trajectory,
        requestedSlots: slots,
      )) {
        counts[anomaly.detector] = (counts[anomaly.detector] ?? 0) + 1;
        severities[anomaly.detector] = anomaly.severity;
        final examples = worked.putIfAbsent(anomaly.detector, () => []);
        if (examples.length < censusLimit && anomaly.census != null) {
          examples.add((player.id, seed, anomaly));
        }
      }
    }
    incidence[player.id] = counts;
    stdout.writeln('${player.id} done (${stopwatch.elapsed.inSeconds}s)');
  }

  final detectors = severities.keys.toList()
    ..sort(
      (a, b) => severities[a] == severities[b]
          ? a.compareTo(b)
          : severities[a]!.index.compareTo(severities[b]!.index),
    );

  stdout
    ..writeln()
    ..writeln('== anomaly incidence: $seeds seeds x $slots slots per archetype')
    ..writeln(
      '   counts are anomalies raised, so one run may contribute more '
      'than one',
    )
    ..writeln();

  final width = detectors.fold(
    22,
    (w, d) => d.length + 2 > w ? d.length + 2 : w,
  );
  for (final detector in detectors) {
    stdout.writeln('  ${severities[detector]!.id.padRight(12)}$detector');
  }
  stdout
    ..writeln()
    ..write('archetype'.padRight(24));
  for (final detector in detectors) {
    stdout.write(_abbreviate(detector).padLeft(10));
  }
  stdout.writeln();
  for (final entry in incidence.entries) {
    stdout.write(entry.key.padRight(24));
    for (final detector in detectors) {
      stdout.write('${entry.value[detector] ?? 0}'.padLeft(10));
    }
    stdout.writeln();
  }

  for (final detector in detectors) {
    final examples = worked[detector];
    if (examples == null || examples.isEmpty) continue;
    stdout
      ..writeln()
      ..writeln('=' * width)
      ..writeln('$detector (${severities[detector]!.id})');
    for (final (archetype, seed, anomaly) in examples) {
      stdout
        ..writeln()
        ..writeln('--- $archetype seed $seed')
        ..writeln(anomaly.summary)
        ..writeln(anomaly.census);
    }
  }
}

String _abbreviate(String detector) {
  final parts = detector.split('_');
  return parts.length == 1
      ? detector.substring(0, detector.length.clamp(0, 9))
      : parts.map((part) => part.substring(0, 3)).join('.');
}
