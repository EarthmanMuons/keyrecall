import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:path_provider/path_provider.dart';

import 'attempt_diagnosis.dart';
import 'attempt_feedback.dart';
import 'attempt_transcript.dart';
import 'practice_failure.dart';
import 'practice_ownership.dart';
import 'profile_color.dart';

/// Where this install keeps its history.
///
/// One directory holding the profile index and a subdirectory per profile.
final storageRootProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/keyrecall')..createSync(recursive: true);
});

/// The profile index.
final profileRepositoryProvider = FutureProvider<ProfileRepository>((
  ref,
) async {
  final root = await ref.watch(storageRootProvider.future);
  return FileProfileRepository(root);
});

/// The journal and checkpoint store.
final practiceStoreProvider = FutureProvider<PracticeStore>((ref) async {
  final root = await ref.watch(storageRootProvider.future);
  return FilePracticeStore(root);
});

/// Every material the app can represent.
///
/// What exists, not what anybody is offered: the goal narrows it and the
/// scheduler chooses from what is left. A provider so a screen can ask what
/// exists without reaching for a catalog constant, and so a test can install a
/// small one.
///
/// Both families, always. Arpeggios are generated, admitted, paced, and
/// progressed by the same family-neutral rules as scales, so a scale-only mode
/// would only preserve somewhere for single-family assumptions to hide.
final practiceCatalogProvider = Provider<List<TechnicalMaterial>>(
  (ref) => [...allScales, ...allRootPositionArpeggios],
);

/// What the active profile is working toward, and drawing from now.
///
/// Absent storage means nobody has been asked, which is [PracticePlan.normal]:
/// a goal over everything, and no focus.
final practicePlanProvider =
    AsyncNotifierProvider<PracticePlanNotifier, PracticePlan>(
      PracticePlanNotifier.new,
      retry: (_, _) => null,
    );

class PracticePlanNotifier extends AsyncNotifier<PracticePlan> {
  /// Whose plan this notifier is holding, or null while it has none.
  PracticeSessionIdentity? _owner;

  /// Whether this build's scope has been torn down.
  bool _disposed = false;

  /// Names each build, so one superseded mid-load cannot claim ownership after
  /// the build that replaced it already has.
  int _builds = 0;

  /// The writes already queued, which the next one is ordered behind.
  Future<void> _writes = Future<void>.value();

  @override
  Future<PracticePlan> build() async {
    final build = ++_builds;
    _owner = null;
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final repository = await ref.watch(profileRepositoryProvider.future);
    final store = await ref.watch(practiceStoreProvider.future);
    final profile = await repository.selectedOrOldest();
    if (profile == null) return PracticePlan.normal;
    final plan =
        await store.loadPracticePlan(profile.id) ?? PracticePlan.normal;
    if (build == _builds) _owner = PracticeSessionIdentity.next(profile.id);
    return plan;
  }

  /// Records [plan] and applies it to the next undecided slot.
  ///
  /// The loop reads this provider, so replacing the plan reopens the sitting
  /// against the new scope. What survives that is the decision, not the
  /// attempt: it is durable, so the reopened sitting finds it pending and
  /// presents the same exercise again, while anything being recorded at the
  /// time goes with the screen that was recording it.
  ///
  /// Ordered as well as owned. Two saves in flight can finish in either order,
  /// and the second to land would otherwise be the one stored and shown
  /// however recently it was asked for.
  Future<void> apply(PracticePlan plan) {
    final owner = _owner;
    if (owner == null) return Future<void>.value();

    final saving = _writes.then((_) => _save(owner, plan));
    // A failed save must not swallow the one queued behind it.
    _writes = saving.then((_) {}, onError: (_, _) {});
    return saving;
  }

  /// Saves [plan] for [owner], publishing it only while [owner] is still whose
  /// plan this is.
  ///
  /// The save itself is addressed to a profile, so it stands whoever is
  /// selected by the time it lands. What ownership governs is the publish.
  Future<void> _save(PracticeSessionIdentity owner, PracticePlan plan) async {
    if (_disposed) return;
    final store = await ref.read(practiceStoreProvider.future);
    await store.savePracticePlan(owner.profileId, plan);
    if (_disposed || _owner != owner) return;
    state = AsyncValue.data(plan);
  }

  /// Drops the focus, keeping the goal.
  Future<void> practiceNormally() async {
    final plan = state.value;
    if (plan == null || !plan.isFocused) return;
    await apply(plan.practicingNormally());
  }
}

