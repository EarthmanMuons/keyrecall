import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import '../elapsed_days.dart';
import '../params/learner_params.dart';
import '../state/learner_state.dart';
import '../state/material_execution_state.dart';
import '../state/material_memory_state.dart';
import '../state/monotonic_time.dart';
import 'evidence_weights.dart';
import 'loadings.dart';
import 'memory_update_diagnostics.dart';
import 'outcome.dart';
import 'prediction.dart';
import 'retained_consolidation.dart';

double _sigmoid(double logit) => 1.0 / (1.0 + math.exp(-logit));

/// `1 - d_e(1 - M)`: how likely the material can be produced on an attempt
/// offering [guidance], given an unaided recall probability of
/// [independentRetrievalP].
///
/// Support props availability up even when independent recall would fail:
/// continuous cueing makes availability near-certain, previewed notes partly
/// compensate, and an unguided attempt uses [independentRetrievalP] unchanged.
double _materialAvailableProbability(
  double independentRetrievalP,
  GuidanceContext guidance,
) => 1.0 - guidance.retrievalDemand * (1.0 - independentRetrievalP);

/// The V1 learner model: it predicts an attempt, then learns from what
/// happened.
///
/// Prediction is read-only, so taking a state snapshot before calling
/// [predict] captures everything the prediction used, and predicting is never
/// itself evidence. [applyOutcome] mutates the state it is given, in the
/// ordering the production contract requires.
class LearnerModel {
  /// The versioned constants this model reasons with.
  final LearnerParams params;

  /// The model reading [params].
  ///
  /// There is no semantic switch to pass. [LearnerParams.modelVersion] is what
  /// an attempt records and what replay refuses to reinterpret under, so it has
  /// to name one transition function rather than a family of them.
  const LearnerModel({this.params = v1LearnerParams});

  /// The model as the frozen Python prototype defined it.
  ///
  /// For the reference-equivalence and digest tests. The older model preserved,
  /// not a configuration of the current one.
  const LearnerModel.v1Prototype() : params = v1PrototypeLearnerParams;

  /// Whether this is the preserved prototype rather than a live model.
  ///
  /// Read from the recorded version rather than stored beside it, so the two
  /// cannot disagree.
  bool get _isPrototype =>
      params.modelVersion == v1PrototypeLearnerParams.modelVersion;

  /// Whether execution evidence is attributed at the difficulty the attempt
  /// actually demonstrated rather than the one it was asked for.
  ///
  /// See [demonstratedTempoBpm]. False only for [LearnerModel.v1Prototype],
  /// which recorded achieved tempo without consuming it.
  bool get attributesDemonstratedDifficulty => !_isPrototype;

  /// Whether bilateral coordination participates in challenge prediction.
  ///
  /// False only for [LearnerModel.v1Prototype], whose recorded prediction
  /// semantics predate the coordination channel's admission consequence.
  bool get includesCoordinationInChallenge => !_isPrototype;

  /// A cold-start state with every competency at the registry prior.
  LearnerState newState({required DateTime at, double? competencyPriorMean}) =>
      LearnerState.cold(
        params,
        at: at,
        competencyPriorMean: competencyPriorMean,
      );

  /// A cold-start state seeded from a self-report [tier].
  LearnerState placementState(PlacementTier tier, {required DateTime at}) =>
      LearnerState.atPlacement(tier, params, at: at);

  /// Advances [state] to [at] without evidence.
  void propagate(LearnerState state, DateTime at) =>
      state.propagateTo(at, params);

  /// Propagates [state] to [at] and then folds one attempt's evidence in.
  ///
  /// The two halves of the transition contract, for callers with no reason to
  /// separate them. [applyOutcome] stays strict rather than propagating on its
  /// own, because where propagation happens is what replay reproduces.
  ///
  /// Atomic with respect to every rejection, propagation's included: both
  /// halves run against a copy and are committed back only once the whole
  /// transition succeeds, so a refused attempt leaves no timestamps or
  /// variances behind.
  MemoryUpdateDiagnostics propagateAndApplyOutcome({
    required LearnerState state,
    required Exercise exercise,
    required Outcome outcome,
    required EvidenceWeights weights,
    required Prediction prediction,
    required DateTime at,
  }) {
    final next = state.copy();
    propagate(next, at);
    final diagnostics = applyOutcome(
      state: next,
      exercise: exercise,
      outcome: outcome,
      weights: weights,
      prediction: prediction,
      at: at,
    );
    state.adoptFrom(next);
    return diagnostics;
  }

