import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Whether oscillating support and an empty sitting are one defect.
///
/// Two findings that look like they share a cause. A learner who cannot start a
/// material is introduced at the previewed rung, recovered to full cueing,
/// and - because an unstarted attempt writes no execution evidence - is
/// introduced again. Over a wide catalog the scheduler eventually escapes
/// sideways to another scale; over a narrow one there is nowhere sideways to
/// go, and the slot admits nothing.
///
/// If the seeds that oscillate over the wide catalog are the seeds that run dry
/// over the narrow one, and the terminal traces show the same alternation, then
/// there is one recovery-state defect rather than two scheduler issues.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '40')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('archetype', defaultsTo: 'true_beginner')
    ..addOption('terminals', defaultsTo: '2');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final terminalLimit = int.parse(options.option('terminals')!);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('archetype'),
  );

  // A goal aimed at a handful of scales, which is the production path to a
  // narrow catalog.
  final goal = PracticeGoal(
    id: 'FIVE_SCALES',
    targetMaterialIds: {
      for (final material in allScales.take(5)) material.materialId,
    },
  );
  final narrow = goal.scopeOf(allScales);

  var bothOscillateAndDry = 0;
  var oscillatesOnly = 0;
  var driesOnly = 0;
  var neither = 0;
  final dryOscillators = <int>[];
  final terminals = <String>[];

  for (var seed = 0; seed < seeds; seed++) {
    final wide = runTrajectory(
      player: player,
      seed: seed,
      materials: allScales,
      slots: slots,
    );
    final oscillates = clusterKindsIn(
      wide,
    ).contains(ClusterKind.oscillatingSupport);

    final scoped = runTrajectory(
      player: player,
      seed: seed,
      materials: narrow,
      slots: slots,
    );
    final dry = scoped.slots.length < slots;

    if (oscillates && dry) {
      bothOscillateAndDry++;
      dryOscillators.add(seed);
    } else if (oscillates) {
      oscillatesOnly++;
    } else if (dry) {
      driesOnly++;
    } else {
      neither++;
    }

    if (dry && terminals.length < terminalLimit) {
      terminals.add(_terminal(seed, scoped));
    }
  }

  stdout
    ..writeln('${player.id}: $seeds seeds x $slots slots')
    ..writeln('  wide   = ${allScales.length} materials')
    ..writeln('  narrow = ${narrow.length}, through PracticeGoal.scopeOf\n')
    ..writeln(
      '  oscillates wide AND dries narrow  '
      '${bothOscillateAndDry.toString().padLeft(4)}',
    )
    ..writeln(
      '  oscillates wide only              '
      '${oscillatesOnly.toString().padLeft(4)}',
    )
    ..writeln(
      '  dries narrow only                 '
      '${driesOnly.toString().padLeft(4)}',
    )
    ..writeln(
      '  neither                           '
      '${neither.toString().padLeft(4)}',
    );

  final dry = bothOscillateAndDry + driesOnly;
  if (dry > 0) {
    stdout.writeln(
      '\n  of the $dry that dry, '
      '${(100 * bothOscillateAndDry / dry).round()}% also oscillate',
    );
  }

  stdout.writeln('\nthe last slots before the sitting admitted nothing:\n');
  for (final terminal in terminals) {
    stdout.writeln('$terminal\n');
  }
}

/// The tail of a sitting that ran dry.
String _terminal(int seed, Trajectory trajectory, {int show = 8}) {
  final tail = trajectory.slots.length <= show
      ? trajectory.slots
      : trajectory.slots.sublist(trajectory.slots.length - show);
  return [
    '  seed $seed, dry after ${trajectory.slots.length} slots',
    for (final slot in tail)
      '    ${slot.index.toString().padLeft(3)} '
          '${slot.chosen.material.materialId.padRight(18)}'
          '${slot.chosen.conditions.hands.id.padRight(9)}'
          'g=${slot.chosen.guidance.independence} '
          '${(slot.winner.challengeBypass?.id ?? 'in-band').padRight(22)}'
          'started=${slot.outcome.started} '
          'motor=${slot.outcome.motorScore.toStringAsFixed(2)}',
  ].join('\n');
}
