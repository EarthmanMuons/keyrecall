import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'pending_decision.dart';
import 'performance_closure.dart';
import 'practice_store.dart';

/// Generates the ids a transaction needs.
///
/// Injectable so a test can make a run reproducible. Production passes
/// [newProfileId], which is a random UUID.
typedef IdGenerator = String Function();

/// What the scheduler decided to present, ready to show the learner.
///
/// Returned by [PracticeSession.decide] once the decision is durable. Holding
/// one means an exercise is outstanding: the transaction is open until it is
/// committed or abandoned.
@immutable
class PresentedAttempt {
  /// The durable record of what was decided.
  final PendingDecision decision;

  const PresentedAttempt(this.decision);

  /// The exercise to present.
  Exercise get exercise => decision.exercise;

  /// What the model expected of it.
  Prediction get prediction => decision.decision.prediction;

  @override
  String toString() => 'PresentedAttempt(${decision.attemptId}, $exercise)';
}

/// Thrown when the transaction is asked to do something out of order.
class PracticeStateError extends StateError {
  PracticeStateError(super.message);
}

/// One practice sitting, and the transaction that makes each attempt durable.
///
/// Runs the ordered attempt transaction and survives being interrupted at any
/// point in it:
///
/// ```text
/// decide()   propagate a scratch copy, evaluate, select,
///            persist the decision, then present
/// commit()   compute the whole transition on a copy,
///            append the attempt durably,
///            then replace canonical state and clear the decision
/// ```
///
/// Committing in that order is one of this package's central guarantees:
/// nothing the session keeps moves until the attempt is history.
///
/// The two failure modes the ordering exists to prevent:
///
/// **A crash after presenting** leaves a decision with no outcome. On the next
/// [open] it surfaces as [pending], and the caller must resolve it explicitly
/// by committing a real outcome or calling [abandonPending]. Nothing invents an
/// outcome, because nothing observed one.
///
/// **A crash during commit** is safe in either order it can fail. The attempt
/// id is chosen at decide time and is the journal's idempotency key, so on
/// restart the journal either already contains the attempt, in which case the
/// stale decision is simply cleared, or it does not, in which case the attempt
/// is still pending. The update is never applied twice, because learner state
/// is not stored: it is replayed from the journal, and the journal holds each
/// attempt exactly once.
///
/// **Retrying is not the same as overlapping.** All of that makes a failed
/// step safe to run again *after* it has stopped, and says nothing about
/// running two at once. A session is a single-writer object: [decide],
/// [commit], and [abandonPending] each read and mutate the same state, and
/// none of them holds a lock. A caller must let one finish before starting the
/// next.
///
/// Do not read the idempotency key as permission to enter [commit] twice
/// concurrently. Two overlapping commits do not collapse into one: the second
/// folds the same outcome into a copy of state whose age depends on how the
/// two interleaved, so it produces a *different* record under the same attempt
/// id, and the journal rejects that as a collision rather than absorbing it as
/// a retry. Nothing here is corrupted, but the caller is handed a failure it
/// cannot act on, and the attempt it thought it recorded may be the one that
/// was rejected.
class PracticeSession {
  /// The learner model in force.
  final LearnerModel learner;

  /// The scheduler in force.
  final SchedulerPipeline pipeline;

  /// Where history is kept.
  final PracticeStore store;

  /// Whose sitting this is.
  final Profile profile;

  /// This sitting's id, which scopes the attempt cap and the recency window.
  final String sessionId;

  /// The candidate set for this sitting.
  final List<Exercise> candidates;

  /// The build recorded on each attempt, when the app knows it.
  final String? appBuildVersion;

  final IdGenerator _nextId;
  final SessionState _session;
  final AttemptJournal _journal;

  LearnerState _state;

  PendingDecision? _pending;
  PresentedAttempt? _outstanding;