  /// Whether an outcome demonstrated the execution it was asked for.
  bool executionWasManaged(Outcome outcome) =>
      outcome.completed &&
      outcome.motorScore >= params.materialExecution.demonstratedMotorScore;

  /// The competency mean used for prediction, including the hand-transfer
  /// adjustment.
  ///
  /// An under-observed hand is nudged toward the better-observed one, most
  /// while it is uncertain and less as its own evidence accumulates. It never
  /// writes the paired competency's stored state, so right-hand practice is
  /// never recorded as a left-hand observation.
  double effectiveCompetencyMean(LearnerState state, Competency competency) {
    final target = state.competency(competency);
    final shrinkage =
        target.variance /
        (target.variance + params.competencyTransfer.shrinkageTau);
    var mean = target.mean;
    final familySource = competency.familyTransferSource;
    if (familySource != null) {
      mean +=
          params.competencyTransfer.rhoFamily *
          shrinkage *
          (state.competency(familySource).mean - target.mean);
    }
    final paired = competency.pairedHand;
    if (paired != null) {
      mean +=
          params.competencyTransfer.rhoHand *
          shrinkage *
          (state.competency(paired).mean - target.mean);
    }
    return mean;
  }

  /// `D_motor(e)`: everything that makes the physical task harder. Positive is
  /// harder.
  ///
  /// Guidance is absent: it makes the material available rather than the
  /// physical task easier.
  double motorDifficulty(Exercise exercise) {
    final difficulty = params.difficulty;
    final conditions = exercise.conditions;
    return difficulty.tempoBeta *
            math.log(conditions.tempoBpm / difficulty.referenceTempoBpm) +
        difficulty.octaveBeta * math.max(0, conditions.octaves - 1) +
        difficulty.handBeta *
            (conditions.hands == HandConfiguration.together ? 1.0 : 0.0) +
        difficulty.directionBeta *
            (conditions.direction == ExerciseDirection.upDown ? 1.0 : 0.0);
  }

  /// The tempo an attempt actually demonstrated, in BPM.
  ///
  /// Capped at the requested tempo. A scale played slower demonstrates the
  /// easier task, and playing faster is not credited beyond what the scheduler
  /// chose.
  ///
  /// Only execution difficulty moves. Playing C harmonic minor slowly is still
  /// recalling C harmonic minor.
  double demonstratedTempoBpm(Exercise exercise, Outcome outcome) {
    final requested = exercise.conditions.tempoBpm;
    if (!attributesDemonstratedDifficulty) return requested;
    // An attempt with no measurable pace demonstrates nothing about tempo, so
    // it is attributed at what it was asked for rather than at zero.
    final ratio = outcome.measuredTempoRatio;
    if (ratio == null) return requested;
    return math.min(requested, requested * ratio);
  }

  /// `P(execution succeeds)` at the difficulty [outcome] actually demonstrated.
  ///
  /// The baseline an attempt's execution surprise is measured against. At the
  /// requested tempo it is exactly [executionProbability].
  double demonstratedExecutionProbability(
    LearnerState state,
    Exercise exercise,
    Outcome outcome,
  ) {
    final tempo = demonstratedTempoBpm(exercise, outcome);
    if (tempo == exercise.conditions.tempoBpm) {
      return executionProbability(state, exercise);
    }
    return executionProbability(state, exercise.atTempo(tempo));
  }

  /// `M(t)`: the probability the material would be retrieved with no support.
  ///
  /// Falls back to the configured prior for a material with no memory state,
  /// which is what a never-practiced material has.
  double independentRetrievalProbability(
    LearnerState state,
    Exercise exercise,
    DateTime at,
  ) {
    final memory = state.materialMemory[exercise.material.materialId];
    return memory?.retrievabilityOrPrior(at) ??
        params.materialMemory.priorRetrievability;
  }

