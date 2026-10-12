import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

/// Recovery episodes for [PlausibilityCohort] players under v1-14.
///
/// An episode opens on an attempt whose retrieval test failed and runs through
/// the recovery decisions that follow it in the same session. It ends when a
/// recovery attempt does not fail retrieval, or when the session does. After
/// it, the next attempt on the same strand that tests retrieval outside
/// recovery says whether the episode left anything behind.
///
/// Writes one JSON line per player and seed pair; `--traces` adds that many
/// episodes in full.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profiles', defaultsTo: '')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption('traces', defaultsTo: '0');
  final options = parser.parse(arguments);
  final chosen = options.option('profiles')!;
  final profiles = chosen.isEmpty
      ? PlausibilityCohort.profiles
      : [
          for (final index in chosen.split(','))
            PlausibilityCohort.profiles[int.parse(index)],
        ];
  final traces = int.parse(options.option('traces')!);
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
      final episodes = _episodes(census.records);
      stdout.writeln(
        jsonEncode({
          'player': player.id,
          'seeds': pair,
          'attempts': census.records.length,
          'covered': ServiceOutcomes.of(census).covered,
          'recovery attempts': census.records.where(_isRecovery).length,
          'retest after success': _retestAfterSuccess(census.records),
          'episodes': [for (final e in episodes) e.summary(census.records)],
          if (traces > 0)
            'traces': [
              for (final e in episodes.take(traces)) e.trace(census.records),
            ],
        }),
      );
    }
  }
}

bool _isRecovery(AttemptRecord record) =>
    record.decision?.challengeBypass == ChallengeBypass.recovery;

Outcome? _outcomeOf(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) => outcome,
      _ => null,
    };

String _describe(Outcome? outcome) {
  if (outcome == null) return 'unmeasured';
  if (!outcome.started) return 'not started';
  if (!outcome.completed) return 'incomplete';
  if (const LearnerModel().executionWasManaged(outcome)) return 'managed';
  return outcome.motorScore == null ? 'completed, untimed' : 'completed';
}

class _Episode {
  final int entry;
  final List<int> recovery = [];
  String exit = 'session ended';
  int? next;

  _Episode(this.entry);

  Map<String, Object?> summary(List<AttemptRecord> records) {
    final entered = records[entry];
    final last = recovery.isEmpty ? entry : recovery.last;
    final after = next == null ? null : _outcomeOf(records[next!]);
    return {
      'entry': entry,
      'strand':
          '${entered.exercise.material.materialId}/'
          '${entered.exercise.conditions.hands.name}',
      'family': entered.exercise.material.familyId,
      'entry guidance': entered.exercise.guidance.toString(),
      'entry result': _describe(_outcomeOf(entered)),
      'steps': [
        for (final index in recovery)
          '${_outcomeOf(records[index])?.retrieval.name}: '
              '${_describe(_outcomeOf(records[index]))}',
      ],
      'exit': exit,
      'next gap': next == null ? null : next! - last,
      'next retrieval': after?.retrieval.name,
      'next result': after == null ? null : _describe(after),
    };
  }

  Map<String, Object?> trace(List<AttemptRecord> records) => {
    for (final index in [entry, ...recovery, ?next])
      '$index': {
        'exercise':
            '${records[index].exercise.material.materialId} '
            '${records[index].exercise.conditions.hands.name} '
            '${records[index].exercise.conditions.octaves}oct '
            '${records[index].exercise.conditions.direction.name} '
            '${records[index].exercise.conditions.tempoBpm.round()}bpm '
            '${records[index].exercise.guidance}',
        'retrieval': _outcomeOf(records[index])?.retrieval.name,
        'result': _describe(_outcomeOf(records[index])),
      },
  };
}

List<_Episode> _episodes(List<AttemptRecord> records) {
  final episodes = <_Episode>[];
  _Episode? open;
  for (final (index, record) in records.indexed) {
    final outcome = _outcomeOf(record);
    final failed = outcome?.retrieval == FactualRetrieval.failed;
    final sameSession =
        index > 0 &&
        records[index - 1].identity.sessionId == record.identity.sessionId;
    if (open != null && _isRecovery(record) && sameSession) {
      open.recovery.add(index);
      if (!failed) {
        open.exit = _describe(outcome);
        open = null;
        continue;
      }
    } else if (open != null) {
      open.exit = sameSession ? 'not offered' : 'session ended';
      open = null;
    }
    if (failed && open == null) {
      open = _Episode(index);
      episodes.add(open);
    }
  }
  for (final episode in episodes) {
    final strand = executionContextOf(records[episode.entry].exercise);
    final after = episode.recovery.isEmpty
        ? episode.entry
        : episode.recovery.last;
    for (var i = after + 1; i < records.length; i++) {
      final outcome = _outcomeOf(records[i]);
      if (executionContextOf(records[i].exercise) == strand &&
          !_isRecovery(records[i]) &&
          outcome != null &&
          outcome.retrieval.isTested) {
        episode.next = i;
        break;
      }
    }
  }
  return episodes;
}

/// How often a strand's next retrieval test outside recovery succeeded, when
/// its previous one had: the rate an episode's retest is compared with.
Map<String, int> _retestAfterSuccess(List<AttemptRecord> records) {
  final previous = <ExecutionContext, bool>{};
  var tests = 0, succeeded = 0;
  for (final record in records) {
    final outcome = _outcomeOf(record);
    if (_isRecovery(record) || outcome == null || !outcome.retrieval.isTested) {
      continue;
    }
    final strand = executionContextOf(record.exercise);
    final passed = outcome.retrieval == FactualRetrieval.succeeded;
    if (previous[strand] == true) {
      tests++;
      if (passed) succeeded++;
    }
    previous[strand] = passed;
  }
  return {'tests': tests, 'succeeded': succeeded};
}
