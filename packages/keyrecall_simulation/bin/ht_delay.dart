import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What wins the slots between hands-together becoming offerable and being
/// chosen.
///
/// The latency alone cannot say which ranking layer is responsible, and the two
/// answers call for different fixes:
///
/// - the material was selected, but another realization of it won: a
///   within-material ordering question, answered by preferring the first
///   hands-together realization while it is new;
/// - a different material was selected: a material-scheduling question, where
///   a same-material preference would produce a satisfying regression test and
///   barely move the latency.
///
/// So every slot in the gap is attributed to one of them.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '30')
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
    for (final bucket in buckets) Isolate.run(() => _gapsFor(bucket, slots)),
  ]);

  final totals = <String, _Gaps>{};
  for (final batch in batches) {
    batch.forEach((archetype, gaps) {
      totals.update(
        archetype,
        (into) => into..absorb(gaps),
        ifAbsent: () => gaps,
      );
    });
  }

  stdout
    ..writeln(
      'what wins while hands together waits, $seeds seeds x $slots slots, '
      '${buckets.length} isolates in ${stopwatch.elapsed.inSeconds}s\n'
      '  gap = slots between the first offer of HT(M) and its selection,\n'
      '        or the end of the sitting when it is never selected\n',
    )
    ..writeln(
      '${'archetype'.padRight(22)}${'gaps'.padLeft(6)}${'slots'.padLeft(7)}'
      '${'other M'.padLeft(9)}${'M as RH'.padLeft(9)}${'M as LH'.padLeft(9)}'
      '${'M other'.padLeft(9)}',
    );

  for (final player in PlayerArchetypes.all) {
    final gaps = totals[player.id] ?? _Gaps();
    String share(int count) =>
        gaps.total == 0 ? '-' : '${(100 * count / gaps.total).round()}%';

    stdout.writeln(
      '${player.id.padRight(22)}${gaps.gaps.toString().padLeft(6)}'
      '${gaps.total.toString().padLeft(7)}'
      '${share(gaps.otherMaterial).padLeft(9)}'
      '${share(gaps.sameAsRight).padLeft(9)}'
      '${share(gaps.sameAsLeft).padLeft(9)}'
      '${share(gaps.sameOther).padLeft(9)}',
    );
  }
}

/// Per-archetype tallies, in plain fields so they cross an isolate boundary.
class _Gaps {
  int gaps = 0;
  int total = 0;
  int otherMaterial = 0;
  int sameAsRight = 0;
  int sameAsLeft = 0;
  int sameOther = 0;

  void absorb(_Gaps other) {
    gaps += other.gaps;
    total += other.total;
    otherMaterial += other.otherMaterial;
    sameAsRight += other.sameAsRight;
    sameAsLeft += other.sameAsLeft;
    sameOther += other.sameOther;
  }
}

Map<String, _Gaps> _gapsFor(List<TrajectoryJob> jobs, int slots) {
  final byArchetype = <String, _Gaps>{};

  for (final job in jobs) {
    final gaps = byArchetype.putIfAbsent(job.archetypeId, _Gaps.new);
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );

    // The first material to be offered hands together, followed to its own
    // selection. One material throughout, for the reason every other clock
    // here is per material.
    String? tracked;
    var offeredAt = -1;
    for (final slot in trajectory.slots) {
      final offered = slot.handsTogether.fullyEligibleSelectable;
      if (offered.isEmpty) continue;
      tracked = offered.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      offeredAt = slot.index;
      break;
    }
    if (tracked == null) continue;

    gaps.gaps++;
    for (final slot in trajectory.slots.skip(offeredAt)) {
      final conditions = slot.chosen.conditions;
      final isTracked = slot.chosen.material.materialId == tracked;
      if (isTracked && conditions.hands == HandConfiguration.together) break;
      gaps.total++;
      if (!isTracked) {
        gaps.otherMaterial++;
      } else if (conditions.hands == HandConfiguration.right) {
        gaps.sameAsRight++;
      } else if (conditions.hands == HandConfiguration.left) {
        gaps.sameAsLeft++;
      } else {
        gaps.sameOther++;
      }
    }
  }

  return byArchetype;
}