  /// `P(acceptable motor execution | material available)`.
  ///
  /// Reads only motor competencies and the material execution residual.
  /// Bilateral coordination is a separate required channel, joining this one in
  /// the motor-control bottleneck of [Prediction.overallP].
  double executionProbability(LearnerState state, Exercise exercise) {
    final loadings = motorLoadings(exercise.structuralQ);
    var competencyTerm = 0.0;
    for (final entry in loadings.entries) {
      competencyTerm += entry.value * effectiveCompetencyMean(state, entry.key);
    }

    final residual = state.materialExecution[executionContextOf(exercise)];

    return _sigmoid(
      competencyTerm +
          (residual?.residualMean ?? 0.0) -
          motorDifficulty(exercise),
    );
  }

  /// `P(the hands stay together)`.
  ///
  /// Carries no motor-difficulty penalty, which would otherwise charge the
  /// two-hand task twice.
  double coordinationProbability(LearnerState state, Exercise exercise) {
    if (exercise.conditions.hands != HandConfiguration.together) return 1.0;
    final loadings = coordinationLoadings(exercise.structuralQ);
    var coordinationTerm = 0.0;
    for (final entry in loadings.entries) {
      coordinationTerm +=
          entry.value * effectiveCompetencyMean(state, entry.key);
    }
    return _sigmoid(coordinationTerm);
  }

  /// `P(the pitch/form structure is known)`.
  ///
  /// Carries no motor-difficulty penalty: this channel is about knowing the
  /// scale's shape, not about executing it.
  double topologyProbability(LearnerState state, Exercise exercise) {
    final loadings = topologyLoadings(exercise.structuralQ);
    var topologyTerm = 0.0;
    for (final entry in loadings.entries) {
      topologyTerm += entry.value * effectiveCompetencyMean(state, entry.key);
    }
    return _sigmoid(topologyTerm);
  }

  /// All five channels for [exercise] at [at].
  ///
  /// Read-only: it never inserts state, so predicting a candidate the
  /// scheduler goes on to reject leaves no trace in the learner.
  Prediction predict(
    LearnerState state,
    Exercise exercise, {
    required DateTime at,
  }) {
    final independentRetrievalP = independentRetrievalProbability(
      state,
      exercise,
      at,
    );
    return predictionFromChannels(
      guidance: exercise.guidance,
      independentRetrievalP: independentRetrievalP,
      executionP: executionProbability(state, exercise),
      coordinationP: coordinationProbability(state, exercise),
      topologyP: topologyProbability(state, exercise),
    );
  }

  /// Assembles the model prediction from already-computed channels.
  Prediction predictionFromChannels({
    required GuidanceContext guidance,
    required double independentRetrievalP,
    required double executionP,
    required double coordinationP,
    required double topologyP,
  }) => Prediction(
    independentRetrievalP: independentRetrievalP,
    materialAvailableP: _materialAvailableProbability(
      independentRetrievalP,
      guidance,
    ),
    executionP: executionP,
    coordinationP: includesCoordinationInChallenge ? coordinationP : 1.0,
    topologyP: topologyP,
  );

