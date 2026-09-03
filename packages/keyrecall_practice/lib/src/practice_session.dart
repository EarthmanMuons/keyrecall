import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'pending_decision.dart';
import 'performance_closure.dart';
import 'practice_store.dart';
import 'requirement_state.dart';
import 'scope_resolution.dart';

/// Generates the ids a transaction needs.
///
/// Injectable so a test can make a run reproducible. Production passes
/// [newProfileId], which is a random UUID.
typedef IdGenerator = String Function();

/// The result of asking a practice session what happens next.
sealed class PracticeDecision {
  const PracticeDecision();
}

/// What the scheduler decided to present, ready to show the learner.
///
/// Returned by [PracticeSession.decideOutcome] once the decision is durable.
/// Holding one means an exercise is outstanding: the transaction is open
/// until it is committed or abandoned.
@immutable
class PresentedAttempt extends PracticeDecision {
  /// The durable record of what was decided.
  final PendingDecision decision;

  /// Curriculum coverage at the instant this exercise was selected.
  final ScopeCoverage? coverage;

  const PresentedAttempt(this.decision, {this.coverage});

  /// The exercise to present.
  Exercise get exercise => decision.exercise;

  /// What the model expected of it.
  Prediction get prediction => decision.decision.prediction;

  @override
  String toString() => 'PresentedAttempt(${decision.attemptId}, $exercise)';
}

/// Useful work was requested, but no exercise could be presented.
@immutable
class PracticeBlocked extends PracticeDecision {
  final BlockedReason reason;
  final SelectionBlocked selection;
  final ScopeCoverage coverage;

  PracticeBlocked(this.selection, {required this.coverage})
    : reason = selection.reason;
}

/// No requirement in the active scope warrants work now.
@immutable
class PracticeCaughtUp extends PracticeDecision {
  final ScopeCoverage coverage;

  const PracticeCaughtUp(this.coverage);
}

/// The requested goal or focus could not be resolved completely.
@immutable
class PracticeInvalidScope extends PracticeDecision {
  final List<ScopeResolutionFailure> failures;

  PracticeInvalidScope(Iterable<ScopeResolutionFailure> failures)
    : failures = List.unmodifiable(failures);
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
/// **A crash after presenting** leaves a decision with no outcome. On the next
/// [open] it surfaces as [pending], and the caller must resolve it by
/// committing a real outcome or calling [abandonPending]. Nothing invents an
/// outcome, because nothing observed one.
///
/// **A crash during commit** is safe in either order it can fail. The attempt
/// id is chosen at decide time and is the journal's idempotency key, so on
/// restart the journal either already holds the attempt, and the stale decision
/// is cleared, or it does not, and the attempt is still pending. The update is
/// never applied twice, because learner state is replayed from the journal
/// rather than stored.
///
/// **Retrying is not the same as overlapping.** A session is a single-writer
/// object: [decide], the close methods, and [abandonPending] each read and
/// mutate the same state and none holds a lock, so a caller must let one
/// finish before starting the next. The idempotency key is not permission to
/// enter a close twice concurrently: the second fold produces a different
/// record under the same attempt id, which the journal rejects as a collision
/// rather than absorbing as a retry.
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

  final List<TechnicalMaterial> _materials;
  final InstrumentProfile _instrument;
  final PracticeScopeResolver _scopeResolver;
  final PracticeScopeEvaluator _scopeEvaluator;

  /// The build recorded on each attempt, when the app knows it.
  final String? appBuildVersion;

  final IdGenerator _nextId;
  final SessionState _session;
  final AttemptJournal _journal;

  LearnerState _state;

  PendingDecision? _pending;
  PresentedAttempt? _outstanding;
  late ScopeResolution _scopeResolution;

