import 'package:keyrecall_domain/keyrecall_domain.dart';

import '../params/learner_params.dart';
import 'competency_state.dart';
import 'material_execution_state.dart';
import 'material_memory_state.dart';
import 'monotonic_time.dart';

/// What a learner says about their own experience at placement.
///
/// Self-report shifts the starting competency means but never makes the model
/// confident, so direct performance can override it quickly.
enum PlacementTier {
  beginner('BEGINNER'),
  someExperience('SOME_EXPERIENCE'),
  advanced('ADVANCED');

  const PlacementTier(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The tier with the given [id].
  ///
  /// Throws [ArgumentError] when no tier matches.
  static PlacementTier fromId(String id) => values.firstWhere(
    (tier) => tier.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown placement tier'),
  );

  /// The starting competency mean for this tier.
  double priorMean(PlacementParams params) => switch (this) {
    PlacementTier.beginner => params.beginnerMean,
    PlacementTier.someExperience => params.someExperienceMean,
    PlacementTier.advanced => params.advancedMean,
  };
}

/// Everything KeyRecall persistently believes about one learner.
///
/// Three layers, each answering a different question: what transferable
/// technique the learner has ([competencies]), whether one exact scale is
/// independently available ([materialMemory]), and whether a material and
/// hand context deviates from what the shared competencies predict
/// ([materialExecution]).
///
/// Short-lived scheduling context belongs to session state instead, so a
/// temporary session condition is never stored as persistent ability.
class LearnerState {
  /// Belief about each transferable competency, keyed by competency.
  final Map<Competency, CompetencyState> competencies;

  /// Memory state per material, keyed by material id.
  final Map<String, MaterialMemoryState> materialMemory;

  /// Execution residual per material and hand configuration.
  final Map<ExecutionContext, MaterialExecutionState> materialExecution;

  LearnerState({
    required this.competencies,
    Map<String, MaterialMemoryState>? materialMemory,
    Map<ExecutionContext, MaterialExecutionState>? materialExecution,
  }) : materialMemory = materialMemory ?? {},
       materialExecution = materialExecution ?? {};

  /// A cold-start state with every competency at the configured prior.
  ///
  /// Pass [competencyPriorMean] to start from something other than the
  /// registry's prior; [LearnerState.atPlacement] is the self-report path.
  factory LearnerState.cold(
    LearnerParams params, {
    required DateTime at,
    double? competencyPriorMean,
  }) => LearnerState(
    competencies: {
      for (final competency in Competency.values)
        competency: CompetencyState(
          competency: competency,
          mean: competencyPriorMean ?? params.competency.priorMean,
          variance: params.competency.priorVariance,
          updatedAt: at,
        ),
    },
  );

  /// A cold-start state seeded from a self-report [tier].
  ///
  /// Shifts every competency mean to the tier's value while holding
  /// uncertainty broad, so a few real attempts can overturn the self-report.
  factory LearnerState.atPlacement(
    PlacementTier tier,
    LearnerParams params, {
    required DateTime at,
  }) {
    final state = LearnerState.cold(
      params,
      at: at,
      competencyPriorMean: tier.priorMean(params.placement),
    );
    for (final competency in state.competencies.values) {
      competency.variance = params.placement.priorVarianceBroad;
    }
    return state;
  }

  /// The belief about [competency].
  CompetencyState competency(Competency competency) =>
      competencies[competency]!;

  /// The memory state for [materialId], creating it at its priors if absent.
  MaterialMemoryState materialMemoryFor(
    String materialId,
    LearnerParams params,
  ) => materialMemory.putIfAbsent(
    materialId,
    () => MaterialMemoryState.prior(materialId, params.materialMemory),
  );

  /// The execution residual for [context], creating it at its priors if
  /// absent.
  MaterialExecutionState materialExecutionFor(
    ExecutionContext context,
    DateTime at,
    LearnerParams params,
  ) => materialExecution.putIfAbsent(
    context,
    () => MaterialExecutionState.prior(context, at, params.materialExecution),
  );

  /// The instant every propagating layer has been advanced to.
  ///
  /// Layers are created at different times, so this is the latest of them:
  /// the point this state as a whole is current as of.
  DateTime get lastPropagatedAt {
    var latest = competencies.values.first.updatedAt;
    for (final state in competencies.values) {
      if (state.updatedAt.isAfter(latest)) latest = state.updatedAt;
    }
    for (final state in materialExecution.values) {
      if (state.updatedAt.isAfter(latest)) latest = state.updatedAt;
    }
    return latest;
  }

  /// Advances every layer to [now] without evidence.
  ///
  /// Memory needs no propagation: retrievability is computed on demand from
  /// the activation anchor rather than stored as a value that would go stale
  /// between calls.
  ///
  /// Throws [ArgumentError] if [now] precedes [lastPropagatedAt], checked
  /// before anything is written so a rejected call cannot leave some layers
  /// advanced and others behind.
  void propagateTo(DateTime now, LearnerParams params) {
    requireForwardPropagation(now, lastPropagatedAt, 'this learner state');
    for (final state in competencies.values) {
      state.propagateTo(now, params.competency);
    }
    for (final state in materialExecution.values) {
      state.propagateTo(now, params.materialExecution);
    }
  }

  /// An independent deep copy, for recording state before and after an
  /// attempt.
  LearnerState copy() => LearnerState(
    competencies: {
      for (final entry in competencies.entries) entry.key: entry.value.copy(),
    },
    materialMemory: {
      for (final entry in materialMemory.entries) entry.key: entry.value.copy(),
    },
    materialExecution: {
      for (final entry in materialExecution.entries)
        entry.key: entry.value.copy(),
    },
  );

  @override
  String toString() =>
      'LearnerState(${competencies.length} competencies, '
      '${materialMemory.length} materials, '
      '${materialExecution.length} execution contexts)';
}
