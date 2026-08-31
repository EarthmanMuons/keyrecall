import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How long hands-together takes to arrive for each material.
///
/// Three clocks, mapped to the stages that could be responsible, and all three
/// about **the same scale**. A latency that pairs readiness on C major with an
/// offer on G major measures nothing.
///
/// - **ready**: the hands-together prerequisite passed for this material.
/// - **offered**: a fully eligible hands-together candidate was selectable.
/// - **chosen**: one was actually selected.
///
/// Then `offered - ready` is what eligibility, admission, and the repetition
/// guard cost, and `chosen - offered` is what ranking costs.
///
/// Nothing is clamped. A negative latency means the instrument is wrong, and
/// should say so rather than becoming a plausible zero.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '40')
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
    for (final bucket in buckets) Isolate.run(() => _latencyFor(bucket, slots)),
  ]);

  final totals = <String, _Latency>{};
  for (final batch in batches) {
    batch.forEach((archetype, latency) {
      totals.update(
        archetype,
        (into) => into..absorb(latency),
        ifAbsent: () => latency,
      );
    });
  }

  stdout
    ..writeln(
      'hands-together latency per material, $seeds seeds x $slots slots, '
      '${buckets.length} isolates in ${stopwatch.elapsed.inSeconds}s\n'
      '  ready   = stage 2a satisfied the hands-together prerequisite\n'
      '  offered = a fully eligible candidate remained selectable\n'
      '  chosen  = one was selected\n'
      '  latencies are in slots, for the same material throughout\n',
    )
    ..writeln(
      '${'archetype'.padRight(22)}${'ready'.padLeft(7)}${'offrd'.padLeft(7)}'
      '${'chosn'.padLeft(7)}${'off p50'.padLeft(9)}${'off p90'.padLeft(9)}'
      '${'sel p50'.padLeft(9)}${'sel p90'.padLeft(9)}${'bad'.padLeft(5)}'
      '${'trans'.padLeft(7)}${'run'.padLeft(5)}',
    );

  for (final player in PlayerArchetypes.all) {
    final latency = totals[player.id] ?? _Latency();
    stdout.writeln(
      '${player.id.padRight(22)}${latency.everReady.toString().padLeft(7)}'
      '${latency.everOffered.toString().padLeft(7)}'
      '${latency.everChosen.toString().padLeft(7)}'
      '${_quantile(latency.offerLatency, 0.5).padLeft(9)}'
      '${_quantile(latency.offerLatency, 0.9).padLeft(9)}'
      '${_quantile(latency.selectLatency, 0.5).padLeft(9)}'
      '${_quantile(latency.selectLatency, 0.9).padLeft(9)}'
      '${latency.impossible.toString().padLeft(5)}'
      '${latency.transitions.toString().padLeft(7)}'
      '${latency.longestRun.toString().padLeft(5)}',
    );
  }
}

/// Per-archetype tallies, in plain fields so they cross an isolate boundary.
class _Latency {
  int everReady = 0;
  int everOffered = 0;
  int everChosen = 0;
  int impossible = 0;
  int transitions = 0;
  int longestRun = 0;
  final List<int> offerLatency = [];
  final List<int> selectLatency = [];

  void absorb(_Latency other) {
    everReady += other.everReady;
    everOffered += other.everOffered;
    everChosen += other.everChosen;
    impossible += other.impossible;
    transitions += other.transitions;
    if (other.longestRun > longestRun) longestRun = other.longestRun;
    offerLatency.addAll(other.offerLatency);
    selectLatency.addAll(other.selectLatency);
  }
}

Map<String, _Latency> _latencyFor(List<TrajectoryJob> jobs, int slots) {
  final byArchetype = <String, _Latency>{};

  for (final job in jobs) {
    final latency = byArchetype.putIfAbsent(job.archetypeId, _Latency.new);
    final trajectory = runTrajectory(
      player: playerOf(job.archetypeId),
      seed: job.seed,
      materials: allScales,
      slots: slots,
    );

    // How often the transition term decided a slot, and how many in a row.
    // A run of first coordination attempts on different scales is a phase
    // rather than a defect; a long one crowding out everything due is not.
    var run = 0;
    for (final slot in trajectory.slots) {
      if (slot.winner.rankKey!.coordinationTransition) {
        latency.transitions++;
        run++;
        if (run > latency.longestRun) latency.longestRun = run;
      } else {
        run = 0;
      }
    }

    final readyAt = <String, int>{};
    final offeredAt = <String, int>{};
    final chosenAt = <String, int>{};
    for (final slot in trajectory.slots) {
      for (final id in slot.handsTogether.prerequisiteSatisfied) {
        readyAt.putIfAbsent(id, () => slot.index);
      }
      for (final id in slot.handsTogether.fullyEligibleSelectable) {
        offeredAt.putIfAbsent(id, () => slot.index);
      }
      if (slot.chosen.conditions.hands == HandConfiguration.together) {
        chosenAt.putIfAbsent(slot.chosen.material.materialId, () => slot.index);
      }
    }

    for (final ready in readyAt.entries) {
      latency.everReady++;
      final offered = offeredAt[ready.key];
      if (offered == null) continue;
      latency.everOffered++;
      if (offered < ready.value) {
        latency.impossible++;
        continue;
      }
      latency.offerLatency.add(offered - ready.value);

      final chosen = chosenAt[ready.key];
      if (chosen == null) continue;
      if (chosen < offered) {
        latency.impossible++;
        continue;
      }
      latency.everChosen++;
      latency.selectLatency.add(chosen - offered);
    }
  }

  return byArchetype;
}

String _quantile(List<int> values, double q) {
  if (values.isEmpty) return '-';
  final ordered = [...values]..sort();
  return '${ordered[((ordered.length - 1) * q).round()]}';
}
