import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'attempt_record.dart';
import 'canonical_json.dart' as canonical;
import 'canonical_json.dart';
import 'codecs/learner_codec.dart';
import 'schema.dart';

/// A learner state saved so a later start does not have to replay everything.
///
/// Disposable by design. The journal is the source of truth, and a checkpoint
/// is only an accelerator: deleting every checkpoint must cost time and nothing
/// else. That is why one carries the hash of its own content and the point in
/// history it covers, and why a mismatch is grounds to discard it rather than
/// to trust it over the journal.
@immutable
class LearnerStateCheckpoint {
  /// The wire format this checkpoint was written in.
  final int schemaVersion;

  /// Which profile's state this is.
  ///
  /// A checkpoint restored under the wrong profile would hand one person
  /// another person's learning history, so ownership travels with the state
  /// rather than with wherever it happened to be filed.
  final String profileId;

  /// The learner parameter registry that produced the state.
  ///
  /// A checkpoint taken under one model version is not valid input for
  /// another, since the same journal replayed under different constants
  /// produces a different state.
  final String learnerModelVersion;

  /// The journal sequence of the last attempt folded into this state.
  ///
  /// A position in the *history*, not in a sitting. A history spans many
  /// sessions, so a within-session index cannot say what a checkpoint already
  /// includes: resuming from one would silently reapply every attempt from
  /// every other session.
  final int throughJournalSequence;

  /// The attempt at that position, so a resume can be checked rather than
  /// trusted.
  final String throughAttemptId;

  /// When the covered attempt happened, in UTC.
  final DateTime coversThrough;

  /// The saved state.
  final LearnerState state;

  /// Hash of the canonical encoding of [state].
  final String contentHash;

  const LearnerStateCheckpoint._({
    required this.schemaVersion,
    required this.profileId,
    required this.learnerModelVersion,
    required this.throughJournalSequence,
    required this.throughAttemptId,
    required this.coversThrough,
    required this.state,
    required this.contentHash,
  });

  /// Captures [state] as it stands.
  ///
  /// Takes a deep copy. Learner state is mutable, and a checkpoint that aliased
  /// it would keep changing as practice continued, drifting away from the hash
  /// and the position it claims. Representing state at a particular point in
  /// history is the whole of what a checkpoint is.
  ///
  /// The hash is computed here rather than supplied, so a checkpoint cannot be
  /// constructed already claiming to be something it is not.
  factory LearnerStateCheckpoint.capture({
    required LearnerState state,
    required String profileId,
    required String learnerModelVersion,
    required int throughJournalSequence,
    required String throughAttemptId,
    required DateTime coversThrough,
  }) {
    final captured = state.copy();
    return LearnerStateCheckpoint._(
      schemaVersion: checkpointSchemaVersion,
      profileId: profileId,
      learnerModelVersion: learnerModelVersion,
      throughJournalSequence: throughJournalSequence,
      throughAttemptId: throughAttemptId,
      coversThrough: coversThrough.toUtc(),
      state: captured,
      contentHash: canonical.contentHash(encodeLearnerState(captured)),
    );
  }

  /// Captures the state a replay reached, positioned at [record].
  ///
  /// The ordinary way to make one: the position and the state come from the
  /// same place, so they cannot disagree.
  factory LearnerStateCheckpoint.after(
    AttemptRecord record, {
    required LearnerState state,
    required String learnerModelVersion,
  }) => LearnerStateCheckpoint.capture(
    state: state,
    profileId: record.identity.profileId,
    learnerModelVersion: learnerModelVersion,
    throughJournalSequence: record.journalSequence,
    throughAttemptId: record.identity.attemptId,
    coversThrough: record.identity.occurredAt,
  );

  /// Whether this checkpoint can seed a replay under [learnerModelVersion].
  ///
  /// A checkpoint from another model version is not wrong, it is simply not
  /// usable as a shortcut, and the honest response is to replay from the
  /// journal instead.
  bool isUsableUnder(String learnerModelVersion) =>
      this.learnerModelVersion == learnerModelVersion;

  /// Writes this checkpoint.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'profile_id': profileId,
    'learner_model_version': learnerModelVersion,
    'through_journal_sequence': throughJournalSequence,
    'through_attempt_id': throughAttemptId,
    'covers_through': encodeTime(coversThrough),
    'content_hash': contentHash,
    'state': encodeLearnerState(state),
  };

  /// Reads a checkpoint back and verifies it against its own hash.
  ///
  /// Throws [JournalFormatException] when the content does not hash to what the
  /// checkpoint claims, which is corruption rather than a stale cache.
  factory LearnerStateCheckpoint.fromJson(
    Map<String, Object?> json, {
    required LearnerParams params,
  }) {
    final version = requireInt(json, 'schema_version');
    if (version != checkpointSchemaVersion) {
      throw JournalFormatException(
        'checkpoint schema version $version is not readable by this build, '
        'which writes version $checkpointSchemaVersion',
      );
    }

    const location = 'checkpoint';
    final stateJson = requireMap(json, 'state', location: location);
    final claimed = requireString(json, 'content_hash', location: location);
    final actual = canonical.contentHash(stateJson);
    if (claimed != actual) {
      throw JournalFormatException(
        'checkpoint content does not match its hash; it claims $claimed but '
        'hashes to $actual',
        location: location,
      );
    }

    return LearnerStateCheckpoint._(
      schemaVersion: version,
      profileId: requireString(json, 'profile_id', location: location),
      learnerModelVersion: requireString(
        json,
        'learner_model_version',
        location: location,
      ),
      throughJournalSequence: requireInt(
        json,
        'through_journal_sequence',
        location: location,
      ),
      throughAttemptId: requireString(
        json,
        'through_attempt_id',
        location: location,
      ),
      coversThrough: requireTime(json, 'covers_through', location: location),
      state: decodeLearnerState(stateJson, params: params, location: location),
      contentHash: actual,
    );
  }

  @override
  String toString() =>
      'LearnerStateCheckpoint($profileId, through #$throughJournalSequence, '
      '$learnerModelVersion)';
}

/// The hash of [state] as a checkpoint would record it.
///
/// Replay compares against this to prove it reproduced the recorded history
/// rather than merely producing something plausible.
String learnerStateHash(LearnerState state) =>
    canonical.contentHash(encodeLearnerState(state));
