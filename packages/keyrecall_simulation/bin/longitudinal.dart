import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Characterizes every archetype across the named calendar schedules.
///
/// The question the sweep cannot ask. A sweep counts anomalies over one
/// unbroken sitting; this reports the shape of a run that practice and
/// forgetting both act on, which is the only way to see whether a break costs
/// a learner a sitting or traps them.
///
/// Reported rather than asserted, for the same reason the observational
/// detectors are: nobody yet knows what share of a returning sitting should go
/// to reacquisition, and a threshold picked today would become a second
/// specification.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '10', help: 'Seeds per archetype.')
    ..addOption('slots', defaultsTo: '12', help: 'Attempts per sitting.')
    ..addOption(
      'archetypes',
      help: 'Which archetypes to run. Every one when omitted.',
    )
    ..addOption(
      'schedules',
      defaultsTo: LongitudinalSchedules.all.keys.join(','),
      help: 'Which named schedules to run.',
    )
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final schedules = options.option('schedules')!.split(',');
  final only = options.option('archetypes')?.split(',');
  final players = [
    for (final player in PlayerArchetypes.all)
      if (only == null || only.contains(player.id)) player,
  ];

  final stopwatch = Stopwatch()..start();
  for (final schedule in schedules) {
    final days = LongitudinalSchedules.all[schedule];
    if (days == null) {
      stderr.writeln('unknown schedule: $schedule');
      exitCode = 2;
      return;
    }
    final buckets = dealTrajectoryJobs(seeds, players: players);
    final running = [
      for (final bucket in buckets)
        Isolate.run(() => _summarize(bucket, schedule, slots)),
    ];
    final rows = [for (final batch in await Future.wait(running)) ...batch];

    stdout
      ..writeln()
      ..writeln('== $schedule: days ${days.join(', ')}, $slots slots each')
      ..writeln(
        '   ${_header('archetype')} '
        'pre% reacq% cons% pass none resume never sup%  cov  ht ctr 2oc ung  '
        'opn ans str dry',
      );
    for (final player in players) {
      final mine = rows.where((row) => row.archetype == player.id).toList();
      if (mine.isEmpty) continue;
      stdout.writeln('   ${_row(player.id, mine)}');
    }
  }
  stdout
    ..writeln()
    ..writeln('characterized in ${stopwatch.elapsed.inSeconds}s');
}

String _header(String first) => first.padRight(24);

String _row(String archetype, List<_Row> rows) {
  String firstSitting(Milestone milestone) {
    final reached = [for (final row in rows) ?row.milestones[milestone.id]];
    // Blank rather than a number when most runs never got there: a median over
    // the few that did would describe a different population.
    if (reached.length * 2 < rows.length) return '  -';
    return _median(
      reached.map((s) => s.toDouble()),
    ).toStringAsFixed(0).padLeft(3);
  }

  final resumed = [
    for (final row in rows)
      for (final resume in row.resumes)
        if (resume != null) resume.toDouble(),
  ];
  final never = rows.fold(
    0,
    (total, row) => total + row.resumes.where((r) => r == null).length,
  );

  return [
    archetype.padRight(24),
    _percent(_median(rows.map((row) => row.preFrontierShare))).padLeft(4),
    _percent(_median(rows.map((row) => row.reacquisitionShare))).padLeft(6),
    _percent(_median(rows.map((row) => row.consolidationShare))).padLeft(5),
    _total(rows.map((row) => row.progressionPassedOver)).padLeft(4),
    _total(rows.map((row) => row.noProgressionSelectable)).padLeft(4),
    (resumed.isEmpty ? '-' : _median(resumed).toStringAsFixed(1)).padLeft(6),
    '$never'.padLeft(5),
    _percent(_median(rows.map((row) => row.supportedShare))).padLeft(5),
    _median(
      rows.map((row) => row.coverage.toDouble()),
    ).toStringAsFixed(0).padLeft(4),
    for (final milestone in Milestone.values) firstSitting(milestone),
    _total(rows.map((row) => row.probesOpened)).padLeft(5),
    _total(rows.map((row) => row.probesAnswered)).padLeft(4),
    _total(rows.map((row) => row.probesStranded)).padLeft(4),
    _total(rows.map((row) => row.dry)).padLeft(4),
  ].join(' ');
}

