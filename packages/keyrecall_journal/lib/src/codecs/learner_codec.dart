import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import '../canonical_json.dart';
import '../schema.dart';

/// Writes the four predicted channels.
Map<String, Object?> encodePrediction(Prediction prediction) => {
  'independent_retrieval_p': prediction.independentRetrievalP,
  'material_available_p': prediction.materialAvailableP,
  'execution_p': prediction.executionP,
  'topology_p': prediction.topologyP,
};

/// Reads the four predicted channels back.
///
/// Overall success is deliberately not stored: it is the product of two of
/// these, and storing it would create a second place for it to be wrong.
Prediction decodePrediction(Map<String, Object?> json, {String? location}) =>
    Prediction(
      independentRetrievalP: requireDouble(
        json,
        'independent_retrieval_p',
        location: location,
      ),
      materialAvailableP: requireDouble(
        json,
        'material_available_p',
        location: location,
      ),
      executionP: requireDouble(json, 'execution_p', location: location),
      topologyP: requireDouble(json, 'topology_p', location: location),
    );

/// Writes what was observed.
///
/// `retrieval_succeeded` is `true`, `false`, or `null`, and `null` means
/// retrieval was never tested. It must never be read, queried, or analyzed as
/// failure.
Map<String, Object?> encodeOutcome(Outcome outcome) => {
  'started': outcome.started,
  'completed': outcome.completed,
  'retrieval_succeeded': outcome.retrieval.jsonValue,
  'material_retrieval': outcome.materialRetrieval,
  'pitch_integrity': outcome.pitchIntegrity,
  'continuity': outcome.continuity,
  'temporal_stability': outcome.temporalStability,
  'achieved_tempo_ratio': outcome.achievedTempoRatio,
  'topology_accuracy': outcome.topologyAccuracy,
  if (outcome.coordination != null) 'coordination': outcome.coordination,
};

/// Reads an outcome back, preserving the three-valued retrieval exactly.
Outcome decodeOutcome(Map<String, Object?> json, {String? location}) {
  final retrieval = json['retrieval_succeeded'];
  if (retrieval != null && retrieval is! bool) {
    throw JournalFormatException(
      'retrieval_succeeded must be true, false, or null, got $retrieval',
      location: location,
    );
  }

  return Outcome(
    started: requireBool(json, 'started', location: location),
    retrieval: FactualRetrieval.fromJson(retrieval as bool?),
    completed: requireBool(json, 'completed', location: location),
    materialRetrieval: requireDouble(
      json,
      'material_retrieval',
      location: location,
    ),
    pitchIntegrity: requireDouble(json, 'pitch_integrity', location: location),
    continuity: requireDouble(json, 'continuity', location: location),
    temporalStability: requireDouble(
      json,
      'temporal_stability',
      location: location,
    ),
    achievedTempoRatio: requireDouble(
      json,
      'achieved_tempo_ratio',
      location: location,
    ),
    topologyAccuracy: requireDouble(
      json,
      'topology_accuracy',
      location: location,
    ),
    // Absent means unmeasured, which is what every record written before
    // coordination existed says about it.
    coordination: json['coordination'] == null
        ? null
        : requireDouble(json, 'coordination', location: location),
  );
}

/// Writes the three evidence weights.
///
/// Competencies the attempt said nothing about are omitted rather than written
/// as zero, which keeps "not observed" and "observed as uninformative"
/// distinguishable in the record itself.
Map<String, Object?> encodeEvidenceWeights(EvidenceWeights weights) => {
  'competencies': {
    for (final entry in weights.competencies.entries) entry.key.id: entry.value,
  },
  'material_execution': weights.materialExecution,
  'material_memory': weights.materialMemory,
};

