import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What hands-together work admitted outside the ordinary band is yielding.
///
/// Every hands-together attempt a `developing` learner makes arrives by a
/// bypass, none inside the challenge band, and almost none is managed. That is
/// admission working as designed and says nothing about whether it is doing the
/// learner any good.
///
/// So attribute each attempt to the exception that admitted it, and ask what
/// moved. Execution success is the wrong sole test: coordination is a channel
/// of its own precisely so that an attempt can fail as execution and still be
/// worth the slot. What would not be worth the slot is an exception firing
/// repeatedly while neither channel moves.
///
/// Reports, per archetype and bypass: attempts, how many were managed, how the
/// coordination competency moved per attempt, and how long the streak of
/// bypassed attempts runs before one lands inside the ordinary band.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetypes', defaultsTo: 'developing,uneven_hands,advanced')
    ..addOption('seeds', defaultsTo: '10')
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
      if (bucket.isNotEmpty) Isolate.run(() => _attemptsFor(bucket, slots)),
  ]);
  final attempts = [for (final batch in batches) ...batch];

  stdout
    ..writeln(
      'hands-together attempts by what admitted them, '
      '$seeds seeds x $slots slots\n'
      '  band    = of those, inside the ordinary challenge band\n'
      '  managed = production accepted the attempt as demonstrated execution\n'
      '  coord   = mean change in the coordination competency, per attempt\n'
      '  scored  = attempts that produced a coordination reading at all\n'
      '  streak  = longest run of bypassed attempts before one lands in band\n',
    )
    ..writeln(
      '${'archetype'.padRight(14)}${'admitted by'.padRight(24)}${'n'.padLeft(6)}'
      '${'band'.padLeft(7)}${'managed'.padLeft(9)}${'scored'.padLeft(8)}'
      '${'coord'.padLeft(10)}${'streak'.padLeft(8)}',
    );

  for (final archetype in archetypes) {
    final mine = [
      for (final attempt in attempts)
        if (attempt.archetype == archetype) attempt,
    ];
    final reasons = {for (final attempt in mine) attempt.bypass}.toList()
      ..sort();
    final longestStreak = mine.fold<int>(
      0,
      (longest, attempt) => attempt.streak > longest ? attempt.streak : longest,
    );

    for (final reason in reasons) {
      final rows = [
        for (final attempt in mine)
          if (attempt.bypass == reason) attempt,
      ];
      final scored = [
        for (final row in rows)
          if (row.coordinationDelta != null) row,
      ];
      final coordination = scored.isEmpty
          ? null
          : scored.fold<double>(0, (sum, r) => sum + r.coordinationDelta!) /
                scored.length;

      stdout.writeln(
        '${archetype.padRight(14)}${reason.padRight(24)}'
        '${rows.length.toString().padLeft(6)}'
        '${'${(100 * rows.where((r) => r.withinBand).length / rows.length).round()}%'.padLeft(7)}'
        '${'${(100 * rows.where((r) => r.managed).length / rows.length).round()}%'.padLeft(9)}'
        '${scored.length.toString().padLeft(8)}'
        '${(coordination == null ? '-' : coordination.toStringAsFixed(4)).padLeft(10)}'
        '${(reason == reasons.first ? longestStreak.toString() : '').padLeft(8)}',
      );
    }
  }
}

/// One hands-together attempt and what it moved.
class _Attempt {
  final String archetype;
  final String bypass;
  final bool withinBand;
  final bool managed;
  final double? coordinationDelta;

  /// How many bypassed attempts had run without one landing in the ordinary
  /// band, counted within this trajectory.
  final int streak;

  const _Attempt({
    required this.archetype,
    required this.bypass,
    required this.withinBand,
    required this.managed,
    required this.coordinationDelta,
    required this.streak,
  });
}

List<_Attempt> _attemptsFor(List<TrajectoryJob> jobs, int slots) {
  final attempts = <_Attempt>[];

  for (final job in jobs) {
    // The coordination estimate before each decision, so the movement an
    // attempt produced is the difference against the next slot's reading.
    final coordinationAt = <int, double>{};
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      observeState: (slot, state) => coordinationAt[slot] = state
          .competency(Competency.handsTogetherCoordination)
          .mean,
    );

    var streak = 0;
    for (final slot in trajectory.slots) {
      if (slot.chosen.conditions.hands != HandConfiguration.together) continue;
      final before = coordinationAt[slot.index];
      final after = coordinationAt[slot.index + 1];
      streak = slot.winner.isWithinChallengeBand ? 0 : streak + 1;
      attempts.add(
        _Attempt(
          archetype: job.archetypeId,
          bypass: slot.winner.challengeBypass?.id ?? 'ordinary band',
          withinBand: slot.winner.isWithinChallengeBand,
          managed: slot.managedExecution,
          coordinationDelta: before == null || after == null
              ? null
              : after - before,
          streak: streak,
        ),
      );
    }
  }

  return attempts;
}
