import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'acquisition_closure.dart';
import 'pending_decision.dart';
import 'performance_closure.dart';
import 'practice_store.dart';
import 'requirement_state.dart';
import 'scheduler_host.dart';
import 'scope_resolution.dart';

/// What is known about a prepared attempt reaching authoritative history.
///
/// Three states, not two. "Not written" and "nobody can say" are different
/// facts about the same failed append, and treating the second as the first is
/// how an attempt that did land gets abandoned.
enum _Durability {
  /// Storage established that no such attempt is recorded.
  ///
  /// The transaction may be written again, or abandoned.
  notWritten,

  /// An append did not answer, and neither did the read that would settle it.
  ///
  /// Nothing may conclude either way while this holds.
  unknown,

  /// This exact attempt is in authoritative history.
  durable,
}

/// One attempt's commit, frozen at the moment it was computed.
///
/// Once a close begins, nothing that would change what is written may still
/// matter. The caller reads its clock again on every call and may hand over a
/// fresh transcript, so a retry that recomputed would offer the same attempt
/// id carrying different content, which an authoritative log refuses.
///
/// The two flags are the phases a commit passes through. They are separate
/// because the boundary between them is the durable append: before it nothing
/// has happened, after it the attempt is history whether or not this session
/// finished tidying up.
class _PreparedCommit {
  /// The attempt exactly as it will be, and was, written.
  final AttemptRecord record;

  /// The learner state this attempt produces, computed on a copy.
  final LearnerState next;

  /// What was observed, for the scheduler's own bookkeeping.
  final Outcome? outcome;

  /// The reading the outcome was derived from, when it came from a
  /// performance.
  ///
  /// Frozen with the rest. A retry that read the transcript again could hand
  /// back a reading describing a different performance than the record it
  /// accompanies, which is one result contradicting itself.
  final PerformanceReading? reading;

  /// What is known about [record] reaching authoritative history.
  _Durability durability = _Durability.notWritten;

  /// Whether canonical state has advanced for it, which happens exactly once.
  bool isApplied = false;

  _PreparedCommit({
    required this.record,
    required this.next,
    required this.outcome,
    this.reading,
  });
}

/// How far a recomputed prediction may drift before a recovered decision is
/// refused.
///
/// Not zero, because the model is floating-point and a rebuild may sum in a
/// different order; the same tolerance replay compares under.
const double _predictionTolerance = 1e-9;

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

/// Supported acquisition was offered instead of ordinary work.
///
/// Outstanding once returned, the way an ordinary presentation is: deciding
/// again while it stands is refused, because it carries the identity the
/// attempt will be recorded under and the record a retry would write. Close it
/// with `closeAcquisition` or abandon it.
///
/// Nothing about it is durable before it is played. There is no decision to
/// recover and no learner state it could leave half-applied, which is why it
/// is not a [PresentedAttempt] and why abandoning it writes nothing.
@immutable
class PresentedAcquisition extends PracticeDecision {
  /// Which presentation this is.
  ///
  /// Its own identity, and not the ordinary attempt's. Two offers of the same
  /// task are two attempts at it, and a screen keyed on the task alone would
  /// keep the finished state of the one before.
  final String attemptId;

  /// The supported task to present.
  final AcquisitionTask task;

  /// Curriculum coverage at the instant it was offered.
  final ScopeCoverage coverage;

  /// The ordinary work this was chosen instead of, if any.
  final Exercise? displaced;

  const PresentedAcquisition({
    required this.attemptId,
    required this.task,
    required this.coverage,
    this.displaced,
  });

  @override
  String toString() => 'PresentedAcquisition($attemptId, $task)';
}

/// Useful work was requested, but no exercise could be presented.
@immutable
class PracticeBlocked extends PracticeDecision {
  final BlockedReason reason;

  /// Every candidate the slot considered, where it was decided in this
  /// isolate. Null where a worker decided it, which sends back the reason and
  /// not ten thousand traces.
  final SelectionResult? selection;

  final ScopeCoverage coverage;

  const PracticeBlocked(this.reason, {required this.coverage, this.selection});
}

/// A verdict arrived for scheduler inputs that are no longer current.
///
/// Not a failure: something legitimately changed while the decision was being
/// computed, and the answer is about a session state that has moved. Deciding
/// again produces a current one.
@immutable
class PracticeSuperseded extends PracticeDecision {
  /// The epoch the discarded verdict answered.
  final int epoch;

  const PracticeSuperseded(this.epoch);
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
/// finish before starting the next. Entering a close twice concurrently
/// produces a second record under the same attempt id, which the journal
/// rejects as a collision rather than absorbing as a retry.
class PracticeSession {
  /// The learner model in force.
  final LearnerModel learner;

  /// The scheduler in force.
  final SchedulerPipeline pipeline;

  /// Where a decision is computed.
  final SchedulerHost scheduler;

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
  AcquisitionJournal _acquisition;

  /// The supported task on screen, if one is.
  ///
  /// Outstanding in the same sense an ordinary presentation is: it has an
  /// identity, it holds the record a retry would write again, and deciding
  /// again while it stands would replace both without closing either.
  PresentedAcquisition? _outstandingAcquisition;