  /// Rejects an attempt this model cannot learn from, writing nothing.
  ///
  /// Four kinds of admissibility, asked in one place so no partial write can
  /// precede one:
  ///
  /// - **Temporal.** Every propagating layer of [state] must stand exactly at
  ///   [at]. Propagation belongs to the caller, and a layer left behind its own
  ///   evidence serializes to something no decoder will read back.
  /// - **Consistency.** Whether retrieval was tested follows from the guidance
  ///   rung rather than being a free field, and an attempt that never began
  ///   cannot have completed or retrieved.
  /// - **Observability.** An untested retrieval carries exactly zero memory
  ///   weight, and an attempt that never began carries no execution evidence.
  ///   Reduced weights stay welcome; weight from an event that did not happen
  ///   does not.
  /// - **Numeric.** A derived tempo about to enter state must be finite. Bounds
  ///   on the supplied weights, prediction, and outcome are their own
  ///   constructors' invariants.
  ///
  /// Throws [ArgumentError] on the first failure.
  void validateTransition({
    required LearnerState state,
    required Exercise exercise,
    required Outcome outcome,
    required EvidenceWeights weights,
    required DateTime at,
  }) {
    state.requireAlignedAt(at);
    final materialId = exercise.material.materialId;
    final observed = state.materialMemory[materialId]?.lastObservedAt;
    if (observed != null) {
      requireForwardPropagation(at, observed, '$materialId memory');
    }

    final tested = exercise.guidance.isRetrievalObserved;
    if (outcome.retrieval.isTested != tested) {
      throw ArgumentError.value(
        outcome.retrieval.name,
        'outcome.retrieval',
        tested
            ? 'this rung tests retrieval, so the attempt observed one'
            : 'this rung supplies the material, so it tested no retrieval',
      );
    }
    if (!outcome.started &&
        (outcome.completed ||
            outcome.retrieval == FactualRetrieval.succeeded)) {
      throw ArgumentError.value(
        outcome,
        'outcome',
        'an attempt that never began produced nothing to complete or retrieve',
      );
    }

    if (!outcome.retrieval.isTested && weights.materialMemory > 0.0) {
      throw ArgumentError.value(
        weights.materialMemory,
        'weights.materialMemory',
        'an untested retrieval is no memory evidence at all',
      );
    }

    if (!outcome.started) {
      // Failing to begin is a real observation, and the memory weight above is
      // where it lands. Nothing downstream of execution may move.
      if (weights.materialExecution > 0.0) {
        throw ArgumentError.value(
          weights.materialExecution,
          'weights.materialExecution',
          'an attempt that never began executed nothing',
        );
      }
      for (final competency in Competency.values) {
        if (weights[competency] > 0.0) {
          throw ArgumentError.value(
            weights[competency],
            'weights[${competency.id}]',
            'an attempt that never began demonstrated no competency',
          );
        }
      }
    }

    if (outcome.measuredTempoRatio case final ratio?) {
      final performed = exercise.conditions.tempoBpm * ratio;
      if (!performed.isFinite) {
        throw ArgumentError.value(
          ratio,
          'outcome.achievedTempoRatio',
          'gives no finite tempo at ${exercise.conditions.tempoBpm} BPM',
        );
      }
    }
  }

  /// Applies one attempt's evidence to [state], in place.
  ///
  /// Each layer learns only from a residual its own prediction helped generate:
  /// motor competencies and the execution residual from
  /// `motorScore - executionP`, topology competencies from
  /// `topologyAccuracy - topologyP`, and memory from
  /// `retrieval.score - independentRetrievalP`. There is no universal
  /// prediction error, and zero-weight layers are left untouched.
  ///
  /// For a factual retrieval with a pre-existing anchor the ordering is
  /// mandatory: retained-consolidation inference, then current-durability
  /// evidence correction, then the causal transition. That separates durability
  /// evidence that existed before the attempt from learning it caused.
  ///
  /// Throws [ArgumentError] for anything [validateTransition] rejects, checked
  /// before the first write, so a rejected attempt leaves [state] untouched.
  ///
  /// Returns the event-local memory attribution. The state changes land in
  /// [state].
  MemoryUpdateDiagnostics applyOutcome({
    required LearnerState state,
    required Exercise exercise,
    required Outcome outcome,
    required EvidenceWeights weights,
    required Prediction prediction,
    required DateTime at,
  }) {
    validateTransition(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: weights,
      at: at,
    );

    final materialId = exercise.material.materialId;
    final q = exercise.structuralQ;
    final motorQ = motorLoadings(q);
    final topologyQ = topologyLoadings(q);
    final coordinationQ = coordinationLoadings(q);

    // Against the difficulty demonstrated, not the one requested. Only
    // execution is a claim about a physical task whose difficulty the
    // performance itself established.
    final deltaExec =
        outcome.motorScore -
        demonstratedExecutionProbability(state, exercise, outcome);
    final deltaTopology = outcome.topologyAccuracy - prediction.topologyP;
    // Absent when nothing measured how together the hands were, which leaves
    // the coordination channel untouched rather than teaching it zero.
    final deltaCoordination = outcome.coordination == null
        ? null
        : outcome.coordination! - coordinationProbability(state, exercise);

    _updateCompetencies(
      state: state,
      weights: weights,
      motorQ: motorQ,
      topologyQ: topologyQ,
      coordinationQ: coordinationQ,
      deltaExec: deltaExec,
      deltaTopology: deltaTopology,
      deltaCoordination: deltaCoordination,
      at: at,
    );

    if (weights.materialExecution > 0.0) {
      _updateExecutionResidual(
        state: state,
        context: executionContextOf(exercise),
        exercise: exercise,
        outcome: outcome,
        weight: weights.materialExecution,
        deltaExec: deltaExec,
        at: at,
      );
    }

    return _updateMaterialMemory(
      memory: state.materialMemoryFor(materialId, params),
      exercise: exercise,
      outcome: outcome,
      weights: weights,
      prediction: prediction,
      at: at,
    );
  }

