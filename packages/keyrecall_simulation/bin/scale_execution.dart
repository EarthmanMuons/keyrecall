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

/// Where v1-14 and allocation at `k` of 2, with or without [ContextRelief],
/// spend a run's slots and what execution each leaves, for one cohort player
/// under [RetrievalMemory] or the frozen familiarity model.
///
/// Counts decisions by family, selection stage, and purpose; attempts by
/// family, hands, and guidance; strands introduced and managed by hands and
/// by which third of the run first reached them; allocation's interventions by
/// strand; and what dose held back. Reads coverage and missed runs, and
/// held-out managed play by family and hands and retrieval by family, 21 days
/// after the day following the last session.
///
/// Writes one JSON line per configuration, seed pair, and arm.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profile', defaultsTo: '19')
    ..addOption('seeds', defaultsTo: '4:104')
    ..addOption(
      'configs',
      help: 'learning:half-life:spacing, or frozen, comma separated',
      defaultsTo: '1:60:0.5',
    )
    ..addOption(
      'arms',
      help: 'v1-14, alloc-2, or relief:trigger:budget:window, comma separated',
      defaultsTo: 'v1-14,alloc-2',
    );
  final options = parser.parse(arguments);
  final profile =
      PlausibilityCohort.profiles[int.parse(options.option('profile')!)];
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
      final delayed = sessions.last.start.add(const Duration(days: 22));
      for (final arm in options.option('arms')!.split(',')) {
        stderr.writeln('${player.id} $config $pair $arm');
        late PlayerState playing;
        final allocator = _allocatorFor(arm);
        final probe = _DoseProbe(allocator);
        final census = await runServiceCensus(
          player: player,
          sessions: sessions,
          playerSeed: playerSeed,
          intervention: probe,
          onClose: (_, state, _) => playing = state,
        );
        stdout.writeln(
          jsonEncode({
            'player': player.id,
            'config': config,
            'seeds': pair,
            'arm': arm,
            'decisions': _tally([
              for (final d in census.decisions)
                '${d.familyId} ${d.stage} ${d.purpose}',
            ]),
            'attempts': _tally([
              for (final r in census.records)
                '${r.exercise.material.familyId} '
                    '${_contextName(executionContextOf(r.exercise))} '
                    'independence ${r.exercise.guidance.independence}',
            ]),
            'strands': _strands(census.records),
            'busiest strands': _busiest(census.records),
            'interventions': _interventions(census),
            'dose': probe.summary,
            'outcomes': ServiceOutcomes.of(
              census,
              intervention: allocator,
            ).toJson(),
            'allocation': ?allocator?.diagnostics,
            'held-out retrieval': {
              for (final MapEntry(:key, :value) in assess(
                standardAssessment(allPracticeMaterials),
                playing,
                at: delayed,
              ).families.entries)
                key: value.retrieval,
            },
            'held-out managed': _heldOut(playing, delayed),
          }),
        );
      }
    }
  }
}

RequirementAllocator? _allocatorFor(String arm) {
  if (arm == 'v1-14') return null;
  if (arm == 'alloc-2') return RequirementAllocator(k: 2, protectionFloor: 0.6);
  final [name, trigger, budget, window] = arm.split(':');
  if (name != 'relief') throw ArgumentError.value(arm, 'arm');
  return RequirementAllocator(
    k: 2,
    protectionFloor: 0.6,
    relief: ContextRelief(
      trigger: int.parse(trigger),
      budget: int.parse(budget),
      window: int.parse(window),
    ),
  );
}

SyntheticPlayer _withMemory(SyntheticPlayer player, String config) {
  final [learning, halfLife, spacing] = [
    for (final part in config.split(':')) double.parse(part),
  ];
  return player.copyWith(
    id: '${player.id}+${RetrievalMemory.version}',
    retrievalMemory: RetrievalMemory(
      initialHalfLifeDays: halfLife,
      retrievalGain: 0.6 * learning,
      previewGain: 0.3 * learning,
      cuedGain: 0.1 * learning,
      acquisitionGain: 0.1 * learning,
      spacingResponsiveness: spacing,
    ),
  );
}

