import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'python_compatible_random.dart';
import 'synthetic_player.dart';
import 'trajectory.dart';

/// Runs [player] through a sitting against the real pipeline.
///
/// Deterministic in every part: the same player, seed, length and catalog
/// produce the same trajectory and therefore the same detector findings, so a
/// pathological seed is a fixture rather than an anecdote.
///
/// The learner model and scheduler are the production ones. Only the person is
/// synthetic, which is what makes a finding here a finding about KeyRecall.
Trajectory runTrajectory({
  required SyntheticPlayer player,
  required int seed,
  required List<TechnicalMaterial> materials,
  int slots = 50,
  DateTime? start,
  double minutesPerSlot = 1.0,
  SchedulerPipeline pipeline = const SchedulerPipeline(learner: LearnerModel()),
  InstrumentProfile? instrument,
  List<Exercise>? generated,
}) {
  final rng = PythonCompatibleRandom(seed);
  final at0 = start ?? DateTime.utc(2026);
  final learner = pipeline.learner;
  final state = learner.placementState(player.placement, at: at0);
  final playing = player.begin();
  final session = SessionState();
  // Generation is learner-blind, so the same catalog and instrument give the
  // same candidates for every seed. A sweep passes one set in rather than
  // rebuilding it eight hundred times.
  final candidates =
      generated ??
      generateCandidates(instrument ?? InstrumentProfile(), materials);

  final recorded = <TrajectorySlot>[];
  for (var index = 0; index < slots; index++) {
    final at = at0.add(
      Duration(seconds: (index * minutesPerSlot * 60).round()),
    );
    learner.propagate(state, at);

    final selection = pipeline.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
    );
    final traces = selection.traces;
    final available = selection.selectable;
    final chosen = selection.selected;
    if (chosen == null) break;

    final exercise = chosen.exercise;
    final residual =
        state.materialExecution[(
          exercise.material.materialId,
          exercise.conditions.hands,
        )];
    final frontierBefore = {...?residual?.demonstratedTempoByOctaves};
    final pacedBefore = residual?.pacedTempoBpm ?? 0;

    final outcome = playing.play(exercise, rng);
    // Both read from every trace rather than from what survived the
    // repetition guard, and both keep the material, because a latency that
    // does not correlate readiness, offer and selection on one scale measures
    // nothing. Two stages, two sets: stage 2a says the learner qualifies,
    // stage 3 says the slot could actually have presented it.
    final ready = {
      for (final trace in traces)
        if (trace.exercise.conditions.hands == HandConfiguration.together &&
            trace.eligibility.tier == EligibilityTier.fullyEligible)
          trace.exercise.material.materialId,
    };
    final offered = {
      for (final trace in traces)
        if (trace.exercise.conditions.hands == HandConfiguration.together &&
            trace.eligibility.tier == EligibilityTier.fullyEligible &&
            trace.challengeSurvived)
          trace.exercise.material.materialId,
    };

    recorded.add(
      TrajectorySlot(
        index: index,
        at: at,
        chosen: exercise,
        winner: chosen,
        // Ranked, and not the winner. What a slot was chosen over is the
        // question every detector actually asks.
        alternatives: [
          for (final trace in available)
            if (!identical(trace, chosen)) trace,
        ]..sort((a, b) => b.rankKey!.compareTo(a.rankKey!)),
        performedTempoBpm: playing.performedTempoFor(exercise),
        outcome: outcome,
        frontierBefore: frontierBefore,
        pacedBefore: pacedBefore,
        transferableBefore: transferableTempoFor(
          state,
          exercise.conditions.hands,
          exercise.conditions.octaves,
        ),
        handsTogetherReady: ready,
        handsTogetherOffered: offered,
      ),
    );

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

  return Trajectory(playerId: player.id, seed: seed, slots: recorded);
}
