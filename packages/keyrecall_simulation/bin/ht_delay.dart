import 'dart:io';

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

  stdout
    ..writeln(
      'what wins while hands together waits, $seeds seeds x $slots slots\n'
      '  gap = slots between the first offer of HT(M) and its selection,\n'
      '        or the end of the sitting when it is never selected\n',
    )
    ..writeln(
      '${'archetype'.padRight(22)}${'gaps'.padLeft(6)}${'slots'.padLeft(7)}'
      '${'other M'.padLeft(9)}${'M as RH'.padLeft(9)}${'M as LH'.padLeft(9)}'
      '${'M other'.padLeft(9)}',
    );

  for (final player in PlayerArchetypes.all) {
    var gaps = 0;
    var total = 0;
    var otherMaterial = 0;
    var sameAsRight = 0;
    var sameAsLeft = 0;
    var sameOther = 0;

    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
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

      gaps++;
      for (final slot in trajectory.slots.skip(offeredAt)) {
        final conditions = slot.chosen.conditions;
        final isTracked = slot.chosen.material.materialId == tracked;
        if (isTracked && conditions.hands == HandConfiguration.together) break;
        total++;
        if (!isTracked) {
          otherMaterial++;
        } else if (conditions.hands == HandConfiguration.right) {
          sameAsRight++;
        } else if (conditions.hands == HandConfiguration.left) {
          sameAsLeft++;
        } else {
          sameOther++;
        }
      }
    }

    String share(int count) =>
        total == 0 ? '-' : '${(100 * count / total).round()}%';

    stdout.writeln(
      '${player.id.padRight(22)}${gaps.toString().padLeft(6)}'
      '${total.toString().padLeft(7)}${share(otherMaterial).padLeft(9)}'
      '${share(sameAsRight).padLeft(9)}${share(sameAsLeft).padLeft(9)}'
      '${share(sameOther).padLeft(9)}',
    );
  }
}
