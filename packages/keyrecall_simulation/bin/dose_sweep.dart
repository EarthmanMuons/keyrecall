import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What family dose control does across its parameter space.
///
/// One arm per configuration, every archetype and seed run against each, and
/// the baseline arm carried alongside so parity can be read rather than
/// assumed. Reported, never scored: the target is a region where a failing
/// family contracts, a yielding learner is untouched and nothing starves, and
/// no single number expresses that.
///
/// Sweeping one axis at a time by default. The interactions worth checking are
/// between the floor and the gap, and `--grid` asks for that pair as a product
/// instead.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption(
      'workers',
      help:
          'Isolates to run across, four when omitted. What limits a sweep is '
          'each worker\'s heap rather than its CPU: every one holds its own '
          'candidate set and the traces of the slot it is on. Measured on one '
          'sweep, two workers took 289s at 0.6GB, four took 200s at 0.8GB, '
          'and eight took 459s at 9.1GB, so past a point more workers are '
          'both slower and the reason a sweep gets killed.',
    )
    ..addOption('slots', defaultsTo: '12', help: 'Attempts per sitting.')
    ..addOption('schedules', defaultsTo: 'normal_month,interrupted')
    ..addOption('archetypes', help: 'Every one when omitted.')
    ..addOption('min-attempts', defaultsTo: '3,4,6,8')
    ..addOption('yield-floor', defaultsTo: '0.2,0.34,0.5,0.67')
    ..addOption('max-gap', defaultsTo: '3,4,6,8,12')
    ..addOption(
      'prereq-relief',
      defaultsTo: '0.5',
      help:
          'What productive prerequisite work multiplies a contraction by, '
          'so lower relieves more and zero cancels it outright.',
    )
    ..addOption('half-life', defaultsTo: '7')
    ..addFlag(
      'grid',
      negatable: false,
      help: 'Sweep the floor against the gap as a product.',
    )
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final only = options.option('archetypes')?.split(',');
  final players = [
    for (final player in PlayerArchetypes.all)
      if (only == null || only.contains(player.id)) player,
  ];
  List<double> numbers(String name) => [
    for (final value in options.option(name)!.split(','))
      double.parse(value.trim()),
  ];
  final minAttempts = numbers('min-attempts');
  final yieldFloors = numbers('yield-floor');
  final gaps = numbers('max-gap');
  final reliefs = numbers('prereq-relief');
  final halfLives = numbers('half-life');

  final arms = <DoseConfig?>[
    null,
    if (options.flag('grid'))
      for (final floor in yieldFloors)
        for (final gap in gaps)
          DoseConfig(
            yieldFloor: floor,
            maximumGap: gap.round(),
            prerequisiteReliefFactor: reliefs.first,
            evidenceHalfLifeDays: halfLives.first,
          )
    else ...[
      for (final value in minAttempts) DoseConfig(minAttempts: value.round()),
      for (final value in yieldFloors) DoseConfig(yieldFloor: value),
      for (final value in gaps) DoseConfig(maximumGap: value.round()),
      for (final value in reliefs) DoseConfig(prerequisiteReliefFactor: value),
      for (final value in halfLives) DoseConfig(evidenceHalfLifeDays: value),
    ],
  ];

  final workers =
      int.tryParse(options.option('workers') ?? '') ??
      (Platform.numberOfProcessors < 4 ? Platform.numberOfProcessors : 4);

  for (final schedule in options.option('schedules')!.split(',')) {
    final sittings = LongitudinalSchedules.named(schedule, slots: slots);
    final jobs = [
      for (final player in players)
        for (var seed = 0; seed < seeds; seed++)
          TrajectoryJob(archetypeId: player.id, seed: seed),
    ];
    final buckets = List.generate(workers, (_) => <TrajectoryJob>[]);
    for (final (index, job) in jobs.indexed) {
      buckets[index % buckets.length].add(job);
    }

    stdout
      ..writeln()
      ..writeln(
        '== dose sweep on $schedule: ${sittings.length} sittings of $slots, '
        '$seeds seeds, ${players.length} archetypes, $workers workers',
      )
      ..writeln(
        '   contracted and changed are the share of slots the mechanism spoke '
        'at and the share it altered',
      )
      ..writeln(
        '   share and after are the low-yield families, median across them',
      )
      ..writeln()
      ..writeln(
        '   ${'arm'.padRight(30)}contr  chang  share  after  streak  '
        'ht  parity  dry',
      );

    // One isolate per bucket for the whole sweep rather than per arm. A worker
    // generates the catalog once, runs each job's baseline once, and carries
    // both across every arm: the baseline is otherwise re-simulated for every
    // configuration, which is most of the work in a sweep of fifteen.
    final stopwatch = Stopwatch()..start();
    final batches = await Future.wait([
      for (final bucket in buckets)
        if (bucket.isNotEmpty)
          Isolate.run(() => _measure(bucket, sittings, arms)),
    ]);
    for (final (index, arm) in arms.indexed) {
      stdout.writeln(
        _row(arm, [
          for (final batch in batches)
            for (final run in batch)
              if (run.arm == index) run,
        ]),
      );
    }
    stdout.writeln('   swept in ${stopwatch.elapsed.inSeconds}s');
  }
}