/// Makes a host for one sitting to decide on.
///
/// A worker isolate in the app, and overridden with an `InProcessScheduler`
/// wherever a test wants the decision on the calling isolate.
///
/// A factory rather than a host, because a host is not shareable. Binding
/// replaces the scope a host holds, so two sittings over one host decide
/// against whichever scope bound last; the sitting that opens a host disposes
/// it, and an isolate is cheap beside that confusion.
final schedulerHostFactoryProvider = Provider<SchedulerHost Function()>(
  (ref) => IsolateScheduler.new,
);

/// One profile as the management screen shows it.
///
/// Carries the history count beside the profile because that is what tells two
/// similarly named profiles apart: which one has been practiced, and how much.
@immutable
class ProfileSummary {
  /// Who this is.
  final Profile profile;

  /// Whether this is the profile the practice loop is running as.
  final bool isActive;

  /// How many attempts this profile has recorded, or null when its history
  /// could not be read.
  final int? attemptsRecorded;

  /// Why the history could not be read, when it could not.
  ///
  /// A journal this build cannot replay is exactly when somebody needs the
  /// switcher, so an unreadable one is reported in place rather than allowed
  /// to fail the screen that offers the way out.
  final String? historyError;

  const ProfileSummary({
    required this.profile,
    required this.isActive,
    this.attemptsRecorded,
    this.historyError,
  });
}

/// Who exists on this install, and what each of them has practiced.
///
/// Retries are off for the same reason the practice loop turns them off: the
/// failures here are unreadable storage, which a retry cannot change.
final profileRosterProvider =
    AsyncNotifierProvider<ProfileRosterNotifier, List<ProfileSummary>>(
      ProfileRosterNotifier.new,
      retry: (_, _) => null,
    );

/// Creating, renaming, switching, erasing, and deleting profiles.
///
/// Every mutation goes through the repository and then reloads this list.
/// Reloading the practice loop is separate and deliberate: reopening a sitting
/// while an exercise is on screen leaves its decision pending, so the loop is
/// invalidated only when a change actually moves the ground under it, which
/// means a change to the active profile.
class ProfileRosterNotifier extends AsyncNotifier<List<ProfileSummary>> {
  /// Whether a write is already running, for the reason [PracticeLoopNotifier]
  /// keeps the same flag.
  bool _writing = false;

  @override
  Future<List<ProfileSummary>> build() async {
    final repository = await ref.watch(profileRepositoryProvider.future);
    final store = await ref.watch(practiceStoreProvider.future);

    final profiles = await repository.list();
    final activeId = (await repository.selected())?.id;
    // Each summary reads one profile's journal, and the reads are independent.
    return Future.wait([
      for (final profile in profiles)
        _summarize(profile, store, isActive: profile.id == activeId),
    ]);
  }

  /// Adds a profile and practices as it.
  ///
  /// The repository does not switch when a profile is created, because a
  /// profile can be made for reasons that have nothing to do with who is at the
  /// instrument. Made from this screen it does switch: somebody adding a
  /// profile is about to use it.
  ///
  /// [placement] is fixed for the life of the profile, because it is the prior
  /// the whole history is computed from: changing it would reinterpret every
  /// attempt rather than update a skill level, and erasing the history is the
  /// honest route to a different starting point.
  Future<Profile?> add(String displayName, PlacementTier placement) =>
      _mutate((repository, store) async {
        final created = await repository.create(
          displayName: displayName,
          placement: placement,
          // Told apart from whoever is already here, which is the whole reason
          // a second profile is being made.
          presentationHint: ProfileColor.unusedAmong(await repository.list())
              .name,
        );
        await repository.select(created.id);
        return (true, created);
      });

  /// Places the learner this install has not asked about yet.
  ///
  /// The first-launch path, where the profile is conjured rather than named:
  /// what matters is that the tier it starts from is the one somebody chose,
  /// since nothing can change it afterwards.
  ///
  /// Placing an install that already has somebody on it returns them
  /// unchanged, because the question was already answered and a second answer
  /// would be one the history cannot honor.
  Future<Profile?> place(PlacementTier placement) =>
      _mutate((repository, store) async {
        final existing = await repository.selectedOrOldest();
        if (existing != null) return (true, existing);

        return (
          true,
          await repository.create(
            displayName: defaultProfileName,
            placement: placement,
            presentationHint: ProfileColor.values.first.name,
          ),
        );
      });

  /// Changes a profile's display name.
  Future<Profile?> rename(String profileId, String displayName) =>
      _mutate((repository, store) async {
        final renamed = await repository.rename(profileId, displayName);
        return (await _isActive(repository, profileId), renamed);
      });