  PracticeSession._({
    required this.learner,
    required this.pipeline,
    required this.store,
    required this.profile,
    required this.sessionId,
    required this.candidates,
    required this.appBuildVersion,
    required IdGenerator nextId,
    required LearnerState state,
    required SessionState session,
    required AttemptJournal journal,
    required PendingDecision? pending,
  }) : _nextId = nextId,
       _state = state,
       _session = session,
       _journal = journal,
       _pending = pending;

  /// Opens a sitting for [profile], recovering whatever the last run left.
  ///
  /// Rebuilds learner state by replaying the journal, using a checkpoint only
  /// as a starting point. A checkpoint that does not match the current model
  /// version, or that fails its own hash, is discarded rather than trusted;
  /// losing one costs replay time and nothing else.
  ///
  /// Placement state is anchored at [Profile.createdAt], so every attempt in
  /// the journal must fall at or after it.
  ///
  /// Only exercises the observation model can read are presented, unless
  /// [presentOnlyMeasurable] says otherwise; see [isMeasurable].
  static Future<PracticeSession> open({
    required PracticeStore store,
    required Profile profile,
    required List<TechnicalMaterial> materials,
    LearnerModel learner = const LearnerModel(),
    SchedulerPipeline? pipeline,
    InstrumentProfile? instrument,
    PlacementTier placement = PlacementTier.someExperience,
    String? sessionId,
    String? appBuildVersion,
    IdGenerator? nextId,
    bool presentOnlyMeasurable = true,
  }) async {
    final resolvedPipeline = pipeline ?? SchedulerPipeline(learner: learner);
    final generator = nextId ?? newProfileId;
    final journal = await store.loadJournal(
      profile.id,
      createdAt: profile.createdAt,
    );

    // Anchored to when the profile was created, not to the journal header or
    // any wall clock a store happened to stamp. Placement is the state before
    // any practice, so its instant has to be stable across reopens and under
    // the caller's control, or replay would propagate from a different origin
    // each time.
    final initial = learner.placementState(placement, at: profile.createdAt);
    final replay = replayJournal(
      journal,
      model: learner,
      initial: initial,
      from: await _usableCheckpoint(store, profile.id, learner),
    );
    if (!replay.isFaithful) {
      throw JournalFormatException(
        'replaying the journal for ${profile.id} did not reproduce it: '
        '${replay.divergences.first}',
      );
    }

    final pending = await _recoverPending(store, profile, journal);

    return PracticeSession._(
      learner: learner,
      pipeline: resolvedPipeline,
      store: store,
      profile: profile,
      sessionId: sessionId ?? generator(),
      // An exercise the observation model cannot read produces no evidence,
      // so presenting one spends a slot and teaches nothing. Tests and
      // simulations that want the whole space say so.
      candidates: [
        for (final exercise in generateCandidates(
          instrument ?? InstrumentProfile(),
          materials,
        ))
          if (!presentOnlyMeasurable || isMeasurable(exercise)) exercise,
      ],
      appBuildVersion: appBuildVersion,
      nextId: generator,
      state: replay.state,
      session: _rebuildSessionState(journal, resolvedPipeline.config),
      journal: journal,
      pending: pending,
    );
  }

  /// The learner state this sitting reasons from.
  ///
  /// Advances only when an attempt is committed durably. Anything that looks
  /// ahead works on a copy, or replay could not reproduce the timeline.
  ///
  /// Read it again after each [commit] rather than holding the object across
  /// one: a commit replaces it wholesale, so a cached reference would quietly
  /// go stale.
  LearnerState get state => _state;

  /// Every attempt recorded for this profile so far.
  AttemptJournal get journal => _journal;

  /// The scheduler's view of this sitting.
  SessionState get session => _session;

  /// A decision from an interrupted run that was never answered.
  ///
  /// Present means the last run showed an exercise and did not record what
  /// happened. Resolve it before deciding again.
  PendingDecision? get pending => _pending;

  /// Whether an exercise is currently outstanding.
  bool get hasOutstandingAttempt => _outstanding != null;

