import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

/// v1-14, allocation at `k` of 2, and allocation with follow-through, on every
/// [PlausibilityCohort] player and seed pair.
///
/// Writes one JSON line per player, seed pair, and arm. Retrieval is reported
/// twice: as the scheduler's estimate of health, and as what the player's
/// retrieval tests actually did, with who was tested and how.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profiles', defaultsTo: '')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption('arms', defaultsTo: 'v1-14,alloc-2,alloc-2-ft');
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
      for (final arm in options.option('arms')!.split(',')) {
        stderr.writeln('${player.id} $pair $arm');
        final followThrough = arm == 'v1-14'
            ? null
            : FollowThrough(
                RequirementAllocator(k: 2, protectionFloor: 0.6),
                enabled: arm.endsWith('-ft'),
              );
        final census = await runServiceCensus(
          player: player,
          sessions: demoSessions(
            from: demoHistoryStart,
            until: demoHistoryEnd,
            seed: schedule,
          ),
          playerSeed: playerSeed,
          intervention: followThrough,
        );
        final records = census.records;
        stdout.writeln(
          jsonEncode({
            'player': player.id,
            'unit': profile.unit,
            'seeds': pair,
            'arm': arm,
            'attempts': records.length,
            'acquisition decisions': census.decisions.length - records.length,
            'outcomes': ServiceOutcomes.of(
              census,
              intervention: followThrough,
            ).toJson(),
            for (final family in TechnicalMaterial.familyIds)
              'strands $family': summarizeStrands(
                records,
                family,
                events: followThrough?.events ?? const [],
              ),
            'retrieval tests': _retrievalTests(records),
            'recovery attempts': records.where(_isRecovery).length,
            'displaced': _displaced(census),
          }),
        );
      }
    }
  }
}

bool _isRecovery(AttemptRecord record) =>
    record.decision?.challengeBypass == ChallengeBypass.recovery;

/// What the player's retrieval tests outside recovery did, by family and rung,
/// with how much practice of the same strand came before each.
Map<String, Object?> _retrievalTests(List<AttemptRecord> records) {
  final prior = <ExecutionContext, int>{};
  final groups = <String, List<(bool, int)>>{};
  for (final record in records) {
    final strand = executionContextOf(record.exercise);
    final before = prior[strand] ?? 0;
    prior[strand] = before + 1;
    final outcome = switch (record.closure.measurement) {
      Measured(:final outcome) => outcome,
      _ => null,
    };
    if (_isRecovery(record) || outcome == null || !outcome.retrieval.isTested) {
      continue;
    }
    final rung = record.exercise.guidance.notesPreviewed
        ? 'previewed'
        : 'unguided';
    groups
        .putIfAbsent('${record.exercise.material.familyId} $rung', () => [])
        .add((outcome.retrieval == FactualRetrieval.succeeded, before));
  }
  return {
    for (final MapEntry(:key, :value) in groups.entries)
      key: {
        'tests': value.length,
        'succeeded': value.where((t) => t.$1).length,
        'median prior attempts': (value.map((t) => t.$2).toList()
          ..sort())[value.length ~/ 2],
      },
  };
}

/// Substitutions by reason, the displaced winner's family, and what its
/// requirement needed at that decision.
Map<String, int> _displaced(ServiceCensus census) {
  final observed = {
    for (final o in census.observations) (o.decision, o.materialId): o,
  };
  final counts = <String, int>{};
  for (final s in census.substitutions) {
    final displaced = observed[(s.decision, s.displacedMaterialId)];
    final need = displaced == null
        ? 'out of scope'
        : !displaced.covered
        ? 'uncovered'
        : displaced.due
        ? 'covered, due'
        : 'covered, healthy';
    counts.update(
      '${s.reason} over ${displaced?.familyId}, $need',
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  return counts;
}