String _row(DoseConfig? arm, List<_Run> runs) {
  final lowYield = [
    for (final run in runs)
      for (final family in run.families)
        if (family.lowYield) family,
  ];
  final reachedHt = [for (final run in runs) ?run.handsTogetherSitting];
  return [
    '   ${_label(arm).padRight(30)}',
    _percent(_mean(runs.map((run) => run.contractedShare))).padLeft(5),
    _percent(_mean(runs.map((run) => run.changedShare))).padLeft(6),
    _percent(_median(lowYield.map((family) => family.share))).padLeft(6),
    _percent(_median(lowYield.map((family) => family.after))).padLeft(6),
    _median(
      lowYield.map((family) => family.streak.toDouble()),
    ).toStringAsFixed(0).padLeft(7),
    _median(
      reachedHt.map((sitting) => sitting.toDouble()),
    ).toStringAsFixed(0).padLeft(4),
    '${runs.where((run) => run.matchesBaseline).length}/${runs.length}'.padLeft(
      8,
    ),
    '${runs.fold(0, (total, run) => total + run.dry)}'.padLeft(5),
  ].join(' ');
}

String _label(DoseConfig? arm) {
  if (arm == null) return 'baseline (no dose control)';
  const centre = DoseConfig();
  final changed = [
    if (arm.minAttempts != centre.minAttempts) 'evidence ${arm.minAttempts}',
    if (arm.yieldFloor != centre.yieldFloor) 'floor ${arm.yieldFloor}',
    if (arm.maximumGap != centre.maximumGap) 'gap ${arm.maximumGap}',
    if (arm.prerequisiteReliefFactor != centre.prerequisiteReliefFactor)
      'relief ${arm.prerequisiteReliefFactor}',
    if (arm.evidenceHalfLifeDays != centre.evidenceHalfLifeDays)
      'half-life ${arm.evidenceHalfLifeDays}d',
  ];
  return changed.isEmpty ? 'centre' : changed.join(', ');
}

String _percent(double share) => '${(share * 100).round()}%';

double _mean(Iterable<double> values) {
  final all = values.toList();
  if (all.isEmpty) return 0;
  return all.reduce((a, b) => a + b) / all.length;
}

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// One family of one run, flattened to what a row needs.
class _Family {
  final bool lowYield;
  final double share;
  final double after;
  final int streak;

  const _Family({
    required this.lowYield,
    required this.share,
    required this.after,
    required this.streak,
  });
}

class _Run {
  /// Which arm produced it, as an index into the sweep's arms.
  final int arm;

  final double contractedShare;
  final double changedShare;
  final List<_Family> families;
  final int? handsTogetherSitting;
  final bool matchesBaseline;
  final int dry;

  const _Run({
    required this.arm,
    required this.contractedShare,
    required this.changedShare,
    required this.families,
    required this.handsTogetherSitting,
    required this.matchesBaseline,
    required this.dry,
  });
}

/// Every arm of the sweep, for one bucket of jobs, in one isolate.
///
/// The catalog is generated once and the baseline run once per job, both
/// carried across every arm. Only the baseline's chosen sequence is retained
/// for the parity comparison, digested to a string, so nothing holds a second
/// trajectory while an arm is running.
List<_Run> _measure(
  List<TrajectoryJob> jobs,
  List<Sitting> sittings,
  List<DoseConfig?> arms,
) {
  final generated = generateCandidates(InstrumentProfile(), allScales);
  const learner = LearnerModel();
  // The V1 policy carries dose control, so the arm the others are compared
  // against is the one with it taken out.
  final baseline = SchedulerPipeline(
    learner: learner,
    config: v1SchedulerConfig.withDose(null),
  );
  final rows = <_Run>[];

  for (final job in jobs) {
    final chosen = _digestOf(
      runSittings(
        player: playerOf(job.archetypeId),
        seed: job.seed,
        materials: allScales,
        sittings: sittings,
        generated: generated,
        pipeline: baseline,
      ),
    );
    for (final (index, arm) in arms.indexed) {
      final pipeline = arm == null
          ? baseline
          : SchedulerPipeline(
              learner: learner,
              config: v1SchedulerConfig.withDose(arm),
            );
      rows.add(_runOf(index, job, sittings, generated, pipeline, chosen));
    }
  }
  return rows;
}

/// The chosen sequence of [trajectory], as one comparable string.
String _digestOf(Trajectory trajectory) => [
  for (final slot in trajectory.slots)
    '${slot.chosen.material.materialId}|'
        '${slot.chosen.conditions.hands.id}|'
        '${slot.chosen.conditions.octaves}|'
        '${slot.chosen.conditions.tempoBpm}|'
        '${slot.chosen.guidance.independence}',
].join(',');

_Run _runOf(
  int arm,
  TrajectoryJob job,
  List<Sitting> sittings,
  List<Exercise> generated,
  SchedulerPipeline pipeline,
  String baseline,
) {
  var spoke = 0;
  var changed = 0;
  final trajectory = runSittings(
    player: playerOf(job.archetypeId),
    seed: job.seed,
    materials: allScales,
    sittings: sittings,
    generated: generated,
    pipeline: pipeline,
    observeDose: (_, dose) {
      if (dose.disposition == DoseDisposition.inactive) return;
      spoke++;
      if (dose.disposition == DoseDisposition.contracted) changed++;
    },
  );
  final slots = trajectory.slots.length;
  final census = censusOfRun(trajectory);

  return _Run(
    arm: arm,
    contractedShare: slots == 0 ? 0 : spoke / slots,
    changedShare: slots == 0 ? 0 : changed / slots,
    families: [
      for (final exposure in familyExposures(trajectory))
        _Family(
          // Enough attempts to mean something, and yielding little enough that
          // the mechanism has an opinion about it.
          lowYield: exposure.attempts >= 8 && exposure.managedYield < 0.2,
          share: exposure.share,
          after: exposure.shareAfterStreaks,
          streak: exposure.longestUnproductiveStreak,
        ),
    ],
    handsTogetherSitting: census.milestones[Milestone.handsTogether],
    matchesBaseline: _digestOf(trajectory) == baseline,
    dry: census.sittings.where((sitting) => sitting.ranDry).length,
  );
}
