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
  void Function(int slot, List<CandidateTrace> traces)? observeTraces,
  void Function(int slot, LearnerState state)? observeState,
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
  TerminalTrajectorySlot? terminal;
  for (var index = 0; index < slots; index++) {
    final at = at0.add(
      Duration(seconds: (index * minutesPerSlot * 60).round()),
    );
    learner.propagate(state, at);
    // Read what is needed immediately: this is the live state, and the slot
    // below moves it.
    observeState?.call(index, state);

    final selection = pipeline.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
    );
    final traces = selection.traces;
    final available = selection.selectable;
    final chosen = selection.selected;
    // Every candidate, which a slot does not retain: a sitting evaluates
    // thousands and only the selectable ones are worth carrying to the end.
    // A diagnostic asking what was refused has to see them as they go past.
    observeTraces?.call(index, traces);
    if (chosen == null) {
      terminal = TerminalTrajectorySlot(
        index: index,
        at: at,
        traces: traces,
        selectable: available,
        candidates: _candidateCounts(candidates.length, traces, available),
      );
      break;
    }

    final exercise = chosen.exercise;
    final residual = state.materialExecution[executionContextOf(exercise)];
    final frontierBefore = {...?residual?.demonstratedTempoByOctaves};
    final pacedBefore = residual?.pacedTempoBpm ?? 0;
    final transferableBefore = transferableTempoFor(
      state,
      exercise.conditions.hands,
      exercise.conditions.octaves,
    );

    final outcome = playing.play(exercise, rng);
    final handsTogetherTraces = traces.where(
      (trace) => trace.exercise.conditions.hands == HandConfiguration.together,
    );
    final handsTogetherSelectable = available.where(
      (trace) => trace.exercise.conditions.hands == HandConfiguration.together,
    );
    final handsTogether = HandsTogetherStages(
      prerequisiteSatisfied: {
        for (final trace in handsTogetherTraces)
          if (trace.handsTogetherPrerequisiteSatisfied == true)
            trace.exercise.material.materialId,
      },
      eligible: {
        for (final trace in handsTogetherTraces)
          if (trace.eligibility.tier == EligibilityTier.fullyEligible)
            trace.exercise.material.materialId,
      },
      admitted: {
        for (final trace in handsTogetherTraces)
          if (trace.isRanked) trace.exercise.material.materialId,
      },
      selectable: {
        for (final trace in handsTogetherSelectable)
          trace.exercise.material.materialId,
      },
      diagnostics: _handsTogetherDiagnostics(
        state,
        handsTogetherTraces,
        handsTogetherSelectable,
      ),
    );
    final candidateCounts = _candidateCounts(
      candidates.length,
      traces,
      available,
    );

    learner.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: learner.predict(state, exercise, at: at),
      at: at,
    );
    final frontierAfter = {
      ...?state
          .materialExecution[executionContextOf(exercise)]
          ?.demonstratedTempoByOctaves,
    };
    recorded.add(
      TrajectorySlot(
        index: index,
        at: at,
        chosen: exercise,
        winner: chosen,
        alternatives: [
          for (final trace in available)
            if (!identical(trace, chosen)) trace,
        ]..sort((a, b) => b.rankKey!.compareTo(a.rankKey!)),
        performedTempoBpm: playing.performedTempoFor(exercise),
        outcome: outcome,
        managedExecution: learner.executionWasManaged(outcome),
        frontierBefore: frontierBefore,
        frontierAfter: frontierAfter,
        pacedBefore: pacedBefore,
        transferableBefore: transferableBefore,
        candidates: candidateCounts,
        handsTogether: handsTogether,
      ),
    );
    pipeline.recordOutcome(session, exercise, outcome);
  }

  return Trajectory(
    playerId: player.id,
    seed: seed,
    slots: recorded,
    terminal: terminal,
  );
}

CandidateStageCounts _candidateCounts(
  int generated,
  List<CandidateTrace> traces,
  List<CandidateTrace> selectable,
) => CandidateStageCounts(
  generated: generated,
  evaluated: traces.length,
  eligible: traces
      .where((trace) => trace.eligibility.tier == EligibilityTier.fullyEligible)
      .length,
  admitted: traces.where((trace) => trace.isRanked).length,
  selectable: selectable.length,
);

Map<String, HandsTogetherDiagnostic> _handsTogetherDiagnostics(
  LearnerState state,
  Iterable<CandidateTrace> traces,
  Iterable<CandidateTrace> selectable,
) {
  final byMaterial = <String, List<CandidateTrace>>{};
  for (final trace in traces) {
    (byMaterial[trace.exercise.material.materialId] ??= []).add(trace);
  }
  final selectableCounts = <String, int>{};
  for (final trace in selectable) {
    final id = trace.exercise.material.materialId;
    selectableCounts[id] = (selectableCounts[id] ?? 0) + 1;
  }
  return {
    for (final entry in byMaterial.entries)
      entry.key: _handsTogetherDiagnostic(
        state,
        entry.value,
        selectableCounts[entry.key] ?? 0,
        state.materialMemory[entry.key]?.hasFactualRetrieval == true,
      ),
  };
}

HandsTogetherDiagnostic _handsTogetherDiagnostic(
  LearnerState state,
  List<CandidateTrace> traces,
  int selectable,
  bool hasFactualRetrieval,
) {
  final probabilities = [for (final trace in traces) trace.prediction.overallP]
    ..sort();
  return HandsTogetherDiagnostic(
    evaluated: traces.length,
    fullyEligible: traces
        .where(
          (trace) => trace.eligibility.tier == EligibilityTier.fullyEligible,
        )
        .length,
    withinChallengeBand: traces
        .where((trace) => trace.isWithinChallengeBand)
        .length,
    admitted: traces.where((trace) => trace.isRanked).length,
    selectable: selectable,
    coordinationTransitions: traces
        .where((trace) => trace.coordinationTransition)
        .length,
    // Asked of the state directly rather than read off a rank key, because
    // most of these candidates never reached ranking and so have none. The
    // question is about the candidate, not about what it competed on.
    advancing: traces
        .where(
          (trace) =>
              realizationRankFor(state, trace.exercise) ==
              RealizationRank.advancing,
        )
        .length,
    fullyEligibleAdvancing: traces
        .where(
          (trace) =>
              trace.eligibility.tier == EligibilityTier.fullyEligible &&
              realizationRankFor(state, trace.exercise) ==
                  RealizationRank.advancing,
        )
        .length,
    hasFactualRetrieval: hasFactualRetrieval,
    minimumOverallP: probabilities.first,
    maximumOverallP: probabilities.last,
    eligibilityCodes: {for (final trace in traces) trace.eligibility.code.id},
    bypasses: {
      for (final trace in traces)
        if (trace.challengeBypass case final bypass?) bypass.id,
    },
  );
}
