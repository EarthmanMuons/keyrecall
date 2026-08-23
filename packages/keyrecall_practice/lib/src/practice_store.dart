import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'pending_decision.dart';

/// Durable storage for one install's practice history.
///
/// The port the application transaction writes through. Three kinds of thing
/// live behind it, and they have different durability requirements on purpose:
///
/// - **Attempts** are append-only and authoritative. Nothing rewrites them.
/// - **A pending decision** is a single mutable slot per profile. It is not
///   history; it records what was presented so an interrupted run can be
///   resolved rather than guessed at.
/// - **Checkpoints** are a single overwritable slot per profile, and losing one
///   costs only replay time.
///
/// Implementations must make [appendAttempt] durable before it returns, and
/// must never leave a partially written attempt visible as history. Beyond
/// that, the engine is free: a file, a database, or anything else that
/// preserves those guarantees.
abstract interface class PracticeStore {
  /// Every attempt recorded for [profileId], oldest first.
  ///
  /// Returns an empty journal for a profile with no history yet, rather than
  /// failing: a first run is not an error.
  Future<AttemptJournal> loadJournal(String profileId);

  /// Durably appends [record] to the end of that profile's history.
  ///
  /// Must be idempotent on the attempt id, so a retry after an interrupted
  /// commit cannot record the same evidence twice.
  Future<void> appendAttempt(AttemptRecord record);

  /// The unresolved decision for [profileId], if a run was interrupted between
  /// presenting an exercise and observing its outcome.
  Future<PendingDecision?> loadPendingDecision(String profileId);

  /// Durably records [decision] as presented but unanswered.
  ///
  /// Called before the exercise reaches the learner. Replaces whatever the
  /// slot held.
  Future<void> savePendingDecision(PendingDecision decision);

  /// Clears the pending slot for [profileId].
  ///
  /// Called after the attempt is committed, or after it is abandoned.
  Future<void> clearPendingDecision(String profileId);

  /// The most recent checkpoint for [profileId], if one was saved.
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId);

  /// Saves [checkpoint], replacing any earlier one.
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint);
}

/// A [PracticeStore] that keeps everything in memory.
///
/// For tests and for exercising the transaction without touching a disk. It
/// enforces the same invariants as a durable store, so a test that passes here
/// is testing the transaction rather than the file format.
class InMemoryPracticeStore implements PracticeStore {
  final Map<String, AttemptJournal> _journals = {};
  final Map<String, PendingDecision> _pending = {};
  final Map<String, LearnerStateCheckpoint> _checkpoints = {};

  /// When the journal for [profileId] was created, for a first run.
  final DateTime createdAt;

  InMemoryPracticeStore({DateTime? createdAt})
    : createdAt = (createdAt ?? DateTime.now()).toUtc();

  @override
  Future<AttemptJournal> loadJournal(String profileId) async =>
      _journalFor(profileId);

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    _journalFor(record.profileId).append(record);
  }

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) async =>
      _pending[profileId];

  @override
  Future<void> savePendingDecision(PendingDecision decision) async {
    _pending[decision.profileId] = decision;
  }

  @override
  Future<void> clearPendingDecision(String profileId) async {
    _pending.remove(profileId);
  }

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) async =>
      _checkpoints[profileId];

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) async {
    _checkpoints[checkpoint.profileId] = checkpoint;
  }

  AttemptJournal _journalFor(String profileId) => _journals.putIfAbsent(
    profileId,
    () => AttemptJournal(
      JournalHeader(profileId: profileId, createdAt: createdAt),
    ),
  );
}
