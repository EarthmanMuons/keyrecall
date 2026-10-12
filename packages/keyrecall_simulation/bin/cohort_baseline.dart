import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

/// How each [PlausibilityCohort] player behaves under v1-14, before any policy
/// is compared on them: what they complete, how well, at what pace, with how
/// much guidance, and how that changes from the first third of the run to the
/// last.
///
/// Writes one JSON line per player and seed pair; `--profiles` takes indexes
/// into the cohort, so a run can be split across processes.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profiles', defaultsTo: '')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104');
  final options = parser.parse(arguments);
  final chosen = options.option('profiles')!;
  final profiles = chosen.isEmpty
      ? PlausibilityCohort.profiles
      : [
          for (final index in chosen.split(','))
            PlausibilityCohort.profiles[int.parse(index)],
        ];
  for (final profile in profiles) {
    final player = profile.player;
    for (final pair in options.option('seeds')!.split(',')) {
      final [schedule, playerSeed] = [
        for (final part in pair.split(':')) int.parse(part),
      ];
      stderr.writeln('${player.id} $pair');
      final census = await runServiceCensus(
        player: player,
        sessions: demoSessions(
          from: demoHistoryStart,
          until: demoHistoryEnd,
          seed: schedule,
        ),
        playerSeed: playerSeed,
      );
      final records = census.records;
      final third = records.length ~/ 3;
      stdout.writeln(
        jsonEncode({
          'player': player.id,
          'unit': profile.unit,
          'seeds': pair,
          'attempts': records.length,
          'whole run': _behavior(records),
          'first third': _behavior(records.sublist(0, third)),
          'last third': _behavior(records.sublist(records.length - third)),
          'first timed attempt': _firstIndex(
            records,
            (o) => o.motorScore != null,
          ),
          'first managed attempt': _firstIndex(
            records,
            const LearnerModel().executionWasManaged,
          ),
          'outcomes': ServiceOutcomes.of(census).toJson(),
        }),
      );
    }
  }
}

Outcome? _outcomeOf(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) => outcome,
      _ => null,
    };

int? _firstIndex(List<AttemptRecord> records, bool Function(Outcome) test) {
  for (final (index, record) in records.indexed) {
    final outcome = _outcomeOf(record);
    if (outcome != null && test(outcome)) return index;
  }
  return null;
}

Map<String, Object?> _behavior(List<AttemptRecord> records) {
  const learner = LearnerModel();
  final outcomes = [for (final r in records) ?_outcomeOf(r)];
  final completed = outcomes.where((o) => o.completed).toList();
  final timed = [
    for (final o in completed)
      if (o.motorScore != null) o,
  ];
  double? share(int part, int whole) => whole == 0 ? null : part / whole;
  return {
    'started': share(outcomes.where((o) => o.started).length, records.length),
    'completed': share(completed.length, records.length),
    'pitch integrity, completed': _quantiles([
      for (final o in completed) o.pitchIntegrity,
    ]),
    'timed share of completed': share(timed.length, completed.length),
    'motor score, timed': _quantiles([for (final o in timed) o.motorScore!]),
    'managed share of timed': share(
      timed.where(learner.executionWasManaged).length,
      timed.length,
    ),
    'chosen tempo ratio': _quantiles([
      for (final o in outcomes) ?o.chosenTempoRatio,
    ]),
    'guided': share(
      records.where((r) => r.exercise.guidance.isMaterialSupplied).length,
      records.length,
    ),
    'recovery': share(
      records
          .where((r) => r.decision?.challengeBypass == ChallengeBypass.recovery)
          .length,
      records.length,
    ),
  };
}

List<double>? _quantiles(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  double at(double q) => values[((values.length - 1) * q).round()];
  return [at(0.1), at(0.5), at(0.9)];
}
