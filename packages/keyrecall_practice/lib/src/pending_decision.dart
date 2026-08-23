import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

/// A decision that has been made and presented, but not yet answered.
///
/// Persisted before the exercise reaches the learner, so a crash between
/// presenting and observing leaves evidence of what was asked. It is
/// deliberately *not* part of the journal: an attempt with no outcome produced
/// no evidence and moved no state, and putting it in the replay stream would
/// invite exactly the manufactured outcome this exists to prevent.
///
/// It holds everything needed to complete the attempt once an outcome arrives,
/// so committing never has to decide again. Re-deciding would ask a state that
/// has since moved on, and would silently answer a different question than the
/// one the learner was shown.
@immutable
class PendingDecision {
  /// The id the completed attempt will carry, and the idempotency key.
  ///
  /// Chosen here rather than at commit, which is what makes recovery decidable:
  /// after a crash, the journal either already contains this id or it does not.
  final String attemptId;

  /// Whose attempt this is.
  final String profileId;

  /// The sitting it belongs to.
  final String sessionId;

  /// Position within that sitting.
  final int indexInSession;

  /// The journal sequence the completed attempt will occupy.
  final int journalSequence;

  /// When the decision was made and the state was current, in UTC.
  ///
  /// The model timestamp of the attempt. The prediction was conditioned on the
  /// state as of this instant, so replay has to use it rather than whenever the
  /// outcome happened to arrive.
  final DateTime decidedAt;

  /// Which model definitions made the decision.
  final ModelProvenance provenance;

  /// What was presented.
  final Exercise exercise;

  /// Why it was chosen.
  final SchedulerDecision decision;

  /// Hash of the state the decision was made from.
  final String stateBeforeHash;

  PendingDecision({
    required this.attemptId,
    required this.profileId,
    required this.sessionId,
    required this.indexInSession,
    required this.journalSequence,
    required DateTime decidedAt,
    required this.provenance,
    required this.exercise,
    required this.decision,
    required this.stateBeforeHash,
  }) : decidedAt = decidedAt.toUtc();

  /// Writes the pending decision.
  Map<String, Object?> toJson() => {
    'schema_version': attemptSchemaVersion,
    'attempt_id': attemptId,
    'profile_id': profileId,
    'session_id': sessionId,
    'index_in_session': indexInSession,
    'journal_sequence': journalSequence,
    'decided_at': encodeTime(decidedAt),
    'provenance': {
      'learner_model_version': provenance.learnerModelVersion,
      'scheduler_model_version': provenance.schedulerModelVersion,
      'app_build_version': provenance.appBuildVersion,
    },
    'exercise': encodeExercise(exercise),
    'decision': encodeDecision(decision, encodePrediction),
    'state_before_hash': stateBeforeHash,
  };

  /// Reads a pending decision back.
  ///
  /// Throws [JournalFormatException] on anything unreadable. A pending slot
  /// that cannot be understood is not something to guess at: it names an
  /// exercise a person may have been shown.
  factory PendingDecision.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != attemptSchemaVersion) {
      throw JournalFormatException(
        'pending decision schema version $version is not readable by this '
        'build, which writes version $attemptSchemaVersion',
      );
    }

    const location = 'pending decision';
    final provenanceJson = requireMap(json, 'provenance', location: location);
    return PendingDecision(
      attemptId: requireString(json, 'attempt_id', location: location),
      profileId: requireString(json, 'profile_id', location: location),
      sessionId: requireString(json, 'session_id', location: location),
      indexInSession: requireInt(json, 'index_in_session', location: location),
      journalSequence: requireInt(json, 'journal_sequence', location: location),
      decidedAt: requireTime(json, 'decided_at', location: location),
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
        appBuildVersion: asOptionalString(
          provenanceJson['app_build_version'],
          'app_build_version',
          location: location,
        ),
      ),
      exercise: decodeExercise(
        requireMap(json, 'exercise', location: location),
        location: location,
      ),
      decision: decodeDecision(
        requireMap(json, 'decision', location: location),
        (prediction) => decodePrediction(prediction, location: location),
        location: location,
      ),
      stateBeforeHash: requireString(
        json,
        'state_before_hash',
        location: location,
      ),
    );
  }

  /// The completed attempt this decision becomes, once [outcome] is known.
  AttemptRecord complete({
    required Outcome outcome,
    required EvidenceWeights weights,
    required MemoryUpdateDiagnostics memoryUpdate,
    required String stateAfterHash,
    DateTime? observedWallTime,
  }) => AttemptRecord(
    journalSequence: journalSequence,
    identity: AttemptIdentity(
      profileId: profileId,
      attemptId: attemptId,
      sessionId: sessionId,
      indexInSession: indexInSession,
      occurredAt: decidedAt,
    ),
    observedWallTime: observedWallTime,
    provenance: provenance,
    exercise: exercise,
    decision: decision,
    outcome: outcome,
    weights: weights,
    memoryUpdate: memoryUpdate,
    stateBeforeHash: stateBeforeHash,
    stateAfterHash: stateAfterHash,
  );

  @override
  String toString() =>
      'PendingDecision($attemptId, ${exercise.material.materialId}, '
      'presented ${encodeTime(decidedAt)})';
}
