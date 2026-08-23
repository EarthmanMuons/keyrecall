import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'canonical_json.dart';
import 'codecs/domain_codec.dart';
import 'codecs/learner_codec.dart';
import 'codecs/scheduler_codec.dart';
import 'schema.dart';

/// Which model definitions interpreted this attempt.
///
/// Recorded on every attempt rather than once per journal, because a journal
/// outlives any single model version and a record must stay interpretable on
/// its own. A version identifier that cannot recover its parameters is not
/// enough for replay, so these must resolve to immutable definitions.
@immutable
class ModelProvenance {
  /// The learner parameter registry in force.
  final String learnerModelVersion;

  /// The scheduler policy configuration in force.
  final String schedulerModelVersion;

  /// The app build that recorded it, when the caller knows.
  final String? appBuildVersion;

  const ModelProvenance({
    required this.learnerModelVersion,
    required this.schedulerModelVersion,
    this.appBuildVersion,
  });

  /// The provenance of a model and scheduler pair as currently configured.
  factory ModelProvenance.of({
    required LearnerParams learnerParams,
    required String schedulerModelVersion,
    String? appBuildVersion,
  }) => ModelProvenance(
    learnerModelVersion: learnerParams.modelVersion,
    schedulerModelVersion: schedulerModelVersion,
    appBuildVersion: appBuildVersion,
  );

  @override
  bool operator ==(Object other) =>
      other is ModelProvenance &&
      other.learnerModelVersion == learnerModelVersion &&
      other.schedulerModelVersion == schedulerModelVersion &&
      other.appBuildVersion == appBuildVersion;

  @override
  int get hashCode =>
      Object.hash(learnerModelVersion, schedulerModelVersion, appBuildVersion);

  @override
  String toString() =>
      'ModelProvenance($learnerModelVersion, $schedulerModelVersion)';
}

/// Which attempt this is, and when.
///
/// [indexInSession] is what orders attempts, not [occurredAt]. A wall clock
/// can be corrected backward between attempts; a monotonic index cannot, so
/// history keeps its order even when the clock does not.
@immutable
class AttemptIdentity {
  /// Locally unique id, and the idempotency key for appending.
  final String attemptId;

  /// The practice sitting this belongs to.
  final String sessionId;

  /// Position within that sitting, counting from zero.
  final int indexInSession;

  /// When the attempt happened, in UTC.
  final DateTime occurredAt;