/// Passes [inner]'s choices through unchanged, or ranking's when there is
/// none, and records what dose did at every decision.
class _DoseProbe implements ServiceIntervention {
  final ServiceIntervention? inner;
  final _contracted = <String, int>{};
  final _held = <String, int>{};
  var _decisions = 0;

  _DoseProbe(this.inner);

  Map<String, Object?> get summary => {
    'decisions': _decisions,
    'contracted': _contracted,
    'held from a ranked, fully eligible candidate': _held,
  };

  @override
  List<ServiceSubstitution> get substitutions => inner?.substitutions ?? [];

  @override
  Map<String, num> get diagnostics => inner?.diagnostics ?? {};

  @override
  void settle(AttemptJournal journal, LearnerModel learner, int decision) =>
      inner?.settle(journal, learner, decision);

  @override
  void record(List<RequirementObservation> observations) =>
      inner?.record(observations);

  @override
  CandidateSelected? intervene({
    required int decision,
    required SelectionResult result,
    required List<RequirementState> requirements,
    required SchedulerPipeline pipeline,
    required LearnerState state,
    required SessionState session,
    required DateTime at,
    required int journalLength,
  }) {
    _decisions++;
    for (final family in result.dose.contracted.keys) {
      _contracted[family] = (_contracted[family] ?? 0) + 1;
    }
    final kept = result.dose.selectable.toSet();
    final held = {
      for (final trace in result.pacing.selectable)
        if (!kept.contains(trace) &&
            trace.eligibility.tier == EligibilityTier.fullyEligible)
          '${trace.exercise.material.familyId} '
              '${_contextName(executionContextOf(trace.exercise))}',
    };
    for (final key in held) {
      _held[key] = (_held[key] ?? 0) + 1;
    }
    return inner?.intervene(
      decision: decision,
      result: result,
      requirements: requirements,
      pipeline: pipeline,
      state: state,
      session: session,
      at: at,
      journalLength: journalLength,
    );
  }
}

