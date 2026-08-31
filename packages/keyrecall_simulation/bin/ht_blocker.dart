import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Which rank term first separates a waiting hands-together candidate from
/// whatever won the slot.
///
/// A transition urgency has to sit above whichever term is doing the blocking.
/// Placed below it, the mechanism never fires and reproduces the starvation it
/// was written to fix.
///
/// Lexicographic keys make this answerable exactly: walk the terms in order and
/// name the first one that differs.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '12')
    ..addOption('slots', defaultsTo: '60');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);

  final stopwatch = Stopwatch()..start();
  final buckets = dealTrajectoryJobs(seeds);
  final batches = await Future.wait([
    for (final bucket in buckets)
      Isolate.run(() => _blockersFor(bucket, slots)),
  ]);

  final totals = _Blockers();
  for (final batch in batches) {
    totals.absorb(batch);
  }

  stdout.writeln(
    '${totals.waits} slots where an offered hands-together candidate lost, '
    '$seeds seeds x $slots slots, ${buckets.length} isolates in '
    '${stopwatch.elapsed.inSeconds}s',
  );
  final ordered = totals.blockers.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in ordered) {
    final seen = (totals.margins[entry.key] ?? [])..sort();
    String at(double q) => seen.isEmpty
        ? '-'
        : seen[((seen.length - 1) * q).round()].toStringAsExponential(1);
    stdout.writeln(
      '  ${entry.key.padRight(24)}${entry.value.toString().padLeft(7)}'
      '${'${(100 * entry.value / totals.waits).round()}%'.padLeft(6)}'
      '   margin p50 ${at(0.5).padLeft(9)}  p90 ${at(0.9).padLeft(9)}'
      '  max ${at(1.0).padLeft(9)}',
    );
  }
  stdout.writeln();
  for (final entry in ordered) {
    stdout
      ..writeln('${entry.key}:')
      ..writeln(totals.examples[entry.key]);
  }
}

/// Tallies in plain fields so they cross an isolate boundary.
class _Blockers {
  int waits = 0;
  final Map<String, int> blockers = {};
  final Map<String, List<double>> margins = {};
  final Map<String, String> examples = {};

  void absorb(_Blockers other) {
    waits += other.waits;
    other.blockers.forEach((term, count) {
      blockers[term] = (blockers[term] ?? 0) + count;
    });
    other.margins.forEach((term, values) {
      (margins[term] ??= []).addAll(values);
    });
    other.examples.forEach((term, example) {
      examples.putIfAbsent(term, () => example);
    });
  }
}

/// The first rank term on which [waiting] and [winner] differ, and by how much.
(String, double)? _firstDifference(RankKey waiting, RankKey winner) {
  if (waiting.tier != winner.tier) return ('tier', 1);
  if (waiting.coordinationTransition != winner.coordinationTransition) {
    return ('coordinationTransition', 1);
  }
  if (waiting.retention != winner.retention) {
    return ('retention', (winner.retention - waiting.retention).abs());
  }
  if (waiting.information != winner.information) {
    return ('information', (winner.information - waiting.information).abs());
  }
  if (waiting.diversity != winner.diversity) {
    return ('diversity', (winner.diversity - waiting.diversity).abs());
  }
  if (waiting.goals != winner.goals) {
    return ('goals', (winner.goals - waiting.goals).abs());
  }
  if (waiting.realization != winner.realization) return ('realization', 1);
  if (waiting.realizationFit != winner.realizationFit) {
    return ('realizationFit', 1);
  }
  return null;
}

_Blockers _blockersFor(List<TrajectoryJob> jobs, int slots) {
  final found = _Blockers();

  for (final job in jobs) {
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );

    for (final slot in trajectory.slots) {
      final offered = slot.handsTogether.fullyEligibleSelectable;
      if (offered.isEmpty) continue;
      if (slot.chosen.conditions.hands == HandConfiguration.together) continue;
      // The best hands-together candidate actually on offer this slot.
      final waiting = slot.alternatives.where(
        (trace) =>
            trace.exercise.conditions.hands == HandConfiguration.together &&
            offered.contains(trace.exercise.material.materialId) &&
            trace.isRanked,
      );
      if (waiting.isEmpty) continue;

      found.waits++;
      final best = waiting.first;
      final difference = _firstDifference(best.rankKey!, slot.winner.rankKey!);
      final term = difference?.$1 ?? 'nothing (a tie the sort broke)';
      found.blockers[term] = (found.blockers[term] ?? 0) + 1;
      if (difference != null) {
        (found.margins[term] ??= []).add(difference.$2);
      }
      found.examples.putIfAbsent(
        term,
        () =>
            '  ${job.archetypeId} seed ${job.seed} slot ${slot.index}\n'
            '    won  ${slot.winner.exercise.material.materialId} '
            '${slot.winner.exercise.conditions.hands.id} '
            '${slot.winner.rankKey}\n'
            '    HT   ${best.exercise.material.materialId} '
            '${best.exercise.conditions.octaves}oct '
            '${best.exercise.conditions.tempoBpm.toStringAsFixed(0)}bpm '
            '${best.rankKey}',
      );
    }
  }

  return found;
}
