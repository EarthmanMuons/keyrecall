import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Characterizes the players a supplied pulse is for, and how often a sitting
/// brings the same kind of timing evidence back.
///
/// Characterization only. Nothing here decides what should open timing
/// remediation; it reports what a rule for that would have to work with.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('recurrence', defaultsTo: true)
    ..addFlag('remediation', defaultsTo: true)
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('slots', defaultsTo: '12,24', help: 'Attempts per sitting.')
    ..addOption(
      'schedule',
      defaultsTo: 'normal_month',
      allowed: LongitudinalSchedules.all.keys,
    );
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slotCounts = options.option('slots')!.split(',').map(int.parse);
  final schedule = options.option('schedule')!;
  final players = PlayerArchetypes.pulseCharacterization;

  stdout.writeln('== response to a supplied pulse, then its withdrawal');
  stdout.writeln(
    'C major, right hand, one octave, asked for 80; '
    '20 seeds x 6 attempts per phase',
  );
  stdout.writeln(
    '${'player'.padRight(30)}${'phase'.padRight(11)}'
    '${'steady'.padLeft(8)}${'cont.'.padLeft(8)}'
    '${'tempo'.padLeft(8)}${'tested'.padLeft(8)}',
  );
  final exercise = Exercise.linear(
    material: allScales.first,
    hands: HandConfiguration.right,
    tempoBpm: 80,
  );
  for (final player in players) {
    final response = pulseResponseOf(player, exercise: exercise);
    for (final phase in PulsePhase.values) {
      final reading = response[phase];
      stdout.writeln(
        '${player.id.padRight(30)}${phase.name.padRight(11)}'
        '${_fixed(reading.temporalStability)}${_fixed(reading.continuity)}'
        '${_fixed(reading.tempoRatio)}${_fixed(reading.pulseTested)}',
      );
    }
  }

  final keys = <String, Object? Function(Exercise)>{
    'execution context': executionContextOf,
    'material': (exercise) => exercise.material.materialId,
    'hands': (exercise) => exercise.conditions.hands,
    'sitting': (_) => null,
  };
  if (options.flag('remediation')) {
    _remediation(
      players,
      seeds: seeds,
      slots: slotCounts.first,
      schedule: schedule,
    );
  }

  if (!options.flag('recurrence')) return;
  for (final slots in slotCounts) {
    final stopwatch = Stopwatch()..start();
    final trajectories = <Trajectory>[];
    for (final player in players) {
      for (var seed = 0; seed < seeds; seed++) {
        trajectories.add(
          runSittings(
            player: player,
            seed: seed,
            materials: allScales,
            sittings: LongitudinalSchedules.named(schedule, slots: slots),
          ),
        );
        stderr.writeln(
          '$slots slots ${player.id} seed $seed '
          '(${stopwatch.elapsed.inSeconds}s)',
        );
      }
    }

    stdout.writeln();
    stdout.writeln(
      '== timing recurrence within a sitting: $schedule, $slots slots, '
      '${players.length} players x $seeds seeds',
    );
    stdout.writeln(
      '${'same kind means'.padRight(20)}${'obs/sit'.padLeft(9)}'
      '${'keys/sit'.padLeft(10)}${'keys 2+'.padLeft(9)}'
      '${'keys 3+'.padLeft(9)}${'sits 2+'.padLeft(9)}'
      '${'sits 3+'.padLeft(9)}${'gap'.padLeft(7)}',
    );
    for (final MapEntry(key: name, value: keyOf) in keys.entries) {
      final recurrence = TimingRecurrence.of(trajectories, keyOf: keyOf);
      final sittings = recurrence.sittings;
      stdout.writeln(
        '${name.padRight(20)}'
        '${(recurrence.observations / sittings).toStringAsFixed(1).padLeft(9)}'
        '${(recurrence.keys / sittings).toStringAsFixed(1).padLeft(10)}'
        '${_share(recurrence.keysObservedAtLeast[2]!, recurrence.keys)}'
        '${_share(recurrence.keysObservedAtLeast[3]!, recurrence.keys)}'
        '${_share(recurrence.sittingsWithAKeyAtLeast[2]!, sittings)}'
        '${_share(recurrence.sittingsWithAKeyAtLeast[3]!, sittings)}'
        '${(recurrence.medianGap?.toStringAsFixed(1) ?? '-').padLeft(7)}',
      );
    }
  }
}

/// Every player through the scheduler with remediation in force.
void _remediation(
  List<SyntheticPlayer> players, {
  required int seeds,
  required int slots,
  required String schedule,
}) {
  final pipeline = SchedulerPipeline(
    learner: const LearnerModel(),
    config: v1SchedulerConfig.withPulseRemediation(
      const PulseRemediationConfig(),
    ),
  );
  stdout.writeln();
  stdout.writeln(
    '== remediation under the scheduler: $schedule, $slots slots, '
    '$seeds seeds',
  );
  stdout.writeln(
    '${'player'.padRight(30)}${'sittings'.padLeft(9)}${'cycles'.padLeft(8)}'
    '${'withdrawn'.padLeft(11)}'
    '${'steady with'.padLeft(13)}${'steady after'.padLeft(14)}',
  );
  final stopwatch = Stopwatch()..start();
  for (final player in players) {
    final reading = RemediationReading.of([
      for (var seed = 0; seed < seeds; seed++)
        runSittings(
          player: player,
          seed: seed,
          materials: allScales,
          sittings: LongitudinalSchedules.named(schedule, slots: slots),
          pipeline: pipeline,
        ),
    ]);
    stderr.writeln(
      'remediation ${player.id} (${stopwatch.elapsed.inSeconds}s)',
    );
    if (reading.supportedButTested > 0) {
      stderr.writeln(
        '${reading.supportedButTested} supported attempts claimed a held pulse',
      );
    }
    stdout.writeln(
      '${player.id.padRight(30)}'
      '${_share(reading.sittingsWithACycle, reading.sittings)}'
      '${reading.cycles.toString().padLeft(8)}'
      '${reading.withdrawals.toString().padLeft(11)}'
      '${_fixed(reading.meanSupportedSteadiness).padLeft(13)}'
      '${_fixed(reading.meanWithdrawnSteadiness).padLeft(14)}',
    );
  }
}

String _fixed(double value) => value.toStringAsFixed(2).padLeft(8);

String _share(int count, int of) =>
    '${of == 0 ? '-' : (100 * count / of).toStringAsFixed(0)}%'.padLeft(9);