  /// Decides what to present next and makes that decision durable.
  ///
  /// Returns null when nothing was admitted, which is a real outcome rather
  /// than an error: the slot is consumed and no attempt is recorded.
  ///
  /// Throws [PracticeStateError] when an attempt is already outstanding or an
  /// unresolved decision is pending, since deciding again would abandon
  /// something a person may have been shown.
  Future<PresentedAttempt?> decide({required DateTime at}) async {
    if (_outstanding != null) {
      throw PracticeStateError(
        'an attempt is already outstanding; commit or abandon it first',
      );
    }
    if (_pending != null) {
      throw PracticeStateError(
        'an unresolved decision from an earlier run is pending; resolve it '
        'first',
      );
    }

    // Evaluated against a scratch copy. This may admit nothing, and canonical
    // state must advance only on a committed attempt.
    final scratch = _state.copy();
    learner.propagate(scratch, at);

    final traces = pipeline.evaluate(
      state: scratch,
      session: _session,
      candidates: candidates,
      at: at,
    );
    final chosen = pipeline.selectChoice(traces, _session);
    // The safety cap counts decision opportunities, not presented attempts, so
    // a slot that admits nothing still consumes one. Deliberate: a sitting that
    // keeps finding nothing to present has to end, and only counting
    // presentations would let it run forever. Do not "fix" this to count
    // commits.
    _session.attemptsThisSession++;
    if (chosen == null) return null;

    final decision = PendingDecision(
      attemptId: _nextId(),
      profileId: profile.id,
      sessionId: sessionId,
      indexInSession: _indexInSession,
      journalSequence: _journal.nextSequence,
      decidedAt: at,
      provenance: ModelProvenance.of(
        learnerParams: learner.params,
        schedulerModelVersion: pipeline.config.modelVersion,
        appBuildVersion: appBuildVersion,
      ),
      exercise: chosen.exercise,
      decision: SchedulerDecision.fromTrace(chosen, pipeline.config),
      stateBeforeHash: learnerStateHash(scratch),
    );

    // Durable before the exercise is shown. Everything after this point is
    // recoverable; before it, nothing was presented.
    await store.savePendingDecision(decision);
    final presented = PresentedAttempt(decision);
    _outstanding = presented;
    return presented;
  }

  /// Records what happened and commits the attempt.
  ///
  /// The whole transition is computed on a copy, and canonical state is only
  /// replaced once the attempt is durably appended. That matters for a storage
  /// failure that does *not* kill the process: if the append throws, the
  /// session is left exactly where it started, the decision is still pending,
  /// and calling [commit] again is safe. Applying the update first would leave
  /// state ahead of the journal, and a retry would then fold the same outcome
  /// in twice from an already-advanced state.
  ///
  /// The decision is cleared last. A crash between the append and the clear
  /// leaves a stale slot that the next [open] recognizes as already committed.
  ///
  /// Single-writer: callers must serialize commits for a session and must not
  /// start one while another is still running. Retrying a commit that has
  /// already failed is safe; entering this method twice concurrently is not,
  /// for the reason given on [PracticeSession]. A UI driving this from a
  /// button has to make that button single-flight rather than relying on the
  /// attempt id to deduplicate.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding.
  Future<AttemptRecord> commit(Outcome outcome, {DateTime? observedWallTime}) =>
      _close(
        termination: AttemptTermination.learnerStopped,
        outcome: outcome,
        observedWallTime: observedWallTime,
      );