  /// Changes the color a profile is recognized by.
  Future<Profile?> recolor(String profileId, ProfileColor color) =>
      _mutate((repository, store) async {
        final restyled = await repository.restyle(profileId, color.name);
        return (await _isActive(repository, profileId), restyled);
      });

  /// Makes [profileId] the profile the practice loop runs as.
  Future<Profile?> select(String profileId) =>
      _mutate((repository, store) async {
        final selected = await repository.select(profileId);
        return (true, selected);
      });

  /// Erases one profile's recorded practice, keeping the profile itself.
  ///
  /// The way to put a test profile back at placement without losing the name
  /// it is recognized by.
  Future<void> eraseHistory(String profileId) =>
      _mutate((repository, store) async {
        final active = await _isActive(repository, profileId);
        await store.erase(profileId);
        return (active, null);
      });

  /// Deletes a profile and everything it recorded.
  ///
  /// Deleting the profile being practiced as leaves the selection on the
  /// oldest one left. Deleting the last one leaves the install with nobody on
  /// it, which puts the app back at the placement question rather than
  /// conjuring a replacement: a profile carries a prior nobody can change
  /// later, so one made on somebody's behalf is the thing to avoid rather
  /// than the tidy outcome.
  Future<void> remove(String profileId) => _mutate((repository, store) async {
    final active = await _isActive(repository, profileId);
    await repository.delete(profileId);
    await store.erase(profileId);
    return (active, null);
  });

  /// Runs [change], reloads this list, and reloads the practice loop when the
  /// change touched the active profile.
  Future<T?> _mutate<T>(
    Future<(bool, T?)> Function(ProfileRepository, PracticeStore) change,
  ) async {
    if (_writing) return null;

    _writing = true;
    try {
      final repository = await ref.read(profileRepositoryProvider.future);
      final store = await ref.read(practiceStoreProvider.future);
      final (touchedActive, result) = await change(repository, store);

      ref.invalidateSelf();
      if (touchedActive) {
        // The plan first: the loop reads it, and reopening a sitting against
        // the previous profile's scope would decide one slot under it.
        ref.invalidate(practicePlanProvider);
        ref.invalidate(practiceLoopProvider);
      }
      return result;
    } finally {
      _writing = false;
    }
  }

  static Future<bool> _isActive(
    ProfileRepository repository,
    String profileId,
  ) async => (await repository.selected())?.id == profileId;

  /// Reads what [profile] has recorded, reporting rather than throwing when
  /// that history cannot be replayed.
  static Future<ProfileSummary> _summarize(
    Profile profile,
    PracticeStore store, {
    required bool isActive,
  }) async {
    try {
      final journal = await store.loadJournal(profile.id);
      return ProfileSummary(
        profile: profile,
        isActive: isActive,
        attemptsRecorded: journal.records.length,
      );
    } catch (error) {
      return ProfileSummary(
        profile: profile,
        isActive: isActive,
        historyError: '$error',
      );
    }
  }
}

/// Why the loop has nothing to present.
enum PracticeIdleReason {
  /// Every admission path declined, which should not happen.
  blocked,

  /// Nothing in the active scope warrants work now.
  caughtUp,

  /// The goal or focus could not be resolved against this catalog.
  invalidScope,
}

/// Everything the panel needs to show about the loop's current position.
@immutable
class PracticeLoopState {
  /// Which live sitting this is.
  ///
  /// What everything asynchronous this sitting starts is bound to, so a result
  /// that outlives it can be told from one that is still current.
  final PracticeSessionIdentity identity;

  /// Whose sitting this is.
  final Profile profile;

  /// The goal and focus this sitting was opened under.
  final PracticePlan plan;

  /// Curriculum coverage as of the last decision, where one reported it.
  final ScopeCoverage? coverage;

  /// Why there is nothing to present, when there is nothing.
  final PracticeIdleReason? idle;

  /// The open sitting.
  final PracticeSession session;

  /// What is on screen waiting to be answered, if anything.
  final PresentedAttempt? presented;

  /// A decision from an earlier run that was never answered.
  final PendingDecision? pending;

  /// The supported task on screen, if one is.
  ///
  /// Not a [PresentedAttempt]: nothing about an acquisition attempt is durable
  /// before it is played, because there is no decision to recover and no
  /// learner state it could leave half-applied. It still carries an identity,
  /// so two offers of the same task are two attempts at it.
  final PresentedAcquisition? acquisition;

  /// The last attempt committed in this sitting.
  final AttemptRecord? lastCommitted;