  AttemptIdentity({
    required this.attemptId,
    required this.sessionId,
    required this.indexInSession,
    required DateTime occurredAt,
  }) : occurredAt = occurredAt.toUtc() {
    if (attemptId.isEmpty) {
      throw ArgumentError.value(attemptId, 'attemptId', 'must not be empty');
    }
    if (sessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (indexInSession < 0) {
      throw ArgumentError.value(
        indexInSession,
        'indexInSession',
        'must not be negative',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AttemptIdentity &&
      other.attemptId == attemptId &&
      other.sessionId == sessionId &&
      other.indexInSession == indexInSession &&
      other.occurredAt == occurredAt;

  @override
  int get hashCode =>
      Object.hash(attemptId, sessionId, indexInSession, occurredAt);

  @override
  String toString() =>
      'AttemptIdentity($attemptId, $sessionId#$indexInSession)';
}

/// One practice attempt, as history records it.
///
/// The journal is the source of truth: learner state is reproducible by
/// replaying these in order, and checkpoints are disposable acceleration.
/// A record therefore holds everything replay needs and nothing it can safely
/// recompute.
///
/// Four things are stored even though replay recomputes them: the presented
/// exercise, the prediction, the evidence weights, and the memory attribution.
/// They are the audit trace. Replay recomputes each and compares, which is how
/// a model change that would silently reinterpret history gets caught instead
/// of being absorbed.
@immutable
class AttemptRecord {
  /// The wire format this record was written in.
  final int schemaVersion;

  /// Which attempt, and when.
  final AttemptIdentity identity;

  /// Which model definitions interpreted it.
  final ModelProvenance provenance;

  /// The exercise actually presented.
  final Exercise exercise;

  /// Why the scheduler chose it, or null when it was not scheduler-selected.
  ///
  /// Absent for a scripted or diagnostic attempt. Present for every attempt the
  /// production loop presents.
  final SchedulerDecision? decision;

  /// What was observed.
  final Outcome outcome;

  /// How informative it was, per layer.
  final EvidenceWeights weights;

  /// Where its consolidation change came from.
  final MemoryUpdateDiagnostics memoryUpdate;

  /// Content hash of the learner state the decision was made from.
  ///
  /// Not the state itself: a full snapshot per attempt would duplicate almost
  /// everything. Replay rebuilds the state and checks it hashes to this, which
  /// catches divergence without the storage cost.
  final String? stateBeforeHash;

  /// Content hash of the state the update produced.
  final String? stateAfterHash;

  const AttemptRecord({
    required this.identity,
    required this.provenance,
    required this.exercise,
    required this.outcome,
    required this.weights,
    required this.memoryUpdate,
    this.decision,
    this.stateBeforeHash,
    this.stateAfterHash,
    this.schemaVersion = attemptSchemaVersion,
  });

  /// This record with state hashes attached.
  AttemptRecord withStateHashes({
    required String before,
    required String after,
  }) => AttemptRecord(
    identity: identity,
    provenance: provenance,
    exercise: exercise,
    outcome: outcome,
    weights: weights,
    memoryUpdate: memoryUpdate,
    decision: decision,
    stateBeforeHash: before,
    stateAfterHash: after,
    schemaVersion: schemaVersion,
  );

  /// Writes this record.
  Map<String, Object?> toJson() => {
    'record_type': JournalRecordType.attempt.id,
    'schema_version': schemaVersion,
    'attempt_id': identity.attemptId,
    'session_id': identity.sessionId,
    'index_in_session': identity.indexInSession,
    'occurred_at': encodeTime(identity.occurredAt),
    'provenance': {
      'learner_model_version': provenance.learnerModelVersion,
      'scheduler_model_version': provenance.schedulerModelVersion,
      'app_build_version': provenance.appBuildVersion,
    },
    'exercise': encodeExercise(exercise),
    'decision': decision == null
        ? null
        : encodeDecision(decision!, encodePrediction),
    'outcome': encodeOutcome(outcome),
    'evidence_weights': encodeEvidenceWeights(weights),
    'memory_update': encodeMemoryDiagnostics(memoryUpdate),
    'state_before_hash': stateBeforeHash,
    'state_after_hash': stateAfterHash,
  };

  /// Reads a record back.
  ///
  /// Throws [JournalFormatException] for an unreadable or unknown-version
  /// record. A journal reader must not guess: this is the historical source of
  /// truth, and a misread record rewrites the past.
  factory AttemptRecord.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != attemptSchemaVersion) {
      throw JournalFormatException(
        'attempt schema version $version is not readable by this build, which '
        'writes version $attemptSchemaVersion; a versioned upgrade function '
        'must run first',
      );
    }

    final attemptId = requireString(json, 'attempt_id');
    final location = 'attempt $attemptId';
    final provenanceJson = requireMap(json, 'provenance', location: location);
    final decisionJson = json['decision'];

    return AttemptRecord(
      schemaVersion: version,
      identity: AttemptIdentity(
        attemptId: attemptId,
        sessionId: requireString(json, 'session_id', location: location),
        indexInSession: requireInt(
          json,
          'index_in_session',
          location: location,
        ),
        occurredAt: requireTime(json, 'occurred_at', location: location),
      ),
      provenance: ModelProvenance(
        learnerModelVersion: requireString(
          provenanceJson,
          'learner_model_version',
          location: location,
        ),
        schedulerModelVersion: requireString(
          provenanceJson,
          'scheduler_model_version',
          location: location,
        ),
        appBuildVersion: provenanceJson['app_build_version'] as String?,
      ),
      exercise: decodeExercise(
        requireMap(json, 'exercise', location: location),
        location: location,
      ),
      decision: decisionJson == null
          ? null
          : decodeDecision(
              decisionJson as Map<String, Object?>,
              (prediction) => decodePrediction(prediction, location: location),
              location: location,
            ),
      outcome: decodeOutcome(
        requireMap(json, 'outcome', location: location),
        location: location,
      ),
      weights: decodeEvidenceWeights(
        requireMap(json, 'evidence_weights', location: location),
        location: location,
      ),
      memoryUpdate: decodeMemoryDiagnostics(
        requireMap(json, 'memory_update', location: location),
        location: location,
      ),
      stateBeforeHash: json['state_before_hash'] as String?,
      stateAfterHash: json['state_after_hash'] as String?,
    );
  }

  @override
  String toString() =>
      'AttemptRecord(${identity.attemptId}, '
      '${exercise.material.materialId}, ${outcome.retrieval.name})';
}
