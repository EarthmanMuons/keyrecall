import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How far one family's evidence moves the other family's predictions.
///
/// Writes each run to [--out] and prints, per run and reading, the one-octave
/// reference and two-octave probes of both families: the change in predicted
/// execution since placement, what the player could actually do, and where
/// the cross-family change in logit came from.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('jobs', defaultsTo: '4')
    ..addOption('out', defaultsTo: 'transfer_census.jsonl');
  final options = parser.parse(arguments);
  final stopwatch = Stopwatch()..start();
  final runs = await runTransferMatrix(
    parallelism: int.parse(options.option('jobs')!),
  );
  File(options.option('out')!).writeAsStringSync(
    [for (final run in runs) jsonEncode(run.toJson())].join('\n'),
  );

  String f(double value) => value.toStringAsFixed(3);
  print(
    'transfer census: ${runs.length} runs, ${stopwatch.elapsed.inSeconds}s',
  );
  print(
    [
      'player',
      'tier',
      'evidence',
      'within_d',
      'cross_d',
      'cross_family_logit',
      'cross_two_d',
      'cross_two_shared_logit',
      'cross_two_p',
      'cross_two_managed',
      'eligible_cross_1',
      'eligible_cross_2',
      'after_one',
      'control_one',
      'after_two',
      'control_two',
      'managed_two',
    ].join('\t'),
  );
  for (final run in runs) {
    final evidence = run.firstFamilyId;
    final cross = otherFamilyOf(evidence);
    TransferCheckpoint at(String phase, int attempts) =>
        run.checkpoints.firstWhere(
          (point) => point.phase == phase && point.attempts == attempts,
        );
    final start = at('first', 0);
    final end = at('first', transferFirstPhaseCheckpoints.last);
    final after = at('second', transferSecondPhaseCheckpoints.last);
    final control = at('control', transferSecondPhaseCheckpoints.last);
    double moved(String family, TransferShape shape, String key) =>
        (end.probe(family, shape).logit[key] ?? 0) -
        (start.probe(family, shape).logit[key] ?? 0);
    double gained(String family, TransferShape shape) =>
        end.probe(family, shape).predicted -
        start.probe(family, shape).predicted;
    const one = TransferShape.rightOneUp;
    const two = TransferShape.rightTwoUpDown;
    print(
      [
        run.playerId,
        run.tier.name,
        evidence,
        f(gained(evidence, one)),
        f(gained(cross, one)),
        f(moved(cross, one, 'family_transfer')),
        f(gained(cross, two)),
        f(
          moved(cross, two, 'own:${Competency.multiOctaveContinuation.id}') +
              moved(cross, two, 'own:${Competency.directionReversal.id}'),
        ),
        f(end.probe(cross, two).predicted),
        f(end.probe(cross, two).managed),
        '${start.eligible['$cross:1']}->${end.eligible['$cross:1']}',
        '${start.eligible['$cross:2']}->${end.eligible['$cross:2']}',
        f(after.probe(cross, one).predicted),
        f(control.probe(cross, one).predicted),
        f(after.probe(cross, two).predicted),
        f(control.probe(cross, two).predicted),
        f(after.probe(cross, two).managed),
      ].join('\t'),
    );
  }
}
