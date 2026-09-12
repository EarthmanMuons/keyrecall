import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether coordination work is what costs a weak learner late in a long run.
///
/// A beginner's execution quality falls in the last part of a run across
/// months, shortly after hands-together work first appears. Whether one causes
/// the other is what this asks: the two could be coincident.
///
/// So the same player and seed are run twice against the same schedule, with
/// the second arm's candidate set holding no hands-together work at all, and
/// the arms are compared from the slot the baseline first reached it. Nothing
/// about the learner model, the scheduler or the player differs between them.
///
/// The three readings, and they are different conclusions:
///
/// ```text
/// the decline goes away withheld    coordination is arriving too early
/// both arms decline                 something else in the long run
/// withheld is worse in the end      desirable difficulty, and it is working
/// ```
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetypes', defaultsTo: 'true_beginner')
    ..addOption('seeds', defaultsTo: '8')
    ..addOption('slots', defaultsTo: '10', help: 'Attempts per sitting.')
    ..addOption('schedule', defaultsTo: 'normal_month')
    ..addOption('days', help: 'Explicit days, overriding the schedule.')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final archetypes = options.option('archetypes')!.split(',');
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final days = options.option('days');
  final sittings = days == null
      ? LongitudinalSchedules.named(options.option('schedule')!, slots: slots)
      : sittingsOnDays([
          for (final day in days.split(',')) int.parse(day.trim()),
        ], slots: slots);

  final jobs = [
    for (final archetype in archetypes)
      for (var seed = 0; seed < seeds; seed++)
        TrajectoryJob(archetypeId: archetype, seed: seed),
  ];
  final buckets = List.generate(
    Platform.numberOfProcessors,
    (_) => <TrajectoryJob>[],
  );
  for (final (index, job) in jobs.indexed) {
    buckets[index % buckets.length].add(job);
  }
  final batches = await Future.wait([
    for (final bucket in buckets)
      if (bucket.isNotEmpty) Isolate.run(() => _compare(bucket, sittings)),
  ]);
  final rows = [for (final batch in batches) ...batch];

  stdout
    ..writeln()
    ..writeln(
      '== coordination withheld: '
      '${sittings.length} sittings of $slots, $seeds seeds',
    )
    ..writeln(
      '   from the slot the baseline first reached hands together, to the end',
    )
    ..writeln();
  for (final archetype in archetypes) {
    final mine = rows.where((row) => row.archetype == archetype).toList();
    final reached = mine.where((row) => row.reachedAt != null).toList();
    stdout.writeln(
      '$archetype: hands together reached in ${reached.length} of '
      '${mine.length} runs',
    );
    if (reached.isEmpty) continue;
    stdout
      ..writeln(
        '   ${'arm'.padRight(10)}  motor  completed  advancing  '
        'pre%  cons%  sup%',
      )
      ..writeln(_arm('baseline', [for (final row in reached) row.baseline]))
      ..writeln(_arm('withheld', [for (final row in reached) row.withheld]));
    final shocks = [for (final row in reached) ?row.shock];
    if (shocks.isNotEmpty) {
      stdout.writeln(
        '   milestone shock at hands together, over 15 slots either side: '
        'median ${_median(shocks.map((s) => s.before)).toStringAsFixed(2)} '
        'to ${_median(shocks.map((s) => s.after)).toStringAsFixed(2)}, '
        'recovered in '
        '${_recovery(shocks)}',
      );
    }
  }
}

String _arm(String name, List<_Metrics> metrics) => [
  '   ${name.padRight(10)}',
  _median(metrics.map((m) => m.motor)).toStringAsFixed(2).padLeft(6),
  _percent(_median(metrics.map((m) => m.completed))).padLeft(10),
  _median(
    metrics.map((m) => m.advancing.toDouble()),
  ).toStringAsFixed(1).padLeft(10),
  _percent(_median(metrics.map((m) => m.preFrontier))).padLeft(5),
  _percent(_median(metrics.map((m) => m.consolidating))).padLeft(6),
  _percent(_median(metrics.map((m) => m.supported))).padLeft(5),
].join(' ');

