import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Every decision a set of trajectories made, in full, for diffing.
///
/// The acceptance test for work that is meant to change nothing: run it before
/// a change and after, and require the two outputs to be byte-identical. A
/// digest would say only that something moved; this says which slot moved
/// first and in which field, which is what makes a divergence diagnosable.
///
/// Emits every semantic field a decision produced rather than a summary:
/// the chosen exercise, each rank term, the eligibility verdict and code, the
/// bypass, the prediction channels, the outcome, and the frontier the attempt
/// left behind.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '3')
    ..addOption('slots', defaultsTo: '40')
    ..addOption(
      'archetypes',
      defaultsTo:
          'developing,uneven_hands,advanced,coordination_limited,'
          'fast_but_placed_low,true_beginner',
    )
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final archetypes = options.option('archetypes')!.split(',');

  final jobs = <TrajectoryJob>[
    for (final archetype in archetypes)
      for (var seed = 0; seed < seeds; seed++)
        TrajectoryJob(archetypeId: archetype, seed: seed),
  ];
  final workers = Platform.numberOfProcessors;
  final buckets = List.generate(workers, (_) => <TrajectoryJob>[]);
  for (final (index, job) in jobs.indexed) {
    buckets[index % workers].add(job);
  }

  final batches = await Future.wait([
    for (final bucket in buckets)
      if (bucket.isNotEmpty) Isolate.run(() => _linesFor(bucket, slots)),
  ]);

  // Reassembled in job order rather than completion order, so the output is a
  // function of the input alone.
  final byJob = <String, List<String>>{};
  for (final batch in batches) {
    byJob.addAll(batch);
  }
  for (final job in jobs) {
    final lines = byJob['${job.archetypeId}/${job.seed}'] ?? const [];
    for (final line in lines) {
      stdout.writeln(line);
    }
  }
}

Map<String, List<String>> _linesFor(List<TrajectoryJob> jobs, int slots) {
  final byJob = <String, List<String>>{};

  for (final job in jobs) {
    final lines = <String>[];
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );

    for (final slot in trajectory.slots) {
      final winner = slot.winner;
      final exercise = winner.exercise;
      final conditions = exercise.conditions;
      final key = winner.rankKey!;
      final prediction = winner.prediction;
      final outcome = slot.outcome;
      lines.add(
        [
          job.archetypeId,
          job.seed,
          slot.index,
          exercise.material.materialId,
          conditions.hands.id,
          conditions.handMotion.id,
          conditions.direction.id,
          conditions.octaves,
          conditions.tempoBpm.toStringAsFixed(4),
          exercise.guidance.independence,
          winner.eligibility.tier.id,
          winner.eligibility.code.id,
          winner.challengeBypass?.id ?? '-',
          winner.isWithinChallengeBand,
          winner.challengeSurvived,
          key.tier.id,
          key.coordinationTransition,
          key.contraryCoordination,
          key.retention.toStringAsFixed(9),
          key.information.toStringAsFixed(9),
          key.diversity.toStringAsFixed(9),
          key.goals.toStringAsFixed(9),
          key.realization.id,
          key.realizationFit.toStringAsFixed(9),
          prediction.independentRetrievalP.toStringAsFixed(9),
          prediction.materialAvailableP.toStringAsFixed(9),
          prediction.executionP.toStringAsFixed(9),
          prediction.topologyP.toStringAsFixed(9),
          outcome.started,
          outcome.completed,
          outcome.retrieval.name,
          outcome.pitchIntegrity.toStringAsFixed(9),
          outcome.achievedTempoRatio.toStringAsFixed(9),
          slot.managedExecution,
          slot.performedTempoBpm.toStringAsFixed(9),
          _frontier(slot.frontierAfter),
          slot.candidates.evaluated,
          slot.candidates.eligible,
          slot.candidates.admitted,
          slot.candidates.selectable,
        ].join('\t'),
      );
    }

    final terminal = trajectory.terminal;
    if (terminal != null) {
      lines.add('${job.archetypeId}\t${job.seed}\t${terminal.index}\tTERMINAL');
    }
    byJob['${job.archetypeId}/${job.seed}'] = lines;
  }

  return byJob;
}

String _frontier(Map<int, double> byOctaves) {
  final spans = byOctaves.keys.toList()..sort();
  return [
    for (final span in spans) '$span:${byOctaves[span]!.toStringAsFixed(4)}',
  ].join(',');
}