/// Reads the evidence weights back.
EvidenceWeights decodeEvidenceWeights(
  Map<String, Object?> json, {
  String? location,
}) {
  final competencies = requireMap(json, 'competencies', location: location);
  return EvidenceWeights(
    competencies: {
      for (final entry in competencies.entries)
        Competency.fromId(entry.key): asDouble(
          entry.value,
          'weight for ${entry.key}',
          location: location,
        ),
    },
    materialExecution: requireDouble(
      json,
      'material_execution',
      location: location,
    ),
    materialMemory: requireDouble(json, 'material_memory', location: location),
  );
}

/// Writes where an attempt's consolidation change came from.
Map<String, Object?> encodeMemoryDiagnostics(MemoryUpdateDiagnostics value) => {
  'consolidation_delta_from_retrieval_inference':
      value.consolidationDeltaFromRetrievalInference,
  'consolidation_delta_from_causal_formation':
      value.consolidationDeltaFromCausalFormation,
};

/// Reads the memory attribution back.
MemoryUpdateDiagnostics decodeMemoryDiagnostics(
  Map<String, Object?> json, {
  String? location,
}) => MemoryUpdateDiagnostics(
  consolidationDeltaFromRetrievalInference: requireDouble(
    json,
    'consolidation_delta_from_retrieval_inference',
    location: location,
  ),
  consolidationDeltaFromCausalFormation: requireDouble(
    json,
    'consolidation_delta_from_causal_formation',
    location: location,
  ),
);

/// Writes a complete learner state.
///
/// Every stored quantity is the one the model actually reasons with. Durability
/// is written in log space, and the consolidation variance is specifically the
/// posterior variance in log-half-life space rather than a generic confidence
/// score, so a later reader cannot mistake one for the other.
Map<String, Object?> encodeLearnerState(LearnerState state) => {
  'competencies': {
    for (final entry in state.competencies.entries)
      entry.key.id: {
        'mean': entry.value.mean,
        'variance': entry.value.variance,
        'updated_at': encodeTime(entry.value.updatedAt),
        'last_evidence_at': encodeOptionalTime(entry.value.lastEvidenceAt),
      },
  },
  'material_memory': {
    for (final entry in state.materialMemory.entries)
      entry.key: encodeMaterialMemory(entry.value),
  },
  'material_execution': {
    for (final entry in state.materialExecution.entries)
      '${entry.key.$1}/${entry.key.$2.id}/${entry.key.$3.id}': {
        'material_id': entry.value.materialId,
        'hands': entry.value.hands.id,
        'hand_motion': entry.value.handMotion.id,
        'residual_mean': entry.value.residualMean,
        'residual_variance': entry.value.residualVariance,
        'updated_at': encodeTime(entry.value.updatedAt),
        'last_evidence_at': encodeOptionalTime(entry.value.lastEvidenceAt),
        'demonstrated_tempo_by_octaves': {
          for (final span in entry.value.demonstratedTempoByOctaves.entries)
            '${span.key}': span.value,
        },
        'paced_tempo_bpm': entry.value.pacedTempoBpm,
        'coordination_ready_tempo_by_octaves': {
          for (final span
              in entry.value.coordinationReadyTempoByOctaves.entries)
            '${span.key}': span.value,
        },
      },
  },
};

/// Writes one material's memory state.
Map<String, Object?> encodeMaterialMemory(MaterialMemoryState memory) => {
  'material_id': memory.materialId,
  'log_current_half_life': memory.logCurrentHalfLife,
  'current_half_life_uncertainty': memory.currentHalfLifeUncertainty,
  'log_consolidated_half_life': memory.logConsolidatedHalfLife,
  'consolidated_log_half_life_variance': memory.consolidatedLogHalfLifeVariance,
  'logit_cold_start': memory.logitColdStart,
  'cold_start_uncertainty': memory.coldStartUncertainty,
  'memory_anchor_at': encodeOptionalTime(memory.memoryAnchorAt),
  'factual_last_retrieval_at': encodeOptionalTime(
    memory.factualLastRetrievalAt,
  ),
  'last_retrieval_attempt_at': encodeOptionalTime(
    memory.lastRetrievalAttemptAt,
  ),
  'established_independence': memory.establishedIndependence,
  'established_independence_at': encodeOptionalTime(
    memory.establishedIndependenceAt,
  ),
};

