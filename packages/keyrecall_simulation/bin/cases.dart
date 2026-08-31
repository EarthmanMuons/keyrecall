import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('detector')
    ..addOption('archetype', help: 'One archetype, or all when omitted.')
    ..addOption('seeds', defaultsTo: '100')
    ..addOption('slots', defaultsTo: '50')
    ..addOption('limit', defaultsTo: '3', help: 'Cases per archetype.')
    ..addOption('order', allowed: ['first', 'worst'], defaultsTo: 'first')
    ..addFlag('summary-only', negatable: false)
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final detector = options.option('detector');
  if (detector == null) {
    stderr.writeln('--detector is required\n\n${parser.usage}');
    exitCode = 64;
    return;
  }
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final limit = int.parse(options.option('limit')!);
  final requestedArchetype = options.option('archetype');
  final players = requestedArchetype == null
      ? PlayerArchetypes.all
      : [
          PlayerArchetypes.all.firstWhere(
            (player) => player.id == requestedArchetype,
            orElse: () => throw ArgumentError.value(
              requestedArchetype,
              'archetype',
              'unknown archetype',
            ),
          ),
        ];
  final generated = generateCandidates(InstrumentProfile(), allScales);
  final jobs = [
    for (final player in players)
      for (var seed = 0; seed < seeds; seed++) (player, seed),
  ];
  final buckets = List.generate(
    Platform.numberOfProcessors,
    (_) => <(SyntheticPlayer, int)>[],
  );
  for (var i = 0; i < jobs.length; i++) {
    buckets[i % buckets.length].add(jobs[i]);
  }
  final trajectories = [
    for (final batch in await Future.wait([
      for (final bucket in buckets)
        if (bucket.isNotEmpty)
          Isolate.run(() => _runCases(bucket, slots, generated)),
    ]))
      ...batch,
  ];
  final found = trajectoryCases(
    trajectories,
    detector: detector,
    requestedSlots: slots,
  );
  final selected = selectTrajectoryCases(
    found,
    limit: limit,
    order: options.option('order') == 'worst'
        ? CaseOrder.worst
        : CaseOrder.first,
  );

  stdout.writeln(
    '$detector: showing ${selected.length} of ${found.length} cases from '
    '${players.length * seeds} trajectories',
  );
  for (final selectedCase in selected) {
    stdout
      ..writeln()
      ..writeln(
        options.flag('summary-only')
            ? '${selectedCase.trajectory.playerId} seed '
                  '${selectedCase.trajectory.seed}\n'
                  '${selectedCase.anomaly.detector} '
                  'magnitude=${selectedCase.anomaly.magnitude.toStringAsFixed(2)}\n'
                  '${selectedCase.anomaly.summary}'
            : renderTrajectoryCase(selectedCase),
      );
  }
}

List<Trajectory> _runCases(
  List<(SyntheticPlayer, int)> jobs,
  int slots,
  List<Exercise> generated,
) => [
  for (final (player, seed) in jobs)
    runTrajectory(
      player: player,
      seed: seed,
      materials: allScales,
      slots: slots,
      generated: generated,
    ),
];
