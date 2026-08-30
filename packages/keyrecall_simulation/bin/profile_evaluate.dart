import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What one candidate costs, broken down.
///
/// The sweep spends almost all of its time in `evaluate`, and so does the app,
/// which makes one of these decisions while somebody waits.
void main(List<String> arguments) {
  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final at0 = DateTime.utc(2026);

  // A state part-way through a sitting, so the frontier and memory paths are
  // populated rather than trivially empty.
  final player = PlayerArchetypes.advanced;
  final state = learner.placementState(player.placement, at: at0);
  final playing = player.begin();
  final session = SessionState();
  final rng = PythonCompatibleRandom(0);
  final candidates = generateCandidates(InstrumentProfile(), allScales);
  for (var i = 0; i < 25; i++) {
    final at = at0.add(Duration(seconds: i * 60));
    learner.propagate(state, at);
    final chosen = pipeline.chooseFrom(
      pipeline.selectable(
        pipeline.evaluate(
          state: state,
          session: session,
          candidates: candidates,
          at: at,
        ),
        session,
      ),
      session,
    );
    if (chosen == null) break;
    final outcome = playing.play(chosen.exercise, rng);
    learner.applyOutcome(
      state: state,
      exercise: chosen.exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(chosen.exercise, outcome),
      prediction: learner.predict(state, chosen.exercise, at: at),
      at: at,
    );
  }

  final at = at0.add(const Duration(seconds: 1500));
  learner.propagate(state, at);

  void measure(String label, int reps, void Function() body) {
    final timer = Stopwatch()..start();
    for (var i = 0; i < reps; i++) {
      body();
    }
    timer.stop();
    stdout.writeln(
      '  ${label.padRight(26)}'
      '${(timer.elapsedMicroseconds / reps).toStringAsFixed(1).padLeft(10)} us',
    );
  }

  stdout.writeln('candidates generated: ${candidates.length}');
  measure('generateCandidates', 5, () {
    generateCandidates(InstrumentProfile(), allScales);
  });
  measure('withExecutionNeighbours', 20, () {
    withExecutionNeighbours(state, candidates);
  });
  measure('evaluate (whole slot)', 20, () {
    pipeline.evaluate(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
    );
  });

  final refined = withExecutionNeighbours(state, candidates);
  stdout.writeln('candidates after refinement: ${refined.length}');
  stdout.writeln('\nper candidate:');

  void perCandidate(String label, void Function(Exercise) body) {
    final timer = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      for (final exercise in refined) {
        body(exercise);
      }
    }
    timer.stop();
    stdout.writeln(
      '  ${label.padRight(26)}'
      '${(timer.elapsedMicroseconds / (20 * refined.length)).toStringAsFixed(3).padLeft(10)} us',
    );
  }

  perCandidate('eligibilityFor', (e) => pipeline.eligibilityFor(state, e));
  perCandidate('predict', (e) => learner.predict(state, e, at: at));
  perCandidate('information', (e) => information(state, e, learner.params));
  perCandidate('realizationRankFor', (e) => realizationRankFor(state, e));
  perCandidate('admissionBandOf', (e) => admissionBandOf(e.material));
  perCandidate('structuralQ', (e) => e.structuralQ);
}
