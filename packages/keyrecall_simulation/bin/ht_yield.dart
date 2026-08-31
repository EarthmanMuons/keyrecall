import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What hands-together work admitted outside the ordinary band is yielding.
///
/// Every hands-together attempt a `developing` learner makes arrives by a
/// bypass, none inside the challenge band, and almost none is managed. That is
/// admission working as designed and says nothing about whether it is doing the
/// learner any good.
///
/// So attribute each attempt to the exception that admitted it, and ask what
/// the coordination channel made of it. Execution success is the wrong sole
/// test: coordination is a channel of its own precisely so an attempt can fail
/// as execution and still be worth the slot.
///
/// The movement reported is the one the learner actually applies, not a
/// difference between two states: the surprise of the measured coordination
/// reading against [LearnerModel.coordinationProbability] at decision time,
/// which is what the update is computed from. A state difference would fold in
/// propagation and every other channel's evidence.
///
/// Streaks are counted per execution context and exception, because that is the
/// grain a policy would act on. A trajectory-wide streak says a learner is
/// being fed bypassed work; it does not say whether one realization is being
/// hammered or many are each failing once.
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
      '  band     = inside the ordinary challenge band\n'
      '  managed  = production accepted it as demonstrated execution\n'
      '  scored   = produced a coordination reading at all\n'
      '  predict  = mean coordination probability before the attempt\n'
      '  read     = mean measured coordination\n'
      '  surprise = read minus predict, which is what the update applies\n'
      '  adverse  = share of scored attempts whose surprise was negative\n'
      '  run      = longest run on one context and exception\n'
      '  after    = attempts on a context whose surprise had already been\n'
      '             adverse twice running\n'
      '  counts are pooled across independent learner states, not one update\n'
      '  sequence\n',
    )
    ..writeln(
      '${'archetype'.padRight(14)}${'admitted by'.padRight(23)}${'n'.padLeft(5)}'
      '${'band'.padLeft(6)}${'mgd'.padLeft(6)}${'scored'.padLeft(8)}'
      '${'predict'.padLeft(9)}${'read'.padLeft(8)}${'surprise'.padLeft(10)}'
      '${'adverse'.padLeft(9)}${'run'.padLeft(6)}${'after'.padLeft(7)}',
    );

  for (final archetype in archetypes) {
    final mine = [
      for (final attempt in attempts)
        if (attempt.archetype == archetype) attempt,
    ];
    final reasons = {for (final attempt in mine) attempt.bypass}.toList()
      ..sort();

    for (final reason in reasons) {
      final rows = [
        for (final attempt in mine)
          if (attempt.bypass == reason) attempt,
      ];
      final scored = [
        for (final row in rows)
          if (row.surprise != null) row,
      ];
      String mean(double Function(_Attempt) of, {int places = 4}) =>
          scored.isEmpty
          ? '-'
          : (scored.fold<double>(0, (sum, r) => sum + of(r)) / scored.length)
                .toStringAsFixed(places);
      String share(int count, int total) =>
          total == 0 ? '-' : '${(100 * count / total).round()}%';

      stdout.writeln(
        '${archetype.padRight(14)}${reason.padRight(23)}'
        '${rows.length.toString().padLeft(5)}'
        '${share(rows.where((r) => r.withinBand).length, rows.length).padLeft(6)}'
        '${share(rows.where((r) => r.managed).length, rows.length).padLeft(6)}'
        '${scored.length.toString().padLeft(8)}'
        '${mean((r) => r.predicted, places: 3).padLeft(9)}'
        '${mean((r) => r.reading!, places: 3).padLeft(8)}'
        '${mean((r) => r.surprise!).padLeft(10)}'
        '${share(scored.where((r) => r.surprise! < 0).length, scored.length).padLeft(9)}'
        '${rows.fold<int>(0, (m, r) => r.run > m ? r.run : m).toString().padLeft(6)}'
        '${rows.where((r) => r.afterAdverse).length.toString().padLeft(7)}',
      );
    }
  }
}

/// One hands-together attempt and what the coordination channel made of it.
class _Attempt {
  final String archetype;
  final String bypass;
  final bool withinBand;
  final bool managed;
  final double predicted;
  final double? reading;
  final double? surprise;

  /// How many attempts in a row this execution context has taken under this
  /// exception, which is the grain a policy would act on.
  final int run;

  /// Whether this context's coordination surprise had already been adverse
  /// twice running when this attempt was admitted.
  final bool afterAdverse;

  const _Attempt({
    required this.archetype,
    required this.bypass,
    required this.withinBand,
    required this.managed,
    required this.predicted,
    required this.reading,
    required this.surprise,
    required this.run,
    required this.afterAdverse,
  });
}

List<_Attempt> _attemptsFor(List<TrajectoryJob> jobs, int slots) {
  const model = LearnerModel();
  final attempts = <_Attempt>[];

  for (final job in jobs) {
    // The live state before each decision, for the coordination probability
    // the update is a surprise against.
    final bySlot = <int, LearnerState>{};
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
      observeState: (slot, state) => bySlot[slot] = state.copy(),
    );

    final runs = <String, int>{};
    final adverse = <String, int>{};
    for (final slot in trajectory.slots) {
      final exercise = slot.chosen;
      if (exercise.conditions.hands != HandConfiguration.together) continue;
      final bypass = slot.winner.challengeBypass?.id ?? 'ordinary band';
      final key =
          '${executionContextOf(exercise)}'
          '|${exercise.conditions.octaves}|$bypass';

      final reading = slot.outcome.coordination;
      final predicted = model.coordinationProbability(
        bySlot[slot.index]!,
        exercise,
      );
      final surprise = reading == null ? null : reading - predicted;

      attempts.add(
        _Attempt(
          archetype: job.archetypeId,
          bypass: bypass,
          withinBand: slot.winner.isWithinChallengeBand,
          managed: slot.managedExecution,
          predicted: predicted,
          reading: reading,
          surprise: surprise,
          run: runs.update(key, (n) => n + 1, ifAbsent: () => 1),
          afterAdverse: (adverse[key] ?? 0) >= 2,
        ),
      );

      if (surprise != null) {
        adverse[key] = surprise < 0 ? (adverse[key] ?? 0) + 1 : 0;
      }
    }
  }

  return attempts;
}
