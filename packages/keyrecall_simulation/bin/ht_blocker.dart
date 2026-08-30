import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Which rank term first separates a waiting hands-together candidate from
/// whatever won the slot.
///
/// The delay is entirely other materials winning, so a transition urgency has
/// to sit above whichever term is actually doing the blocking. Placed below
/// it, the mechanism would never fire and would reproduce the starvation it
/// was written to fix.
///
/// Lexicographic keys make this answerable exactly: walk the terms in order
/// and name the first one that differs.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '12')
    ..addOption('slots', defaultsTo: '60');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);

  final blockers = <String, int>{};
  final margins = <String, List<double>>{};
  final examples = <String, String>{};
  var waits = 0;

  (String, double)? firstDifference(RankKey waiting, RankKey winner) {
    if (waiting.tier != winner.tier) return ('tier', 1);
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

  for (final player in PlayerArchetypes.all) {
    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      );

      for (final slot in trajectory.slots) {
        if (slot.handsTogetherOffered.isEmpty) continue;
        if (slot.chosen.conditions.hands == HandConfiguration.together) {
          continue;
        }
        // The best hands-together candidate actually on offer this slot.
        final waiting = slot.alternatives.where(
          (trace) =>
              trace.exercise.conditions.hands == HandConfiguration.together &&
              slot.handsTogetherOffered.contains(
                trace.exercise.material.materialId,
              ) &&
              trace.challengeSurvived,
        );
        if (waiting.isEmpty) continue;

        waits++;
        final best = waiting.first;
        final difference = firstDifference(best.rankKey!, slot.winner.rankKey!);
        final term = difference?.$1 ?? 'nothing (a tie the sort broke)';
        blockers[term] = (blockers[term] ?? 0) + 1;
        if (difference != null) {
          (margins[term] ??= []).add(difference.$2);
        }
        examples.putIfAbsent(
          term,
          () =>
              '  ${player.id} seed $seed slot ${slot.index}\n'
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
  }

  stdout.writeln('$waits slots where an offered hands-together candidate lost');
  final ordered = blockers.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in ordered) {
    final seen = (margins[entry.key] ?? [])..sort();
    String at(double q) => seen.isEmpty
        ? '-'
        : seen[((seen.length - 1) * q).round()].toStringAsExponential(1);
    stdout.writeln(
      '  ${entry.key.padRight(20)}${entry.value.toString().padLeft(7)}'
      '${'${(100 * entry.value / waits).round()}%'.padLeft(6)}'
      '   margin p50 ${at(0.5).padLeft(9)}  p90 ${at(0.9).padLeft(9)}'
      '  max ${at(1.0).padLeft(9)}',
    );
  }
  stdout.writeln();
  for (final entry in ordered) {
    stdout
      ..writeln('${entry.key}:')
      ..writeln(examples[entry.key]);
  }
}