  /// The last supported attempt recorded in this sitting.
  ///
  /// Held for the same reason [lastCommitted] is: something has to be closed
  /// before the next thing begins. It carries no outcome, so what a screen can
  /// say about it is narrower.
  final AcquisitionAttemptRecord? lastAcquisition;

  /// What [lastCommitted] was read from, when it was read from a performance.
  ///
  /// Absent for a decline, for a hand-entered report, and after a reopen, all
  /// of which produce a record without a correspondence behind it. Nothing
  /// persists this, so it lives exactly as long as the review that reads it.
  final PerformanceReading? lastReading;

  /// Why there is nothing to present, when there is nothing.
  final String? note;

  const PracticeLoopState({
    required this.identity,
    required this.profile,
    required this.plan,
    required this.session,
    this.coverage,
    this.idle,
    this.presented,
    this.pending,
    this.acquisition,
    this.lastCommitted,
    this.lastAcquisition,
    this.lastReading,
    this.note,
  });

  /// Whether an answer is being waited on, from any source.
  bool get isAwaitingAnswer =>
      presented != null || pending != null || acquisition != null;

  /// What is awaiting an answer, and the sitting that issued it.
  ///
  /// What closing an attempt names its target by. An attempt belongs to the
  /// sitting that decided it for as long as it exists, so a completion that
  /// arrives after that sitting was replaced has nothing here to match.
  PracticeAttemptOwner? get attempt {
    final attemptId =
        presented?.decision.attemptId ??
        pending?.attemptId ??
        acquisition?.attemptId;
    return attemptId == null
        ? null
        : PracticeAttemptOwner(session: identity, attemptId: attemptId);
  }

  /// The exercise awaiting an answer, whichever way it got here.
  Exercise? get exercise => presented?.exercise ?? pending?.exercise;

  /// How many attempts this profile has recorded, ever.
  int get attemptsRecorded => session.journal.records.length;

  /// Whether [material] has ever been presented to this learner.
  ///
  /// Presented rather than learned: what it answers is whether a screen may
  /// say the learner has forgotten something, and nothing shown for the first
  /// time can have been forgotten. The attempt on screen is not in the journal
  /// yet, so this reads as of the moment it was decided.
  bool hasMet(TechnicalMaterial material) => session.journal.records.any(
    (record) => record.exercise.material.materialId == material.materialId,
  );
}

/// Drives the practice loop: decide, present, collect, commit, decide again.
/// The practice loop.
///
/// Retries are off. The default is to rebuild a failed provider on a backoff,
/// which suits a flaky network and not this: opening a sitting fails for
/// reasons a retry cannot change, such as a journal recorded under a learner
/// model this build no longer runs. Retrying leaves the loop in a loading
/// state that carries the last error, so it renders as failed but never
/// settles, its future never completes, and an explicit rebuild races the next
/// retry instead of replacing it. A failure here stays a failure until
/// something is done about it.
final practiceLoopProvider =
    AsyncNotifierProvider<PracticeLoopNotifier, PracticeLoopState>(
      PracticeLoopNotifier.new,
      retry: (_, _) => null,
    );

class PracticeLoopNotifier extends AsyncNotifier<PracticeLoopState> {
  /// Whether a write is already running.
  ///
  /// An explicit flag rather than an inference from [state], because moving to
  /// [AsyncValue.loading] does not hide the previous value: Riverpod carries it
  /// forward, so a second caller would still see an answerable exercise and
  /// proceed.
  bool _writing = false;

  /// Which sitting this notifier is holding, or null while it has none.
  ///
  /// Every asynchronous operation this notifier starts carries the identity it
  /// began under and is checked against this before it publishes anything or
  /// starts anything further.
  PracticeSessionIdentity? _owner;

  /// Whether this build's scope has been torn down.
  bool _disposed = false;

  /// Names each build, so one superseded mid-open cannot claim ownership after
  /// the build that replaced it already has.
  int _builds = 0;

  /// How to retry the failure on screen, when it is one the session that
  /// produced it can still answer.
  _Recovery? _recovery;

