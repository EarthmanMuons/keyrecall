import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How long hands-together takes to arrive, measured rather than judged.
///
/// The stall detector conflates two mechanisms and so cannot say which is at
/// fault. This separates them:
///
/// - **admission latency**: slots from both hands completing a material to the
///   first slot where any hands-together realization survives admission. Long
///   here means prerequisites or entry tempo.
/// - **selection latency**: slots from that first admissible offer to the
///   first one actually chosen. Long here means ranking.
///
/// Reported as a distribution because the threshold in the stall detector is
/// uncalibrated, and a bound firing on most runs is more likely to be a bad
/// bound than a scheduler that fails most sittings.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '60')
    ..addOption('slots', defaultsTo: '60')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);

  stdout.writeln(
    'hands-together latency, $seeds seeds x $slots slots, allScales\n'
    '  ready    = both hands completed the same material\n'
    '  admitted = a hands-together candidate first survived admission\n'
    '  chosen   = one was first selected\n',
  );
  stdout.writeln(
    '${'archetype'.padRight(22)}${'runs'.padLeft(6)}'
    '${'ready'.padLeft(8)}${'admitd'.padLeft(8)}${'chosen'.padLeft(8)}'
    '${'adm p50'.padLeft(9)}${'adm p90'.padLeft(9)}'
    '${'sel p50'.padLeft(9)}${'sel p90'.padLeft(9)}',
  );

  for (final player in PlayerArchetypes.all) {
    var reached = 0;
    var admitted = 0;
    var chosen = 0;
    final admissionLatency = <int>[];
    final selectionLatency = <int>[];

    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      );

      final completedHands = <String, Set<HandConfiguration>>{};
      int? readyAt;
      int? admittedAt;
      int? chosenAt;
      for (final slot in trajectory.slots) {
        final hands = slot.chosen.conditions.hands;
        if (chosenAt == null && hands == HandConfiguration.together) {
          chosenAt = slot.index;
        }
        if (admittedAt == null && slot.handsTogetherAdmissible) {
          admittedAt = slot.index;
        }
        if (readyAt == null && slot.outcome.completed) {
          final id = slot.chosen.material.materialId;
          (completedHands[id] ??= {}).add(hands);
          if (completedHands[id]!.containsAll({
            HandConfiguration.right,
            HandConfiguration.left,
          })) {
            readyAt = slot.index;
          }
        }
      }

      if (readyAt == null) continue;
      reached++;
      if (admittedAt == null) continue;
      admitted++;
      admissionLatency.add((admittedAt - readyAt).clamp(0, slots));
      if (chosenAt == null) continue;
      chosen++;
      selectionLatency.add((chosenAt - admittedAt).clamp(0, slots));
    }

    stdout.writeln(
      '${player.id.padRight(22)}${seeds.toString().padLeft(6)}'
      '${reached.toString().padLeft(8)}${admitted.toString().padLeft(8)}'
      '${chosen.toString().padLeft(8)}'
      '${_quantile(admissionLatency, 0.5).padLeft(9)}'
      '${_quantile(admissionLatency, 0.9).padLeft(9)}'
      '${_quantile(selectionLatency, 0.5).padLeft(9)}'
      '${_quantile(selectionLatency, 0.9).padLeft(9)}',
    );
  }
}

String _quantile(List<int> values, double q) {
  if (values.isEmpty) return '-';
  final ordered = [...values]..sort();
  final rank = ((ordered.length - 1) * q).round();
  return '${ordered[rank]}';
}
