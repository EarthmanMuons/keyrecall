import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';
import 'priority.dart';
import 'recovery.dart';
import 'session_state.dart';

/// The staged decision pipeline that chooses what to practice next.
///
/// Four stages, each answering one question with an explicit information
/// boundary: candidate generation (which lives outside this class, because it
/// may not read learner state at all), eligibility and safety, challenge
/// admission, and priority ranking with selection.
///
/// [evaluate] traces every candidate through every stage; [selectChoice] is
/// the canonical V1 answer for what to present.
class SchedulerPipeline {
  /// The learner model supplying predictions and uncertainty.
  final LearnerModel learner;

  /// The versioned policy constants this pipeline applies.
  final SchedulerConfig config;

  const SchedulerPipeline({
    required this.learner,
    this.config = v1PrototypeSchedulerConfig,
  });

  /// Stage 2a: the `REQUIRES` prerequisite gate.
  ///
  /// Two questions, both about the learner rather than about the exercise:
  /// whether both hands are capable before they play together, and whether
  /// this material is appropriate to introduce yet. Foundation material has no
  /// prerequisite of the second kind, which is not the same as being fully
  /// eligible however it is played: C major hands together still waits for
  /// both hands.
  ///
  /// Material admission uses what the learner model actually observes:
  /// per-hand execution, and topology competence per scale form. It cannot ask
  /// whether a hand pattern is already established, because nothing measures
  /// that, so the admission band stands in for it as a curriculum-derived
  /// prior. Two materials in one band are treated identically even when one
  /// introduces a new hand pattern and the other reuses a familiar one, and
  /// that approximation is the reason `EligibilityReason` is coded: stalls
  /// clustering at a band that introduces a new pattern are what would justify
  /// measuring the motor axis directly.
  ///
  /// Provisional rather than forbidden, in every case. A provisional candidate
  /// is outranked by anything fully eligible and is still reachable when
  /// nothing else is, which is what stops a strict prior from leaving a
  /// learner with nothing to play.
  EligibilityDecision eligibilityFor(LearnerState state, Exercise exercise) {
    final material = exercise.material;
    final band = admissionBandOf(material);
    final hands = exercise.conditions.hands;

    if (hands == HandConfiguration.together) {
      final threshold = config.eligibility.handTogetherCompetencyThreshold;
      final rh = state.competency(Competency.rhScaleExecution).mean;
      final lh = state.competency(Competency.lhScaleExecution).mean;
      final means =
          'RH/LH means (${rh.toStringAsFixed(2)}/${lh.toStringAsFixed(2)})';
      if (rh < threshold || lh < threshold) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          '$means below threshold (${threshold.toStringAsFixed(2)})',
          code: EligibilityReason.handsTogetherPrerequisite,
        );
      }
    }

    // Natural minor asks for nothing: it is where minor topology comes from,
    // and requiring familiarity to earn the only material that produces it
    // would keep every minor scale outranked forever.
    if (material.form == ScaleForm.harmonicMinor ||
        material.form == ScaleForm.melodicMinor) {
      final floor = config.eligibility.minorTopologyFloor;
      final familiar = _bestMinorTopology(state, exclude: material.form);
      if (familiar < floor) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          'another minor form is at ${familiar.toStringAsFixed(2)}, '
          'floor ${floor.toStringAsFixed(2)}',
          code: material.form == ScaleForm.melodicMinor
              // Fixed-form melodic minor is the least familiar of the three
              // and waits for either of the others.
              ? EligibilityReason.melodicFormPrerequisite
              : EligibilityReason.minorTopologyPrerequisite,
        );
      }
    }

    if (band != AdmissionBand.foundation) {
      final floor = config.eligibility.executionFloorFor(band);
      final execution = _executionMeanFor(state, hands);
      if (execution < floor) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          '${band.id} asks for execution ${floor.toStringAsFixed(2)}, '
          'learner is at ${execution.toStringAsFixed(2)}',
          code: EligibilityReason.bandExecutionFloor,
        );
      }
      return EligibilityDecision(
        EligibilityTier.fullyEligible,
        '${band.id} met at execution ${execution.toStringAsFixed(2)}',
        code: EligibilityReason.bandExecutionMet,
      );
    }

    // Foundation means no *material* prerequisite. An execution condition can
    // still hold it back: hands-together work on C major is checked above and
    // may be provisional, which is the decomposition working rather than a
    // contradiction.
    return const EligibilityDecision(
      EligibilityTier.fullyEligible,
      'foundation material, and no material prerequisite applies',
      code: EligibilityReason.foundationMaterial,
    );
  }

  /// The weaker hand's execution when both play, otherwise the playing hand's.
  double _executionMeanFor(LearnerState state, HandConfiguration hands) {
    final rh = state.competency(Competency.rhScaleExecution).mean;
    final lh = state.competency(Competency.lhScaleExecution).mean;
    return switch (hands) {
      HandConfiguration.right => rh,
      HandConfiguration.left => lh,
      HandConfiguration.together => rh < lh ? rh : lh,
    };
  }

  /// The best minor topology the learner has, ignoring [exclude].
  ///
  /// Ignoring the form being admitted is what makes this a transfer rule
  /// rather than a self-referential one: A harmonic minor is admitted on the
  /// strength of A natural minor, not of itself. Note that it is any minor
  /// topology rather than the same tonic's, since the curricula give no
  /// support for a per-key ladder either.
  double _bestMinorTopology(LearnerState state, {required ScaleForm exclude}) {
    var best = double.negativeInfinity;
    for (final form in ScaleForm.values) {
      if (form == ScaleForm.major || form == exclude) continue;
      final mean = state.competency(form.topologyCompetency).mean;
      if (mean > best) best = mean;
    }
    return best;
  }

  /// Stage 2b: the workload gate.
  ///
  /// Reads session state only. A hard gate, unlike eligibility, but a narrow
  /// one: V1 caps session length and does not try to diagnose fatigue or
  /// injury from playing behavior.
  SafetyDecision safetyFor(SessionState session) {
    final cap = config.safety.maxSessionAttempts;
    final attempts = session.attemptsThisSession;
    if (attempts >= cap) {
      return SafetyDecision(
        false,
        'session attempt cap reached ($attempts/$cap)',
      );
    }
    return SafetyDecision(true, 'within session attempt cap ($attempts/$cap)');
  }

  /// Stage 3: whether predicted success lands in the "not too easy, not too
  /// hard" band.
  bool isWithinChallengeBand(Prediction prediction) =>
      config.challenge.pMin <= prediction.overallP &&
      prediction.overallP <= config.challenge.pMax;

  /// Whether [exercise] is a proactive step back toward independence.
  ///
  /// One step down from full cueing only: a successful probe is itself a
  /// genuine retrieval test, so it can re-anchor the memory clock and let
  /// ordinary admission take over, with no need to probe straight to fully
  /// unguided. Requires a prior confirmed success and enough time since it,
  /// since probing again immediately would be redundant.
  bool isGuidanceProbe(LearnerState state, Exercise exercise, DateTime at) {
    if (exercise.guidance != GuidanceContext.notesPreviewedOnly) return false;
    final lastSuccess = state
        .materialMemory[exercise.material.materialId]
        ?.factualLastRetrievalAt;
    if (lastSuccess == null) return false;
    return lastSuccess.daysUntil(at) >= config.probe.minDaysSinceLastRetrieval;
  }

  /// Whether [exercise] is a first retrieval test for material that has never
  /// succeeded.
  ///
  /// The unanchored counterpart to [isGuidanceProbe]. Recovery can escalate a
  /// material to maximum cueing after a couple of failures, before any success
  /// ever anchors the clock, and the guidance probe structurally cannot help
  /// there because its precondition is the anchor this material lacks. This is
  /// what keeps offering a retrieval-observing candidate instead of settling
  /// into a permanently cued state. Its clock is the last factual attempt of
  /// any kind, not the last success.
  bool isBootstrapProbe(LearnerState state, Exercise exercise, DateTime at) {
    if (exercise.guidance != GuidanceContext.notesPreviewedOnly) return false;
    final memory = state.materialMemory[exercise.material.materialId];
    if (memory == null || memory.factualLastRetrievalAt != null) return false;
    final lastAttempt = memory.lastRetrievalAttemptAt;
    if (lastAttempt == null) return false;
    return lastAttempt.daysUntil(at) >= config.probe.minDaysSinceLastRetrieval;
  }

  /// Which named exception, if any, admits [exercise] outside the ordinary
  /// band.
  ///
  /// Recovery is checked first and exclusively: while a recovery context is
  /// active, the exact target is the only candidate that may be admitted at
  /// all. An [override] always wins, because it is an explicit caller
  /// instruction rather than a policy inferred from state.
  ChallengeBypass? challengeBypassFor({
    required LearnerState state,
    required Exercise exercise,
    required Prediction prediction,
    required DateTime at,
    required ChallengeBypass? override,
    required Exercise? recoveryTarget,
  }) {
    if (override != null) return override;
    if (recoveryTarget != null) {
      return exercise == recoveryTarget ? ChallengeBypass.recovery : null;
    }
    if (!state.materialMemory.containsKey(exercise.material.materialId)) {
      return prediction.overallP >= config.challenge.pIntroductionMin
          ? ChallengeBypass.newMaterial
          : null;
    }
    if (isGuidanceProbe(state, exercise, at)) {
      return ChallengeBypass.guidanceProbe;
    }
    if (isBootstrapProbe(state, exercise, at)) {
      return ChallengeBypass.bootstrapProbe;
    }
    return null;
  }

  /// Runs every candidate through every stage and returns the full traces.
  ///
  /// Diagnostic values are computed for all candidates, but the stage statuses
  /// follow the real upstream decisions, and a rank key is set only where
  /// priority ranking genuinely ran.
  ///
  /// Pass [overrides] to force admission for a specific candidate, which
  /// scripted diagnostics and explicit learner requests need because those
  /// reasons are not derivable from state.
  List<CandidateTrace> evaluate({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
  }) {
    final failed = session.lastFailedExercise;
    final target = failed == null ? null : recoveryTarget(failed);
    final safety = safetyFor(session);

    // Guidance changes material availability, but not independent retrieval,
    // execution, or topology. Generation emits each realization under all
    // three guidance levels, so those channels are computed once per
    // realization, keyed by the same exercise with guidance normalized away.
    final retrievalCache = <String, double>{};
    final executionCache = <Exercise, double>{};
    final topologyCache = <Exercise, double>{};

    return [
      for (final exercise in candidates)
        _evaluateCandidate(
          state: state,
          session: session,
          exercise: exercise,
          at: at,
          safety: safety,
          recoveryTarget: target,
          override: overrides[exercise],
          retrievalCache: retrievalCache,
          executionCache: executionCache,
          topologyCache: topologyCache,
        ),
    ];
  }

  CandidateTrace _evaluateCandidate({
    required LearnerState state,
    required SessionState session,
    required Exercise exercise,
    required DateTime at,
    required SafetyDecision safety,
    required Exercise? recoveryTarget,
    required ChallengeBypass? override,
    required Map<String, double> retrievalCache,
    required Map<Exercise, double> executionCache,
    required Map<Exercise, double> topologyCache,
  }) {
    final realization = exercise.withGuidance(GuidanceContext.unguided);
    final independentRetrievalP = retrievalCache.putIfAbsent(
      exercise.material.materialId,
      () => learner.independentRetrievalProbability(state, exercise, at),
    );
    final prediction = Prediction(
      independentRetrievalP: independentRetrievalP,
      materialAvailableP: materialAvailableProbability(
        independentRetrievalP,
        exercise.guidance,
      ),
      executionP: executionCache.putIfAbsent(
        realization,
        () => learner.executionProbability(state, exercise),
      ),
      topologyP: topologyCache.putIfAbsent(
        realization,
        () => learner.topologyProbability(state, exercise),
      ),
    );

    final withinBand = isWithinChallengeBand(prediction);
    final bypass = challengeBypassFor(
      state: state,
      exercise: exercise,
      prediction: prediction,
      at: at,
      override: override,
      recoveryTarget: recoveryTarget,
    );
    // A recovery context is exclusive: narrowing which candidate gets the
    // label is not enough, since a candidate that happens to fall in the
    // ordinary band or qualify as new material must not survive alongside the
    // target.
    final survived = recoveryTarget != null && override == null
        ? bypass == ChallengeBypass.recovery
        : withinBand || bypass != null;

    final challengeStatus = safety.isAllowed
        ? StageStatus.reached
        : StageStatus.notReached;
    final priorityStatus = challengeStatus.isReached && survived
        ? StageStatus.reached
        : StageStatus.notReached;

    final eligibility = eligibilityFor(state, exercise);
    final terms = RankKey(
      tier: eligibility.tier,
      retention: retention(prediction, exercise),
      information: information(state, exercise, learner.params),
      diversity: diversity(exercise, session),
      goals: goals(exercise),
    );

    return CandidateTrace(
      exercise: exercise,
      eligibility: eligibility,
      safety: safety,
      challengeStatus: challengeStatus,
      prediction: prediction,
      isWithinChallengeBand: withinBand,
      challengeBypass: bypass,
      challengeSurvived: survived,
      priorityStatus: priorityStatus,
      terms: terms,
      rankKey: priorityStatus.isReached ? terms : null,
    );
  }

  /// Excludes a material that has been selected too many times in a row, as
  /// long as another admitted material exists.
  ///
  /// A pre-selection filter rather than another ranking term: under
  /// lexicographic ranking the diversity term can only break exact ties, so no
  /// diversity penalty could stop a material whose retention score wins
  /// outright. It never removes the only admitted option, which would force a
  /// no-admission slot to avoid repetition.
  List<CandidateTrace> applyRepetitionGuard(
    List<CandidateTrace> traces,
    SessionState session,
  ) {
    final ranked = traces.where((trace) => trace.isRanked).toList();
    if (ranked.isEmpty) return traces;

    final cap = config.diversity.maxConsecutiveMaterialAttempts;
    final overRepeated = {
      for (final trace in ranked) trace.exercise.material.materialId,
    }.where((id) => session.consecutiveAttemptsOf(id) >= cap).toSet();

    final guarded = ranked
        .where(
          (trace) => !overRepeated.contains(trace.exercise.material.materialId),
        )
        .toList();
    return guarded.isEmpty ? ranked : guarded;
  }

  /// The highest-ranking candidate, or null when nothing was admitted.
  ///
  /// The bare lexicographic primitive, kept usable on its own for unit tests.
  /// Production callers want [selectChoice], which applies the repetition
  /// guard first. Ties resolve to the earliest candidate in [traces], so
  /// selection stays deterministic for replay.
  CandidateTrace? selectBest(List<CandidateTrace> traces) {
    CandidateTrace? best;
    for (final trace in traces) {
      if (!trace.isRanked) continue;
      if (best == null || trace.rankKey!.compareTo(best.rankKey!) > 0) {
        best = trace;
      }
    }
    return best;
  }

  /// The canonical V1 choice: repetition guard, then lexicographic ranking.
  ///
  /// Every real caller should use this rather than [selectBest] alone, which
  /// silently omits the guard and can reproduce perseveration.
  CandidateTrace? selectChoice(
    List<CandidateTrace> traces,
    SessionState session,
  ) => selectBest(applyRepetitionGuard(traces, session));
}
