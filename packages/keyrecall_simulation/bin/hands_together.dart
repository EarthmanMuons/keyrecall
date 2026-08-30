import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How long hands-together takes to arrive, measured per material.
///
/// Three clocks, mapped to the stages that could be responsible, and all three
/// about **the same scale**. A latency that pairs readiness on C major with an
/// offer on G major measures nothing, which a first version of this did: it
/// took the first hands-together candidate of any material and any eligibility
/// tier, found one in nearly every opening slot, and concluded the delay was
/// all ranking.
///
/// - **ready**: stage 2a considers the hands-together prerequisite satisfied
///   for this material. The scheduler's own verdict, not both hands having
///   completed it once, so the clock starts where production thinks it starts.
/// - **offered**: a fully eligible hands-together candidate for it survived
///   challenge admission, so the slot could have presented it.
/// - **chosen**: one was actually selected.
///
/// Then `offered - ready` is what prerequisites and admission cost, and
/// `chosen - offered` is what ranking costs.
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

  stdout
    ..writeln(
      'hands-together latency per material, $seeds seeds x $slots slots\n'
      '  ready   = stage 2a satisfied the hands-together prerequisite\n'
      '  offered = a fully eligible candidate survived admission\n'
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
    var everReady = 0;
    var everOffered = 0;
    var everChosen = 0;
    var impossible = 0;
    var transitions = 0;
    var longestRun = 0;
    final offerLatency = <int>[];
    final selectLatency = <int>[];

    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      );

      // How often the transition term decided a slot, and how many in a row.
      // A run of first coordination attempts on different scales is a phase
      // rather than a defect; a long one crowding out everything due is not.
      var run = 0;
      for (final slot in trajectory.slots) {
        if (slot.winner.rankKey!.coordinationTransition) {
          transitions++;
          run++;
          if (run > longestRun) longestRun = run;
        } else {
          run = 0;
        }
      }

      final readyAt = <String, int>{};
      final offeredAt = <String, int>{};
      final chosenAt = <String, int>{};
      for (final slot in trajectory.slots) {
        for (final id in slot.handsTogetherReady) {
          readyAt.putIfAbsent(id, () => slot.index);
        }
        for (final id in slot.handsTogetherOffered) {
          offeredAt.putIfAbsent(id, () => slot.index);
        }
        if (slot.chosen.conditions.hands == HandConfiguration.together) {
          chosenAt.putIfAbsent(
            slot.chosen.material.materialId,
            () => slot.index,
          );
        }
      }

      if (readyAt.isEmpty) continue;
      everReady++;
      if (offeredAt.isEmpty) continue;
      everOffered++;

      // The earliest material to become ready, followed through on itself.
      final first = readyAt.entries.reduce(
        (a, b) => a.value <= b.value ? a : b,
      );
      final offered = offeredAt[first.key];
      if (offered == null) continue;
      if (offered < first.value) {
        impossible++;
        continue;
      }
      offerLatency.add(offered - first.value);

      final chosen = chosenAt[first.key];
      if (chosen == null) continue;
      if (chosen < offered) {
        impossible++;
        continue;
      }
      everChosen++;
      selectLatency.add(chosen - offered);
    }

    stdout.writeln(
      '${player.id.padRight(22)}${everReady.toString().padLeft(7)}'
      '${everOffered.toString().padLeft(7)}${everChosen.toString().padLeft(7)}'
      '${_quantile(offerLatency, 0.5).padLeft(9)}'
      '${_quantile(offerLatency, 0.9).padLeft(9)}'
      '${_quantile(selectLatency, 0.5).padLeft(9)}'
      '${_quantile(selectLatency, 0.9).padLeft(9)}'
      '${impossible.toString().padLeft(5)}'
      '${transitions.toString().padLeft(7)}${longestRun.toString().padLeft(5)}',
    );
  }
}

String _quantile(List<int> values, double q) {
  if (values.isEmpty) return '-';
  final ordered = [...values]..sort();
  return '${ordered[((ordered.length - 1) * q).round()]}';
}
