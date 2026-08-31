import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What each hand motion is asked for the first time it is played.
///
/// `developing` reaches a contrary hands-together frontier and never a parallel
/// one, while playing parallel more often than contrary. The two are identical
/// in predicted difficulty, so any systematic difference has to come from the
/// conditions each is offered under rather than from the exercise.
///
/// The suspicion is an abstraction gap. `ExecutionContext` became
/// motion-specific, so parallel is a context with no evidence once contrary has
/// spent the coordination transition. The transition enters at
/// [handsTogetherEntryTempo], a rung below the slower hand; ordinary execution
/// progression may enter the new context as though hands-together execution
/// were already established.
///
/// So this pairs, per material, the introductory attempt with the first attempt
/// of the other motion, and prints each against the tempos available to derive
/// an entry from.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetypes', defaultsTo: 'developing,advanced,uneven_hands')
    ..addOption('seeds', defaultsTo: '6')
    ..addOption('slots', defaultsTo: '60')
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
      if (bucket.isNotEmpty) Isolate.run(() => _entriesFor(bucket, slots)),
  ]);
  final entries = [for (final batch in batches) ...batch];

  stdout.writeln(
    'first attempt of each hand motion, ${entries.length} recorded\n'
    '  asked   = requested tempo\n'
    '  entry   = handsTogetherEntryTempo, a rung below the slower ready hand\n'
    '  ready   = the slower hand\'s own coordination-ready tempo\n'
    '  sibling = the other motion\'s frontier at this span, or 0\n'
    '  over    = asked minus entry\n',
  );
  stdout.writeln(
    '${'archetype'.padRight(14)}${'motion'.padRight(10)}${'n'.padLeft(5)}'
    '${'asked'.padLeft(8)}${'entry'.padLeft(8)}${'ready'.padLeft(8)}'
    '${'sibling'.padLeft(9)}${'over'.padLeft(7)}${'managed'.padLeft(9)}'
    '${'in band'.padLeft(9)}${'all n'.padLeft(8)}${'all mgd'.padLeft(9)}',
  );

  for (final archetype in archetypes) {
    for (final motion in HandMotion.values) {
      final rows = [
        for (final entry in entries)
          if (entry.archetype == archetype &&
              entry.motion == motion.id &&
              entry.first)
            entry,
      ];
      final every = [
        for (final entry in entries)
          if (entry.archetype == archetype && entry.motion == motion.id) entry,
      ];
      if (rows.isEmpty) continue;
      double mean(double Function(_Entry) of) =>
          rows.fold<double>(0, (sum, row) => sum + of(row)) / rows.length;
      final managed = rows.where((row) => row.managed).length;
      final inBand = rows.where((row) => row.withinBand).length;

      stdout.writeln(
        '${archetype.padRight(14)}${motion.id.toLowerCase().padRight(10)}'
        '${rows.length.toString().padLeft(5)}'
        '${mean((r) => r.asked).toStringAsFixed(0).padLeft(8)}'
        '${mean((r) => r.entry).toStringAsFixed(0).padLeft(8)}'
        '${mean((r) => r.ready).toStringAsFixed(0).padLeft(8)}'
        '${mean((r) => r.sibling).toStringAsFixed(0).padLeft(9)}'
        '${mean((r) => r.asked - r.entry).toStringAsFixed(0).padLeft(7)}'
        '${'${(100 * managed / rows.length).round()}%'.padLeft(9)}'
        '${'${(100 * inBand / rows.length).round()}%'.padLeft(9)}'
        '${every.length.toString().padLeft(8)}'
        '${'${(100 * every.where((r) => r.managed).length / every.length).round()}%'.padLeft(9)}',
      );
    }
  }
}

/// One motion's first attempt on one material.
class _Entry {
  final String archetype;
  final String motion;
  final double asked;
  final double entry;
  final double ready;
  final double sibling;
  final bool managed;
  final bool withinBand;
  final bool first;

  const _Entry({
    required this.archetype,
    required this.motion,
    required this.asked,
    required this.entry,
    required this.ready,
    required this.sibling,
    required this.managed,
    required this.withinBand,
    required this.first,
  });
}

List<_Entry> _entriesFor(List<TrajectoryJob> jobs, int slots) {
  final entries = <_Entry>[];

  for (final job in jobs) {
    // The live state at each slot, read for the reference tempos an entry
    // could be derived from.
    final bySlot = <int, LearnerState>{};
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      observeState: (slot, state) => bySlot[slot] = state.copy(),
    );

    final seen = <(String, HandMotion)>{};
    for (final slot in trajectory.slots) {
      final exercise = slot.winner.exercise;
      final conditions = exercise.conditions;
      if (conditions.hands != HandConfiguration.together) continue;
      final materialId = exercise.material.materialId;
      // Every attempt counts toward the managed rate; only the first of each
      // motion is recorded as an entry, because that is what an entry rule
      // would govern.
      entries.add(
        _Entry(
          archetype: job.archetypeId,
          motion: conditions.handMotion.id,
          asked: 0,
          entry: 0,
          ready: 0,
          sibling: 0,
          managed: slot.managedExecution,
          withinBand: slot.winner.isWithinChallengeBand,
          first: false,
        ),
      );
      if (!seen.add((materialId, conditions.handMotion))) continue;

      final state = bySlot[slot.index]!;
      final span = conditions.octaves;
      final entry = handsTogetherEntryTempo(state, materialId, span);
      final ready = [
        for (final hand in [HandConfiguration.right, HandConfiguration.left])
          state.materialExecution[(materialId, hand, HandMotion.parallel)]
                  ?.coordinationReadyTempoAt(span) ??
              0,
      ].reduce((a, b) => a < b ? a : b);
      final other = conditions.handMotion == HandMotion.contrary
          ? HandMotion.parallel
          : HandMotion.contrary;
      final sibling =
          state
              .materialExecution[(
                materialId,
                HandConfiguration.together,
                other,
              )]
              ?.demonstratedTempoAt(span) ??
          0;

      entries.add(
        _Entry(
          archetype: job.archetypeId,
          motion: conditions.handMotion.id,
          asked: conditions.tempoBpm,
          entry: entry,
          ready: ready,
          sibling: sibling,
          managed: slot.managedExecution,
          withinBand: slot.winner.isWithinChallengeBand,
          first: true,
        ),
      );
    }
  }

  return entries;
}
