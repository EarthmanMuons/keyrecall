import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'coordination_log.dart';
import 'feedback_exposure.dart';
import 'pending_decision.dart';
import 'practice_plan.dart';
import 'profile_lifetime.dart';

/// Durable storage for one install's practice history.
///
/// The port the application transaction writes through. Several kinds of thing
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
/// - **Selection diagnostics** capture competition at decision time. Nothing
///   replays them as learner evidence.
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
/// `docs/roadmap.md` section 4.14.
abstract interface class PracticeStore {
  /// The incarnation of [profileId] that may write now.
  ///
  /// Issued on first ask and durable from then on, so a relaunch that reopens
  /// a history is holding the same incarnation the last one did.
  Future<ProfileLifetime> lifetimeOf(String profileId);

  /// Ends the current incarnation of [profileId] and returns its replacement.
  ///
  /// The barrier erasure and deletion put down. Work accepted before this may
  /// finish computing, but nothing holding the retired incarnation may
  /// persist afterwards: pressing erase is a cut, and history from before it
  /// does not come back because an append was already in flight.
  Future<ProfileLifetime> retireLifetime(String profileId);

  /// Drops everything stored for [profileId], incarnation record included.
  ///
  /// For a profile that is going away rather than starting over. Nothing is
  /// coming back, so there is no incarnation left to authorize.
  Future<void> forget(String profileId);

  /// A view of this store whose writes are refused once [lifetime] is retired.
  ///
  /// What a sitting writes through. The check happens where the write does, so
  /// an erase cannot land between an authorization and the append it allowed.
  PracticeStore boundTo(ProfileLifetime lifetime);

  /// Decision-time diagnostics keyed by attempt id, separate from evidence.
  Future<Map<String, String>> loadSelectionDiagnostics(String profileId);

  /// Records one selection, idempotently on attempt id.
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  );

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

  /// Every acquisition event recorded for [profileId], oldest first.
  ///
  /// Its own log, because replaying attempts produces learner state and an
  /// acquisition attempt is deliberately not evidence for it. Returns an empty
  /// log for a profile with no acquisition history, which is every profile
  /// until one is offered.
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  });

  /// Durably appends [entry] to the end of that profile's acquisition history.
  ///
  /// Must be idempotent on the attempt id, so a retry after an interrupted
  /// commit cannot discharge an obligation twice or record one attempt as two.
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry);

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
  ///
  /// Retires the profile's incarnation as part of the same operation, so work
  /// that was already accepted cannot write the erased history back.
  Future<void> erase(String profileId);
}

/// Lifetime bookkeeping for a store that has no durable incarnations.
///
/// For test doubles and tools standing in for a store. One incarnation per
/// profile that is never retired, so nothing a bound view writes is refused.
mixin UnretiredLifetimes implements PracticeStore {
  final Map<String, ProfileLifetime> _lifetimes = {};

  @override
  Future<ProfileLifetime> lifetimeOf(String profileId) async =>
      _lifetimes.putIfAbsent(profileId, () => ProfileLifetime.next(profileId));

  @override
  Future<ProfileLifetime> retireLifetime(String profileId) async {
    final replacement = ProfileLifetime.next(profileId);
    _lifetimes[profileId] = replacement;
    return replacement;
  }

  @override
  Future<void> forget(String profileId) async {
    _lifetimes.remove(profileId);
    await erase(profileId);
  }

  @override
  PracticeStore boundTo(ProfileLifetime lifetime) => this;
}

/// A [PracticeStore] that keeps everything in memory.
///
/// For tests and for exercising the transaction without touching a disk. It
/// enforces the same invariants as a durable store, so a test that passes here
/// is testing the transaction rather than the file format.
class InMemoryPracticeStore implements PracticeStore {
  final Map<String, ProfileLifetime> _lifetimes = {};

  @override
  Future<ProfileLifetime> lifetimeOf(String profileId) async =>
      _lifetimes.putIfAbsent(profileId, () => ProfileLifetime.next(profileId));

  @override
  Future<ProfileLifetime> retireLifetime(String profileId) async {
    final replacement = ProfileLifetime.next(profileId);
    _lifetimes[profileId] = replacement;
    return replacement;
  }

  @override
  Future<void> forget(String profileId) async {
    await erase(profileId);
    _lifetimes.remove(profileId);
  }

  @override
  PracticeStore boundTo(ProfileLifetime lifetime) =>
      _LifetimeBoundMemoryStore(this, lifetime);

  /// Refuses [lifetime] once it is no longer the incarnation that may write.
  ///
  /// Synchronous against the maps it guards, which is what makes it a barrier
  /// rather than a check: nothing can be retired between this and the write it
  /// authorizes.
  void _requireActive(ProfileLifetime lifetime) {
    final current = _lifetimes[lifetime.profileId];
    if (current == lifetime) return;
    throw RetiredProfileLifetime(lifetime, current);
  }

  final Map<String, Map<String, String>> _selections = {};

