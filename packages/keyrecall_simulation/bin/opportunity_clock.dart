import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

/// Allocation at `k` of 2 under each [OpportunityClock], on cohort players
/// with the frozen familiarity model or [RetrievalMemory].
///
/// Writes one JSON line per player, configuration, seed pair, and clock: the
/// decisions each kind of slot made, the waiting each clock leaves uncounted,
/// every substitution, and the decision sequence, so runs under different
/// clocks can be compared decision by decision.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profiles', defaultsTo: '18,12,19,10,9,11')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption(
      'configs',
      help: 'learning:half-life:spacing[:restoration], or frozen',
      defaultsTo: 'frozen,1:60:0.5',
    )
    ..addOption(
      'clocks',
      defaultsTo: [
        for (final clock in OpportunityClock.values) clock.name,
      ].join(','),
    );
  final options = parser.parse(arguments);
  for (final index in options.option('profiles')!.split(',')) {
    final profile = PlausibilityCohort.profiles[int.parse(index)];
    for (final config in options.option('configs')!.split(',')) {
      final player = config == 'frozen'
          ? profile.player
          : _withMemory(profile.player, config);
      for (final pair in options.option('seeds')!.split(',')) {
        final [schedule, playerSeed] = [
          for (final part in pair.split(':')) int.parse(part),
        ];
        final sessions = demoSessions(
          from: demoHistoryStart,
          until: demoHistoryEnd,
          seed: schedule,
        );
        for (final name in options.option('clocks')!.split(',')) {
          final clock = OpportunityClock.values.byName(name);
          stderr.writeln('${player.id} $config $pair $name');
          final allocator = RequirementAllocator(
            k: 2,
            protectionFloor: 0.6,
            clock: clock,
          );
          final census = await runServiceCensus(
            player: player,
            sessions: sessions,
            playerSeed: playerSeed,
            intervention: allocator,
          );
          final stageOf = {
            for (final decision in census.decisions)
              decision.decision: decision.stage,
          };
          String kindOf(int decision) => switch (stageOf[decision]) {
            'acquisition' => 'acquisition',
            'blocked' => 'blocked',
            _ => 'selected',
          };
          Map<String, int> countBy(Iterable<String> kinds) {
            final counts = <String, int>{};
            for (final kind in kinds) {
              counts.update(kind, (n) => n + 1, ifAbsent: () => 1);
            }
            return counts;
          }

          stdout.writeln(
            jsonEncode({
              'player': player.id,
              'config': config,
              'seeds': pair,
              'clock': name,
              'decisions': census.decisions.length,
              'slots': countBy(census.decisions.map((d) => kindOf(d.decision))),
              'actionable': countBy([
                for (final o in census.observations)
                  if (o.actionable) kindOf(o.decision),
              ]),
              'deferred': countBy([
                for (final o in census.observations)
                  if (o.deferred) kindOf(o.decision),
              ]),
              'substitutions': [
                for (final s in census.substitutions)
                  [s.decision, s.requirementId, s.missed],
              ],
              'sequence': [
                for (final d in census.decisions)
                  '${d.materialId ?? ''}|${d.stage}',
              ],
              'outcomes': ServiceOutcomes.of(
                census,
                intervention: allocator,
              ).toJson(),
              for (final family in TechnicalMaterial.familyIds)
                'strands $family': summarizeStrands(census.records, family),
            }),
          );
        }
      }
    }
  }
}

SyntheticPlayer _withMemory(SyntheticPlayer player, String config) {
  final memory = RetrievalMemory.scenario(config);
  return player.copyWith(
    id: '${player.id}+${memory.version}',
    retrievalMemory: memory,
  );
}
