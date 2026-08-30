import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Which channel pins predicted success at a dry slot, and whether it should.
///
/// Two of the scheduler's three levers are inert for these learners. Guidance
/// does not move overall predicted success at all - the same 0.30 at every rung
/// - and the whole tempo ladder from sixty down to forty moves it by 0.035. So
/// the defect is upstream of admission.
///
/// `overallP` is `materialAvailableP * executionP`, so exactly one of those can
/// be responsible, and cueing is supposed to raise the first. The matrix says
/// which moves and which does not.
///
/// Then the calibration read, because a pessimistic prediction is only a defect
/// if it is wrong: what the synthetic player actually does when asked for the
/// same work.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '40')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('examples', defaultsTo: '2')
    ..addOption('archetype', defaultsTo: 'true_beginner');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final exampleLimit = int.parse(options.option('examples')!);
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

  var shown = 0;
  // Calibration, pooled across every dry state: what the model expected of the
  // gentlest work, and what the player did when actually asked for it.
  final predicted = <double>[];
  final started = <double>[];
  final completed = <double>[];
  final motor = <double>[];

  for (var seed = 0; seed < seeds; seed++) {
    final found = _dryStateFor(
      player: player,
      seed: seed,
      slots: slots,
      materials: narrow,
      pipeline: pipeline,
    );
    if (found == null) continue;
    final (state, gentlest, at) = found;

    if (shown < exampleLimit) {
      shown++;
      stdout
        ..writeln(
          '  seed $seed: ${gentlest.material.materialId} '
          '${gentlest.conditions.hands.id} '
          '${gentlest.conditions.octaves}oct\n',
        )
        ..writeln(
          '    ${'tempo'.padLeft(6)}${'guidance'.padLeft(10)}'
          '${'available'.padLeft(11)}${'execution'.padLeft(11)}'
          '${'topology'.padLeft(10)}${'overall'.padLeft(9)}',
        );
      for (final (tempoBpm, guidance) in [
        (60.0, GuidanceContext.unguided),
        (60.0, GuidanceContext.notesPreviewedOnly),
        (60.0, GuidanceContext.continuouslyCued),
        (52.0, GuidanceContext.continuouslyCued),
        (44.0, GuidanceContext.continuouslyCued),
        (40.0, GuidanceContext.continuouslyCued),
      ]) {
        final variant = Exercise.linear(
          material: gentlest.material,
          hands: gentlest.conditions.hands,
          octaves: gentlest.conditions.octaves,
          direction: gentlest.conditions.direction,
          tempoBpm: tempoBpm,
          guidance: guidance,
        );
        final p = learner.predict(state, variant, at: at);
        stdout.writeln(
          '    ${tempoBpm.toStringAsFixed(0).padLeft(6)}'
          '${'g=${guidance.independence}'.padLeft(10)}'
          '${p.materialAvailableP.toStringAsFixed(3).padLeft(11)}'
          '${p.executionP.toStringAsFixed(3).padLeft(11)}'
          '${p.topologyP.toStringAsFixed(3).padLeft(10)}'
          '${p.overallP.toStringAsFixed(3).padLeft(9)}',
        );
      }
      stdout.writeln();
    }

    // Ask the player for the gentlest work forty times and see what happens.
    final rng = PythonCompatibleRandom(seed);
    final playing = player.begin();
    final floor = Exercise.linear(
      material: gentlest.material,
      hands: gentlest.conditions.hands,
      octaves: gentlest.conditions.octaves,
      direction: gentlest.conditions.direction,
      tempoBpm: 40,
      guidance: GuidanceContext.continuouslyCued,
    );
    predicted.add(learner.predict(state, floor, at: at).overallP);
    for (var i = 0; i < 40; i++) {
      final outcome = playing.play(floor, rng);
      started.add(outcome.started ? 1 : 0);
      completed.add(outcome.completed ? 1 : 0);
      motor.add(outcome.motorScore);
    }
  }

  String mean(List<double> values) => values.isEmpty
      ? '-'
      : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(3);

  stdout
    ..writeln('calibration at the floor: fully cued, forty beats, one octave')
    ..writeln('  predicted overall   ${mean(predicted)}')
    ..writeln('  actually started    ${mean(started)}')
    ..writeln('  actually completed  ${mean(completed)}')
    ..writeln('  actual motor score  ${mean(motor)}');
}

(LearnerState, Exercise, DateTime)? _dryStateFor({
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
    final traces = pipeline.evaluate(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
    );
    final chosen = pipeline.chooseFrom(
      pipeline.selectable(traces, session),
      session,
    );

    if (chosen == null) {
      final eligible = [
        for (final trace in traces)
          if (trace.eligibility.tier == EligibilityTier.fullyEligible) trace,
      ]..sort((a, b) => b.prediction.overallP.compareTo(a.prediction.overallP));
      if (eligible.isEmpty) return null;
      return (state, eligible.first.exercise, at);
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
    session.recordSelection(
      exercise,
      retrievalObserved: exercise.guidance.isRetrievalObserved,
      retrievalFailed: outcome.retrieval == FactualRetrieval.failed,
      config: pipeline.config.diversity,
    );
  }
  return null;
}