  @override
  Future<Map<String, String>> loadSelectionDiagnostics(
    String profileId,
  ) async => Map.unmodifiable(_selections[profileId] ?? const {});

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) async {
    _selections
        .putIfAbsent(profileId, () => {})
        .putIfAbsent(attemptId, () => diagnostics);
  }

  final Map<String, AttemptJournal> _journals = {};

  final Map<String, AcquisitionJournal> _acquisitionLogs = {};
  final Map<String, PendingDecision> _pending = {};
  final Map<String, LearnerStateCheckpoint> _checkpoints = {};
  final Map<String, PracticePlan> _plans = {};
  final Map<String, Map<String, CoordinationSample>> _coordination = {};
  final Map<String, Map<(String, PostAttemptFeedback), FeedbackExposure>>
  _feedback = {};

  /// When every journal this store holds was created, for a first run.
  final DateTime createdAt;

  InMemoryPracticeStore({DateTime? createdAt})
    : createdAt = (createdAt ?? DateTime.now()).toUtc();

  /// A snapshot of the durable history, not the object this store keeps.
  ///
  /// A caller that held the store's own journal would see every later append
  /// appear in what it is holding, which is not how a file behaves and hides
  /// exactly the divergence between live and durable history that a failure
  /// test is looking for.
  @override
  Future<AttemptJournal> loadJournal(
    String profileId, {
    DateTime? createdAt,
  }) async {
    final held = _journalFor(profileId, createdAt);
    return AttemptJournal(held.header)..appendAll(held.records);
  }

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    _journalFor(record.profileId, null).append(record);
  }

  @override
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  }) async {
    final held = _acquisitionFor(profileId, createdAt);
    final copy = AcquisitionJournal(held.header);
    for (final record in held.records) {
      copy.append(record);
    }
    return copy;
  }

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) async {
    _acquisitionFor(entry.identity.profileId, null).append(entry);
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
    await retireLifetime(profileId);
    _selections.remove(profileId);
    _journals.remove(profileId);
    _acquisitionLogs.remove(profileId);
    _pending.remove(profileId);
    _checkpoints.remove(profileId);
    _feedback.remove(profileId);
    _plans.remove(profileId);
    _coordination.remove(profileId);
  }

  AcquisitionJournal _acquisitionFor(String profileId, DateTime? createdAt) =>
      _acquisitionLogs.putIfAbsent(
        profileId,
        () => AcquisitionJournal(
          AcquisitionJournalHeader(
            profileId: profileId,
            createdAt: createdAt ?? this.createdAt,
          ),
        ),
      );

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

/// An [InMemoryPracticeStore] view that writes only as one incarnation.
///
/// Reads pass through: what a retired sitting may not do is persist, and
/// refusing it the history it already replayed would only hide where the
/// refusal came from.
class _LifetimeBoundMemoryStore implements PracticeStore {
  final InMemoryPracticeStore _store;
  final ProfileLifetime _lifetime;

  _LifetimeBoundMemoryStore(this._store, this._lifetime);

  void _authorize(String profileId) {
    if (profileId != _lifetime.profileId) {
      throw ArgumentError.value(
        profileId,
        'profileId',
        'this store writes only for ${_lifetime.profileId}',
      );
    }
    _store._requireActive(_lifetime);
  }

  @override
  Future<ProfileLifetime> lifetimeOf(String profileId) =>
      _store.lifetimeOf(profileId);

  @override
  Future<ProfileLifetime> retireLifetime(String profileId) =>
      _store.retireLifetime(profileId);

  @override
  Future<void> forget(String profileId) => _store.forget(profileId);

  @override
  PracticeStore boundTo(ProfileLifetime lifetime) => _store.boundTo(lifetime);

  @override
  Future<Map<String, String>> loadSelectionDiagnostics(String profileId) =>
      _store.loadSelectionDiagnostics(profileId);

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) async {
    _authorize(profileId);
    await _store.appendSelectionDiagnostics(profileId, attemptId, diagnostics);
  }

  @override
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt}) =>
      _store.loadJournal(profileId, createdAt: createdAt);

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    _authorize(record.profileId);
    await _store.appendAttempt(record);
  }

  @override
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  }) => _store.loadAcquisitionJournal(profileId, createdAt: createdAt);

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) async {
    _authorize(entry.identity.profileId);
    await _store.appendAcquisitionEntry(entry);
  }

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId) =>
      _store.loadFeedbackExposures(profileId);

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) async {
    _authorize(exposure.profileId);
    await _store.appendFeedbackExposure(exposure);
  }

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) =>
      _store.loadPendingDecision(profileId);

  @override
  Future<void> savePendingDecision(PendingDecision decision) async {
    _authorize(decision.profileId);
    await _store.savePendingDecision(decision);
  }

  @override
  Future<void> clearPendingDecision(String profileId) async {
    _authorize(profileId);
    await _store.clearPendingDecision(profileId);
  }

  @override
  Future<List<CoordinationSample>> loadCoordinationSamples(String profileId) =>
      _store.loadCoordinationSamples(profileId);

  @override
  Future<void> appendCoordinationSample(CoordinationSample sample) async {
    _authorize(sample.profileId);
    await _store.appendCoordinationSample(sample);
  }

  @override
  Future<PracticePlan?> loadPracticePlan(String profileId) =>
      _store.loadPracticePlan(profileId);

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) async {
    _authorize(profileId);
    await _store.savePracticePlan(profileId, plan);
  }

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) =>
      _store.loadCheckpoint(profileId);

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) async {
    _authorize(checkpoint.profileId);
    await _store.saveCheckpoint(checkpoint);
  }

  @override
  Future<void> erase(String profileId) => _store.erase(profileId);
}
