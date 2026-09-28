import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'held_out_assessment.dart';
import 'python_compatible_random.dart';
import 'synthetic_player.dart';
import 'trajectory.dart';

/// Runs [player] through one session against the real pipeline.
///
/// Deterministic in every part: the same player, seed, length and catalog
/// produce the same trajectory and therefore the same detector findings, so a
/// pathological seed is a fixture rather than an anecdote.
///
/// The learner model and scheduler are the production ones. Only the person is
/// synthetic, which is what makes a finding here a finding about KeyRecall.
/// How much of each slot a run keeps.
enum TraceRetention {
  /// Every stage of every slot, for scheduler analysis.
  full,

  /// The history alone: what was chosen, what happened, and when.
  ///
  /// Evidence rather than diagnostics. A long run that keeps the ranked
  /// alternatives of every slot holds thousands of traces per slot, which a
  /// replay of the history has no use for.
  selectedOnly,
}

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
  AcquisitionFloor? acquisitionFloor,
  AssessmentSet? assessment,
  CandidateTrace? Function(SelectionResult selection, LearnerState state)?
  chooseInstead,
  void Function(int slot, List<CandidateTrace> traces)? observeTraces,
  void Function(int slot, LearnerState state)? observeState,
  void Function(int slot, PacingDecision pacing)? observePacing,
  void Function(int slot, DoseDecision dose)? observeDose,
}) => runTrajectorySessions(
  player: player,
  seed: seed,
  materials: materials,
  sessions: [Session(at: start ?? DateTime.utc(2026), slots: slots)],
  minutesPerSlot: minutesPerSlot,
  pipeline: pipeline,
  instrument: instrument,
  generated: generated,
  acquisitionFloor: acquisitionFloor,
  assessment: assessment,
  chooseInstead: chooseInstead,
  observeTraces: observeTraces,
  observeState: observeState,
  observePacing: observePacing,
  observeDose: observeDose,
);

