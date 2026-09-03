import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What the scheduler had left at the slot that admitted nothing.
///
/// `runTrajectory` stops at that slot without recording it, which is exactly
/// the slot worth reading: the interesting question is not which materials were
/// selected before it but which states they were all in when nothing qualified.
///
/// Split by whether the same seed oscillated over the wide catalog, because
/// the overlap between oscillating and drying is at chance - thirty one of
/// forty do each, twenty three do both, against twenty four expected if they
/// were independent. So a shared cause has to be shown in the terminal state
/// rather than inferred from the two happening together.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '40')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('archetype', defaultsTo: 'true_beginner');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('archetype'),
  );

  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final goal = PracticeGoal(
    id: 'FIVE_SCALES',
    targetMaterialIds: {
      for (final material in allScales.take(5)) material.materialId,
    },
  );
  final narrow = goal.scopeOf(allScales);

  const conditions = [
    'no material established',
    'every material encountered',
    'recovery active',
    'introducible candidates remain',
    'full-cue candidates generated',
    'full-cue candidates all refused',
  ];

  final tallies = {
    for (final group in ['both', 'dries only'])
      group: {for (final condition in conditions) condition: 0},
  };
  final counts = {'both': 0, 'dries only': 0};
  final examples = <String, String>{};

  for (var seed = 0; seed < seeds; seed++) {
    final oscillates = clusterKindsIn(
      runTrajectory(
        player: player,
        seed: seed,
        materials: allScales,
        slots: slots,
      ),
    ).contains(ClusterKind.oscillatingSupport);

    final census = _dryCensus(
      player: player,
      seed: seed,
      slots: slots,
      materials: narrow,
      pipeline: pipeline,
    );
    if (census == null) continue;

    final group = oscillates ? 'both' : 'dries only';
    counts[group] = counts[group]! + 1;
    for (final condition in conditions) {
      if (census.flags.contains(condition)) {
        tallies[group]![condition] = tallies[group]![condition]! + 1;
      }
    }
    examples.putIfAbsent(group, () => census.detail);
  }

  stdout
    ..writeln(
      '${player.id}: $seeds seeds, scoped to ${narrow.length} '
      'materials\n',
    )
    ..writeln(
      '${'terminal condition'.padRight(36)}'
      '${'both'.padLeft(8)}${'dries only'.padLeft(12)}',
    );
  for (final condition in conditions) {
    stdout.writeln(
      '${condition.padRight(36)}'
      '${tallies['both']![condition].toString().padLeft(8)}'
      '${tallies['dries only']![condition].toString().padLeft(12)}',
    );
  }
  stdout.writeln(
    '${'runs'.padRight(36)}${counts['both'].toString().padLeft(8)}'
    '${counts['dries only'].toString().padLeft(12)}',
  );

  for (final group in ['both', 'dries only']) {
    final detail = examples[group];
    if (detail != null) stdout.writeln('\n--- $group\n$detail');
  }
}

class _Census {
  final Set<String> flags;
  final String detail;

  const _Census(this.flags, this.detail);
}

/// Runs one scoped sitting and describes the slot that admitted nothing.
_Census? _dryCensus({
  required SyntheticPlayer player,
  required int seed,
  required int slots,
  required List<TechnicalMaterial> materials,
  required SchedulerPipeline pipeline,
}) {
  final learner = pipeline.learner;
  final rng = PythonCompatibleRandom(seed);
  final at0 = DateTime.utc(2026);
  final state = learner.placementState(player.placement, at: at0);
  final playing = player.begin();
  final session = SessionState();
  final candidates = generateCandidates(InstrumentProfile(), materials);

  for (var index = 0; index < slots; index++) {
    final at = at0.add(Duration(seconds: index * 60));
    learner.propagate(state, at);
    final selection = pipeline.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
    );
    final traces = selection.traces;
    final available = selection.selectable;
    final chosen = switch (selection) {
      CandidateSelected(:final candidate) => candidate,
      SelectionBlocked() => null,
    };

    if (chosen == null) {
      final flags = <String>{};
      final established = [
        for (final material in materials)
          if (state.materialMemory[material.materialId]?.hasFactualRetrieval ??
              false)
            material.materialId,
      ];
      if (established.isEmpty) flags.add('no material established');
      if (materials.every(
        (m) => state.materialMemory.containsKey(m.materialId),
      )) {
        flags.add('every material encountered');
      }
      if (session.lastFailedExercise != null) flags.add('recovery active');

      final introducible = traces.where(
        (trace) => pipeline.isIntroduction(state, trace.exercise),
      );
      if (introducible.isNotEmpty) flags.add('introducible candidates remain');

      final fullyCued = traces.where(
        (trace) => trace.exercise.guidance.independence == 0,
      );
      if (fullyCued.isNotEmpty) flags.add('full-cue candidates generated');
      if (fullyCued.isNotEmpty &&
          fullyCued.every((trace) => !trace.challengeSurvived)) {
        flags.add('full-cue candidates all refused');
      }

      final reasons = <String, int>{};
      for (final trace in traces) {
        final why = !trace.safety.isAllowed
            ? 'stage 2b safety'
            : !trace.challengeSurvived
            ? 'stage 3 ${trace.eligibility.tier.id}/'
                  '${trace.eligibility.code.id}'
            : 'survived but unselectable';
        reasons[why] = (reasons[why] ?? 0) + 1;
      }
      final ordered = reasons.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return _Census(
        flags,
        [
          '  seed $seed, dry at slot $index, '
              '${traces.length} candidates, '
              '${available.length} selectable',
          '  established: ${established.isEmpty ? 'none' : established.join(', ')}',
          '  recovery target: ${session.lastFailedExercise ?? 'none'}',
          '  why candidates died:',
          for (final entry in ordered.take(6))
            '    ${entry.value.toString().padLeft(5)}  ${entry.key}',
        ].join('\n'),
      );
    }

    final exercise = chosen.exercise;
    final outcome = playing.play(exercise, rng);
    learner.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: learner.predict(state, exercise, at: at),
      at: at,
    );
    pipeline.recordOutcome(session, exercise, outcome);
  }
  return null;
}