  /// Ends the outstanding attempt from what was played.
  ///
  /// The whole path: what arrived becomes a correspondence, the correspondence
  /// becomes a measurement, and the measurement becomes an outcome. An attempt
  /// the observation model cannot read closes with the reason instead, which
  /// is a complete record of an attempt that happened and produced no
  /// evidence.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding.
  Future<AttemptRecord> closeFromPerformance(
    PerformanceTranscript transcript, {
    AttemptTermination termination = AttemptTermination.learnerStopped,
    MeasurementPolicy policy = MeasurementPolicy.standard,
    DateTime? observedWallTime,
  }) {
    final outstanding = _outstanding ?? _pendingAsOutstanding();
    final reading = readPerformance(
      exercise: outstanding.decision.exercise,
      transcript: transcript,
      policy: policy,
    );

    return switch (reading) {
      PerformanceMeasured(:final outcome) => _close(
        termination: termination,
        outcome: outcome,
        observedWallTime: observedWallTime,
      ),
      PerformanceUnmeasurable(:final reason) => _close(
        termination: termination,
        unavailable: reason,
        observedWallTime: observedWallTime,
      ),
    };
  }

  /// Ends the outstanding attempt with nothing measured.
  ///
  /// The honest close for an attempt that ended without anyone establishing how
  /// it went: a timeout, or any path that is not a learner reporting. It moves
  /// no learner state, because nothing was observed, and the record exists to
  /// say the attempt ended rather than to claim anything about the
  /// performance.
  ///
  /// The transaction discipline is the same as [commit]'s, for the same
  /// reasons.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding.
  Future<AttemptRecord> closeUnmeasured({
    required AttemptTermination termination,
    MeasurementUnavailableReason reason =
        MeasurementUnavailableReason.notAvailable,
    DateTime? observedWallTime,
  }) => _close(
    termination: termination,
    unavailable: reason,
    observedWallTime: observedWallTime,
  );

  /// Commits the outstanding attempt, with or without a measurement.
  ///
  /// Exactly one of [outcome] and [unavailable] is meaningful; the nullability
  /// stays inside this method so no caller and nothing stored ever sees an
  /// outcome that may or may not be there.
  Future<AttemptRecord> _close({
    required AttemptTermination termination,
    Outcome? outcome,
    MeasurementUnavailableReason? unavailable,
    DateTime? observedWallTime,
  }) async {
    final outstanding = _outstanding ?? _pendingAsOutstanding();
    final decision = outstanding.decision;
    final at = decision.decidedAt;

    final next = _state.copy();
    final AttemptClosure closure;

    if (outcome != null) {
      learner.propagate(next, at);
      final prediction = learner.predict(next, decision.exercise, at: at);
      final weights = evidenceWeightsFor(decision.exercise, outcome);
      final diagnostics = learner.applyOutcome(
        state: next,
        exercise: decision.exercise,
        outcome: outcome,
        weights: weights,
        prediction: prediction,
        at: at,
      );
      closure = AttemptClosure.measured(
        termination: termination,
        outcome: outcome,
        weights: weights,
        memoryUpdate: diagnostics,
      );
    } else {
      closure = AttemptClosure.unmeasured(
        termination: termination,
        reason: unavailable ?? MeasurementUnavailableReason.notAvailable,
      );
    }

    final record = decision.complete(
      closure: closure,
      stateAfterHash: learnerStateHash(next),
      observedWallTime: observedWallTime,
    );

    // Nothing above this line touched anything the session keeps. Everything
    // below it only runs once the attempt is history.
    await store.appendAttempt(record);

    _state = next;
    _journal.append(record);
    // The exercise was presented either way, so the sitting knows it was. A
    // retrieval failure is a claim about the performance, and an unmeasured
    // attempt supports no such claim.
    _session.recordSelection(
      decision.exercise,
      retrievalFailed: outcome?.retrieval == FactualRetrieval.failed,
      config: pipeline.config.diversity,
    );
    _outstanding = null;
    _pending = null;

    await store.clearPendingDecision(profile.id);
    return record;
  }

  /// Discards an unresolved decision without recording anything.
  ///
  /// The honest response to an interrupted attempt nobody observed. It moved no
  /// state and produced no evidence, so history should not claim otherwise.
  Future<void> abandonPending() async {
    await store.clearPendingDecision(profile.id);
    _pending = null;
    _outstanding = null;
  }