String _recovery(List<MilestoneShock> shocks) {
  final recovered = [for (final shock in shocks) ?shock.recoveredAfter];
  if (recovered.isEmpty) return 'no run recovered';
  return '${_median(recovered.map((r) => r.toDouble())).toStringAsFixed(0)} '
      'slots in ${recovered.length} of ${shocks.length} runs';
}

String _percent(double share) => '${(share * 100).round()}%';

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// What one arm did over the slots being compared.
class _Metrics {
  final double motor;
  final double completed;
  final int advancing;
  final double preFrontier;
  final double consolidating;
  final double supported;

  const _Metrics({
    required this.motor,
    required this.completed,
    required this.advancing,
    required this.preFrontier,
    required this.consolidating,
    required this.supported,
  });
}

class _Row {
  final String archetype;
  final int? reachedAt;
  final _Metrics baseline;
  final _Metrics withheld;
  final MilestoneShock? shock;

  const _Row({
    required this.archetype,
    required this.reachedAt,
    required this.baseline,
    required this.withheld,
    required this.shock,
  });
}

List<_Row> _compare(List<TrajectoryJob> jobs, List<Sitting> sittings) {
  final everything = generateCandidates(InstrumentProfile(), allScales);
  // The counterfactual is the candidate set, not a second scheduler: work that
  // is never offered cannot be chosen, and nothing else about the arm differs.
  final withoutCoordination = [
    for (final exercise in everything)
      if (exercise.conditions.hands != HandConfiguration.together) exercise,
  ];

  return [
    for (final job in jobs)
      _rowFor(
        job,
        runSittings(
          player: playerOf(job.archetypeId),
          seed: job.seed,
          materials: allScales,
          sittings: sittings,
          generated: everything,
        ),
        runSittings(
          player: playerOf(job.archetypeId),
          seed: job.seed,
          materials: allScales,
          sittings: sittings,
          generated: withoutCoordination,
        ),
      ),
  ];
}

_Row _rowFor(TrajectoryJob job, Trajectory baseline, Trajectory withheld) {
  final at = baseline.slots.indexWhere(Milestone.handsTogether.reachedBy);
  final shocks = milestoneShocks(baseline);
  return _Row(
    archetype: job.archetypeId,
    reachedAt: at < 0 ? null : at,
    baseline: _measure(baseline, from: at),
    withheld: _measure(withheld, from: at),
    shock: shocks
        .where((shock) => shock.milestone == Milestone.handsTogether)
        .firstOrNull,
  );
}

/// What an arm did over the slots from [from] to the end.
///
/// Positional rather than by slot index, and read through [readRun] so the
/// classification of a slot accounts for the whole run before it even when the
/// window does not.
_Metrics _measure(Trajectory trajectory, {required int from}) {
  final start = from < 0 ? 0 : from;
  final slots = trajectory.slots.skip(start).toList();
  if (slots.isEmpty) {
    return const _Metrics(
      motor: 0,
      completed: 0,
      advancing: 0,
      preFrontier: 0,
      consolidating: 0,
      supported: 0,
    );
  }
  final readings = readRun(trajectory).skip(start).toList();
  final scores = [for (final slot in slots) slot.outcome.motorScore]..sort();
  int counting(bool Function(SlotReading reading) matches) =>
      readings.where(matches).length;

  return _Metrics(
    motor: scores[scores.length ~/ 2],
    completed:
        slots.where((slot) => slot.outcome.completed).length / slots.length,
    advancing: counting((reading) => reading.work == SlotWork.advancing),
    preFrontier:
        counting((reading) => reading.work == SlotWork.preFrontier) /
        slots.length,
    consolidating:
        counting((reading) => reading.work == SlotWork.consolidating) /
        slots.length,
    supported: counting((reading) => reading.supported) / slots.length,
  );
}
