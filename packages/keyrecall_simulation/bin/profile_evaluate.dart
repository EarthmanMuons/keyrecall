import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Where a decision spends its time, and how much of that work repeats.
///
/// Two questions, because they call for different fixes. Elapsed time per
/// stage says which stage to look at; the number of distinct inputs a stage is
/// called with says whether the answer is a cache rather than a faster
/// implementation. A stage called nine thousand times on twelve hundred
/// distinct inputs is doing eight thousand redundant evaluations, and no
/// amount of tightening the inner loop recovers that.
///
/// Stages are timed by calling them over the same candidate set rather than by
/// sampling inside [SchedulerPipeline.evaluate], so the totals will not add up
/// to it exactly: the pipeline's own caching means it does less than this does.
/// That gap is itself the measurement.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('archetype', defaultsTo: 'developing')
    ..addOption('warmup', defaultsTo: '30')
    ..addOption('slot', defaultsTo: '20')
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final slot = int.parse(options.option('slot')!);
  final warmup = int.parse(options.option('warmup')!);

  const model = LearnerModel();
  const pipeline = SchedulerPipeline(learner: model);
  final player = playerOf(options.option('archetype')!);

  // A state partway through a real sitting, so the frontiers, memory and
  // residuals a decision reads are populated the way they are in practice.
  final state = _stateAfter(player, slot, pipeline);
  final session = SessionState();
  final at = DateTime.utc(2026).add(Duration(minutes: slot));
  final generated = generateCandidates(InstrumentProfile(), allScales);
  final candidates = withExecutionNeighbours(state, generated);

  stdout.writeln(
    'one decision for ${player.id} at slot $slot\n'
    '  generated  ${generated.length}\n'
    '  refined    ${candidates.length}\n',
  );

  double timed(String label, int repeats, void Function() body) {
    for (var i = 0; i < warmup; i++) {
      body();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < repeats; i++) {
      body();
    }
    final ms = watch.elapsedMicroseconds / 1000 / repeats;
    stdout.writeln('  ${label.padRight(28)}${ms.toStringAsFixed(2)} ms');
    return ms;
  }

  stdout.writeln('elapsed per decision');
  timed('evaluate (whole)', 20, () {
    pipeline.evaluate(
      state: state,
      session: session,
      candidates: generated,
      at: at,
    );
  });
  timed('withExecutionNeighbours', 20, () {
    withExecutionNeighbours(state, generated);
  });
  timed('eligibilityFor', 20, () {
    for (final exercise in candidates) {
      pipeline.eligibilityFor(state, exercise);
    }
  });
  timed('independentRetrievalP', 20, () {
    for (final exercise in candidates) {
      model.independentRetrievalProbability(state, exercise, at);
    }
  });
  timed('executionProbability', 20, () {
    for (final exercise in candidates) {
      model.executionProbability(state, exercise);
    }
  });
  timed('topologyProbability', 20, () {
    for (final exercise in candidates) {
      model.topologyProbability(state, exercise);
    }
  });
  timed('information', 20, () {
    for (final exercise in candidates) {
      information(state, exercise, model.params);
    }
  });
  timed('informationKeyFor', 20, () {
    for (final exercise in candidates) {
      informationKeyFor(exercise);
    }
  });
  timed('information (cached)', 20, () {
    final cache = <InformationKey, double>{};
    for (final exercise in candidates) {
      cache.putIfAbsent(
        informationKeyFor(exercise),
        () => information(state, exercise, model.params),
      );
    }
  });
  timed('structuralQ', 20, () {
    for (final exercise in candidates) {
      exercise.structuralQ;
    }
  });
  timed('realizationRankFor', 20, () {
    for (final exercise in candidates) {
      realizationRankFor(state, exercise);
    }
  });
  timed('realizationFitFor', 20, () {
    for (final exercise in candidates) {
      realizationFitFor(
        state,
        exercise,
        practiceEntryPolicy: const PracticeEntryPolicy.uniform(60),
      );
    }
  });
  timed('isCoordinationTransition', 20, () {
    for (final exercise in candidates) {
      isCoordinationTransition(state, exercise);
    }
  });
  timed('diversity', 20, () {
    for (final exercise in candidates) {
      diversity(exercise, session);
    }
  });

  stdout.writeln('\ndistinct inputs across ${candidates.length} candidates');
  void cardinality(String label, Set<Object?> values) {
    final share = (100 * values.length / candidates.length).toStringAsFixed(1);
    stdout.writeln(
      '  ${label.padRight(34)}${values.length.toString().padLeft(6)}'
      '  ($share% of candidates)',
    );
  }

  cardinality('exercise identity', candidates.toSet());
  cardinality('material id', {
    for (final e in candidates) e.material.materialId,
  });
  cardinality('execution context', {
    for (final e in candidates) executionContextOf(e),
  });
  cardinality('guidance-normalized realization', {
    for (final e in candidates) e.withGuidance(GuidanceContext.unguided),
  });
  cardinality('structuralQ', {
    for (final e in candidates) e.structuralQ.map((c) => c.id).join(','),
  });
  cardinality('information inputs', {
    for (final e in candidates)
      '${e.material.materialId}|${executionContextOf(e)}'
          '|${e.structuralQ.map((c) => c.id).join(',')}'
          '|${e.guidance.retrievalDemand}|${e.guidance.isRetrievalObserved}',
  });
  cardinality('eligibility inputs', {
    for (final e in candidates)
      '${e.material.materialId}|${e.conditions}|${e.guidance.independence}',
  });
}

/// Learner state after [slots] real decisions, so the profile reads a
/// populated state rather than a placement prior.
LearnerState _stateAfter(
  SyntheticPlayer player,
  int slots,
  SchedulerPipeline pipeline,
) {
  final trajectory = runTrajectory(
    player: player,
    seed: 0,
    materials: allScales,
    slots: slots,
    pipeline: pipeline,
  );
  final learner = pipeline.learner;
  final at0 = DateTime.utc(2026);
  final state = learner.placementState(player.placement, at: at0);
  final playing = player.begin();
  final rng = PythonCompatibleRandom(0);
  for (final slot in trajectory.slots) {
    learner.propagate(state, slot.at);
    final outcome = playing.play(slot.chosen, rng);
    learner.applyOutcome(
      state: state,
      exercise: slot.chosen,
      outcome: outcome,
      weights: evidenceWeightsFor(slot.chosen, outcome),
      prediction: learner.predict(state, slot.chosen, at: slot.at),
      at: slot.at,
    );
  }
  return state;
}