  @override
  Future<PracticeLoopState> build() async {
    final build = ++_builds;
    _owner = null;
    _recovery = null;
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final repository = await ref.watch(profileRepositoryProvider.future);
    final store = await ref.watch(practiceStoreProvider.future);

    // Never conjures anybody. An install with no profile has not answered the
    // placement question, and answering it is what creates the learner; a
    // sitting opened before that would run as somebody started from a prior
    // nobody chose. The gate above this screen is what makes it unreachable.
    final profile = await repository.selectedOrOldest();
    if (profile == null) {
      throw StateError('no profile on this install has been placed yet');
    }
    // Scheduling is the expensive part of a slot and blocks whatever isolate
    // computes it, so it does not happen on the one that draws. The worker
    // holds the sitting's scope and nothing else; this isolate stays
    // authoritative for state and for what is written.
    //
    // One host per sitting, disposed with it. A host bound to a scope that is
    // no longer this sitting's is a host answering somebody else's question.
    final scheduler = ref.watch(schedulerHostFactoryProvider)();
    ref.onDispose(scheduler.dispose);
    // The plan is read before the sitting opens rather than applied to it
    // afterwards, so the first slot of a sitting is decided under the scope the
    // learner last asked for.
    final catalog = ref.watch(practiceCatalogProvider);
    final plan = await ref.watch(practicePlanProvider.future);
    final scope = plan.resolve(catalog);
    final session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: catalog,
      scheduler: scheduler,
      goal: scope.goal,
      focus: scope.focus,
    );

    final identity = PracticeSessionIdentity.next(profile.id);
    if (build == _builds) _owner = identity;

