import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

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
///
/// Trajectories run across isolates. Almost all of a sweep is `evaluate`,
/// which is pure computation, and a trajectory is determined by its archetype,
/// seed and configuration, so the only thing parallelism changes is how long
/// it takes. `trajectory_digest_test.dart` holds that to account.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'seeds',
      defaultsTo: '25',
      help:
          'Seeds per archetype. Twenty-five is the iteration sweep, a couple '
          'of minutes; a hundred or more is the wide one to run deliberately '
          'either side of a scheduler change.',
    )
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
  final worked = <String, List<(String, int, _Finding)>>{};

  // Trajectories are independent and deterministic in the archetype, the seed
  // and the configuration, so they can run at once and be assembled in a fixed
  // order afterwards. Dealt round robin rather than one isolate per archetype:
  // a true beginner's sitting costs a fraction of an advanced one, so grouping
  // by archetype leaves the slowest one gating the whole sweep.
  final stopwatch = Stopwatch()..start();
  final workers = Platform.numberOfProcessors;
  final buckets = List.generate(workers, (_) => <_Job>[]);
  var next = 0;
  for (final player in PlayerArchetypes.all) {
    for (var seed = 0; seed < seeds; seed++) {
      buckets[next++ % workers].add(_Job(player: player, seed: seed));
    }
  }

  final running = [
    for (final bucket in buckets)
      if (bucket.isNotEmpty) Isolate.run(() => _findingsFor(bucket, slots)),
  ];
  final findings = [for (final batch in await Future.wait(running)) ...batch];
  stdout.writeln(
    'swept ${PlayerArchetypes.all.length * seeds} trajectories across '
    '${running.length} isolates in ${stopwatch.elapsed.inSeconds}s',
  );

  for (final player in PlayerArchetypes.all) {
    final counts = <String, int>{};
    for (final finding in findings) {
      if (finding.archetype != player.id) continue;
      counts[finding.detector] = (counts[finding.detector] ?? 0) + 1;
      severities[finding.detector] = finding.severity;
      final examples = worked.putIfAbsent(finding.detector, () => []);
      if (examples.length < censusLimit && finding.census != null) {
        examples.add((player.id, finding.seed, finding));
      }
    }
    incidence[player.id] = counts;
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
    for (final (archetype, seed, finding) in examples) {
      stdout
        ..writeln()
        ..writeln('--- $archetype seed $seed')
        ..writeln(finding.summary)
        ..writeln(finding.census);
    }
  }
}

String _abbreviate(String detector) {
  final parts = detector.split('_');
  return parts.length == 1
      ? detector.substring(0, detector.length.clamp(0, 9))
      : parts.map((part) => part.substring(0, 3)).join('.');
}

/// One trajectory to run.
class _Job {
  final SyntheticPlayer player;
  final int seed;

  const _Job({required this.player, required this.seed});
}

/// One anomaly, flattened to what crosses an isolate boundary.
class _Finding {
  final String archetype;
  final String detector;
  final AnomalySeverity severity;
  final int seed;
  final String summary;
  final String? census;

  const _Finding({
    required this.archetype,
    required this.detector,
    required this.severity,
    required this.seed,
    required this.summary,
    this.census,
  });
}

/// Every anomaly one bucket of trajectories produces, in its own isolate.
List<_Finding> _findingsFor(List<_Job> jobs, int slots) {
  final generated = generateCandidates(InstrumentProfile(), allScales);
  return [
    for (final job in jobs)
      for (final anomaly in detectAnomalies(
        runTrajectory(
          player: job.player,
          seed: job.seed,
          materials: allScales,
          slots: slots,
          generated: generated,
        ),
        requestedSlots: slots,
      ))
        _Finding(
          archetype: job.player.id,
          detector: anomaly.detector,
          severity: anomaly.severity,
          seed: job.seed,
          summary: anomaly.summary,
          census: anomaly.census,
        ),
  ];
}
