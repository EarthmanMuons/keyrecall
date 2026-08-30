import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What slowing down would do for a learner the band has refused everything.
///
/// Candidate generation offers sixty, eighty, a hundred and a hundred and
/// twenty. The ladder beneath sixty - fifty eight down to forty - exists as an
/// adjacency relation and is never asked for, because the only things that
/// materialize a tempo off the generated set are derived from frontier
/// evidence a struggling learner does not have.
///
/// So at a dry slot the gentlest thing in existence is sixty, predicted at
/// about 0.30 against a floor of 0.60. This asks what the same exercise would
/// be predicted at on the rungs below, using the learner state those sittings
/// actually reached.
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
  final band = pipeline.config.challenge;
  final goal = PracticeGoal(
    id: 'FIVE_SCALES',
    targetMaterialIds: {
      for (final material in allScales.take(5)) material.materialId,
    },
  );
  final narrow = goal.scopeOf(allScales);
  final descent = [
    for (final rung in metronomeLadder)
      if (rung <= 60) rung,
  ]..sort((a, b) => b.compareTo(a));

  var dry = 0;
  var rescued = 0;
  final crossings = <double>[];
  final atForty = <double>[];
  final columns = {for (final rung in descent) rung: <double>[]};

  for (var seed = 0; seed < seeds; seed++) {
    final found = _dryStateFor(
      player: player,
      seed: seed,
      slots: slots,
      materials: narrow,
      pipeline: pipeline,
    );
    if (found == null) continue;
    dry++;

    // The gentlest fully eligible realization the slot had, slowed down.
    final gentlest = found.$2;
    double? crossedAt;
    for (final rung in descent) {
      final slower = gentlest.atTempo(rung);
      final p = learner.predict(found.$1, slower, at: found.$3).overallP;
      columns[rung]!.add(p);
      if (crossedAt == null && p >= band.pMin) crossedAt = rung;
      if (rung == descent.last) atForty.add(p);
    }
    if (crossedAt != null) {
      rescued++;
      crossings.add(crossedAt);
    }
  }

  String mean(List<double> values) => values.isEmpty
      ? '-'
      : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(3);

  stdout
    ..writeln('${player.id}: $dry dry sittings of $seeds')
    ..writeln('band floor ${band.pMin}\n')
    ..writeln('predicted success on the gentlest eligible exercise, slowed:');
  for (final rung in descent) {
    final values = columns[rung]!;
    final crossed = values.where((p) => p >= band.pMin).length;
    stdout.writeln(
      '  ${rung.toStringAsFixed(0).padLeft(3)} bpm   mean p '
      '${mean(values)}   in band ${crossed.toString().padLeft(3)} of $dry',
    );
  }

  stdout
    ..writeln()
    ..writeln(
      '  rescued before reaching forty   '
      '${rescued.toString().padLeft(3)} of $dry',
    )
    ..writeln(
      '  still below band at forty       '
      '${(dry - rescued).toString().padLeft(3)} of $dry',
    );
  if (crossings.isNotEmpty) {
    final ordered = [...crossings]..sort();
    stdout.writeln(
      '  first rung inside the band: median '
      '${ordered[ordered.length ~/ 2].toStringAsFixed(0)} bpm, '
      'slowest ${ordered.first.toStringAsFixed(0)} bpm',
    );
  }
}

/// The learner state, gentlest fully eligible exercise, and instant at the
/// slot that admitted nothing.
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