String _percent(double share) => '${(share * 100).round()}%';

String _total(Iterable<int> counts) =>
    '${counts.fold(0, (total, count) => total + count)}';

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// One run, flattened to what crosses an isolate boundary.
class _Row {
  final String archetype;
  final double preFrontierShare;
  final double reacquisitionShare;
  final double consolidationShare;
  final double supportedShare;

  /// Over returning sittings only, the two ways a reacquiring slot happens.
  final int progressionPassedOver;
  final int noProgressionSelectable;
  final List<int?> resumes;
  final int coverage;
  final Map<String, int> milestones;
  final int probesOpened;
  final int probesAnswered;
  final int probesStranded;
  final int dry;

  const _Row({
    required this.archetype,
    required this.preFrontierShare,
    required this.reacquisitionShare,
    required this.consolidationShare,
    required this.supportedShare,
    required this.progressionPassedOver,
    required this.noProgressionSelectable,
    required this.resumes,
    required this.coverage,
    required this.milestones,
    required this.probesOpened,
    required this.probesAnswered,
    required this.probesStranded,
    required this.dry,
  });
}

List<_Row> _summarize(List<TrajectoryJob> jobs, String schedule, int slots) {
  final generated = generateCandidates(InstrumentProfile(), allScales);
  final sittings = LongitudinalSchedules.named(schedule, slots: slots);
  return [
    for (final job in jobs)
      _rowFor(
        job,
        censusOfRun(
          runSittings(
            player: playerOf(job.archetypeId),
            seed: job.seed,
            materials: allScales,
            sittings: sittings,
            generated: generated,
          ),
        ),
      ),
  ];
}

_Row _rowFor(TrajectoryJob job, LongitudinalCensus census) {
  final returning = census.recoveries().toList();
  final played = census.sittings.fold(0, (total, s) => total + s.slots);
  return _Row(
    archetype: job.archetypeId,
    // Over returning sittings only: the share of an ordinary sitting spent on
    // known work answers a different question.
    preFrontierShare: _shareOf(
      returning,
      census,
      (sitting) => sitting.preFrontier,
    ),
    reacquisitionShare: _shareOf(
      returning,
      census,
      (sitting) => sitting.reacquiring,
    ),
    consolidationShare: _shareOf(
      returning,
      census,
      (sitting) => sitting.consolidating,
    ),
    supportedShare: played == 0
        ? 0
        : census.sittings.fold(0, (total, s) => total + s.supported) / played,
    progressionPassedOver: returning.fold(
      0,
      (total, recovery) =>
          total + census.sittings[recovery.sitting].progressionPassedOver,
    ),
    noProgressionSelectable: returning.fold(
      0,
      (total, recovery) =>
          total + census.sittings[recovery.sitting].noProgressionSelectable,
    ),
    resumes: [for (final recovery in returning) recovery.sittingsToProgress],
    coverage: census.sittings.last.coverage,
    milestones: {
      for (final entry in census.milestones.entries) entry.key.id: entry.value,
    },
    probesOpened: census.sittings.fold(0, (t, s) => t + s.probesOpened),
    probesAnswered: census.sittings.fold(0, (t, s) => t + s.probesAnswered),
    probesStranded: census.sittings.where((s) => s.probeStranded).length,
    dry: census.sittings.where((s) => s.ranDry).length,
  );
}

double _shareOf(
  List<GapRecovery> returning,
  LongitudinalCensus census,
  int Function(SittingSummary sitting) count,
) {
  if (returning.isEmpty) return 0;
  var slots = 0;
  var matching = 0;
  for (final recovery in returning) {
    final sitting = census.sittings[recovery.sitting];
    slots += sitting.slots;
    matching += count(sitting);
  }
  return slots == 0 ? 0 : matching / slots;
}