  /// Saves a checkpoint at the current position, if there is history to cover.
  ///
  /// Purely an accelerator for the next [open]. Failing to save one costs time
  /// and nothing else.
  Future<LearnerStateCheckpoint?> saveCheckpoint() async {
    if (_journal.isEmpty) return null;
    final checkpoint = LearnerStateCheckpoint.after(
      _journal.records.last,
      state: _state,
      learnerModelVersion: learner.params.modelVersion,
    );
    await store.saveCheckpoint(checkpoint);
    return checkpoint;
  }

  int get _indexInSession =>
      _journal.session(sessionId).length + (_pending == null ? 0 : 1);

  PresentedAttempt _pendingAsOutstanding() {
    final pending = _pending;
    if (pending == null) {
      throw PracticeStateError('no attempt is outstanding to commit');
    }
    return PresentedAttempt(pending);
  }

  /// Reads the checkpoint only if it is safe to start from.
  static Future<LearnerStateCheckpoint?> _usableCheckpoint(
    PracticeStore store,
    String profileId,
    LearnerModel learner,
  ) async {
    try {
      final checkpoint = await store.loadCheckpoint(profileId);
      if (checkpoint == null) return null;
      return checkpoint.isUsableUnder(learner.params.modelVersion)
          ? checkpoint
          : null;
    } on JournalFormatException {
      // A corrupt or stale checkpoint is a cache miss, not a failure: the
      // journal still holds the history it was standing in for.
      return null;
    }
  }

  /// Decides what an unresolved decision means, given what the journal holds.
  ///
  /// Validates before accepting it. A pending slot is the one input here that
  /// is neither replayed nor hash-checked, and committing it writes an attempt
  /// keyed on the *slot's* profile id, so a misplaced or corrupted file could
  /// otherwise append one person's practice into another person's history.
  static Future<PendingDecision?> _recoverPending(
    PracticeStore store,
    Profile profile,
    AttemptJournal journal,
  ) async {
    final pending = await store.loadPendingDecision(profile.id);
    if (pending == null) return null;

    if (pending.profileId != profile.id) {
      throw JournalFormatException(
        'pending decision belongs to profile ${pending.profileId} but was '
        'found under ${profile.id}',
        location: 'pending decision ${pending.attemptId}',
      );
    }

    if (journal.contains(pending.attemptId)) {
      // Committed before the crash, then interrupted before the slot was
      // cleared. The attempt is already history; the slot is merely stale, and
      // its sequence is legitimately behind.
      await store.clearPendingDecision(profile.id);
      return null;
    }

    if (pending.journalSequence != journal.nextSequence) {
      throw JournalFormatException(
        'pending decision targets journal sequence '
        '${pending.journalSequence}, but the next position is '
        '${journal.nextSequence}; an uncommitted attempt that does not target '
        'the end of history is impossible transaction state',
        location: 'pending decision ${pending.attemptId}',
      );
    }

    if (pending.decidedAt.isBefore(profile.createdAt)) {
      throw JournalFormatException(
        'pending decision was made at ${encodeTime(pending.decidedAt)}, before '
        'the profile existed at ${encodeTime(profile.createdAt)}',
        location: 'pending decision ${pending.attemptId}',
      );
    }

    return pending;
  }

  /// Rebuilds what the scheduler needs to know about the sitting in progress.
  ///
  /// Only the recency window carries over, from the tail of the journal. The
  /// attempt cap and any recovery context deliberately do not: a restart is a
  /// new sitting, and a recovery context that outlived the failure it responded
  /// to would answer a question nobody is still asking.
  static SessionState _rebuildSessionState(
    AttemptJournal journal,
    SchedulerConfig config,
  ) {
    final window = config.diversity.recentWindow;
    final recent = journal.records
        .map((record) => record.exercise.material.materialId)
        .toList();
    return SessionState(
      recentMaterialIds: recent.length <= window
          ? recent
          : recent.sublist(recent.length - window),
    );
  }
}