  /// The record built for it, held so a retry writes the same event.
  AcquisitionAttemptRecord? _acquisitionInFlight;

  /// Whether an acquisition write left what is durable unknown.
  ///
  /// Set when neither an append nor the read that would settle it answered.
  /// While it holds, the in-memory log may be behind the file, and nothing may
  /// build another event from it.
  bool _acquisitionDurabilityUnknown = false;

  /// Attempts whose presentation has already been acknowledged.
  final Set<String> _acknowledged = {};

  LearnerState _state;

  /// Which version of this session's scheduler inputs is current.
  ///
  /// Optimistic concurrency for an answer computed elsewhere, and nothing to do
  /// with the state hashes recorded on attempts: those establish that persisted
  /// history is what it claims to be, while this establishes that an
  /// asynchronous verdict was computed from inputs that still hold. It advances
  /// whenever anything a scheduling decision reads changes, not only when an
  /// attempt commits.
  int _epoch = 0;

  /// Whether [scheduler] holds the scope currently in force.
  bool _bound = false;

  PendingDecision? _pending;
  PresentedAttempt? _outstanding;

  /// The commit in progress, frozen at the moment it was computed.
  _PreparedCommit? _commit;

  /// Hash of the placement state this profile's history propagates from.
  ///
  /// Held because a checkpoint's digest covers it: the prior is what every
  /// posterior in the journal is a function of, so a checkpoint taken under
  /// one placement must not seed a replay under another.
  final String _genesisStateHash;

  late ScopeResolution _scopeResolution;

  PracticeSession._({
    required this.learner,
    required this.pipeline,
    required this.scheduler,
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
    required AcquisitionJournal acquisition,
    required PendingDecision? pending,
    required String genesisStateHash,
  }) : _nextId = nextId,
       _genesisStateHash = genesisStateHash,
       _state = state,
       _session = session,
       _journal = journal,
       _acquisition = acquisition,
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
    SchedulerHost? scheduler,
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
    final resolvedScheduler = scheduler ?? InProcessScheduler(resolvedPipeline);
    final generator = nextId ?? newProfileId;
    final journal = await store.loadJournal(
      profile.id,
      createdAt: profile.createdAt,
    );
    _requireOwnership(journal.header.profileId, profile.id, 'journal');

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
      from: await _usableCheckpoint(
        store,
        profile.id,
        learner,
        journal,
        learnerStateHash(initial),
      ),
    );
    if (!replay.isFaithful) {
      throw JournalFormatException(
        'replaying the journal for ${profile.id} did not reproduce it: '
        '${replay.divergences.first}',
      );
    }

    final acquisition = await store.loadAcquisitionJournal(
      profile.id,
      createdAt: profile.createdAt,
    );
    _requireOwnership(
      acquisition.header.profileId,
      profile.id,
      'acquisition log',
    );
    final pending = await _recoverPending(
      store,
      profile,
      journal,
      learner,
      replay.state,
    );