  void _updateCompetencies({
    required LearnerState state,
    required EvidenceWeights weights,
    required Map<Competency, double> motorQ,
    required Map<Competency, double> topologyQ,
    required Map<Competency, double> coordinationQ,
    required double deltaExec,
    required double deltaTopology,
    required double? deltaCoordination,
    required DateTime at,
  }) {
    for (final competency in Competency.values) {
      final weight = weights[competency];
      final channel = _channelOf(competency);
      final loading =
          switch (channel) {
            _Channel.topology => topologyQ[competency],
            _Channel.motor => motorQ[competency],
            _Channel.coordination => coordinationQ[competency],
          } ??
          0.0;
      if (weight <= 0.0 || loading <= 0.0) continue;

      final delta = switch (channel) {
        _Channel.topology => deltaTopology,
        _Channel.motor => deltaExec,
        _Channel.coordination => deltaCoordination,
      };
      if (delta == null) continue;
      final belief = state.competency(competency);
      belief.mean += params.competency.learningRate * loading * weight * delta;
      belief.variance = math.max(
        params.competency.minVariance,
        belief.variance * (1 - params.competency.evidenceShrinkage * weight),
      );
      belief.lastEvidenceAt = at;
    }
  }

  void _updateExecutionResidual({
    required LearnerState state,
    required ExecutionContext context,
    required Exercise exercise,
    required Outcome outcome,
    required double weight,
    required double deltaExec,
    required DateTime at,
  }) {
    final residual = state.materialExecutionFor(
      context,
      at,
      params,
      familyId: exercise.material.familyId,
    );
    residual.residualMean +=
        params.materialExecution.learningRate * weight * deltaExec;
    residual.residualVariance = math.max(
      params.materialExecution.minVariance,
      residual.residualVariance *
          (1 - params.materialExecution.evidenceShrinkage * weight),
    );
    residual.lastEvidenceAt = at;

    // Absent when the attempt established no pace, which leaves both records
    // of a performed tempo untouched rather than filing one at zero.
    final performedTempoBpm = switch (outcome.measuredTempoRatio) {
      final ratio? => exercise.conditions.tempoBpm * ratio,
      null => null,
    };

    // A separate record from the frontier, and a separate bar: pitch rather
    // than motor quality, because a hand that plays the right notes unevenly is
    // ready for the other hand to join it.
    if (performedTempoBpm != null &&
        outcome.completed &&
        outcome.pitchIntegrity >=
            params.materialExecution.handsTogetherPitchIntegrity) {
      // At the tempo actually played, since this is where hands-together work
      // starts and so has to be where the hand actually is. The frontier beside
      // it records the request instead.
      residual.readyForHandsTogether(
        octaves: exercise.conditions.octaves,
        tempoBpm: performedTempoBpm,
      );
    }

    // The execution frontier moves only on an attempt that was managed:
    // through to the end, and played rather than endured. A maximum rather than
    // the latest, so working slowly on something already taken faster does not
    // walk it back down.
    if (!executionWasManaged(outcome)) return;
    residual.demonstrate(
      octaves: exercise.conditions.octaves,
      tempoBpm: exercise.conditions.tempoBpm,
    );
    // And how fast they were actually going, which the frontier does not
    // record: an unseen scale should arrive near the demonstrated pace rather
    // than near the last request.
    if (performedTempoBpm != null) residual.paced(performedTempoBpm);
  }