  PracticeSession._({
    required this.learner,
    required this.pipeline,
    required this.store,
    required this.profile,
    required this.sessionId,
    required List<TechnicalMaterial> materials,
    required InstrumentProfile instrument,
    required PracticeScopeResolver scopeResolver,
    required PracticeScopeEvaluator scopeEvaluator,
    required PracticeGoal goal,
    required PracticeFocus focus,
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
       _pending = pending,
       _materials = List.unmodifiable(materials),
       _instrument = instrument,
       _scopeResolver = scopeResolver,
       _scopeEvaluator = scopeEvaluator {
    _scopeResolution = _resolve(goal, focus);
  }

  /// Opens a sitting for [profile], recovering whatever the last run left.
  ///
  /// Rebuilds learner state by replaying the journal, using a checkpoint only
  /// as a starting point. A checkpoint that does not match the current model
  /// version, or that fails its own hash, is discarded rather than trusted;
  /// losing one costs replay time and nothing else.
  ///
  /// Placement state is anchored at [Profile.createdAt] and seeded from
  /// [Profile.placement], so every attempt in the journal must fall at or
  /// after it and the prior it propagates from comes from the profile rather
  /// than from whoever opened the session.
  ///
  /// [goal] and [focus] resolve structurally before any scheduling decision.
  static Future<PracticeSession> open({
    required PracticeStore store,
    required Profile profile,
    required List<TechnicalMaterial> materials,
    LearnerModel learner = const LearnerModel(),
    SchedulerPipeline? pipeline,
    InstrumentProfile? instrument,
    PracticeGoal goal = PracticeGoal.generalFluency,
    PracticeFocus focus = PracticeFocus.unrestricted,
    PracticeScopeResolver? scopeResolver,
    PracticeScopeEvaluator scopeEvaluator = const PracticeScopeEvaluator(),
    String? sessionId,
    String? appBuildVersion,
    IdGenerator? nextId,
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
    final initial = learner.placementState(
      profile.placement,
      at: profile.createdAt,
    );
    final replay = replayJournal(
      journal,
      model: learner,
      initial: initial,
      from: await _usableCheckpoint(store, profile.id, learner, journal),
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
      materials: materials,
      instrument: instrument ?? InstrumentProfile(),
      scopeResolver: scopeResolver ?? PracticeScopeResolver(),
      scopeEvaluator: scopeEvaluator,
      goal: goal,
      focus: focus,
      appBuildVersion: appBuildVersion,
      nextId: generator,
      state: replay.state,
      session: _rebuildSessionState(journal, learner, resolvedPipeline.config),
      journal: journal,
      pending: pending,
    );
  }

  /// The learner state this sitting reasons from.
  ///
  /// Advances only when an attempt is committed durably. Anything that looks
  /// ahead works on a copy, or replay could not reproduce the timeline.
  ///
  /// Read it again after each close rather than holding the object across
  /// one: a commit replaces it wholesale, so a cached reference would quietly
  /// go stale.
  LearnerState get state => _state;

  /// Every attempt recorded for this profile so far.
  AttemptJournal get journal => _journal;

  /// The scheduler's view of this sitting.
  SessionState get session => _session;

  /// The current structural candidate envelope, empty for an invalid scope.
  List<Exercise> get candidates => switch (_scopeResolution) {
    ValidPracticeScope(:final scope) => List.unmodifiable({
      for (final requirement in scope.requirements) ...requirement.candidates,
    }),
    InvalidPracticeScope() => const [],
  };

  /// A decision from an interrupted run that was never answered.
  ///
  /// Present means the last run showed an exercise and did not record what
  /// happened. Resolve it before deciding again.
  PendingDecision? get pending => _pending;

  /// Whether an exercise is currently outstanding.
  bool get hasOutstandingAttempt => _outstanding != null;

  /// Applies a new goal or focus to the next undecided slot.
  ///
  /// An outstanding or recovered decision remains unchanged until it closes or
  /// is abandoned.
  void updateScope({
    required PracticeGoal goal,
    PracticeFocus focus = PracticeFocus.unrestricted,
  }) {
    _scopeResolution = _resolve(goal, focus);
  }

  /// Decides what to present next and makes that decision durable.
  ///
  /// Invalid and caught-up scopes return before scheduling and consume no
  /// decision opportunity. A selected or blocked scheduling attempt consumes
  /// one.
  ///
  /// Throws [PracticeStateError] when an attempt is already outstanding or an
  /// unresolved decision is pending, since deciding again would abandon
  /// something a person may have been shown.
  Future<PracticeDecision> decideOutcome({required DateTime at}) async {
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

    final resolution = _scopeResolution;
    if (resolution case InvalidPracticeScope(:final failures)) {
      return PracticeInvalidScope(failures);
    }
    final scope = (resolution as ValidPracticeScope).scope;

    final scratch = _state.copy();
    learner.propagate(scratch, at);

    final evaluated = _scopeEvaluator.evaluate(
      scope: scope,
      state: scratch,
      journal: _journal,
      learner: learner,
      at: at,
    );
    if (scope.isNarrow && evaluated.isCaughtUp) {
      return PracticeCaughtUp(evaluated.coverage);
    }
    final due = scope.isNarrow
        ? evaluated.dueRequirements.toList()
        : evaluated.requirements;
    final candidates = <Exercise>{
      for (final state in due) ...state.resolved.candidates,
    }.toList();
    final acquisitionFloor = scope.isNarrow
        ? _scopeResolver.acquisitionFloorFor(due.map((state) => state.resolved))
        : null;

    final selection = pipeline.decide(
      state: scratch,
      session: _session,
      candidates: candidates,
      at: at,
      acquisitionFloor: acquisitionFloor,
    );
    if (selection case final SelectionBlocked blocked) {
      return PracticeBlocked(blocked, coverage: evaluated.coverage);
    }
    final chosen = (selection as CandidateSelected).candidate;

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
    final presented = PresentedAttempt(decision, coverage: evaluated.coverage);
    _outstanding = presented;
    return presented;
  }

  /// The presented attempt, or null for a blocked scheduling request.
  ///
  /// Compatibility for callers that have not yet adopted [decideOutcome]. New
  /// product code must match the reasoned result instead of treating blocked
  /// practice as ordinary absence.
  Future<PresentedAttempt?> decide({required DateTime at}) async =>
      switch (await decideOutcome(at: at)) {
        final PresentedAttempt presented => presented,
        PracticeBlocked() ||
        PracticeCaughtUp() ||
        PracticeInvalidScope() => null,
      };

  /// Ends the outstanding attempt with an outcome established elsewhere.
  ///
  /// The seam between this transaction and the observation model. A caller
  /// that already knows how an attempt went states it here, which is what lets
  /// the scheduler, the journal, and this transaction be exercised over
  /// trajectories that no transcript could produce: an outcome is not
  /// invertible into a performance that measures back to it, so routing those
  /// through [closeFromPerformance] would make them assertions about
  /// measurement instead. Learner-facing attempts do not come this way; they
  /// are measured.
  ///
  /// The whole transition is computed on a copy, and canonical state is only
  /// replaced once the attempt is durably appended. That matters for a storage
  /// failure that does *not* kill the process: if the append throws, the
  /// session is left exactly where it started, the decision is still pending,
  /// and calling this again is safe. Applying the update first would leave
  /// state ahead of the journal, and a retry would then fold the same outcome
  /// in twice from an already-advanced state.
  ///
  /// The decision is cleared last. A crash between the append and the clear
  /// leaves a stale slot that the next [open] recognizes as already committed.
  ///
  /// Single-writer: retrying a close that has already failed is safe, and
  /// entering this method twice concurrently is not, for the reason given on
  /// [PracticeSession]. A UI driving this from a button has to make that button
  /// single-flight rather than relying on the attempt id to deduplicate.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding.
  Future<AttemptRecord> closeWithOutcome(
    Outcome outcome, {
    AttemptTermination termination = AttemptTermination.learnerStopped,
    DateTime? observedWallTime,
  }) => _close(
    termination: termination,
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
  /// The reading comes back beside the record because the record deliberately
  /// does not carry it. History stores the outcome, which is what replay needs
  /// and what a later model must be able to reinterpret; the correspondence
  /// behind it is transient, and a caller that wants to say where something
  /// went wrong has to be handed it while it still exists.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding.
  Future<ClosedAttempt> closeFromPerformance(
    PerformanceTranscript transcript, {
    AttemptTermination termination = AttemptTermination.learnerStopped,
    MeasurementPolicy policy = MeasurementPolicy.standard,
    DateTime? observedWallTime,
  }) async {
    final outstanding = _outstanding ?? _pendingAsOutstanding();
    final reading = readPerformance(
      exercise: outstanding.decision.exercise,
      transcript: transcript,
      policy: policy,
    );

    return ClosedAttempt(
      record: await _close(
        termination: termination,
        outcome: reading.outcome,
        observedWallTime: observedWallTime,
      ),
      reading: reading,
    );
  }

  /// Ends the outstanding attempt with the learner reporting that they could
  /// not retrieve the material.
  ///
  /// A retrieval failure with no execution beside it, which is a state the
  /// learner model already carries: memory evidence at full weight for the
  /// rung, no execution evidence at all, and a recovery context that offers
  /// the same exercise one rung more supportive. Without this the only way to
  /// say it was to play something wrong, which manufactures execution evidence
  /// that never happened.
  ///
  /// The claim is about retrieval, so it is only available at a rung that
  /// tests retrieval. It is also a claim that nothing was played, so
  /// [transcript] is required: the caller shows what arrived rather than being
  /// trusted to have called this at the right moment. An attempt with notes in
  /// it is a question for measurement, and [closeFromPerformance] is where it
  /// belongs.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding, when the
  /// outstanding attempt is at a rung that supplies the material anyway, or
  /// when anything was played.
  Future<AttemptRecord> closeDeclined({
    required PerformanceTranscript transcript,
    DateTime? observedWallTime,
  }) {
    final outstanding = _outstanding ?? _pendingAsOutstanding();
    final guidance = outstanding.decision.exercise.guidance;
    if (!guidance.isRetrievalObserved) {
      throw PracticeStateError(
        'nothing to fail to retrieve: this rung supplies the material',
      );
    }
    if (transcript.isNotEmpty) {
      throw PracticeStateError(
        '${transcript.length} notes were played, so what happened is a '
        'question for measurement rather than for the learner',
      );
    }

    return _close(
      termination: AttemptTermination.learnerDeclined,
      outcome: Outcome(
        started: false,
        retrieval: FactualRetrieval.failed,
        completed: false,
        materialRetrieval: 0.0,
        pitchIntegrity: 0.0,
        continuity: 0.0,
        temporalStability: 0.0,
        achievedTempoRatio: 0.0,
        topologyAccuracy: 0.0,
      ),
      observedWallTime: observedWallTime,
    );
  }

  /// Ends the outstanding attempt with nothing measured.
  ///
  /// The honest close for an attempt that ended without anyone establishing how
  /// it went: a timeout, or any path that is not a learner reporting. It moves
  /// no learner state, because nothing was observed, and the record exists to
  /// say the attempt ended rather than to claim anything about the
  /// performance.
  ///
  /// The transaction discipline is the same as [closeWithOutcome]'s, for the
  /// same
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
    pipeline.recordOutcome(_session, decision.exercise, outcome);
    _outstanding = null;
    _pending = null;

    await store.clearPendingDecision(profile.id);
    return record;
  }

  /// Discards an unresolved decision without recording anything.
  ///
  /// Costs nothing and recovers nothing: the decision moved no state and wrote
  /// no evidence, and the sitting's own state is rebuilt from the journal, so
  /// an abandoned slot leaves no trace to clean up. Presenting the decision
  /// again is the better answer wherever the exercise can still be played,
  /// which is why the app does that instead.
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

  ScopeResolution _resolve(PracticeGoal goal, PracticeFocus focus) =>
      _scopeResolver.resolve(
        goal: goal,
        focus: focus,
        catalog: _materials,
        instrument: _instrument,
      );

  /// Reads the checkpoint only if it is safe to start from.
  static Future<LearnerStateCheckpoint?> _usableCheckpoint(
    PracticeStore store,
    String profileId,
    LearnerModel learner,
    AttemptJournal journal,
  ) async {
    try {
      final checkpoint = await store.loadCheckpoint(profileId);
      if (checkpoint == null) return null;
      // A checkpoint covering history the journal does not hold is standing in
      // for attempts that are gone, which is what an erase leaves behind if a
      // sitting saves one after it.
      if (checkpoint.throughJournalSequence >= journal.length) return null;
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
  /// Only the recency and pacing windows carry over, from the tail of the
  /// journal. The attempt cap and any recovery context deliberately do not: a
  /// restart is a new sitting, and a recovery context that outlived the failure
  /// it responded to would answer a question nobody is still asking.
  ///
  /// Allocation, unlike recovery, is a question about the recent past rather
  /// than about the last attempt, so reopening the app must not clear the
  /// pressure the work before it built up.
  static SessionState _rebuildSessionState(
    AttemptJournal journal,
    LearnerModel learner,
    SchedulerConfig config,
  ) {
    final records = journal.records;
    final recent = records
        .map((record) => record.exercise.material.materialId)
        .toList();
    final window = config.diversity.recentWindow;
    final session = SessionState(
      recentMaterialIds: recent.length <= window
          ? recent
          : recent.sublist(recent.length - window),
    );
    if (config.pacing case final pacing?) {
      final paced = records.length <= pacing.window
          ? records
          : records.sublist(records.length - pacing.window);
      for (final record in paced) {
        session.recordFamilySelection(
          record.exercise,
          productive: switch (record.closure.measurement) {
            Measured(:final outcome) => learner.executionWasManaged(outcome),
            MeasurementUnavailable() => false,
          },
          config: pacing,
        );
      }
    }
    return session;
  }
}