    // An unresolved decision is presented again rather than discarded. It was
    // shown to someone under an attempt id that is already durable, and
    // playing it closes that same attempt: nothing here has to invent what
    // happened, and nothing has to throw the slot away.
    if (session.pending != null) {
      return PracticeLoopState(
        identity: identity,
        profile: profile,
        plan: plan,
        session: session,
        pending: session.pending,
        note: 'resuming an attempt an earlier run never closed',
      );
    }
    // A sitting that opened and could not be decided is a scheduling failure,
    // not an unreadable history: nothing about what is recorded is in doubt,
    // and offering to erase it would answer a question nobody asked.
    try {
      return await _decide(
        PracticeLoopState(
          identity: identity,
          profile: profile,
          plan: plan,
          session: session,
        ),
      );
    } catch (error) {
      throw PracticeLoopFailure(PracticeFailure.scheduling, error);
    }
  }

  /// Whether [session] is the sitting this notifier is still holding.
  bool _owns(PracticeSessionIdentity session) =>
      !_disposed && _owner == session;

  /// Records that the learner could not retrieve the material, and moves on.
  ///
  /// Not a skip: it commits a real retrieval failure, which is what opens the
  /// recovery context that offers the same exercise with the material shown.
  ///
  /// Single-flight for the same reason [finish] is.
  Future<void> decline(
    AttemptCompletion completion, {
    required PracticeAttemptOwner attempt,
  }) async {
    final current = _answerable(attempt);
    if (current == null) return;
    // Carried rather than looked up: the session refuses a decline once
    // anything has been played, and what this attempt played is not whatever
    // the transcript holds by the time this runs.
    final transcript = completion.transcript;

    await _close(attempt, () async {
      final record = await current.session.closeDeclined(
        transcript: transcript,
        observedWallTime: DateTime.now().toUtc(),
      );
      return PracticeLoopState(
        identity: current.identity,
        profile: current.profile,
        plan: current.plan,
        session: current.session,
        lastCommitted: record,
      );
    });
  }

  /// Says the outstanding attempt has actually reached the learner.
  ///
  /// Deciding is not presenting: the next exercise is prepared while the last
  /// one's review is still on screen, and a prepared decision can be discarded
  /// before anybody sees it.
  Future<void> acknowledgePresentation(PracticeAttemptOwner attempt) async {
    final current = state.value;
    if (current == null || current.attempt != attempt) return;
    await current.session.acknowledgePresentation(attempt.attemptId);
  }

  /// Records what a supported attempt produced and moves on.
  ///
  /// Separate from [finish] because almost nothing it does applies. There is
  /// no outcome to derive, no learner state to advance, no pending decision to
  /// clear, and no review to show: an acquisition attempt is an event in its
  /// own log, and what happens next is whatever the scheduler makes of it.
  ///
  /// An attempt the learner stopped partway is recorded like any other. Where
  /// it ran out and what the waits were are what the task was offered for.
  Future<void> finishAcquisition(
    AttemptCompletion completion, {
    required PracticeAttemptOwner attempt,
  }) async {
    final current = _answerable(attempt);
    if (current == null || current.acquisition == null) return;

    await _close(attempt, () async {
      final record = await current.session.closeAcquisition(
        completion.transcript,
        at: DateTime.now().toUtc(),
        // An interrupted capture is still an observation of what was played,
        // and what it is not is the learner stopping. Recording it as an
        // ordinary attempt would put an incomplete traversal down to them.
        termination: completion.isInterrupted
            ? AttemptTermination.inputInterrupted
            : completion.termination,
      );
      return PracticeLoopState(
        identity: current.identity,
        profile: current.profile,
        plan: current.plan,
        session: current.session,
        coverage: current.coverage,
        lastAcquisition: record,
      );
    });
  }

  /// Commits what was played and moves to the next exercise.
  ///
  /// The production path: what arrived on the wire becomes the evidence,
  /// without anyone being asked how it went.
  ///
  /// [termination] says which of the ways an attempt can end this was. It is
  /// metadata beside the evidence rather than part of it: an attempt somebody
  /// stopped at six notes and one a timeout closed at six notes are different
  /// observations of the same performance, and neither is a worse one.
  ///
  /// A timeout that arrives with nothing played closes unmeasured. An
  /// interruption and an attempt at nothing look identical from here, so
  /// measuring would pick one.
  ///
  /// Single-flight for the same reason [decline] is.
  Future<void> finish(
    AttemptCompletion completion, {
    required PracticeAttemptOwner attempt,
  }) async {
    final current = _answerable(attempt);
    if (current == null) return;
    final transcript = completion.transcript;

    await _close(attempt, () async {
      if (completion.isInterrupted) {
        final record = await current.session.closeUnmeasured(
          termination: AttemptTermination.inputInterrupted,
          reason: MeasurementUnavailableReason.inputInterrupted,
          observedWallTime: DateTime.now().toUtc(),
        );
        return PracticeLoopState(
          identity: current.identity,
          profile: current.profile,
          plan: current.plan,
          session: current.session,
          lastCommitted: record,
        );
      }

      final unplayed =
          transcript.isEmpty &&
          completion.termination != AttemptTermination.learnerStopped;
      if (unplayed) {
        final record = await current.session.closeUnmeasured(
          termination: completion.termination,
          reason: MeasurementUnavailableReason.nothingPlayed,
          observedWallTime: DateTime.now().toUtc(),
        );
        return PracticeLoopState(
          identity: current.identity,
          profile: current.profile,
          plan: current.plan,
          session: current.session,
          lastCommitted: record,
        );
      }

      final closed = await current.session.closeFromPerformance(
        transcript,
        termination: completion.termination,
        observedWallTime: DateTime.now().toUtc(),
      );
      await _recordCoordination(closed.record, closed.reading);
      return PracticeLoopState(
        identity: current.identity,
        profile: current.profile,
        plan: current.plan,
        session: current.session,
        lastCommitted: closed.record,
        lastReading: closed.reading,
      );
    });
  }

  /// The sitting [attempt] belongs to, if it is still the one on screen and
  /// nothing else is being written.
  ///
  /// The ownership check is here rather than at the transaction, because a
  /// completion that names an attempt this sitting is not holding is evidence
  /// about somebody else's slot and there is nowhere to put it.
  PracticeLoopState? _answerable(PracticeAttemptOwner attempt) {
    final current = state.value;
    if (_writing || current == null || !current.isAwaitingAnswer) return null;
    return current.attempt == attempt ? current : null;
  }

  /// Carries one attempt's close through, and decides the next slot.
  ///
  /// [close] is allowed to finish whatever it started: an append in flight owes
  /// authoritative history an answer, and abandoning it on the strength of a
  /// profile switch is what leaves one attempt in the file and none in the
  /// sitting. What ownership governs is everything after it, which is
  /// publishing state and asking for another decision.
  ///
  /// No loading state: committing is an append and a scheduler decision, and
  /// replacing the screen with a spinner for that is how an app teaches
  /// someone to wait for it.
  Future<void> _close(
    PracticeAttemptOwner attempt,
    Future<PracticeLoopState> Function() close,
  ) async {
    _writing = true;
    try {
      final PracticeLoopState closed;
      try {
        closed = await close();
      } catch (error, stackTrace) {
        // The transaction stays frozen on the session, so the recovery is to
        // write this same attempt again rather than to open a sitting that
        // would find its decision pending and its performance gone.
        _fail(
          attempt.session,
          PracticeFailure.commit,
          error,
          stackTrace,
          retry: () => _close(attempt, close),
        );
        return;
      }
      if (!_owns(attempt.session)) return;
      await _publish(closed);
    } finally {
      _writing = false;
    }
  }

  /// Decides the next slot from [closed] and publishes the result.
  Future<void> _publish(PracticeLoopState closed) async {
    final PracticeLoopState decided;
    try {
      decided = await _decide(closed);
    } catch (error, stackTrace) {
      _fail(
        closed.identity,
        PracticeFailure.scheduling,
        error,
        stackTrace,
        retry: () => _publish(closed),
      );
      return;
    }
    if (!_owns(closed.identity)) return;
    _recovery = null;
    state = AsyncValue.data(decided);
  }

  /// Puts a failure on screen, with what would answer it.
  void _fail(
    PracticeSessionIdentity session,
    PracticeFailure kind,
    Object error,
    StackTrace stackTrace, {
    required Future<void> Function() retry,
  }) {
    if (!_owns(session)) return;
    _recovery = _Recovery(session: session, retry: retry);
    state = AsyncValue.error(PracticeLoopFailure(kind, error), stackTrace);
  }

  /// Answers the failure on screen.
  ///
  /// A frozen close is finished and a failed decision is asked again, both on
  /// the session that owns them. Anything else reopens, which is what a
  /// sitting that never opened has.
  Future<void> retry() async {
    final recovery = _recovery;
    if (recovery == null || !_owns(recovery.session) || _writing) {
      _recovery = null;
      ref.invalidateSelf();
      return;
    }
    await recovery.retry();
  }

  /// Erases this profile's history and starts over from placement.
  ///
  /// Destroys recorded practice, which is what makes it a deliberate act
  /// rather than part of the loop: the journal exists so history is not
  /// rewritten, and this is the one operation that admits someone wants none
  /// of it.
  Future<void> eraseHistory() async {
    if (_writing) return;

    _writing = true;
    final current = state.value;
    state = const AsyncValue.loading();
    try {
      // The profile is resolved here rather than taken from the loop state,
      // because the usual reason to erase is that the loop would not load and
      // there is no state to take it from: a journal recorded under a learner
      // model this build no longer runs cannot be replayed, and this is the
      // way out. Requiring a loaded loop made the button do nothing in the one
      // situation it exists for.
      final repository = await ref.read(profileRepositoryProvider.future);
      final store = await ref.read(practiceStoreProvider.future);
      final profile = current?.profile ?? await repository.selectedOrOldest();
      if (profile != null) await store.erase(profile.id);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    } finally {
      _writing = false;
    }
    ref.invalidateSelf();
    // Erasing takes the plan with the history, so what is on screen has to be
    // read again rather than assumed.
    ref.invalidate(practicePlanProvider);
    // The switcher shows what each profile has recorded, and one of those
    // counts just went to zero.
    ref.invalidate(profileRosterProvider);
  }

  /// Reopens from storage, as a relaunch would.
  ///
  /// The interesting case is doing this while an exercise is on screen: the
  /// decision is already durable, so the reopened session finds it pending and
  /// refuses to move past it. That is the crash-safety path, exercised without
  /// having to kill the process.
  void reopen() => ref.invalidateSelf();

  /// Saves a checkpoint, which only makes the next open faster.
  Future<void> saveCheckpoint() async {
    final current = state.value;
    if (current == null) return;
    await current.session.saveCheckpoint();
  }

  Future<void> recordFeedbackExposure({
    required AttemptRecord record,
    required List<ProgressEvent> progress,
  }) async {
    final store = await ref.read(practiceStoreProvider.future);
    await store.appendFeedbackExposure(
      FeedbackExposure(
        profileId: record.profileId,
        attemptId: record.identity.attemptId,
        shownAt: DateTime.now().toUtc(),
        postAttemptFeedback: record.closure.measurement is Measured
            ? PostAttemptFeedback.diagnostic
            : PostAttemptFeedback.none,
        progressFeedback: progress.isEmpty
            ? ProgressFeedback.none
            : ProgressFeedback.personalProgress,
        progressEvents: progress.map((event) => event.type),
      ),
    );
  }

  /// Logs how far apart the hands arrived, for the calibration question about
  /// what "together" should mean.
  ///
  /// Instrumentation rather than evidence, so a failed write is swallowed: the
  /// attempt is already history, and losing a diagnostic line must not fail the
  /// screen or the loop that produced it.
  Future<void> _recordCoordination(
    AttemptRecord record,
    PerformanceReading? reading,
  ) async {
    final measurement = reading?.measurement;
    final coordination = measurement?.coordination;
    // Nothing to calibrate a bound against when no moment was measured, and a
    // sample standing in for one would be calibrating against itself.
    if (measurement == null || coordination == null) return;
    final measured = record.closure.measurement;
    if (measured is! Measured) return;
    final outcome = measured.outcome;

    try {
      final store = await ref.read(practiceStoreProvider.future);
      final conditions = record.exercise.conditions;
      await store.appendCoordinationSample(
        CoordinationSample(
          profileId: record.profileId,
          attemptId: record.identity.attemptId,
          observedAt: record.identity.occurredAt,
          materialId: record.exercise.material.materialId,
          familyId: record.exercise.material.familyId,
          hands: conditions.hands.id,
          handMotion: conditions.handMotion.id,
          direction: conditions.direction.id,
          octaves: conditions.octaves,
          tempoBpm: conditions.tempoBpm,
          achievedTempoRatio: outcome.measuredTempoRatio,
          guidanceIndependence: record.exercise.guidance.independence,
          coordinationScore: coordination,
          synchronizedAsynchronyMs: measurement.policy.synchronizedAsynchronyMs,
          reportedAsFault:
              diagnose(
                exercise: record.exercise,
                closure: record.closure,
                reading: reading,
              )?.fault ==
              AttemptFault.coordination,
          moments: measurement.handAsynchronies,
        ),
      );
    } catch (_) {
      // A diagnostic log nobody is waiting on.
    }
  }

  Future<void> recordAttemptDetailsViewed(AttemptRecord record) async {
    final store = await ref.read(practiceStoreProvider.future);
    await store.appendFeedbackExposure(
      FeedbackExposure(
        profileId: record.profileId,
        attemptId: record.identity.attemptId,
        shownAt: DateTime.now().toUtc(),
        postAttemptFeedback: PostAttemptFeedback.detailedDiagnostic,
        progressFeedback: ProgressFeedback.none,
        progressEvents: const [],
      ),
    );
  }

  /// Asks the scheduler for the next exercise.
  ///
  /// Every terminal practice outcome is surfaced instead of retried.
  Future<PracticeLoopState> _decide(PracticeLoopState from) async {
    final decision = await from.session.decideOutcome(
      at: DateTime.now().toUtc(),
    );
    return switch (decision) {
      final PresentedAttempt presented => PracticeLoopState(
        identity: from.identity,
        profile: from.profile,
        plan: from.plan,
        session: from.session,
        presented: presented,
        coverage: presented.coverage ?? from.coverage,
        lastCommitted: from.lastCommitted,
        lastAcquisition: from.lastAcquisition,
        lastReading: from.lastReading,
        note: from.note,
      ),
      // The inputs moved while the decision was being computed. The loop asks
      // again rather than showing an answer about a session that has changed.
      PracticeSuperseded() => from,
      PracticeBlocked(:final reason, :final coverage) => PracticeLoopState(
        identity: from.identity,
        profile: from.profile,
        plan: from.plan,
        session: from.session,
        coverage: coverage,
        idle: PracticeIdleReason.blocked,
        lastCommitted: from.lastCommitted,
        lastAcquisition: from.lastAcquisition,
        lastReading: from.lastReading,
        note: 'practice blocked: ${reason.name}',
      ),
      PracticeCaughtUp(:final coverage) => PracticeLoopState(
        identity: from.identity,
        profile: from.profile,
        plan: from.plan,
        session: from.session,
        coverage: coverage,
        idle: PracticeIdleReason.caughtUp,
        lastCommitted: from.lastCommitted,
        lastAcquisition: from.lastAcquisition,
        lastReading: from.lastReading,
        note: 'practice caught up',
      ),
      final PresentedAcquisition offered => PracticeLoopState(
        identity: from.identity,
        profile: from.profile,
        plan: from.plan,
        session: from.session,
        acquisition: offered,
        coverage: offered.coverage,
        lastCommitted: from.lastCommitted,
        lastAcquisition: from.lastAcquisition,
        lastReading: from.lastReading,
        note: from.note,
      ),
      PracticeInvalidScope(:final failures) => PracticeLoopState(
        identity: from.identity,
        profile: from.profile,
        plan: from.plan,
        session: from.session,
        coverage: from.coverage,
        idle: PracticeIdleReason.invalidScope,
        lastCommitted: from.lastCommitted,
        lastAcquisition: from.lastAcquisition,
        lastReading: from.lastReading,
        note:
            'invalid practice scope: '
            '${failures.map((failure) => failure.code.name).join(', ')}',
      ),
    };
  }
}

/// What would answer the failure on screen, and whose it is.
@immutable
class _Recovery {
  /// The sitting that produced the failure, and the only one this answers for.
  final PracticeSessionIdentity session;

  /// Finishes what failed: a frozen close, or a decision asked again.
  final Future<void> Function() retry;

  const _Recovery({required this.session, required this.retry});
}