/// Reads a complete learner state back, validating every invariant.
///
/// Persisted state is untrusted input. A broken envelope or an impossible
/// timestamp ordering fails here rather than propagating into a prediction.
LearnerState decodeLearnerState(
  Map<String, Object?> json, {
  required LearnerParams params,
  String? location,
}) {
  final competencyJson = requireMap(json, 'competencies', location: location);
  final competencies = <Competency, CompetencyState>{};
  for (final competency in Competency.values) {
    final entry = requireMap(competencyJson, competency.id, location: location);
    final variance = requireDouble(entry, 'variance', location: location);
    if (variance <= 0) {
      throw JournalFormatException(
        '${competency.id} variance must be positive, got $variance',
        location: location,
      );
    }
    competencies[competency] = CompetencyState(
      competency: competency,
      mean: requireDouble(entry, 'mean', location: location),
      variance: variance,
      updatedAt: requireTime(entry, 'updated_at', location: location),
      lastEvidenceAt: readOptionalTime(
        entry,
        'last_evidence_at',
        location: location,
      ),
    );
  }

  final memoryJson = requireMap(json, 'material_memory', location: location);
  final materialMemory = {
    for (final entry in memoryJson.entries)
      entry.key: decodeMaterialMemory(
        asMap(entry.value, 'memory for ${entry.key}', location: location),
        params: params,
        location: location,
      ),
  };

  final executionJson = requireMap(
    json,
    'material_execution',
    location: location,
  );
  final materialExecution = <ExecutionContext, MaterialExecutionState>{};
  for (final entry in executionJson.entries) {
    final value = asMap(
      entry.value,
      'execution residual for ${entry.key}',
      location: location,
    );
    final variance = requireDouble(
      value,
      'residual_variance',
      location: location,
    );
    if (variance <= 0) {
      throw JournalFormatException(
        'residual variance must be positive, got $variance',
        location: location,
      );
    }
    final residual = MaterialExecutionState(
      materialId: requireString(value, 'material_id', location: location),
      hands: HandConfiguration.fromId(
        requireString(value, 'hands', location: location),
      ),
      handMotion: HandMotion.fromId(
        requireString(value, 'hand_motion', location: location),
      ),
      residualMean: requireDouble(value, 'residual_mean', location: location),
      residualVariance: variance,
      updatedAt: requireTime(value, 'updated_at', location: location),
      lastEvidenceAt: readOptionalTime(
        value,
        'last_evidence_at',
        location: location,
      ),
      demonstratedTempoByOctaves: {
        for (final span in requireMap(
          value,
          'demonstrated_tempo_by_octaves',
          location: location,
        ).entries)
          int.parse(span.key): asDouble(
            span.value,
            span.key,
            location: location,
          ),
      },
      pacedTempoBpm: requireDouble(
        value,
        'paced_tempo_bpm',
        location: location,
      ),
      coordinationReadyTempoByOctaves: {
        for (final span in requireMap(
          value,
          'coordination_ready_tempo_by_octaves',
          location: location,
        ).entries)
          int.parse(span.key): asDouble(
            span.value,
            span.key,
            location: location,
          ),
      },
    );
    materialExecution[residual.context] = residual;
  }

  return LearnerState(
    competencies: competencies,
    materialMemory: materialMemory,
    materialExecution: materialExecution,
  );
}

