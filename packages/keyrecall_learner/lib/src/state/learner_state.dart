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
/// independently available ([materialMemory]), and whether a material under
/// one execution context deviates from what the shared competencies predict
/// ([materialExecution]).
///
/// Short-lived scheduling context belongs to session state instead, so a
/// temporary session condition is never stored as persistent ability.
class LearnerState {
  /// Belief about each transferable competency, keyed by competency.
  final Map<Competency, CompetencyState> competencies;

  /// Memory state per material, keyed by material id.
  final Map<String, MaterialMemoryState> materialMemory;

  /// Execution residual per material, hand configuration, and hand motion.
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
    LearnerParams params, {
    required String familyId,
  }) => materialExecution.putIfAbsent(
    context,
    () => MaterialExecutionState.prior(
      context,
      familyId,
      at,
      params.materialExecution,
    ),
  );

  /// Whether [competency] has ever received informative evidence.
  ///
  /// The domain question every prerequisite really wants, asked once here so
  /// policy does not have to know how evidence is represented. A mean cannot
  /// answer it: placement seeds every competency at a value chosen from what
  /// the learner said about themselves, so a mean above a threshold may mean
  /// somebody has demonstrated something or may mean they were asked a
  /// question at onboarding and answered it optimistically. Those are
  /// different claims, and a gate that cannot tell them apart is admitting on
  /// a self-report.
  bool isObserved(Competency competency) =>
      this.competency(competency).lastEvidenceAt != null;

  /// Whether this hand has ever played [materialId] informatively.
  ///
  /// Execution residuals are the one thing learner state keys by hand as well
  /// as by material, which makes them the only place a hand-scoped question
  /// about a specific scale can be answered at all. Memory is per material:
  /// it knows a scale was retrieved and not which hand was playing.
  /// Motion-agnostic, deliberately. The question is whether this hand
  /// configuration has met this material at all, which parallel and contrary
  /// hands-together work both answer; where they differ is what each has
  /// demonstrated, which the frontiers keep apart.
  bool hasPlayed(String materialId, HandConfiguration hands) =>
      materialExecution.entries.any(
        (entry) =>
            entry.key.$1 == materialId &&
            entry.key.$2 == hands &&
            entry.value.lastEvidenceAt != null,
      );

  /// Requires every propagating layer to stand exactly at [now].
  ///
  /// [lastPropagatedAt] cannot answer this. A maximum says nothing is ahead of
  /// [now]; it says nothing about a layer left behind, and a layer behind its
  /// own evidence produces a state that decodes as impossible. Propagation
  /// advances all of them together, so anything else is a caller that moved
  /// one by hand.
  ///
  /// Memory is deliberately absent: retrievability is computed on demand from
  /// the activation anchor rather than propagated, so a memory state has no
  /// timestamp to be aligned. What it does constrain is its own observation
  /// history, which the update path checks where it reads it.
  ///
  /// Throws [ArgumentError] naming the first layer that disagrees.
  void requireAlignedAt(DateTime now) {
    for (final state in competencies.values) {
      _requireLayerAt(
        now,
        state.updatedAt,
        '${state.competency.id} competency',
      );
    }
    for (final state in materialExecution.values) {
      _requireLayerAt(
        now,
        state.updatedAt,
        '${state.materialId}/${state.hands.id} residual',
      );
    }
  }

  static void _requireLayerAt(DateTime now, DateTime reached, String subject) {
    if (reached == now) return;
    throw ArgumentError.value(
      now,
      'at',
      '$subject stands at ${reached.toIso8601String()}; propagate the whole '
          'state to the attempt first',
    );
  }

  /// The instant every propagating layer has been advanced to.
  ///
  /// Layers are created at different times, so this is the latest of them:
  /// the point this state as a whole is current as of. A summary, not a
  /// guarantee: [requireAlignedAt] is what establishes alignment.
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

  /// Takes on [other]'s values in place, layer by layer.
  ///
  /// How a transition computed on a copy is committed back. Every layer that
  /// already exists keeps its identity, so a caller holding one competency or
  /// one material's memory goes on holding the same object. A layer the
  /// transition created arrives as a copy, and one it never had is dropped.
  void adoptFrom(LearnerState other) {
    for (final entry in other.competencies.entries) {
      competencies[entry.key]!.adoptFrom(entry.value);
    }

    materialMemory.removeWhere(
      (key, _) => !other.materialMemory.containsKey(key),
    );
    for (final entry in other.materialMemory.entries) {
      final held = materialMemory[entry.key];
      if (held == null) {
        materialMemory[entry.key] = entry.value.copy();
      } else {
        held.adoptFrom(entry.value);
      }
    }

    materialExecution.removeWhere(
      (key, _) => !other.materialExecution.containsKey(key),
    );
    for (final entry in other.materialExecution.entries) {
      final held = materialExecution[entry.key];
      if (held == null) {
        materialExecution[entry.key] = entry.value.copy();
      } else {
        held.adoptFrom(entry.value);
      }
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