  MemoryUpdateDiagnostics _updateMaterialMemory({
    required MaterialMemoryState memory,
    required Exercise exercise,
    required Outcome outcome,
    required EvidenceWeights weights,
    required Prediction prediction,
    required DateTime at,
  }) {
    final memoryParams = params.materialMemory;
    final anchorBefore = memory.memoryAnchorAt;
    final currentHalfLifeBefore = memory.currentHalfLifeDays;
    var inferenceDelta = 0.0;

    // Factual bookkeeping rather than an evidence-weighted estimate: an
    // untested retrieval updates neither timestamp.
    if (outcome.retrieval.isTested) {
      memory.lastRetrievalAttemptAt = at;
    }

    if (anchorBefore != null && outcome.retrieval.isTested) {
      inferenceDelta = updateRetainedConsolidationPosterior(
        memory: memory,
        retrievalSucceeded: outcome.retrieval == FactualRetrieval.succeeded,
        elapsedDays: anchorBefore.daysUntil(at),
        evidenceWeight: weights.materialMemory,
        params: memoryParams,
      );
    }

    if (weights.materialMemory > 0.0) {
      if (anchorBefore != null) {
        _correctCurrentDurability(
          memory: memory,
          weight: weights.materialMemory,
          delta: outcome.retrieval.score - prediction.independentRetrievalP,
        );
      } else if (outcome.retrieval == FactualRetrieval.failed) {
        // The half-life clock has never anchored, so the cold-start belief is
        // the operative prediction; only it and its own uncertainty move.
        _correctColdStartBelief(
          memory: memory,
          weight: weights.materialMemory,
          delta: outcome.retrieval.score - memory.coldStartEstimate,
        );
      }
    }

    // A rung just failed stops being established, so the ladder waits for the
    // next success to say where the learner is rather than offering the same
    // step again immediately.
    if (outcome.retrieval == FactualRetrieval.failed) {
      memory.establishedIndependence = null;
      memory.establishedIndependenceAt = null;
    }

    final quality = outcome.practiceQuality;

    if (outcome.retrieval == FactualRetrieval.succeeded) {
      final formationDelta = _formMemory(
        memory: memory,
        guidance: exercise.guidance,
        quality: quality,
        currentHalfLifeBefore: currentHalfLifeBefore,
        at: at,
      );
      return MemoryUpdateDiagnostics(
        consolidationDeltaFromRetrievalInference: inferenceDelta,
        consolidationDeltaFromCausalFormation: formationDelta,
      );
    }

    if (quality > 0.0) {
      _restoreFromSupportedPractice(
        memory: memory,
        guidance: exercise.guidance,
        quality: quality,
        at: at,
      );
    }
    return MemoryUpdateDiagnostics(
      consolidationDeltaFromRetrievalInference: inferenceDelta,
    );
  }

  /// Surprise-driven correction of current durability, in log space.
  ///
  /// Surprising outcomes move the estimate more than expected ones, while the
  /// reversion term creates a stable interior equilibrium under repeated
  /// expected failure. Bounded below by the configured floor and above by
  /// retained consolidation.
  void _correctCurrentDurability({
    required MaterialMemoryState memory,
    required double weight,
    required double delta,
  }) {
    final memoryParams = params.materialMemory;
    final priorLogHalfLife = math.log(memoryParams.initialCurrentHalfLifeDays);
    final corrected =
        memory.logCurrentHalfLife +
        weight *
            (memoryParams.alphaCurrentDurability * delta -
                memoryParams.reversionLambdaCurrentDurability *
                    (memory.logCurrentHalfLife - priorLogHalfLife));

    memory.logCurrentHalfLife = math.min(
      math.max(corrected, math.log(memoryParams.minHalfLifeDays)),
      memory.logConsolidatedHalfLife,
    );
    memory.currentHalfLifeUncertainty = math.max(
      memoryParams.minUncertainty,
      memory.currentHalfLifeUncertainty *
          (1 - memoryParams.evidenceShrinkage * weight),
    );
  }

  /// The same surprise-driven correction, applied to the pre-anchor belief in
  /// logit space.
  void _correctColdStartBelief({
    required MaterialMemoryState memory,
    required double weight,
    required double delta,
  }) {
    final memoryParams = params.materialMemory;
    final priorLogit = logit(memoryParams.priorRetrievability);
    final corrected =
        memory.logitColdStart +
        weight *
            (memoryParams.alphaColdStart * delta -
                memoryParams.reversionLambdaColdStart *
                    (memory.logitColdStart - priorLogit));

    memory.logitColdStart = math.min(
      math.max(corrected, logit(memoryParams.minColdStartProbability)),
      logit(memoryParams.maxColdStartProbability),
    );
    memory.coldStartUncertainty = math.max(
      memoryParams.minUncertainty,
      memory.coldStartUncertainty *
          (1 - memoryParams.evidenceShrinkage * weight),
    );
  }

