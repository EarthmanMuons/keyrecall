import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether the coordination transition is causing short cycles.
///
/// `short_cycle_repetition` more than doubled for one archetype in the same
/// sweep as the transition term landed. An observational detector moving that
/// far alongside a production change is a regression until shown otherwise,
/// even though its threshold is uncalibrated.
///
/// Classifies each alternation by how close it sits to a transition, since the
/// trajectory already records whether the winner of every slot carried one.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '25')
    ..addOption('slots', defaultsTo: '50');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);

  const categories = [
    'transition won inside it',
    'a cycling scale just transitioned',
    'transition elsewhere in the run',
    'no transition involvement',
  ];

  stdout.writeln(
    'short cycles by transition involvement, $seeds seeds x $slots slots\n',
  );
  stdout.writeln(
    '${'archetype'.padRight(22)}${'cycles'.padLeft(8)}'
    '${categories.map((c) => c.split(' ').first.padLeft(11)).join()}',
  );

  final examples = <String, String>{};
  for (final player in PlayerArchetypes.all) {
    final counts = {for (final category in categories) category: 0};
    var cycles = 0;

    for (var seed = 0; seed < seeds; seed++) {
      final trajectory = runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      );
      final anySlot = trajectory.slots;
      final transitionedAt = <String, int>{
        for (final slot in anySlot)
          if (slot.winner.rankKey!.coordinationTransition)
            slot.chosen.material.materialId: slot.index,
      };

      // The detector's own condition: the same two materials alternating,
      // reported once the run reaches six slots.
      var run = 0;
      for (var i = 2; i < anySlot.length; i++) {
        final same =
            anySlot[i].chosen.material.materialId ==
            anySlot[i - 2].chosen.material.materialId;
        run = same ? run + 1 : 0;
        if (run != 4) continue;

        cycles++;
        final window = anySlot.sublist(i - 5, i + 1);
        final pair = {
          for (final slot in window) slot.chosen.material.materialId,
        };
        final wonInside = window.any(
          (slot) => slot.winner.rankKey!.coordinationTransition,
        );
        final justTransitioned = pair.any((id) {
          final at = transitionedAt[id];
          return at != null && at < i && i - at <= 8;
        });

        final category = wonInside
            ? categories[0]
            : justTransitioned
            ? categories[1]
            : transitionedAt.isNotEmpty
            ? categories[2]
            : categories[3];
        counts[category] = counts[category]! + 1;

        examples.putIfAbsent(
          '${player.id}/$category',
          () => [
            '  ${player.id} seed $seed, slots ${i - 5} to $i  [$category]',
            for (final slot in window)
              '    ${slot.index.toString().padLeft(3)} '
                  '${slot.chosen.material.materialId.padRight(18)}'
                  '${slot.chosen.conditions.hands.id.padRight(9)}'
                  '${slot.winner.challengeBypass?.id ?? 'in-band'}'
                  '${slot.winner.rankKey!.coordinationTransition ? '  TRANSITION' : ''}',
          ].join('\n'),
        );
      }
    }

    stdout.writeln(
      '${player.id.padRight(22)}${cycles.toString().padLeft(8)}'
      '${categories.map((c) => counts[c].toString().padLeft(11)).join()}',
    );
  }

  stdout.writeln('\nlegend: ${categories.join(' | ')}\n');
  for (final key in ['developing', 'tempo_noncompliant']) {
    for (final category in categories) {
      final example = examples['$key/$category'];
      if (example != null) stdout.writeln('$example\n');
    }
  }
}
