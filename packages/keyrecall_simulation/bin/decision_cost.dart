import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('slots', defaultsTo: '0,10,40,80')
    ..addOption('seed', defaultsTo: '0');
  final options = parser.parse(arguments);
  final slots = {
    for (final slot in options.option('slots')!.split(',')) int.parse(slot),
  };
  final seed = int.parse(options.option('seed')!);
  final players = [
    PlayerArchetypes.trueBeginner,
    PlayerArchetypes.developing,
    PlayerArchetypes.advanced,
  ];

  final stopwatch = Stopwatch()..start();
  final samples = await runDecisionCostMatrix(
    scopes: ArpeggioPolicyScope.values,
    players: players,
    slots: slots,
    seed: seed,
    onProgress: (completed, total) => stderr.writeln(
      'completed $completed/$total trajectories '
      '(${stopwatch.elapsed.inSeconds}s)',
    ),
  );

  stdout
    ..writeln(
      'decision cost census: slots ${slots.join(",")}, seed $seed, '
      '${stopwatch.elapsed.inSeconds}s',
    )
    ..writeln(
      'scope\tplayer\tslot\tmaterials\tgenerated\tevaluated\tmaterials_seen\t'
      'realizations\tfully_eligible\tprovisional\tchallenge_reached\t'
      'challenge_survived\tranked\tinformation_keys\tguarded\tafter_cap\t'
      'selectable\tranked_of_evaluated\tevaluated_of_generated\t'
      'realization_share\tus_per_candidate\t'
      'us_per_material\trequirements_ms\tevaluate_ms\tguard_ms\tcap_ms\t'
      'pace_ms\tdecide_ms\tassemble_ms\tslot_ms',
    );
  for (final sample in samples) {
    stdout.writeln(
      [
        sample.scope.name,
        sample.playerId,
        sample.slot,
        sample.catalogMaterials,
        sample.generated,
        sample.evaluated,
        sample.distinctMaterials,
        sample.distinctRealizations,
        sample.fullyEligible,
        sample.provisional,
        sample.challengeReached,
        sample.challengeSurvived,
        sample.ranked,
        sample.informationKeys,
        sample.guarded,
        sample.afterIntroductionCap,
        sample.selectable,
        sample.rankedShare.toStringAsFixed(4),
        sample.neighborExpansion.toStringAsFixed(3),
        sample.realizationShare.toStringAsFixed(3),
        sample.microsecondsPerCandidate.toStringAsFixed(1),
        sample.microsecondsPerMaterial.toStringAsFixed(1),
        _ms(sample.requirements),
        _ms(sample.evaluate),
        _ms(sample.guard),
        _ms(sample.cap),
        _ms(sample.pace),
        _ms(sample.decide),
        _ms(sample.assemble),
        _ms(sample.slotTotal),
      ].join('\t'),
    );
  }
}

String _ms(Duration duration) =>
    (duration.inMicroseconds / 1000).toStringAsFixed(1);
