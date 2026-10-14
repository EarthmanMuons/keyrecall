import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

/// v1-14 and allocation at `k` of 2 with cohort players given
/// [RetrievalMemory], one configuration of learning strength, initial
/// half-life, and spacing responsiveness at a time.
///
/// Read a day after the last session starts and 21 days after that, the same
/// instants for both arms: the player's true retrievability of every material,
/// a held-out assessment from its own draws, and the scheduler's expectation of
/// the same questions. Readings never encode, so they cannot move the run.
///
/// Writes one JSON line per player, configuration, seed pair, and arm.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profiles', defaultsTo: '18,12,19,10,9,11')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption(
      'configs',
      help: 'learning:half-life:spacing, comma separated',
      defaultsTo:
          '1:60:0.5,0.5:15:0,0.5:15:1,0.5:240:0.5,2:15:0.5,2:240:0,2:240:1',
    )
    ..addOption('arms', defaultsTo: 'v1-14,alloc-2');
  final options = parser.parse(arguments);
  final assessment = standardAssessment(allPracticeMaterials);
  for (final index in options.option('profiles')!.split(',')) {
    final profile = PlausibilityCohort.profiles[int.parse(index)];
    for (final config in options.option('configs')!.split(',')) {
      final [learning, halfLife, spacing] = [
        for (final part in config.split(':')) double.parse(part),
      ];
      final player = profile.player.copyWith(
        id: '${profile.player.id}+${RetrievalMemory.version}',
        retrievalMemory: RetrievalMemory(
          initialHalfLifeDays: halfLife,
          retrievalGain: 0.6 * learning,
          previewGain: 0.3 * learning,
          cuedGain: 0.1 * learning,
          acquisitionGain: 0.1 * learning,
          spacingResponsiveness: spacing,
        ),
      );
      for (final pair in options.option('seeds')!.split(',')) {
        final [schedule, playerSeed] = [
          for (final part in pair.split(':')) int.parse(part),
        ];
        final sessions = demoSessions(
          from: demoHistoryStart,
          until: demoHistoryEnd,
          seed: schedule,
        );
        final end = sessions.last.start.add(const Duration(days: 1));
        for (final arm in options.option('arms')!.split(',')) {
          stderr.writeln('${player.id} $config $pair $arm');
          final allocator = arm == 'v1-14'
              ? null
              : RequirementAllocator(k: 2, protectionFloor: 0.6);
          late PracticeSession last;
          late PlayerState playing;
          final census = await runServiceCensus(
            player: player,
            sessions: sessions,
            playerSeed: playerSeed,
            intervention: allocator,
            onClose: (session, state, _) {
              last = session;
              playing = state;
            },
          );
          final records = census.records;
          final outcomes = [
            for (final r in records)
              if (r.closure.measurement case Measured(:final outcome)) outcome,
          ];
          stdout.writeln(
            jsonEncode({
              'player': player.id,
              'unit': profile.unit,
              'config': config,
              'seeds': pair,
              'arm': arm,
              'attempts': records.length,
              'starting': _retrievable(
                (m) =>
                    playing.player.materialFamiliarity[m] ??
                    playing.player.familiarity,
              ),
              'end': _reading(assessment, last, playing, end),
              'delayed': _reading(
                assessment,
                last,
                playing,
                end.add(const Duration(days: 21)),
              ),
              'outcomes': ServiceOutcomes.of(
                census,
                intervention: allocator,
              ).toJson(),
              for (final family in TechnicalMaterial.familyIds)
                'strands $family': summarizeStrands(records, family),
              'recovery attempts': records
                  .where(
                    (r) =>
                        r.decision?.challengeBypass == ChallengeBypass.recovery,
                  )
                  .length,
              'not started': outcomes.where((o) => !o.started).length,
            }),
          );
        }
      }
    }
  }
}

/// Expected materials retrievable, if each were asked once, by family.
Map<String, double> _retrievable(double Function(String materialId) of) => {
  'all': [
    for (final m in allPracticeMaterials) of(m.materialId),
  ].fold(0.0, (a, b) => a + b),
  for (final family in TechnicalMaterial.familyIds)
    family: [
      for (final m in allPracticeMaterials)
        if (m.familyId == family) of(m.materialId),
    ].fold(0.0, (a, b) => a + b),
};

Map<String, Object?> _reading(
  AssessmentSet assessment,
  PracticeSession session,
  PlayerState playing,
  DateTime at,
) {
  const learner = LearnerModel();
  final belief = session.state.copy();
  learner.propagate(belief, at);
  final reading = assess(assessment, playing, at: at, state: belief);
  Map<String, Object?> summary(AssessmentReading r) => {
    'held-out retrieval': r.retrieval,
    'held-out managed': r.managed,
    'estimated retrieval': r.predictedRetrieval,
  };
  return {
    'retrievable': _retrievable((m) => playing.familiarityAt(m, at)),
    'all': summary(reading),
    for (final MapEntry(:key, :value) in reading.families.entries)
      key: summary(value),
  };
}