Map<String, int> _tally(Iterable<String> keys) {
  final counts = <String, int>{};
  for (final key in keys) {
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return Map.fromEntries(
    counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

String _contextName(ExecutionContext context) {
  final (_, hands, motion) = context;
  return hands == HandConfiguration.together
      ? '${hands.id} ${motion.id}'
      : hands.id;
}

Map<String, Object?> _strands(List<AttemptRecord> records) {
  const learner = LearnerModel();
  final introduced = <ExecutionContext, int>{};
  final managed = <ExecutionContext, int>{};
  for (final (index, record) in records.indexed) {
    final strand = executionContextOf(record.exercise);
    introduced.putIfAbsent(strand, () => index);
    if (record.closure.measurement case Measured(
      :final outcome,
    ) when learner.executionWasManaged(outcome)) {
      managed.putIfAbsent(strand, () => index);
    }
  }
  List<String> keys(Map<ExecutionContext, int> first) => [
    for (final MapEntry(key: strand, value: index) in first.entries)
      '${_familyOf[strand.$1]} ${_contextName(strand)} '
          'third ${1 + 3 * index ~/ records.length}',
  ];
  return {
    'introduced': _tally(keys(introduced)),
    'managed': _tally(keys(managed)),
  };
}

/// The ten strands with the most attempts: how many, how many were managed,
/// and the mean motor score of those that carried one.
List<Map<String, Object?>> _busiest(List<AttemptRecord> records) {
  const learner = LearnerModel();
  final attempts = <ExecutionContext, int>{};
  final managed = <ExecutionContext, int>{};
  final motor = <ExecutionContext, List<double>>{};
  for (final record in records) {
    final strand = executionContextOf(record.exercise);
    attempts[strand] = (attempts[strand] ?? 0) + 1;
    if (record.closure.measurement case Measured(:final outcome)) {
      if (learner.executionWasManaged(outcome)) {
        managed[strand] = (managed[strand] ?? 0) + 1;
      }
      if (outcome.motorScore case final score?) {
        (motor[strand] ??= []).add(score);
      }
    }
  }
  final ranked = attempts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final MapEntry(key: strand, value: count) in ranked.take(10))
      {
        'strand': '${strand.$1} ${_contextName(strand)}',
        'attempts': count,
        'managed': managed[strand] ?? 0,
        'mean motor': switch (motor[strand]) {
          final scores? => scores.reduce((a, b) => a + b) / scores.length,
          null => null,
        },
      },
  ];
}

/// Allocation's interventions by strand, family, and whether the hands play
/// together.
///
/// A strand is newly managed when it had no managed attempt before its first
/// intervention and has one by the end, so interventions per newly managed
/// strand counts every intervention in a group against the strands it moved.
Map<String, Object?> _interventions(ServiceCensus census) {
  const learner = LearnerModel();
  final selected = [
    for (final d in census.decisions)
      if (d.stage != 'acquisition' && d.stage != 'blocked') d,
  ];
  if (selected.length != census.records.length) {
    throw StateError(
      '${selected.length} selections for ${census.records.length} attempts',
    );
  }
  final interventions = <ExecutionContext, int>{};
  final whileUnmanaged = <ExecutionContext, int>{};
  final managedBefore = <ExecutionContext>{};
  final managed = <ExecutionContext>{};
  for (final (index, record) in census.records.indexed) {
    final decision = selected[index];
    if (decision.materialId != record.exercise.material.materialId) {
      throw StateError('decision ${decision.decision} is not its attempt');
    }
    final strand = executionContextOf(record.exercise);
    if (decision.stage == 'intervened') {
      if (!interventions.containsKey(strand) && managed.contains(strand)) {
        managedBefore.add(strand);
      }
      interventions[strand] = (interventions[strand] ?? 0) + 1;
      if (!managed.contains(strand)) {
        whileUnmanaged[strand] = (whileUnmanaged[strand] ?? 0) + 1;
      }
    }
    if (record.closure.measurement case Measured(
      :final outcome,
    ) when learner.executionWasManaged(outcome)) {
      managed.add(strand);
    }
  }
  String group(ExecutionContext strand) =>
      '${_familyOf[strand.$1]} '
      '${strand.$2 == HandConfiguration.together ? 'together' : 'single'}';
  final groups = <String, List<ExecutionContext>>{};
  for (final strand in interventions.keys) {
    (groups[group(strand)] ??= []).add(strand);
  }
  final total = interventions.values.fold(0, (a, b) => a + b);
  final ranked = interventions.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {
    'total': total,
    'top three share': total == 0
        ? null
        : ranked.take(3).fold(0, (a, e) => a + e.value) / total,
    'strands with 20 or more and never managed': [
      for (final MapEntry(key: strand, value: count) in ranked)
        if (count >= 20 && !managed.contains(strand)) strand,
    ].length,
    'groups': {
      for (final MapEntry(key: name, value: strands) in groups.entries)
        name: () {
          final count = strands.fold(0, (a, s) => a + interventions[s]!);
          final newly = strands
              .where((s) => !managedBefore.contains(s) && managed.contains(s))
              .length;
          return {
            'interventions': count,
            'while unmanaged': strands.fold(
              0,
              (a, s) => a + (whileUnmanaged[s] ?? 0),
            ),
            'strands': strands.length,
            'newly managed': newly,
            'per newly managed': newly == 0 ? null : count / newly,
          };
        }(),
    },
    'busiest': [
      for (final MapEntry(key: strand, value: count) in ranked.take(5))
        {
          'strand': '${strand.$1} ${_contextName(strand)}',
          'interventions': count,
          'while unmanaged': whileUnmanaged[strand] ?? 0,
          'managed': managed.contains(strand),
        },
    ],
  };
}

final _familyOf = {
  for (final m in allPracticeMaterials) m.materialId: m.familyId,
};

Map<String, double> _heldOut(PlayerState playing, DateTime at) {
  final standard = standardAssessment(allPracticeMaterials);
  return {
    for (final family in TechnicalMaterial.familyIds)
      for (final hands in HandConfiguration.values)
        '$family ${hands.id}': assess(
          AssessmentSet(
            id: '${standard.id} $family ${hands.id}',
            seed: standard.seed,
            repetitions: standard.repetitions,
            exercises: [
              for (final e in standard.exercises)
                if (e.material.familyId == family &&
                    e.conditions.hands == hands)
                  e,
            ],
          ),
          playing,
          at: at,
        ).managed,
  };
}