  /// Causal learning from a successful factual retrieval.
  ///
  /// Anchors activation, records the success, grows consolidation toward its
  /// saturating target in proportion to execution quality and retrieval
  /// context, then grows current durability toward the resulting envelope.
  ///
  /// A first success identifies no forgetting rate, having no anchored interval
  /// before it, but still establishes stronger post-attempt memory. Growth
  /// starts from whichever is higher of the pre-attempt and evidence-corrected
  /// durability, so correction can revise downward without making a successful
  /// practice event net destructive.
  ///
  /// Returns the consolidation growth in days.
  double _formMemory({
    required MaterialMemoryState memory,
    required GuidanceContext guidance,
    required double quality,
    required double currentHalfLifeBefore,
    required DateTime at,
  }) {
    final memoryParams = params.materialMemory;
    memory.memoryAnchorAt = at;
    memory.factualLastRetrievalAt = at;
    // The rung this was produced under, which the next question is built from.
    // The latest rather than the best ever, so a recovery success resumes from
    // where the learner just succeeded.
    //
    // Its clock moves only when the rung does, or practising at an established
    // rung would push the step toward independence away every time.
    if (memory.establishedIndependence != guidance.independence) {
      memory.establishedIndependence = guidance.independence;
      memory.establishedIndependenceAt = at;
    }

    final successFactor = switch (guidance.independence) {
      1 => memoryParams.retrievalSuccessFactorNotesPreviewed,
      2 => memoryParams.retrievalSuccessFactorUnguided,
      _ => throw StateError(
        'a continuously cued attempt cannot report a successful factual '
        'retrieval: it never tested one',
      ),
    };

    final consolidationBefore = memory.consolidatedHalfLifeDays;
    final consolidationGap = math.max(
      0.0,
      memoryParams.consolidationGrowthTargetDays - consolidationBefore,
    );
    final consolidation = math.min(
      consolidationBefore +
          memoryParams.consolidationGrowthRate *
              successFactor *
              quality *
              consolidationGap,
      memoryParams.maxMemoryHalfLifeDays,
    );

    final currentBase = math.max(
      currentHalfLifeBefore,
      memory.currentHalfLifeDays,
    );
    final current =
        currentBase +
        memoryParams.successCurrentDurabilityRate *
            successFactor *
            quality *
            (consolidation - currentBase);

    memory.logConsolidatedHalfLife = math.log(consolidation);
    memory.logCurrentHalfLife = math.log(current);
    return consolidation - consolidationBefore;
  }

  /// Causal learning from productive practice that did not test retrieval, or
  /// tested it and failed.
  ///
  /// Moves an existing activation anchor partway toward the present and
  /// restores current durability partway toward consolidation. It writes no
  /// factual retrieval success and grows no consolidation, so supported
  /// practice helps reacquisition without manufacturing an event.
  void _restoreFromSupportedPractice({
    required MaterialMemoryState memory,
    required GuidanceContext guidance,
    required double quality,
    required DateTime at,
  }) {
    final memoryParams = params.materialMemory;
    final practiceFactor = switch (guidance.independence) {
      0 => memoryParams.supportedPracticeFactorConcurrentCues,
      1 => memoryParams.supportedPracticeFactorNotesPreviewed,
      _ => memoryParams.supportedPracticeFactorUnguided,
    };

    final anchor = memory.memoryAnchorAt;
    if (anchor != null) {
      final fraction =
          memoryParams.supportedActivationRestorationRate *
          practiceFactor *
          quality;
      memory.memoryAnchorAt = anchor.plusDays(fraction * anchor.daysUntil(at));
    }

    final current = memory.currentHalfLifeDays;
    memory.logCurrentHalfLife = math.log(
      current +
          memoryParams.supportedCurrentDurabilityRate *
              practiceFactor *
              quality *
              (memory.consolidatedHalfLifeDays - current),
    );
  }
}

/// Which prediction each competency's evidence is measured against.
enum _Channel { motor, topology, coordination }

_Channel _channelOf(Competency competency) {
  if (competency.isTopology) return _Channel.topology;
  return coordinationCompetencies.contains(competency)
      ? _Channel.coordination
      : _Channel.motor;
}
