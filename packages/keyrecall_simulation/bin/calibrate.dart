import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Fits synthetic players to one exported sitting.
///
/// Deliberately diagnostic. It prints what the sitting looked like, what the
/// ensemble found, what the sitting could and could not speak to, and what a
/// few ensemble members do when they answer the same questions. It does not
/// run anything forward: whether a fitted learner would have a good six months
/// is a different question, asked once this one reads sensibly.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('samples', defaultsTo: '4000')
    ..addOption('keep', defaultsTo: '40')
    ..addOption('replays', defaultsTo: '5')
    ..addOption('seed', defaultsTo: '0')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help') || options.rest.isEmpty) {
    stdout.writeln('usage: calibrate <sitting.json>\n${parser.usage}');
    return;
  }

  final export = decodeSittingExport(
    File(options.rest.first).readAsStringSync(),
  );
  final observed = profileOf(observationsOf(export));
  final presented = [for (final attempt in export.attempts) attempt.exercise];

  stdout
    ..writeln('== the sitting')
    ..writeln(_describe(observed))
    ..writeln();

  final ensemble = fitPlayers(
    target: observed,
    presented: presented,
    vary: firstSitting,
    samples: int.parse(options.option('samples')!),
    keep: int.parse(options.option('keep')!),
    replays: int.parse(options.option('replays')!),
    seed: int.parse(options.option('seed')!),
  );

  stdout
    ..writeln('== the fit')
    ..writeln(
      calibrationReport(
        ensemble: ensemble,
        observed: observed,
        vary: firstSitting,
      ),
    )
    ..writeln()
    ..writeln('== what three of them do with the same sitting');
  for (final fit in [
    ensemble.first,
    ensemble[ensemble.length ~/ 2],
    ensemble.last,
  ]) {
    stdout
      ..writeln('   distance ${fit.distance.toStringAsFixed(3)}')
      ..writeln(_describe(profileOf(replay(fit.player, presented, seed: 7))));
  }
}

String _describe(SittingProfile profile) {
  String hands(Map<HandConfiguration, double> values, {int digits = 2}) => [
    for (final hand in HandConfiguration.values)
      if (values[hand] case final value?)
        '${hand.id.toLowerCase()} ${value.toStringAsFixed(digits)}',
  ].join(', ');

  return [
    '   attempts   ${profile.attempts}',
    '   played     ${hands(profile.achievedTempo, digits: 0)}',
    '   motor      ${hands(profile.motor)}',
    '   slope      ${hands(profile.tempoSlope)}',
    '   ratio      ${profile.tempoRatio.toStringAsFixed(2)}',
    '   sprints    ${(profile.sprintShare * 100).round()}%',
    '   completed  ${(profile.completionRate * 100).round()}%',
    if (profile.handsTogetherPenalty case final penalty?)
      '   ht cost    ${penalty.toStringAsFixed(2)}',
    if (profile.familiarMotor case final familiar?)
      '   familiar   ${familiar.toStringAsFixed(2)}',
    if (profile.unfamiliarMotor case final unfamiliar?)
      '   unfamiliar ${unfamiliar.toStringAsFixed(2)}',
  ].join('\n');
}
