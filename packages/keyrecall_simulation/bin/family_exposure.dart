import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether the dose of a hard realization family responds to it failing.
///
/// Support already adapts: a family that keeps failing gets more guidance. The
/// question this asks is the other one, which nothing currently answers.
/// **Does its share of the sitting contract when the learner keeps giving the
/// same answer?**
///
/// Read `share` against `after`, the family's share of the slots following an
/// unproductive run. Equal means the cadence did not respond at all, and the
/// scheduler asked the same question at the same rate through a run of
/// failures. Realization-family pacing is the mechanism that could respond,
/// and `aside` counts the times it did.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '6')
    ..addOption(
      'archetypes',
      help: 'Which archetypes to run. Every one when omitted.',
    )
    ..addOption('slots', defaultsTo: '10', help: 'Attempts per sitting.')
    ..addOption('schedule', defaultsTo: 'normal_month')
    ..addOption('days', help: 'Explicit days, overriding the schedule.')
    ..addOption('window', defaultsTo: '10', help: 'Slots an answer may take.')
    ..addOption('streak', defaultsTo: '5', help: 'Failures that ask for one.')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final window = int.parse(options.option('window')!);
  final streak = int.parse(options.option('streak')!);
  final days = options.option('days');
  final sittings = days == null
      ? LongitudinalSchedules.named(options.option('schedule')!, slots: slots)
      : sittingsOnDays([
          for (final day in days.split(',')) int.parse(day.trim()),
        ], slots: slots);

  final only = options.option('archetypes')?.split(',');
  final players = [
    for (final player in PlayerArchetypes.all)
      if (only == null || only.contains(player.id)) player,
  ];
  final buckets = dealTrajectoryJobs(seeds, players: players);
  final batches = await Future.wait([
    for (final bucket in buckets)
      Isolate.run(() => _exposures(bucket, sittings, window, streak)),
  ]);
  final rows = [for (final batch in batches) ...batch];

  final total = sittings.fold(0, (count, sitting) => count + sitting.slots);
  stdout
    ..writeln()
    ..writeln(
      '== family exposure: ${sittings.length} sittings of $slots, '
      '$seeds seeds, $total slots',
    )
    ..writeln(
      '   share is of the run after the family first appeared; after is of '
      'the $window slots following a run of $streak attempts that yielded '
      'nothing',
    )
    ..writeln();
  for (final player in players) {
    final mine = rows.where((row) => row.archetype == player.id).toList();
    if (mine.isEmpty) continue;
    stdout
      ..writeln(player.id)
      ..writeln(
        '   ${'family'.padRight(18)}first  att  share  after  yield  '
        'longest  runs  toManaged  aside',
      );
    final families = {for (final row in mine) row.family}.toList()..sort();
    for (final family in families) {
      final held = mine.where((row) => row.family == family).toList();
      stdout.writeln(_row(family, held));
    }
    stdout.writeln();
  }
}

String _row(String family, List<_Row> rows) => [
  '   ${family.padRight(18)}',
  _median(
    rows.map((row) => row.firstSlot.toDouble()),
  ).toStringAsFixed(0).padLeft(4),
  _median(
    rows.map((row) => row.attempts.toDouble()),
  ).toStringAsFixed(0).padLeft(5),
  _percent(_median(rows.map((row) => row.share))).padLeft(6),
  _percent(_median(rows.map((row) => row.shareAfterStreaks))).padLeft(6),
  _percent(_median(rows.map((row) => row.managedYield))).padLeft(6),
  _median(
    rows.map((row) => row.longestStreak.toDouble()),
  ).toStringAsFixed(0).padLeft(8),
  '${rows.fold(0, (total, row) => total + row.streaks)}'.padLeft(5),
  _recovery(rows).padLeft(10),
  '${rows.fold(0, (total, row) => total + row.setAsides)}'.padLeft(6),
].join(' ');

String _recovery(List<_Row> rows) {
  final slots = [for (final row in rows) ?row.slotsToNextManaged];
  return slots.isEmpty
      ? '-'
      : _median(slots.map((s) => s.toDouble())).toStringAsFixed(0);
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

class _Row {
  final String archetype;
  final String family;
  final int firstSlot;
  final int attempts;
  final double share;
  final double shareAfterStreaks;
  final double managedYield;
  final int longestStreak;
  final int streaks;
  final int? slotsToNextManaged;
  final int setAsides;

  const _Row({
    required this.archetype,
    required this.family,
    required this.firstSlot,
    required this.attempts,
    required this.share,
    required this.shareAfterStreaks,
    required this.managedYield,
    required this.longestStreak,
    required this.streaks,
    required this.slotsToNextManaged,
    required this.setAsides,
  });
}

List<_Row> _exposures(
  List<TrajectoryJob> jobs,
  List<Sitting> sittings,
  int window,
  int streak,
) {
  final generated = generateCandidates(InstrumentProfile(), allScales);
  final rows = <_Row>[];
  for (final job in jobs) {
    // What pacing actually did, which only the run can say: a set-aside is a
    // substitution at the slot, not a property of the trajectory it produced.
    final setAsides = <String, int>{};
    final trajectory = runSittings(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      sittings: sittings,
      generated: generated,
      observePacing: (_, pacing) {
        if (pacing.setAside case final aside?) {
          for (final family in aside.pressuredFamilies) {
            setAsides.update(family, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      },
    );
    for (final exposure in familyExposures(
      trajectory,
      window: window,
      streakLength: streak,
      setAsides: setAsides,
    )) {
      rows.add(
        _Row(
          archetype: job.archetypeId,
          family: exposure.family,
          firstSlot: exposure.firstSlot,
          attempts: exposure.attempts,
          share: exposure.share,
          shareAfterStreaks: exposure.shareAfterStreaks,
          managedYield: exposure.managedYield,
          longestStreak: exposure.longestUnproductiveStreak,
          streaks: exposure.streaks,
          slotsToNextManaged: exposure.slotsToNextManaged,
          setAsides: exposure.setAsides,
        ),
      );
    }
  }
  return rows;
}
