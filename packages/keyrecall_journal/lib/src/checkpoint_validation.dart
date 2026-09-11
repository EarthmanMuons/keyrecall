import 'package:meta/meta.dart';

import 'attempt_journal.dart';
import 'checkpoint.dart';

/// Why a checkpoint may not stand in for the history it claims to cover.
///
/// Rejecting a checkpoint is not the same as rejecting a journal. A checkpoint
/// is disposable acceleration, so an unusable one costs a full replay and
/// nothing else; only the journal itself failing to load is corruption.
@immutable
class CheckpointRejection {
  /// What is wrong, in human-readable form.
  final String reason;

  const CheckpointRejection(this.reason);

  @override
  String toString() => 'CheckpointRejection: $reason';
}

/// Checks whether [checkpoint] may seed a replay of [journal].
///
/// Returns null when it may, and the reason it may not otherwise.
///
/// A checkpoint asserts that every attempt through its sequence adds up to the
/// state it carries. Every part of that assertion is checked here rather than
/// at each call site, because the parts are only meaningful together: a
/// position nobody verified names a state nobody compared, and accepting one
/// replaces authoritative history with whatever the file happened to hold.
///
/// The model version is checked in every replay mode. A checkpoint already
/// contains one model's reading of everything before it, so seeding another
/// model from it produces a hybrid estimate rather than a counterfactual.
///
/// A covered attempt that recorded no state hash is rejected too. Nothing is
/// wrong with such a journal, but there is nothing to check the checkpoint
/// against, and an unverifiable shortcut is not one worth taking.
///
/// [genesisStateHash] is the hash of the state replay begins from. It and the
/// skipped records are both covered by the checkpoint's history digest, which
/// is what makes skipping them safe: the covered attempt's own state hash says
/// only that the state at that position was reached, and nothing at all about
/// whether the attempts before it still say what they said.
CheckpointRejection? validateCheckpointAgainstJournal(
  LearnerStateCheckpoint checkpoint, {
  required AttemptJournal journal,
  required String learnerModelVersion,
  required String genesisStateHash,
}) {
  if (checkpoint.profileId != journal.header.profileId) {
    return CheckpointRejection(
      'checkpoint belongs to profile ${checkpoint.profileId}, but this '
      'journal holds ${journal.header.profileId}',
    );
  }

  if (!checkpoint.isUsableUnder(learnerModelVersion)) {
    return CheckpointRejection(
      'checkpoint was taken under learner model '
      '"${checkpoint.learnerModelVersion}" but replay is running '
      '"$learnerModelVersion"; replay from the journal instead',
    );
  }

  final sequence = checkpoint.throughJournalSequence;
  if (sequence < 0 || sequence >= journal.length) {
    return CheckpointRejection(
      'checkpoint covers history through sequence $sequence, which this '
      'journal of ${journal.length} attempts does not hold',
    );
  }

  // Sequences are contiguous from zero, so the covered attempt is at that
  // index.
  final covered = journal.records[sequence];
  if (covered.identity.attemptId != checkpoint.throughAttemptId) {
    return CheckpointRejection(
      'checkpoint claims to cover attempt ${checkpoint.throughAttemptId} at '
      'sequence $sequence, but this journal has '
      '${covered.identity.attemptId} there',
    );
  }

  if (checkpoint.coversThrough != covered.identity.occurredAt) {
    return CheckpointRejection(
      'checkpoint covers through ${checkpoint.coversThrough}, but attempt '
      '${covered.identity.attemptId} happened at '
      '${covered.identity.occurredAt}',
    );
  }

  final internal = learnerStateHash(checkpoint.state);
  if (internal != checkpoint.contentHash) {
    return CheckpointRejection(
      'checkpoint content does not match its hash; it claims '
      '${checkpoint.contentHash} but hashes to $internal',
    );
  }

  final history = journal.historyHashThrough(
    sequence,
    genesisStateHash: genesisStateHash,
  );
  if (history != checkpoint.coversHistoryHash) {
    return CheckpointRejection(
      'checkpoint stands in for history ${checkpoint.coversHistoryHash}, but '
      'this journal through sequence $sequence, replayed from '
      '$genesisStateHash, is $history',
    );
  }

  final recorded = covered.stateAfterHash;
  if (recorded == null) {
    return CheckpointRejection(
      'attempt ${covered.identity.attemptId} records no state hash, so the '
      'checkpoint cannot be checked against the history it claims',
    );
  }
  if (recorded != checkpoint.contentHash) {
    return CheckpointRejection(
      'checkpoint holds state ${checkpoint.contentHash}, but attempt '
      '${covered.identity.attemptId} produced $recorded; the journal is '
      'authoritative',
    );
  }

  return null;
}
