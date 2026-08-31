import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'attempt_trace.dart';

/// Renders [trace] as a JSON line, one per attempt.
///
/// The shape came from the research prototype this model was designed in, so a
/// run could be diffed against it attempt by attempt. That prototype is
/// retired; the shape stays because the recorded runs and external analysis
/// read it. Timestamps become days elapsed from [epoch].
///
/// This is the comparison format, not the production journal format: it exists
/// to prove the port reproduces the reference, and it should follow the
/// prototype if the two ever diverge.
Map<String, Object?> attemptTraceToJson(
  AttemptTrace trace, {
  required DateTime epoch,
}) {
  final q = trace.structuralQ;
  final loadings = trace.loadings;
  return {
    'attempt_index': trace.attemptIndex,
    'at_days': epoch.daysUntil(trace.at),
    'profile': trace.profile.id,
    'exercise': _exerciseJson(trace.exercise),
    'Q': {
      for (final competency in Competency.values)
        competency.id: q.contains(competency) ? 1 : 0,
    },
    'q': {
      for (final competency in Competency.values)
        competency.id: loadings[competency] ?? 0.0,
    },
    'predicted_independent_retrieval_p': trace.prediction.independentRetrievalP,
    'predicted_material_available_p': trace.prediction.materialAvailableP,
    'predicted_execution_p': trace.prediction.executionP,
    'predicted_topology_p': trace.prediction.topologyP,
    'predicted_p': trace.prediction.overallP,
    'outcome': _outcomeJson(trace.outcome),
    'evidence_weights': {
      'competencies': {
        for (final competency in Competency.values)
          competency.id: trace.weights[competency],
      },
      'material_execution': trace.weights.materialExecution,
      'material_memory': trace.weights.materialMemory,
    },
    'memory_update': {
      'consolidation_delta_from_retrieval_inference':
          trace.memoryUpdate.consolidationDeltaFromRetrievalInference,
      'consolidation_delta_from_causal_formation':
          trace.memoryUpdate.consolidationDeltaFromCausalFormation,
    },
    'state_before': learnerStateToJson(trace.stateBefore, epoch: epoch),
    'state_after': learnerStateToJson(trace.stateAfter, epoch: epoch),
  };
}

Map<String, Object?> _exerciseJson(Exercise exercise) => {
  'material_id': exercise.material.materialId,
  'hands': exercise.conditions.hands.id,
  'octaves': exercise.conditions.octaves,
  'tempo_bpm': exercise.conditions.tempoBpm,
  'direction': exercise.conditions.direction.id,
  'guidance': {
    'notes_previewed': exercise.guidance.notesPreviewed,
    'concurrent_pitch_cues': exercise.guidance.concurrentPitchCues,
  },
  'opportunities':
      exercise.opportunities.map((opportunity) => opportunity.id).toList()
        ..sort(),
};

Map<String, Object?> _outcomeJson(Outcome outcome) => {
  'started': outcome.started,
  'completed': outcome.completed,
  'retrieval_succeeded': outcome.retrieval.jsonValue,
  'material_retrieval': outcome.materialRetrieval,
  'pitch_integrity': outcome.pitchIntegrity,
  'continuity': outcome.continuity,
  'temporal_stability': outcome.temporalStability,
  'achieved_tempo_ratio': outcome.achievedTempoRatio,
  'topology_accuracy': outcome.topologyAccuracy,
};

/// Renders [state] as a snapshot, in the same shape [attemptTraceToJson] uses.
Map<String, Object?> learnerStateToJson(
  LearnerState state, {
  required DateTime epoch,
}) {
  double? days(DateTime? at) => at == null ? null : epoch.daysUntil(at);

  return {
    'competencies': {
      for (final entry in state.competencies.entries)
        entry.key.id: {
          'mean': entry.value.mean,
          'variance': entry.value.variance,
        },
    },
    'material_memory': {
      for (final entry in state.materialMemory.entries)
        entry.key: {
          'current_half_life_days': entry.value.currentHalfLifeDays,
          'log_current_half_life': entry.value.logCurrentHalfLife,
          'current_half_life_uncertainty':
              entry.value.currentHalfLifeUncertainty,
          'consolidated_half_life_days': entry.value.consolidatedHalfLifeDays,
          'log_consolidated_half_life': entry.value.logConsolidatedHalfLife,
          'consolidated_log_half_life_variance':
              entry.value.consolidatedLogHalfLifeVariance,
          'cold_start_estimate': entry.value.coldStartEstimate,
          'logit_cold_start': entry.value.logitColdStart,
          'cold_start_uncertainty': entry.value.coldStartUncertainty,
          'memory_anchor_at': days(entry.value.memoryAnchorAt),
          'factual_last_retrieval_at': days(entry.value.factualLastRetrievalAt),
          'last_retrieval_attempt_at': days(entry.value.lastRetrievalAttemptAt),
        },
    },
    'material_execution': {
      for (final entry in state.materialExecution.entries)
        '${entry.key.$1}/${entry.key.$2.id}': {
          'residual_mean': entry.value.residualMean,
          'residual_variance': entry.value.residualVariance,
        },
    },
  };
}
