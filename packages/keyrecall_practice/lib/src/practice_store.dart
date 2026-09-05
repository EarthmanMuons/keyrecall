import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'coordination_log.dart';
import 'feedback_exposure.dart';
import 'pending_decision.dart';
import 'practice_plan.dart';

/// Durable storage for one install's practice history.
///
/// The port the application transaction writes through. Four kinds of thing
/// live behind it, and they have different durability requirements on purpose:
///
/// - **Attempts** are append-only and authoritative. Nothing rewrites them.
/// - **Feedback exposures** are append-only observations of review screens.
/// - **A pending decision** is a single mutable slot per profile. It is not
///   history; it records what was presented so an interrupted run can be
///   resolved rather than guessed at.
/// - **Checkpoints** are a single overwritable slot per profile, and losing one
///   costs only replay time.
/// - **Coordination samples** are an append-only diagnostic log, not evidence.
///   Nothing replays them and losing them costs only the ability to look back
///   at how far apart the hands actually arrived.
/// - **A practice plan** is a single overwritable slot per profile. It is
///   intent rather than evidence: what the learner is working toward and what
///   they asked to draw from, which nothing in the journal can reconstruct.
///
/// Implementations must make [appendAttempt] durable before it returns, and
/// must never leave a partially written attempt visible as history. Beyond
/// that, the engine is free: a file, a database, or anything else that
/// preserves those guarantees.
///
/// Operations on one profile must not interleave, within one store. Each of
/// them reads, decides and writes, and callers are not one writer: a practice
/// loop committing an attempt and a roster erasing that profile are separate
/// objects with separate guards. Two stores over one root serialize nothing
/// against each other, so an install has one store per storage root.
///
/// Ordering is all this gives, and a caller holding state it read earlier can
/// still act on history that has since been erased. A checkpoint covering
/// attempts the journal no longer has is refused by [PracticeSession], and the
/// journal's contiguous sequence refuses a stale append, except from a session
/// that read the journal empty: sequence zero is valid against the journal an
/// erase leaves, so that attempt survives the erase. See
/// `docs/design/future-planning.md` section 4.14.
abstract interface class PracticeStore {
  /// Every attempt recorded for [profileId], oldest first.
  ///
  /// Returns an empty journal for a profile with no history yet, rather than
  /// failing: a first run is not an error.
  ///
  /// [createdAt] stamps a journal being created for the first time, and is
  /// ignored once one exists. The caller supplies it so no store invents a
  /// timestamp from a clock the caller does not control.
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt});

  /// Durably appends [record] to the end of that profile's history.
  ///
  /// Must be idempotent on the attempt id, so a retry after an interrupted
  /// commit cannot record the same evidence twice.
  Future<void> appendAttempt(AttemptRecord record);

  /// Every post-attempt feedback exposure for [profileId], oldest first.
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId);

  /// Durably records what was shown after an attempt.
  ///
  /// Idempotent for the same attempt and post-attempt feedback level.
  Future<void> appendFeedbackExposure(FeedbackExposure exposure);

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

  /// Every coordination sample recorded for [profileId], oldest first.
  Future<List<CoordinationSample>> loadCoordinationSamples(String profileId);

  /// Appends [sample] to that profile's diagnostic log.
  ///
  /// Idempotent on the attempt id: an attempt observes its hands once.
  Future<void> appendCoordinationSample(CoordinationSample sample);

  /// What [profileId] is working toward, or null where nobody has said.
  ///
  /// Absent is not the same as the default plan: a caller that wants to know
  /// whether the question was ever answered can still tell.
  Future<PracticePlan?> loadPracticePlan(String profileId);

  /// Saves [plan] for [profileId], replacing any earlier one.
  Future<void> savePracticePlan(String profileId, PracticePlan plan);

  /// The most recent checkpoint for [profileId], if one was saved.
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId);

  /// Saves [checkpoint], replacing any earlier one.
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint);

  /// Erases everything recorded for [profileId].
  ///
  /// Destroys history rather than correcting it, which is the one operation a
  /// journal is otherwise built to prevent, so nothing in the practice loop
  /// calls it: it exists for a person who has decided to start over.
  Future<void> erase(String profileId);
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
  final Map<String, PracticePlan> _plans = {};
  final Map<String, Map<String, CoordinationSample>> _coordination = {};
  final Map<String, Map<(String, PostAttemptFeedback), FeedbackExposure>>
  _feedback = {};

  /// When the journal for [profileId] was created, for a first run.
  final DateTime createdAt;

  InMemoryPracticeStore({DateTime? createdAt})
    : createdAt = (createdAt ?? DateTime.now()).toUtc();

  @override
  Future<AttemptJournal> loadJournal(
    String profileId, {
    DateTime? createdAt,
  }) async => _journalFor(profileId, createdAt);

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    _journalFor(record.profileId, null).append(record);
  }

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(
    String profileId,
  ) async => List.unmodifiable(_feedback[profileId]?.values ?? const []);

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) async {
    final journal = _journalFor(exposure.profileId, null);
    if (!journal.records.any(
      (record) => record.identity.attemptId == exposure.attemptId,
    )) {
      throw StateError('feedback refers to an attempt that is not recorded');
    }
    final exposures = _feedback.putIfAbsent(exposure.profileId, () => {});
    exposures.putIfAbsent((
      exposure.attemptId,
      exposure.postAttemptFeedback,
    ), () => exposure);
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
  Future<List<CoordinationSample>> loadCoordinationSamples(
    String profileId,
  ) async => List.unmodifiable(_coordination[profileId]?.values ?? const []);

  @override
  Future<void> appendCoordinationSample(CoordinationSample sample) async {
    _coordination
        .putIfAbsent(sample.profileId, () => {})
        .putIfAbsent(sample.attemptId, () => sample);
  }

  @override
  Future<PracticePlan?> loadPracticePlan(String profileId) async =>
      _plans[profileId];

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) async {
    _plans[profileId] = plan;
  }

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) async =>
      _checkpoints[profileId];

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) async {
    _checkpoints[checkpoint.profileId] = checkpoint;
  }

  @override
  Future<void> erase(String profileId) async {
    _journals.remove(profileId);
    _pending.remove(profileId);
    _checkpoints.remove(profileId);
    _feedback.remove(profileId);
    _plans.remove(profileId);
    _coordination.remove(profileId);
  }

  AttemptJournal _journalFor(String profileId, DateTime? createdAt) =>
      _journals.putIfAbsent(
        profileId,
        () => AttemptJournal(
          JournalHeader(
            profileId: profileId,
            createdAt: createdAt ?? this.createdAt,
          ),
        ),
      );
}