    return PracticeSession._(
      learner: learner,
      pipeline: resolvedPipeline,
      scheduler: resolvedScheduler,
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
      genesisStateHash: learnerStateHash(initial),
      session: _rebuildSessionState(journal, learner, resolvedPipeline.config),
      journal: journal,
      acquisition: acquisition,
      pending: pending,
    );
  }

  /// The learner state this sitting reasons from.
  ///
  /// Advances only when an attempt is durably present in authoritative
  /// history, and exactly once for that attempt. Anything that looks ahead
  /// works on a copy, or replay could not reproduce the timeline.
  ///
  /// Mutable, because the learner model is. Treat it as read-only: advancing
  /// it here puts this sitting's state somewhere replaying the journal cannot
  /// reach.
  ///
  /// Read it again after each close rather than holding the object across
  /// one: a commit replaces it wholesale, so a cached reference would quietly
  /// go stale.
  LearnerState get state => _state;

  /// Every attempt recorded for this profile so far.
  AttemptJournal get journal => _journal;

  /// Every acquisition event recorded for this profile so far.
  AcquisitionJournal get acquisitionJournal => _acquisition;

  /// What acquisition history says about this profile now.
  ///
  /// Replayed rather than held, so it is whatever the durable log produces and
  /// cannot drift from it.
  AcquisitionProgress get acquisitionProgress => _acquisition.replay();

  /// The scheduler's view of this sitting.
  SessionState get session => _session;

  /// Which version of this session's scheduler inputs is current.
  ///
  /// A verdict computed elsewhere carries the epoch it answered, and one that
  /// no longer matches is discarded rather than applied.
  int get decisionEpoch => _epoch;

  /// The current structural candidate envelope, empty for an invalid scope.
  List<Exercise> get candidates => switch (_scopeResolution) {
    ValidPracticeScope(:final scope) => List.unmodifiable(
      distinctCandidatesOf(scope.requirements),
    ),
    InvalidPracticeScope() => const [],
  };

  /// A decision from an interrupted run that was never answered.
  ///
  /// Present means the last run showed an exercise and did not record what
  /// happened. Resolve it before deciding again.
  PendingDecision? get pending => _pending;

  /// Whether anything is currently outstanding, ordinary or supported.
  ///
  /// A commit whose evidence is durable but whose transaction did not finish
  /// counts: closing again is what completes it.
  bool get hasOutstandingAttempt =>
      _outstanding != null ||
      _outstandingAcquisition != null ||
      _commit != null;

  /// The supported task on screen, if one is.
  PresentedAcquisition? get outstandingAcquisition => _outstandingAcquisition;

  /// Applies a new goal or focus to the next undecided slot.
  ///
  /// An outstanding or recovered decision remains unchanged until it closes or
  /// is abandoned.
  void updateScope({
    required PracticeGoal goal,
    PracticeFocus focus = PracticeFocus.unrestricted,
  }) {
    _scopeResolution = _resolve(goal, focus);
    _epoch++;
    _bound = false;
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
    if (_outstandingAcquisition != null) {
      throw PracticeStateError(
        'a supported task is already outstanding; record or abandon it first',
      );
    }
    if (_commit != null) {
      throw PracticeStateError(
        'an attempt is committed but its transaction did not finish; close it '
        'again first',
      );
    }

    final resolution = _scopeResolution;
    if (resolution case InvalidPracticeScope(:final failures)) {
      return PracticeInvalidScope(failures);
    }
    final validScope = resolution as ValidPracticeScope;
    final scope = validScope.scope;

    // The caller passes a clock reading, which the observation boundary turns
    // into a model time before anything is evaluated or persisted.
    final observed = at.toUtc();
    at = _observationTime(observed);
    final observedWallTime = at == observed ? null : observed;

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
    // Two questions of the same value, and only one of them is narrow. Ordinary
    // admission reaches for a safe entry when a scoped slot has nothing left to
    // offer, which a general sitting never runs out of work to need. Acquisition
    // asks something else of it: which realizations are the family's floor at
    // all, and that is as true of general practice as of a scoped goal. Passing
    // it only for a narrow scope left a beginner practising normally unable to
    // reach supported work at the exact exercise they keep not managing.
    final familyFloor = _scopeResolver.acquisitionFloorFor(
      due.map((state) => state.resolved),
    );
    final acquisitionFloor = scope.isNarrow ? familyFloor : null;

    // Captured before binding, not after. Binding is asynchronous, and a scope
    // change during it leaves the host holding the old scope while the request
    // that follows carries the new epoch, so an old-scope verdict passes the
    // check that exists to catch exactly that. Marking the binding current
    // afterwards would also undo the invalidation the scope change performed.
    final epoch = _epoch;
    if (!_bound) {
      await scheduler.bind(
        scope: scope,
        entry: validScope.entryPolicy,
        learner: learner,
        config: pipeline.config,
      );
      if (epoch != _epoch) return PracticeSuperseded(epoch);
      _bound = true;
    }
    final verdict = await scheduler.decide(
      epoch: epoch,
      state: scratch,
      session: _session,
      dueRequirementIds: [
        for (final requirement in due) requirement.resolved.requirement.id,
      ],
      at: at,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: familyFloor,
      acquisition: acquisitionProgress,
      attemptedExercises: attemptedExercises(_journal.records),
      executionEvidenceRevisions: executionEvidenceRevisions(_journal.records),
    );
    // Nothing is applied and nothing is written: while this was computed, the
    // inputs it answers about stopped being the current ones.
    if (verdict.epoch != _epoch) return PracticeSuperseded(verdict.epoch);

    verdict.effect.applyTo(_session);
    if (verdict.acquisitionTask case final task?) {
      final offered = PresentedAcquisition(
        attemptId: _nextId(),
        task: task,
        coverage: evaluated.coverage,
        displaced: verdict.displacedByAcquisition,
      );
      _outstandingAcquisition = offered;
      return offered;
    }
    if (verdict.chosen == null) {
      return PracticeBlocked(
        verdict.blockedReason!,
        selection: verdict.result,
        coverage: evaluated.coverage,
      );
    }
    final chosen = verdict.chosen!;

    final decision = PendingDecision(
      attemptId: _nextId(),
      profileId: profile.id,
      sessionId: sessionId,
      indexInSession: _indexInSession,
      journalSequence: _journal.nextSequence,
      decidedAt: at,
      observedWallTime: observedWallTime,
      provenance: ModelProvenance.of(
        learnerParams: learner.params,
        schedulerModelVersion: pipeline.config.modelVersion,
        appBuildVersion: appBuildVersion,
      ),
      exercise: chosen.exercise,
      decision: SchedulerDecision.fromTrace(chosen, pipeline.config),
      stateBeforeHash: learnerStateHash(scratch),
    );

    if (verdict.diagnostics.isNotEmpty) {
      try {
        await store.appendSelectionDiagnostics(
          profile.id,
          decision.attemptId,
          verdict.diagnostics,
        );
      } catch (_) {
        // Losing diagnostics must not prevent practice.
      }
    }
    // Durable before the exercise is shown. Everything after this point is
    // recoverable; before it, nothing was presented.
    await store.savePendingDecision(decision);
    final presented = PresentedAttempt(decision, coverage: evaluated.coverage);
    _outstanding = presented;
    return presented;
  }

  /// Records that the outstanding attempt has actually reached the learner.
  ///
  /// Deciding is not presenting. The next exercise is prepared while the last
  /// one's review is still on screen, and a prepared decision can be discarded
  /// by a profile or scope change before anybody sees it. Discharging an
  /// obligation there would say a question had been asked that never was.
  ///
  /// Idempotent per attempt, and applies to a decision resumed from an earlier
  /// run as readily as to one this sitting made: a pending attempt that comes
  /// back on screen is being presented now.
  ///
  /// Named rather than assumed. A caller reporting this from a frame callback
  /// says which attempt was drawn, so a decision that has since been replaced
  /// cannot be acknowledged in place of the one that actually reached the
  /// learner.
  Future<void> acknowledgePresentation(String attemptId) async {
    final decision = _outstanding?.decision ?? _pending;
    if (decision == null || decision.attemptId != attemptId) return;
    if (!_acknowledged.add(attemptId)) return;
    await _serveAcquisitionProbe(decision);
  }

  /// Records that presenting [decision] asked what acquisition earned.
  ///
  /// Keyed on the exercise being presented rather than on why it was chosen. A
  /// parent reaches the learner because the service phase served an owed probe
  /// or because ordinary ranking picked it, and either way the question has
  /// been asked; discharging only the first would ask it again next slot.
  ///
  /// A failed write leaves the obligation owed, which costs a redundant probe
  /// later. Failing the attempt instead would cost the learner their practice,
  /// which is the worse of the two.
  Future<void> _serveAcquisitionProbe(PendingDecision decision) async {
    try {
      await _reconcileAcquisition();
    } catch (error) {
      // Storage is still not answering. The obligation stays owed, which is
      // what an unserved probe already means, and the next presentation tries
      // again.
      await _recordServiceFailure(decision, error);
      return;
    }
    final logicalTime = _observationTime(decision.decidedAt);
    final service = acquisitionServiceOf(
      presented: decision.exercise,
      progress: acquisitionProgress,
      identity: AttemptIdentity(
        profileId: decision.profileId,
        attemptId: decision.attemptId,
        sessionId: decision.sessionId,
        indexInSession: decision.indexInSession,
        occurredAt: logicalTime,
      ),
      journalSequence: _acquisition.nextSequence,
      // The decision time is already past the observation boundary, so the
      // raw reading is the one recorded when it was decided.
      observedWallTime: logicalTime == decision.decidedAt
          ? decision.observedWallTime
          : decision.decidedAt,
    );
    if (service == null) return;
    try {
      await _appendAcquisition(service);
    } catch (error) {
      await _recordServiceFailure(decision, error);
    }
  }

  /// Appends [entry] and leaves memory agreeing with what is durable.
  ///
  /// An acknowledged append is authoritative: what was written is known, so it
  /// goes into the log here rather than being read back for. A reload that
  /// failed afterwards would otherwise leave memory a record behind the file,
  /// and every later write would collide with a sequence the file already has.
  ///
  /// An append that threw may still have landed, so nothing concludes from an
  /// exception that nothing was written. The durable log is read and has to
  /// hold this exact event: an id that comes back carrying different content is
  /// a collision rather than the write succeeding, and calling that success
  /// would drop what was actually recorded.
  Future<void> _appendAcquisition(AcquisitionEntry entry) async {
    try {
      await store.appendAcquisitionEntry(entry);
    } catch (error, stack) {
      final AcquisitionJournal durable;
      try {
        durable = await store.loadAcquisitionJournal(profile.id);
      } catch (_) {
        // Neither the write nor the read answered, so what is durable is
        // unknown. Saying so is the point: the next event must not be built
        // against a log that may already be a record behind the file.
        _acquisitionDurabilityUnknown = true;
        Error.throwWithStackTrace(error, stack);
      }

      // A successful read is a trustworthy baseline whatever it proves about
      // this entry, so it is adopted before anything is concluded. Keeping the
      // old log because the read did not contain what was hoped for is what
      // leaves memory permanently behind the file.
      _acquisition = durable;
      _acquisitionDurabilityUnknown = false;

      final held = durable.records.where(
        (record) => record.identity.attemptId == entry.identity.attemptId,
      );
      if (held.isEmpty ||
          contentHash(held.single.toJson()) != contentHash(entry.toJson())) {
        Error.throwWithStackTrace(error, stack);
      }
      return;
    }
    _acquisition.append(entry);
  }

  /// Reloads acquisition history when what is durable is not known.
  ///
  /// Called before another acquisition event is built, because the sequence it
  /// will carry comes from this log. Proposing one against a log that is a
  /// record behind the file produces an event the store refuses forever, under
  /// a new id each time.
  Future<void> _reconcileAcquisition() async {
    if (!_acquisitionDurabilityUnknown) return;
    _acquisition = await store.loadAcquisitionJournal(profile.id);
    _acquisitionDurabilityUnknown = false;
  }

  /// Says that a service write did not land, without failing the attempt.
  ///
  /// Non-blocking is not the same as invisible. One lost write costs a
  /// redundant probe and a systematic one is storage quietly failing, which is
  /// worth being able to find. The next ordinary presentation of the same
  /// parent tries again, so nothing retries here.
  ///
  /// Recorded under a key derived from the attempt rather than the attempt's
  /// own, because the selection diagnostics for it are already written and
  /// keyed by that id.
  Future<void> _recordServiceFailure(
    PendingDecision decision,
    Object error,
  ) async {
    try {
      await store.appendSelectionDiagnostics(
        decision.profileId,
        '${decision.attemptId}:acquisition-service',
        'acquisition probe service was not recorded\n'
            'parent=${decision.exercise}\n'
            'error=$error\n'
            'the obligation is left owed; a later presentation discharges it',
      );
    } catch (_) {
      // Storage is failing broadly, and the attempt's own append will say so.
    }
  }

  /// The presented attempt, or null for a blocked scheduling request.
  ///
  /// Compatibility for callers that have not yet adopted [decideOutcome]. New
  /// product code must match the reasoned result instead of treating blocked
  /// practice as ordinary absence.
  Future<PresentedAttempt?> decide({required DateTime at}) async {
    final decision = await decideOutcome(at: at);
    if (decision case final PresentedAttempt presented) return presented;
    // A caller on this path has said it only presents ordinary attempts, so an
    // offered task is declined here rather than left standing. Leaving it
    // outstanding would refuse the caller's next decision over something it
    // never showed anybody.
    if (decision is PresentedAcquisition) {
      _outstandingAcquisition = null;
      _acquisitionInFlight = null;
    }
    return null;
  }

  /// Records what an acquisition attempt produced.
  ///
  /// Not a transaction, because there is nothing to make consistent. There is
  /// no pending decision to clear, no learner state to advance, and no outcome
  /// to derive: the whole of what an acquisition attempt does is add an event
  /// to its own log, and that log answers to nothing but itself.
  ///
  /// Records an attempt the learner stopped partway as readily as one that
  /// finished. Where it ran out, what it cost to get that far, and how long the
  /// waits were are the observations acquisition exists to keep.
  ///
  /// The caller supplies [at] because presentation time belongs to the loop
  /// that presented it, not to a clock this reads.
  Future<AcquisitionAttemptRecord> closeAcquisition(
    PerformanceTranscript transcript, {
    required DateTime at,
    AttemptTermination termination = AttemptTermination.learnerStopped,
    MeasurementPolicy policy = MeasurementPolicy.standard,
  }) async {
    final outstanding = _outstandingAcquisition;
    if (outstanding == null) {
      throw PracticeStateError('no supported task is outstanding');
    }
    // Built once and held. A retry after an uncertain write must offer the
    // same event under the same id, or the store's idempotency has nothing to
    // recognize and the same attempt lands twice.
    if (_acquisitionInFlight == null) await _reconcileAcquisition();
    final logicalTime = _observationTime(at);
    final record = _acquisitionInFlight ??= acquisitionRecordOf(
      observation: observeAcquisition(
        task: outstanding.task,
        transcript: transcript,
        policy: policy,
      ),
      identity: AttemptIdentity(
        profileId: profile.id,
        attemptId: outstanding.attemptId,
        sessionId: sessionId,
        indexInSession: _indexInSession,
        occurredAt: logicalTime,
      ),
      journalSequence: _acquisition.nextSequence,
      termination: termination,
      observedWallTime: logicalTime == at ? null : at,
      executionEvidenceRevision:
          executionEvidenceRevisions(_journal.records)[executionContextOf(
            outstanding.task.parent,
          )] ??
          0,
    );
    await _appendAcquisition(record);
    _outstandingAcquisition = null;
    _acquisitionInFlight = null;
    _epoch++;
    return record;
  }

  /// The model time an observation read at [wallTime] belongs to.
  ///
  /// The observation boundary. A device clock really can be corrected backward
  /// mid-session, and the model timeline cannot follow it: every memory
  /// transition is driven by elapsed time, and propagating backward is
  /// illegal. A reading behind where history already stands is raised to it
  /// here, before anything is persisted, and the raw reading is kept for
  /// diagnostics.
  ///
  /// The journal tail bounds this whether or not that last attempt was
  /// measured. An unmeasured attempt moved no state, but it is still recorded
  /// history, and the log refuses a record that precedes it.
  DateTime _observationTime(DateTime wallTime) {
    var logical = wallTime.toUtc();
    for (final lowerBound in [
      profile.createdAt,
      if (_journal.records.isNotEmpty)
        _journal.records.last.identity.occurredAt,
      if (_acquisition.records.isNotEmpty)
        _acquisition.records.last.identity.occurredAt,
    ]) {
      if (logical.isBefore(lowerBound)) logical = lowerBound;
    }
    return logical;
  }

  /// Ends the outstanding attempt with an outcome established elsewhere.
  ///
  /// The seam between this transaction and the observation model. A caller that
  /// already knows how an attempt went states it here, which is what exercises
  /// the scheduler and the journal over trajectories no transcript could
  /// produce: an outcome is not invertible into a performance that measures
  /// back to it. Learner-facing attempts are measured instead.
  ///
  /// The whole transition is computed on a copy, and canonical learner state
  /// is only replaced once the attempt is durably appended. That matters for a
  /// storage failure that does *not* kill the process: if the append throws
  /// having written nothing, the session is left exactly where it started, the
  /// decision is still pending, and calling this again is safe. Applying the
  /// update first would leave state ahead of the journal, and a retry would
  /// then fold the same outcome in twice from an already-advanced state.
  ///
  /// The attempt is computed once and held. Calling this again finishes that
  /// transaction rather than building a second one, so an outcome or wall-clock
  /// reading supplied to a retry is ignored: the record was already decided,
  /// and possibly already written.
  ///
  /// The decision is cleared last. A crash between the append and the clear
  /// leaves a stale slot that the next [open] recognizes as already committed,
  /// and a *failed* clear leaves this transaction open, so closing again
  /// finishes it and returns the same record.
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
  /// The reading comes back beside the record because the record does not carry
  /// it. History stores the outcome, which is what replay needs and what a
  /// later model reinterprets, while the correspondence behind it is transient
  /// and has to be handed over while it still exists.
  ///
  /// Throws [PracticeStateError] when no attempt is outstanding.
  Future<ClosedAttempt> closeFromPerformance(
    PerformanceTranscript transcript, {
    AttemptTermination termination = AttemptTermination.learnerStopped,
    MeasurementPolicy policy = MeasurementPolicy.standard,
    DateTime? observedWallTime,
  }) async {
    if (_commit case final held? when held.reading == null) {
      throw PracticeStateError(
        'this attempt was closed without a performance, and that transaction '
        'is still open; finish it the way it was started',
      );
    }

    // Resuming asks nothing of this transcript: the reading was frozen with
    // the record, so the pair handed back always describes one performance.
    final commit = await _commitTransaction(() {
      final outstanding = _outstanding ?? _pendingAsOutstanding();
      final reading = readPerformance(
        exercise: outstanding.decision.exercise,
        transcript: transcript,
        policy: policy,
      );
      return _prepare(
        termination: termination,
        outcome: reading.outcome,
        unavailable: null,
        observedWallTime: observedWallTime,
        reading: reading,
      );
    });

    return ClosedAttempt(record: commit.record, reading: commit.reading!);
  }

  /// Ends the outstanding attempt with the learner reporting that they could
  /// not retrieve the material.
  ///
  /// A retrieval failure with no execution beside it, which the learner model
  /// already carries: memory evidence at full weight for the rung, no execution
  /// evidence, and a recovery context one rung more supportive. Without it the
  /// only way to say so is to play something wrong, which manufactures
  /// execution evidence that never happened.
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
    // Only when this is a new transaction. Resuming one asks nothing of the
    // caller's arguments, so validating them again could refuse to finish a
    // close whose record may already be history.
    if (_commit == null) {
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
  /// The transaction discipline is [closeWithOutcome]'s.
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
  }) async => (await _commitTransaction(
    () => _prepare(
      termination: termination,
      outcome: outcome,
      unavailable: unavailable,
      observedWallTime: observedWallTime,
    ),
  )).record;

  /// Carries a close through to the end, preparing one only if none is open.
  ///
  /// [prepare] runs exactly once per transaction, when it begins. A retry
  /// resumes what is already held, so nothing a caller passes a second time is
  /// consulted: the complete result was decided when the close started, and
  /// may already be written.
  Future<_PreparedCommit> _commitTransaction(
    _PreparedCommit Function() prepare,
  ) async {
    // Prepared once. A retry finishes this transaction rather than computing a
    // second one: the caller reads its clock again on every call, so rebuilding
    // would offer the same attempt id carrying different content, which an
    // authoritative log is right to refuse.
    final commit = _commit ??= prepare();

    // The durable append is the boundary. Canonical learner state does not
    // advance until the attempt is in authoritative history, and advances
    // exactly once for it. Scheduler bookkeeping, the pending slot, and probe
    // service legitimately move on either side of this line; learner state
    // does not.
    if (commit.durability != _Durability.durable) await _appendAttempt(commit);

    if (!commit.isApplied) {
      _state = commit.next;
      _epoch++;
      _journal.append(commit.record);
      // The exercise was presented either way, so the sitting knows it was. A
      // retrieval failure is a claim about the performance, and an unmeasured
      // attempt supports no such claim.
      pipeline.recordOutcome(
        _session,
        commit.record.exercise,
        commit.outcome,
        at: commit.record.identity.occurredAt,
      );
      commit.isApplied = true;
    }

    // A committed attempt reached the learner, whatever the caller said about
    // presenting it. Serving here too is idempotent, and it stops an
    // obligation outliving the question it asks: an owed probe is offered
    // again every slot, so a caller that never acknowledges is served the same
    // probe until the sitting ends.
    await acknowledgePresentation(commit.record.identity.attemptId);
    _outstanding = null;
    _pending = null;

    await store.clearPendingDecision(profile.id);
    _commit = null;
    return commit;
  }

  /// Computes the attempt this close will commit, and freezes it.
  ///
  /// Everything that decides what gets written happens here, on a copy, before
  /// anything durable is touched.
  _PreparedCommit _prepare({
    required AttemptTermination termination,
    required Outcome? outcome,
    required MeasurementUnavailableReason? unavailable,
    required DateTime? observedWallTime,
    PerformanceReading? reading,
  }) {
    final decision = (_outstanding ?? _pendingAsOutstanding()).decision;
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

    return _PreparedCommit(
      record: decision.complete(
        closure: closure,
        stateAfterHash: learnerStateHash(next),
        observedWallTime: observedWallTime,
      ),
      next: next,
      outcome: outcome,
      reading: reading,
    );
  }

  /// Appends the prepared attempt, settling what happened when the answer is
  /// uncertain.
  ///
  /// An append that threw may still have landed, so nothing concludes from an
  /// exception that nothing was written. There are three answers and no
  /// others: this exact attempt is in history and the append committed, no
  /// attempt with that id is there and the same record may be written again,
  /// or that id is there carrying different content, which is a collision and
  /// not something to resolve by picking one.
  Future<void> _appendAttempt(_PreparedCommit commit) async {
    final record = commit.record;
    // Uncertain from the moment the write is in flight, and only settled by an
    // answer. A throw is not an answer.
    commit.durability = _Durability.unknown;
    try {
      await store.appendAttempt(record);
      commit.durability = _Durability.durable;
      return;
    } catch (error, stack) {
      final AttemptJournal durable;
      try {
        durable = await store.loadJournal(profile.id);
      } catch (_) {
        Error.throwWithStackTrace(error, stack);
      }

      _reconcileAttempt(commit, durable);
      if (commit.durability == _Durability.notWritten) {
        Error.throwWithStackTrace(error, stack);
      }
    }
  }

  void _reconcileAttempt(_PreparedCommit commit, AttemptJournal journal) {
    final record = commit.record;
    commit.durability = _Durability.unknown;
    final held = journal.records.where(
      (held) => held.identity.attemptId == record.identity.attemptId,
    );
    if (held.isEmpty) {
      commit.durability = _Durability.notWritten;
      return;
    }
    if (contentHash(held.single.toJson()) != contentHash(record.toJson())) {
      throw JournalFormatException(
        'attempt ${record.identity.attemptId} is recorded with different '
        'content than this transaction holds',
        location: 'attempt ${record.identity.attemptId}',
      );
    }
    commit.durability = _Durability.durable;
  }

  /// Discards an unresolved decision without recording anything.
  ///
  /// Costs nothing and recovers nothing: the decision moved no state and wrote
  /// no evidence, so an abandoned slot leaves no trace. Presenting the decision
  /// again is the better answer wherever the exercise can still be played.
  ///
  /// A close that has begun may only be abandoned once storage has established
  /// that its attempt is absent from history. An append that threw may still
  /// have landed, so where that is unknown this reads history to settle it and
  /// fails if it cannot.
  ///
  /// Throws [PracticeStateError] when the attempt is already history.
  Future<void> abandonPending() async {
    if (_commit case final commit?) {
      // An append that threw may still have landed. Abandoning on the strength
      // of not knowing is what leaves one attempt in the file and none in the
      // sitting, and every later commit then aims at a sequence storage has
      // already filled.
      if (commit.durability == _Durability.unknown) {
        final durable = await store.loadJournal(profile.id);
        _reconcileAttempt(commit, durable);
      }
      if (commit.durability == _Durability.durable) {
        throw PracticeStateError(
          'this attempt is already history and cannot be abandoned; close it '
          'again to finish the transaction',
        );
      }
    }
    await store.clearPendingDecision(profile.id);
    _commit = null;
    _pending = null;
    _outstanding = null;
    _outstandingAcquisition = null;
    _acquisitionInFlight = null;
    _epoch++;
  }

  /// Saves a checkpoint at the current position, if there is history to cover.
  ///
  /// Purely an accelerator for the next [open]. Failing to save one costs time
  /// and nothing else.
  Future<LearnerStateCheckpoint?> saveCheckpoint() async {
    if (_journal.isEmpty) return null;
    final checkpoint = LearnerStateCheckpoint.after(
      _journal,
      throughSequence: _journal.length - 1,
      state: _state,
      learnerModelVersion: learner.params.modelVersion,
      genesisStateHash: _genesisStateHash,
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
  ///
  /// Anything wrong with it means a full replay rather than a failure: the
  /// journal is authoritative, and losing a checkpoint costs only time.
  static Future<LearnerStateCheckpoint?> _usableCheckpoint(
    PracticeStore store,
    String profileId,
    LearnerModel learner,
    AttemptJournal journal,
    String genesisStateHash,
  ) async {
    try {
      final checkpoint = await store.loadCheckpoint(profileId);
      if (checkpoint == null) return null;
      // Every part of what a checkpoint claims is checked against the journal
      // before it stands in for history: position, identity, time, its own
      // hash, the digest of the records it skips, and agreement with the state
      // the covered attempt produced. A checkpoint covering history the journal
      // does not hold is one of those rejections, which is what an erase leaves
      // behind if a sitting saves one after it.
      final rejection = validateCheckpointAgainstJournal(
        checkpoint,
        journal: journal,
        learnerModelVersion: learner.params.modelVersion,
        genesisStateHash: genesisStateHash,
      );
      return rejection == null ? checkpoint : null;
    } on JournalFormatException {
      // A corrupt or stale checkpoint is a cache miss, not a failure: the
      // journal still holds the history it was standing in for.
      return null;
    }
  }

  /// Refuses history belonging to somebody other than the profile opening it.
  ///
  /// The store checks this too. It is checked again here because a store is a
  /// port: a history whose owner nobody verified would be replayed into this
  /// person's learner state, and no amount of internal consistency in that
  /// file can establish whose it is.
  static void _requireOwnership(String owner, String profileId, String what) {
    if (owner == profileId) return;
    throw JournalFormatException(
      'this $what belongs to profile $owner, but $profileId opened it',
    );
  }

  /// Decides what an unresolved decision means, given what the journal holds.
  ///
  /// Validates before accepting it, because completing one appends it. A
  /// pending slot is disposable recovery state, and disposable state must not
  /// be able to manufacture authoritative history: a misplaced file would
  /// append one person's practice into another person's history, and an
  /// altered one would append an attempt that no longer replays.
  ///
  /// A slot from another learner-model version is abandoned rather than
  /// refused. Everything else that disagrees with the journal throws.
  static Future<PendingDecision?> _recoverPending(
    PracticeStore store,
    Profile profile,
    AttemptJournal journal,
    LearnerModel learner,
    LearnerState state,
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

    if (pending.provenance.learnerModelVersion != learner.params.modelVersion) {
      // Not damage, and not something to reinterpret. The decision was made
      // under one model's reading of this history, and completing it now would
      // apply today's model's update to yesterday's decision. Abandoning costs
      // one exercise nobody finished; deciding again is the honest answer.
      await store.clearPendingDecision(profile.id);
      return null;
    }

    _requireRecoverableClaims(pending, journal, learner, state);
    return pending;
  }

  /// Refuses a pending decision whose recomputable claims do not hold.
  ///
  /// A pending slot is disposable, and the attempt it names is not history
  /// yet. Completing one appends it, so every claim it makes that can be
  /// checked against authoritative history is checked here rather than after
  /// it has become part of that history. Nothing else stands between a damaged
  /// slot and a journal that no longer replays.
  ///
  /// Throws [JournalFormatException] for a claim the journal contradicts.
  static void _requireRecoverableClaims(
    PendingDecision pending,
    AttemptJournal journal,
    LearnerModel learner,
    LearnerState state,
  ) {
    final location = 'pending decision ${pending.attemptId}';
    void refuse(String message) =>
        throw JournalFormatException(message, location: location);

    if (journal.records.isNotEmpty) {
      final tail = journal.records.last.identity.occurredAt;
      if (pending.decidedAt.isBefore(tail)) {
        refuse(
          'pending decision was made at ${encodeTime(pending.decidedAt)}, '
          'before the last recorded attempt at ${encodeTime(tail)}; the model '
          'timeline cannot run backward',
        );
      }
    }

    final inSession = journal.session(pending.sessionId);
    if (inSession.isNotEmpty) {
      final last = inSession.last.identity.indexInSession;
      if (pending.indexInSession <= last) {
        refuse(
          'pending decision is at index ${pending.indexInSession} in session '
          '${pending.sessionId}, which does not advance past $last',
        );
      }
    }

    // The decision was made from state propagated to its own time, exactly as
    // deciding makes one, so that is what its claims are checked against.
    final scratch = state.copy();
    learner.propagate(scratch, pending.decidedAt);

    final before = learnerStateHash(scratch);
    if (pending.stateBeforeHash != before) {
      refuse(
        'pending decision was made from state ${pending.stateBeforeHash}, but '
        'this history propagated to ${encodeTime(pending.decidedAt)} is '
        '$before',
      );
    }

    final replayed = learner.predict(
      scratch,
      pending.exercise,
      at: pending.decidedAt,
    );
    final recorded = pending.decision.prediction;
    for (final (channel, expected, actual) in [
      (
        'independent_retrieval_p',
        recorded.independentRetrievalP,
        replayed.independentRetrievalP,
      ),
      (
        'material_available_p',
        recorded.materialAvailableP,
        replayed.materialAvailableP,
      ),
      ('execution_p', recorded.executionP, replayed.executionP),
      ('coordination_p', recorded.coordinationP, replayed.coordinationP),
      ('topology_p', recorded.topologyP, replayed.topologyP),
    ]) {
      if ((expected - actual).abs() > _predictionTolerance) {
        refuse(
          'pending decision predicted $channel $expected, but this history '
          'predicts $actual',
        );
      }
    }
  }

  /// Rebuilds what the scheduler needs to know about the sitting in progress.
  ///
  /// A restart is a new sitting, so it carries what [SessionState.resuming]
  /// carries and nothing else.
  static SessionState _rebuildSessionState(
    AttemptJournal journal,
    LearnerModel learner,
    SchedulerConfig config,
  ) => SessionState.resuming([
    for (final record in journal.records)
      PriorSelection(
        record.exercise,
        productive: switch (record.closure.measurement) {
          Measured(:final outcome) => learner.executionWasManaged(outcome),
          MeasurementUnavailable() => false,
        },
        at: record.identity.occurredAt,
      ),
  ], config: config);
}
