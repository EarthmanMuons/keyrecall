import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How the production goals unfold over daily sittings, per archetype.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('sittings', defaultsTo: '10')
    ..addOption('slots', defaultsTo: '20', help: 'slots per sitting')
    ..addOption('jobs', defaultsTo: '8')
    ..addOption(
      'target-shapes',
      allowed: [for (final value in TargetShapePreference.values) value.name],
      defaultsTo: 'off',
    );
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final sittings = int.parse(options.option('sittings')!);
  final slots = int.parse(options.option('slots')!);

  final stopwatch = Stopwatch()..start();
  final runs = await runGoalTrajectoryMatrix(
    seeds: seeds,
    sittings: sittings,
    slotsPerSitting: slots,
    parallelism: int.parse(options.option('jobs')!),
    targetShapes: TargetShapePreference.values.byName(
      options.option('target-shapes')!,
    ),
    onProgress: (completed, total) {
      if (completed == total || completed % 16 == 0) {
        stderr.writeln(
          'completed $completed/$total (${stopwatch.elapsed.inSeconds}s)',
        );
      }
    },
  );
  stdout.writeln(
    'goal trajectories: $seeds seeds, $sittings sittings of $slots slots, '
    '${stopwatch.elapsed.inSeconds}s',
  );

  final columns = <String, String Function(List<GoalTrajectoryRun>)>{
    'runs': (group) => '${group.length}',
    'picks': (group) => _mean(group.map((run) => run.selections.length)),
    'covered': (group) => _share(
      group.map((run) => run.finalCovered),
      group.map((run) => run.targetCount),
    ),
    'complete': (group) => '${group.where((run) => run.isComplete).length}',
    'first_cover': (group) => _slot(group, (run) => run.slotCovering(1e-9)),
    'cov25': (group) => _slot(group, (run) => run.slotCovering(0.25)),
    'cov50': (group) => _slot(group, (run) => run.slotCovering(0.5)),
    'cov75': (group) => _slot(group, (run) => run.slotCovering(0.75)),
    'cov100': (group) => _slot(group, (run) => run.slotCovering(1)),
    'caught_up': (group) => _mean(
      group.map(
        (run) => run.sittings.where((end) => end == SittingEnd.caughtUp).length,
      ),
    ),
    'blocked': (group) => _mean(
      group.map(
        (run) => run.sittings.where((end) => end == SittingEnd.blocked).length,
      ),
    ),
    'materials': (group) => _mean(
      group.map(
        (run) => {for (final pick in run.selections) pick.materialId}.length,
      ),
    ),
    'top_share': (group) => _meanOf(group.map(_topShare)),
    'arpeggio': (group) => _pickShare(
      group,
      (pick) => pick.familyId == TechnicalMaterial.arpeggioFamilyId,
    ),
    'altered': (group) => _pickShare(
      group,
      (pick) => pick.form != null && !coreForms.contains(pick.form),
    ),
    'support': (group) => _pickShare(group, (pick) => !pick.isTarget),
    'live': (group) => _pickShare(group, (pick) => pick.isLiveSupport),
    'target_shaped': (group) =>
        _pickShare(group, (pick) => pick.isTargetShaped),
    'unguided': (group) =>
        _pickShare(group, (pick) => !pick.guidance.isMaterialSupplied),
    'cued': (group) =>
        _pickShare(group, (pick) => pick.guidance.concurrentPitchCues),
    'ht': (group) =>
        _pickShare(group, (pick) => pick.hands == HandConfiguration.together),
    'lh': (group) =>
        _pickShare(group, (pick) => pick.hands == HandConfiguration.left),
    'two_oct': (group) => _pickShare(group, (pick) => pick.octaves >= 2),
    'up_down': (group) =>
        _pickShare(group, (pick) => pick.direction == ExerciseDirection.upDown),
    'first_arp': (group) => _first(
      group,
      (pick) => pick.familyId == TechnicalMaterial.arpeggioFamilyId,
    ),
    'first_altered': (group) => _first(
      group,
      (pick) => pick.form != null && !coreForms.contains(pick.form),
    ),
    'first_ht': (group) =>
        _first(group, (pick) => pick.hands == HandConfiguration.together),
    'first_2oct': (group) => _first(group, (pick) => pick.octaves >= 2),
    'first_unguided': (group) =>
        _first(group, (pick) => !pick.guidance.isMaterialSupplied),
    'first_shaped': (group) => _first(group, (pick) => pick.isTargetShaped),
  };

  final byScope = <GoalTrajectoryScope, List<GoalTrajectoryRun>>{};
  final byPlayer = <String, List<GoalTrajectoryRun>>{};
  for (final run in runs) {
    byScope.putIfAbsent(run.scope, () => []).add(run);
    byPlayer
        .putIfAbsent('${run.scope.name}\t${run.playerId}', () => [])
        .add(run);
  }

  stdout
    ..writeln()
    ..writeln(['scope', ...columns.keys].join('\t'));
  for (final MapEntry(key: scope, value: group) in byScope.entries) {
    stdout.writeln(
      [
        scope.name,
        for (final column in columns.values) column(group),
      ].join('\t'),
    );
  }
  stdout
    ..writeln()
    ..writeln(['scope', 'player', ...columns.keys].join('\t'));
  for (final MapEntry(key: key, value: group) in byPlayer.entries) {
    stdout.writeln(
      [key, for (final column in columns.values) column(group)].join('\t'),
    );
  }
}

String _mean(Iterable<int> values) => values.isEmpty
    ? '-'
    : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1);

String _meanOf(Iterable<double> values) => values.isEmpty
    ? '-'
    : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(3);

String _share(Iterable<int> parts, Iterable<int> wholes) {
  final whole = wholes.fold(0, (sum, value) => sum + value);
  return whole == 0
      ? '-'
      : (parts.fold(0, (sum, value) => sum + value) / whole).toStringAsFixed(3);
}

/// The mean slot at which [slotOf] happened, over the runs where it did, and
/// how many of them it did in.
String _slot(
  List<GoalTrajectoryRun> group,
  int? Function(GoalTrajectoryRun) slotOf,
) {
  final slots = [for (final run in group) ?slotOf(run)];
  return slots.isEmpty ? '-' : '${_mean(slots)}/${slots.length}';
}

String _first(
  List<GoalTrajectoryRun> group,
  bool Function(GoalTrajectorySelection) test,
) => _slot(group, (run) => run.firstSlotWhere(test));

String _pickShare(
  List<GoalTrajectoryRun> group,
  bool Function(GoalTrajectorySelection) test,
) {
  final picks = group.fold(0, (sum, run) => sum + run.selections.length);
  final hits = group.fold(0, (sum, run) => sum + run.count(test));
  return picks == 0 ? '-' : (hits / picks).toStringAsFixed(3);
}

/// The share of a run's picks that went to its most-picked material.
double _topShare(GoalTrajectoryRun run) {
  if (run.selections.isEmpty) return 0;
  final counts = <String, int>{};
  for (final pick in run.selections) {
    counts[pick.materialId] = (counts[pick.materialId] ?? 0) + 1;
  }
  final top = counts.values.reduce((a, b) => a > b ? a : b);
  return top / run.selections.length;
}
