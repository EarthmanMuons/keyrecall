import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What happens to each hand motion after coordination is introduced.
///
/// The transition now always spends itself on contrary motion, which is what
/// the pedagogy asks for. The question that leaves is whether parallel
/// hands-together work is reached afterwards by ordinary execution
/// progression, or whether separate frontiers are technically correct while
/// the scheduler never offers one of them.
///
/// Parallel arriving later is intended. Parallel never arriving at all would
/// be a defect, and it would belong to ordinary realization progression rather
/// than to the introductory preference, which is spent by then.
///
/// Also reports how far candidates get through the stages, because the terms
/// that only ranking consumes are computed for every candidate evaluated and
/// only the surviving ones can use them.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '20')
    ..addOption('slots', defaultsTo: '60')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);

  final stopwatch = Stopwatch()..start();
  final buckets = dealTrajectoryJobs(seeds);
  final batches = await Future.wait([
    for (final bucket in buckets) Isolate.run(() => _countsFor(bucket, slots)),
  ]);

  final totals = <String, _Counts>{};
  for (final batch in batches) {
    batch.forEach((archetype, counts) {
      totals.update(
        archetype,
        (into) => into..absorb(counts),
        ifAbsent: () => counts,
      );
    });
  }

  stdout
    ..writeln(
      'hands-together by motion, $seeds seeds x $slots slots, '
      '${buckets.length} isolates in ${stopwatch.elapsed.inSeconds}s\n'
      '  intro   = materials whose coordination transition was spent\n'
      '  contra  = of those, introduced through contrary motion\n'
      '  par     = of those, that went on to be played parallel\n'
      '  gap     = median slots from the introduction to that first parallel\n'
      '  attempts, and the widest tempo each motion reached\n',
    )
    ..writeln(
      '${'archetype'.padRight(20)}${'intro'.padLeft(7)}${'contra'.padLeft(7)}'
      '${'par'.padLeft(6)}${'gap'.padLeft(6)}${'contra n'.padLeft(10)}'
      '${'par n'.padLeft(8)}${'contra bpm'.padLeft(12)}'
      '${'par bpm'.padLeft(10)}',
    );

  for (final player in PlayerArchetypes.all) {
    final counts = totals[player.id] ?? _Counts();
    stdout.writeln(
      '${player.id.padRight(20)}${counts.introduced.toString().padLeft(7)}'
      '${counts.introducedContrary.toString().padLeft(7)}'
      '${counts.reachedParallel.toString().padLeft(6)}'
      '${_median(counts.gaps).padLeft(6)}'
      '${counts.contraryAttempts.toString().padLeft(10)}'
      '${counts.parallelAttempts.toString().padLeft(8)}'
      '${counts.widestContrary.toStringAsFixed(0).padLeft(12)}'
      '${counts.widestParallel.toStringAsFixed(0).padLeft(10)}',
    );
  }

  stdout.writeln('\nhow far candidates get, averaged over every slot');
  stdout.writeln(
    '${'archetype'.padRight(20)}${'evaluated'.padLeft(11)}'
    '${'eligible'.padLeft(10)}${'admitted'.padLeft(10)}'
    '${'selectable'.padLeft(12)}${'ranked %'.padLeft(10)}',
  );
  for (final player in PlayerArchetypes.all) {
    final counts = totals[player.id] ?? _Counts();
    if (counts.slots == 0) continue;
    final evaluated = counts.evaluated / counts.slots;
    final admitted = counts.admitted / counts.slots;
    stdout.writeln(
      '${player.id.padRight(20)}${evaluated.toStringAsFixed(0).padLeft(11)}'
      '${(counts.eligible / counts.slots).toStringAsFixed(0).padLeft(10)}'
      '${admitted.toStringAsFixed(0).padLeft(10)}'
      '${(counts.selectable / counts.slots).toStringAsFixed(0).padLeft(12)}'
      '${(100 * admitted / evaluated).toStringAsFixed(1).padLeft(10)}',
    );
  }
}

/// Per-archetype tallies, in plain fields so they cross an isolate boundary.
class _Counts {
  int introduced = 0;
  int introducedContrary = 0;
  int reachedParallel = 0;
  int contraryAttempts = 0;
  int parallelAttempts = 0;
  double widestContrary = 0;
  double widestParallel = 0;
  final List<int> gaps = [];

  int slots = 0;
  int evaluated = 0;
  int eligible = 0;
  int admitted = 0;
  int selectable = 0;

  void absorb(_Counts other) {
    introduced += other.introduced;
    introducedContrary += other.introducedContrary;
    reachedParallel += other.reachedParallel;
    contraryAttempts += other.contraryAttempts;
    parallelAttempts += other.parallelAttempts;
    if (other.widestContrary > widestContrary) {
      widestContrary = other.widestContrary;
    }
    if (other.widestParallel > widestParallel) {
      widestParallel = other.widestParallel;
    }
    gaps.addAll(other.gaps);
    slots += other.slots;
    evaluated += other.evaluated;
    eligible += other.eligible;
    admitted += other.admitted;
    selectable += other.selectable;
  }
}

Map<String, _Counts> _countsFor(List<TrajectoryJob> jobs, int slots) {
  final byArchetype = <String, _Counts>{};

  for (final job in jobs) {
    final counts = byArchetype.putIfAbsent(job.archetypeId, _Counts.new);
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );

    // The slot each material's coordination transition was spent in, and the
    // motion it was spent on.
    final introducedAt = <String, int>{};
    final introducedWith = <String, HandMotion>{};
    final firstParallelAt = <String, int>{};

    for (final slot in trajectory.slots) {
      final exercise = slot.winner.exercise;
      if (exercise.conditions.hands != HandConfiguration.together) continue;
      final materialId = exercise.material.materialId;
      final motion = exercise.conditions.handMotion;

      if (slot.winner.terms.coordinationTransition) {
        introducedAt.putIfAbsent(materialId, () => slot.index);
        introducedWith.putIfAbsent(materialId, () => motion);
      }
      if (motion == HandMotion.contrary) {
        counts.contraryAttempts++;
      } else {
        counts.parallelAttempts++;
        firstParallelAt.putIfAbsent(materialId, () => slot.index);
      }

      final reached = slot.frontierAfter.values.fold<double>(
        0,
        (widest, tempo) => tempo > widest ? tempo : widest,
      );
      if (motion == HandMotion.contrary) {
        if (reached > counts.widestContrary) counts.widestContrary = reached;
      } else if (reached > counts.widestParallel) {
        counts.widestParallel = reached;
      }
    }

    introducedAt.forEach((materialId, at) {
      counts.introduced++;
      if (introducedWith[materialId] == HandMotion.contrary) {
        counts.introducedContrary++;
      }
      final parallel = firstParallelAt[materialId];
      if (parallel != null && parallel >= at) {
        counts.reachedParallel++;
        counts.gaps.add(parallel - at);
      }
    });

    for (final slot in trajectory.slots) {
      counts.slots++;
      counts.evaluated += slot.candidates.evaluated;
      counts.eligible += slot.candidates.eligible;
      counts.admitted += slot.candidates.admitted;
      counts.selectable += slot.candidates.selectable;
    }
  }

  return byArchetype;
}

String _median(List<int> values) {
  if (values.isEmpty) return '-';
  final ordered = [...values]..sort();
  return '${ordered[ordered.length ~/ 2]}';
}