/// Reads one material's memory state back and validates it.
///
/// The checks are the persisted-state contract: a positive current durability
/// inside the consolidation envelope, positive uncertainties, and retrieval
/// history that cannot claim a success without an anchor at or after it.
MaterialMemoryState decodeMaterialMemory(
  Map<String, Object?> json, {
  required LearnerParams params,
  String? location,
}) {
  final memory = MaterialMemoryState(
    materialId: requireString(json, 'material_id', location: location),
    logCurrentHalfLife: requireDouble(
      json,
      'log_current_half_life',
      location: location,
    ),
    currentHalfLifeUncertainty: requireDouble(
      json,
      'current_half_life_uncertainty',
      location: location,
    ),
    logConsolidatedHalfLife: requireDouble(
      json,
      'log_consolidated_half_life',
      location: location,
    ),
    consolidatedLogHalfLifeVariance: requireDouble(
      json,
      'consolidated_log_half_life_variance',
      location: location,
    ),
    logitColdStart: requireDouble(json, 'logit_cold_start', location: location),
    coldStartUncertainty: requireDouble(
      json,
      'cold_start_uncertainty',
      location: location,
    ),
    memoryAnchorAt: readOptionalTime(
      json,
      'memory_anchor_at',
      location: location,
    ),
    factualLastRetrievalAt: readOptionalTime(
      json,
      'factual_last_retrieval_at',
      location: location,
    ),
    lastRetrievalAttemptAt: readOptionalTime(
      json,
      'last_retrieval_attempt_at',
      location: location,
    ),
    establishedIndependence: asOptionalInt(
      json['established_independence'],
      'established_independence',
      location: location,
    ),
    establishedIndependenceAt: readOptionalTime(
      json,
      'established_independence_at',
      location: location,
    ),
  );
  validateMaterialMemory(memory, params: params, location: location);
  return memory;
}

/// Enforces the persisted-state invariants on [memory].
///
/// Throws [JournalFormatException] on the first violation.
void validateMaterialMemory(
  MaterialMemoryState memory, {
  required LearnerParams params,
  String? location,
}) {
  void fail(String message) => throw JournalFormatException(
    '${memory.materialId}: $message',
    location: location,
  );

  final current = memory.currentHalfLifeDays;
  final consolidated = memory.consolidatedHalfLifeDays;
  if (!(current > 0)) {
    fail('current half-life must be positive, got $current');
  }
  if (current > consolidated) {
    fail(
      'current half-life ($current d) exceeds consolidation ($consolidated d)',
    );
  }
  if (consolidated > params.materialMemory.maxMemoryHalfLifeDays) {
    fail(
      'consolidation ($consolidated d) exceeds the configured bound '
      '(${params.materialMemory.maxMemoryHalfLifeDays} d)',
    );
  }
  if (!(memory.currentHalfLifeUncertainty > 0)) {
    fail('current half-life uncertainty must be positive');
  }
  if (!(memory.coldStartUncertainty > 0)) {
    fail('cold-start uncertainty must be positive');
  }
  if (!(memory.consolidatedLogHalfLifeVariance > 0)) {
    fail('consolidation posterior variance must be positive');
  }
  if (!memory.logitColdStart.isFinite) {
    fail('cold-start logit must be finite');
  }

  final anchor = memory.memoryAnchorAt;
  final factual = memory.factualLastRetrievalAt;
  if (factual != null && anchor == null) {
    fail('a factual retrieval success requires an activation anchor');
  }
  if (factual != null && anchor != null && factual.isAfter(anchor)) {
    fail('factual retrieval success is later than the activation anchor');
  }
}

/// Rebuilds the state a never-practiced material starts from.
///
/// Kept beside the decoder because "new material" and "material absent from
/// the journal" must produce the same thing, and because anchor existence, not
/// factual-success existence, is what decides whether the cold-start belief or
/// the decay curve is operative.
MaterialMemoryState newMaterialMemory(
  String materialId,
  LearnerParams params,
) => MaterialMemoryState.prior(materialId, params.materialMemory);

/// The natural log of [days], for callers writing durability by hand.
double logDays(double days) => math.log(days);