/// Runs [player] through [sessions] spread across simulated calendar time.
///
/// What crosses a session boundary is what crosses it in the app. The learner
/// state persists and keeps decaying through the gap, since that is the whole
/// question a run across weeks asks; the session's own scheduling context is
/// rebuilt the way a restart rebuilds it, through [SessionState.resuming], so
/// a probe opened before a break cannot be answered after one just because the
/// harness held the object.
///
/// Slot indices run across the whole run rather than restarting each session,
/// so a detector reading a window of slots reads one ordered history and can
/// ask which session a slot belonged to.
Trajectory runTrajectorySessions({
  required SyntheticPlayer player,
  required int seed,
  required List<TechnicalMaterial> materials,
  required List<Session> sessions,
  double minutesPerSlot = 1.0,
  SchedulerPipeline pipeline = const SchedulerPipeline(learner: LearnerModel()),
  TraceRetention traceRetention = TraceRetention.full,
  InstrumentProfile? instrument,
  List<Exercise>? generated,
  AcquisitionFloor? acquisitionFloor,
  AssessmentSet? assessment,

  /// Substitutes what a slot asks for, leaving every other stage alone.
  ///
  /// The seam a paired experiment about selection needs: the decision is made
  /// by the real pipeline and only its winner is replaced, so a policy can be
  /// tried without a second run loop drifting away from this one. Returning
  /// null keeps the pipeline's choice. A replacement must be selectable in
  /// this slot; selection bookkeeping follows the final choice.
  CandidateTrace? Function(SelectionResult selection, LearnerState state)?
  chooseInstead,
  void Function(int slot, List<CandidateTrace> traces)? observeTraces,
  void Function(int slot, LearnerState state)? observeState,
  void Function(int slot, PacingDecision pacing)? observePacing,
  void Function(int slot, DoseDecision dose)? observeDose,
}) {
  for (var i = 1; i < sessions.length; i++) {
    final ends = sessions[i - 1].at.add(
      Duration(
        seconds: ((sessions[i - 1].slots - 1) * minutesPerSlot * 60).round(),
      ),
    );
    if (sessions[i].at.isBefore(ends)) {
      throw ArgumentError.value(
        sessions,
        'sessions',
        'session $i starts before session ${i - 1} has finished',
      );
    }
  }

  final rng = PythonCompatibleRandom(seed);
  final learner = pipeline.learner;
  final state = learner.placementState(player.placement, at: sessions.first.at);
  final playing = player.begin();
  // Generation is learner-blind, so the same catalog and instrument give the
  // same candidates for every seed. A sweep passes one set in rather than
  // rebuilding it eight hundred times.
  final candidates =
      generated ??
      generateCandidates(instrument ?? InstrumentProfile(), materials);

  final recorded = <TrajectorySlot>[];
  final terminals = <TerminalTrajectorySlot>[];
  final history = <PriorSelection>[];
  final readings = <AssessmentReading>[];
  var nextIndex = 0;

  void read(DateTime at) {
    if (assessment == null) return;
    learner.propagate(state, at);
    playing.restUntil(at);
    readings.add(
      assess(
        assessment,
        playing,
        at: at,
        afterSlots: recorded.length,
        state: state,
        learner: learner,
      ),
    );
  }

  for (var sessionIndex = 0; sessionIndex < sessions.length; sessionIndex++) {
    final session = SessionState.resuming(history, config: pipeline.config);
    var lastAt = sessions[sessionIndex].at;
    // Both ends of every session. The one on arrival is the person a break
    // handed back, before this session's practice starts moving them again,
    // which is the only place a returner can be measured.
    read(lastAt);
    for (var slot = 0; slot < sessions[sessionIndex].slots; slot++) {
      final index = nextIndex++;
      final at = lastAt = sessions[sessionIndex].at.add(
        Duration(seconds: (slot * minutesPerSlot * 60).round()),
      );
      learner.propagate(state, at);
      // Belief and person age together at the top of a slot. A run whose
      // player forgets nothing is unmoved by this, which is what keeps every
      // existing trajectory where it was.
      playing.restUntil(at);
      final probeBefore = session.tempoProbe;
      final probeFreshBefore = session.tempoProbeIsFresh;
      // Read what is needed immediately: this is the live state, and the slot
      // below moves it.
      observeState?.call(index, state);

      final slotEvaluation = pipeline.evaluateSlot(
        state: state,
        session: session,
        candidates: candidates,
        at: at,
        acquisitionFloor: acquisitionFloor,
      );
      final selection = slotEvaluation.result;
      observePacing?.call(index, selection.pacing);
      observeDose?.call(index, selection.dose);
      final traces = selection.traces;
      final available = selection.selectable;
      final selected = switch (selection) {
        CandidateSelected(:final candidate) => candidate,
        SelectionBlocked() || AcquisitionOffered() => null,
      };
      // A slot the pipeline could not fill stays unfilled: the seam replaces a
      // choice, it does not rescue a blocked decision.
      final chosen = selected == null
          ? null
          : chooseInstead?.call(selection, state) ?? selected;
      if (chosen != null && !available.contains(chosen)) {
        throw ArgumentError.value(
          chosen,
          'chooseInstead',
          "the replacement must belong to this slot's selectable candidates",
        );
      }
      session.recordSelectionOpportunity(
        guidanceProbeAvailable: slotEvaluation.guidanceProbeAvailable,
        guidanceProbeSelected:
            chosen?.challengeBypass == ChallengeBypass.guidanceProbe,
      );
      session.attemptsThisSession++;
      // Every candidate, which a slot does not retain: a session evaluates
      // thousands and only the selectable ones are worth carrying to the end.
      // A diagnostic asking what was refused has to see them as they go past.
      observeTraces?.call(index, traces);
      if (chosen == null) {
        terminals.add(
          TerminalTrajectorySlot(
            index: index,
            at: at,
            session: sessionIndex,
            traces: traceRetention == TraceRetention.full ? traces : const [],
            selectable: traceRetention == TraceRetention.full
                ? available
                : const [],
            candidates: _candidateCounts(candidates.length, traces, available),
            probe: ProbeState(
              pendingBefore: probeBefore,
              freshBefore: probeFreshBefore,
              pendingAfter: probeBefore,
              freshAfter: probeFreshBefore,
            ),
          ),
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
        family: exercise.material.familyId,
      );

      final outcome = playing.play(
        exercise,
        rng,
        delivery: _deliveryFor(exercise, chosen.challengeBypass),
      );
      final full = traceRetention == TraceRetention.full;
      final handsTogetherTraces = traces.where(
        (trace) =>
            trace.exercise.conditions.hands == HandConfiguration.together,
      );
      final handsTogetherSelectable = available.where(
        (trace) =>
            trace.exercise.conditions.hands == HandConfiguration.together,
      );
      final handsTogether = !full
          ? const HandsTogetherStages(
              prerequisiteSatisfied: {},
              eligible: {},
              admitted: {},
              selectable: {},
            )
          : HandsTogetherStages(
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
      pipeline.recordOutcome(session, exercise, outcome, at: at);
      final managedExecution = learner.executionWasManaged(outcome);
      history.add(
        PriorSelection(exercise, productive: managedExecution, at: at),
      );
      recorded.add(
        TrajectorySlot(
          index: index,
          at: at,
          session: sessionIndex,
          chosen: exercise,
          winner: chosen,
          alternatives: full
              ? ([
                  for (final trace in available)
                    if (!identical(trace, chosen)) trace,
                ]..sort((a, b) => b.rankKey!.compareTo(a.rankKey!)))
              : const [],
          performedTempoBpm: playing.lastPerformedTempoBpm,
          outcome: outcome,
          managedExecution: managedExecution,
          frontierBefore: frontierBefore,
          frontierAfter: frontierAfter,
          pacedBefore: pacedBefore,
          transferableBefore: transferableBefore,
          candidates: candidateCounts,
          handsTogether: handsTogether,
          probe: ProbeState(
            pendingBefore: probeBefore,
            freshBefore: probeFreshBefore,
            pendingAfter: session.tempoProbe,
            freshAfter: session.tempoProbeIsFresh,
          ),
        ),
      );
    }
    read(lastAt);
  }

  return Trajectory(
    playerId: player.id,
    seed: seed,
    slots: recorded,
    sessions: sessions,
    terminals: terminals,
    assessments: readings,
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

/// What the app would have put in front of the player for [exercise] chosen
/// under [bypass]: a metronome where the bypass supplies a pulse, and nothing
/// the evidence rule reads otherwise.
PresentationDelivery? _deliveryFor(Exercise exercise, ChallengeBypass? bypass) {
  if (bypass?.suppliesPulse != true) return null;
  const countIn = 4;
  return PresentationDelivery(
    tempo: TempoDelivery.complete(
      countIn,
      continuingBeats: realize(exercise).moments.length + countIn,
    ),
  );
}
