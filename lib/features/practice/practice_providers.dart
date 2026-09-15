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
///
/// Retries are off here and on everything below it, for the reason the
/// practice loop turns them off: these fail on storage this build cannot
/// read, which a retry cannot change. Retried, a failure never settles, so
/// what is waiting on it stays loading and the recovery that would fix it is
/// never offered.
final storageRootProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/keyrecall')..createSync(recursive: true);
}, retry: (_, _) => null);

/// The profile index.
final profileRepositoryProvider = FutureProvider<ProfileRepository>((
  ref,
) async {
  final root = await ref.watch(storageRootProvider.future);
  return FileProfileRepository(root);
}, retry: (_, _) => null);

/// Which build of the app is writing, as the installed package names it.
///
/// Recorded on every attempt beside the model versions. A presentation is
/// resolved by this build's policy and drawn by its renderers, so the build is
/// part of what the recorded conditions mean.
///
/// Overridden at launch, where there is a package to ask. Nothing else may
/// hold a sitting closed while it asks: a test binding has no package, and a
/// build that cannot name itself says nothing rather than naming something
/// else.
final appBuildVersionProvider = Provider<String?>((ref) => null);

/// The journal and checkpoint store.
final practiceStoreProvider = FutureProvider<PracticeStore>((ref) async {
  final root = await ref.watch(storageRootProvider.future);
  return FilePracticeStore(root);
}, retry: (_, _) => null);

/// Storage, paired, with nothing reconciled yet.
///
/// What repairing a broken artifact runs through. Repair cannot depend on the
/// install having started cleanly: reconciliation reads the same metadata it
/// would be repairing, so a recovery that waited for reconciliation to succeed
/// would wait for the thing it exists to fix.
final profileLifecycleRawProvider = FutureProvider<ProfileLifecycle>(
  (ref) async => ProfileLifecycle(
    repository: await ref.watch(profileRepositoryProvider.future),
    store: await ref.watch(practiceStoreProvider.future),
  ),
);

/// Who exists on this install, and what each of them may still write.
///
/// Everything that creates, erases, or deletes a profile goes through here,
/// and so does everything that needs to know who is active: resolving that is
/// the first thing after a deletion the last run did not finish, and a sitting
/// opened before that repair would run as somebody this install has already
/// decided to forget.
final profileLifecycleProvider = FutureProvider<ProfileLifecycle>((ref) async {
  final lifecycle = await ref.watch(profileLifecycleRawProvider.future);
  await lifecycle.resumeDeletions();
  return lifecycle;
}, retry: (_, _) => null);

/// Whether a profile mutation is running.
///
/// Watched by the controls that must not compete with one another. Ordering
/// the writes is the roster's job; this is only so a screen can stop offering
/// a switch whose result it would have to guess at.
final profileMutationProvider = NotifierProvider<ProfileMutationNotifier, bool>(
  ProfileMutationNotifier.new,
);

class ProfileMutationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void _running(bool running) => state = running;
}

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

/// Orders plan reads behind the plan writes already accepted for a profile.
///
/// Above the notifier, because a plan notifier is replaced whenever the
/// selection changes and its own queue cannot order a write against the read
/// the notifier that replaced it performs. Once a mutation for a profile is
/// accepted, a later load of that profile sees it or something later, rather
/// than the state it was asked to replace.
final practicePlanWritesProvider = Provider<ProfileWriteQueue>(
  (ref) => ProfileWriteQueue(),
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

/// Which loaded plan a save is publishing for.
///
/// Deliberately not a [PracticeSessionIdentity]. A plan belongs to a profile
/// and to one incarnation of this notifier, which is a shorter lifecycle than
/// a sitting and not in step with it: reading the two generations as the same
/// kind of thing would suggest a relationship that does not exist.
@immutable
class _PlanOwner {
  final String profileId;
  final int generation;

  /// The incarnation this plan was loaded under, and the only one it writes
  /// as: a plan saved after the history it describes was erased would be
  /// intent for a learner nobody is any more.
  final ProfileLifetime lifetime;

  const _PlanOwner({
    required this.profileId,
    required this.generation,
    required this.lifetime,
  });

  factory _PlanOwner.next(ProfileLifetime lifetime) => _PlanOwner(
    profileId: lifetime.profileId,
    generation: ++_loaded,
    lifetime: lifetime,
  );

  static int _loaded = 0;

  @override
  bool operator ==(Object other) =>
      other is _PlanOwner &&
      other.profileId == profileId &&
      other.generation == generation &&
      other.lifetime == lifetime;

  @override
  int get hashCode => Object.hash(profileId, generation, lifetime);
}

class PracticePlanNotifier extends AsyncNotifier<PracticePlan> {
  /// Whose plan this notifier is holding, or null while it has none.
  _PlanOwner? _owner;

  /// Whether this build's scope has been torn down.
  bool _disposed = false;

  /// Names each build, so one superseded mid-load cannot claim ownership after
  /// the build that replaced it already has.
  int _builds = 0;

  @override
  Future<PracticePlan> build() async {
    final build = ++_builds;
    _owner = null;
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final lifecycle = await ref.watch(profileLifecycleProvider.future);
    final store = lifecycle.store;
    final writes = ref.watch(practicePlanWritesProvider);
    final profile = await lifecycle.repository.selectedOrOldest();
    if (profile == null) return PracticePlan.normal;
    final lifetime = await store.lifetimeOf(profile.id);
    // Ownership is established before the plan is read, and deliberately not
    // from it. A plan nobody can decode is exactly the one that has to be
    // replaceable, and a recovery that needed the stored plan to construct
    // its own address would be unreachable for the failure it exists for.
    if (build == _builds) _owner = _PlanOwner.next(lifetime);
    try {
      final stored = await writes.run(
        profile.id,
        () => store.loadPracticePlan(profile.id),
      );
      return stored ?? PracticePlan.normal;
    } catch (error) {
      throw PracticeLoopFailure(
        PracticeFailure.plan,
        UnusablePracticePlan(PlanFault.unreadable, '$error'),
        profileId: profile.id,
      );
    }
  }

  /// Records [plan] and applies it to the next undecided slot.
  ///
  /// The loop reads this provider, so replacing the plan reopens the sitting
  /// against the new scope. What survives that is the decision, not the
  /// attempt: it is durable, so the reopened sitting finds it pending and
  /// presents the same exercise again, while anything being recorded at the
  /// time goes with the screen that was recording it.
  ///
  /// Ordered as well as owned, on the profile's queue rather than this
  /// notifier's. Two saves in flight can finish in either order, and the
  /// second to land would otherwise be the one stored and shown however
  /// recently it was asked for; a load that overtook an accepted save would
  /// show the state that save was asked to replace.
  ///
  /// Accepting one is taking it on. The write is queued here rather than when
  /// its turn comes, and the store is resolved here too, because a notifier
  /// disposed while this is queued can no longer be asked for one and a
  /// mutation that was accepted is owed to the profile it names.
  Future<void> apply(PracticePlan plan) {
    final owner = _owner;
    if (owner == null) return Future<void>.value();
    final lifecycle = ref.read(profileLifecycleProvider.future);

    return ref
        .read(practicePlanWritesProvider)
        .run(owner.profileId, () => _save(owner, plan, lifecycle));
  }

  /// Saves [plan] for [owner], publishing it only while [owner] is still whose
  /// plan this is.
  ///
  /// The save is addressed to a profile, so it stands whoever is selected by
  /// the time it lands and whether or not anything is still reading this. What
  /// ownership governs is the publish.
  Future<void> _save(
    _PlanOwner owner,
    PracticePlan plan,
    Future<ProfileLifecycle> lifecycleFuture,
  ) async {
    final lifecycle = await lifecycleFuture;
    try {
      await lifecycle.store
          .boundTo(owner.lifetime)
          .savePracticePlan(owner.profileId, plan);
    } on RetiredProfileLifetime {
      // The history this plan was asked for is gone. A plan is intent rather
      // than evidence, so there is nothing to recover and nothing to report:
      // whatever erased it is already reopening what comes next.
      return;
    }
    if (_disposed || _owner != owner) return;
    state = AsyncValue.data(plan);
  }

  /// Replaces whatever is stored with normal practice.
  ///
  /// The way out of a plan this build cannot read, and the reason it takes no
  /// argument and reads nothing: the stored plan is the thing that failed, so
  /// recovery cannot be asked to reconstruct it. It is addressed to the
  /// profile incarnation this notifier loaded for, so an erase in the meantime
  /// refuses it rather than putting a plan back under a learner nobody is.
  Future<void> replaceWithNormalPractice() => apply(PracticePlan.normal);

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

/// What came of asking the roster to change something.
///
/// Not a nullable result. "Nothing happened because something else was
/// running" and "it happened" are different answers, and a screen that
/// confirms an unexamined one announces a switch that never occurred.
@immutable
sealed class ProfileMutation<T> {
  const ProfileMutation();
}

/// The change landed.
@immutable
class ProfileChanged<T> extends ProfileMutation<T> {
  /// What it produced.
  final T value;

  const ProfileChanged(this.value);
}

/// Part of the change landed, and the rest did not.
///
/// Carries what was committed, so finishing operates on that rather than
/// running the whole thing again.
@immutable
class ProfilePartlyChanged<T> extends ProfileMutation<T> {
  /// What was committed before it stopped.
  final T value;

  /// What stopped the rest.
  final Object cause;

  const ProfilePartlyChanged(this.value, this.cause);
}

/// Nothing was attempted, because another change was already running.
@immutable
class ProfileMutationBusy<T> extends ProfileMutation<T> {
  const ProfileMutationBusy();
}

/// The change was attempted and did not land.
@immutable
class ProfileMutationFailed<T> extends ProfileMutation<T> {
  /// What went wrong.
  final Object error;

  const ProfileMutationFailed(this.error);
}

/// Creating, renaming, switching, erasing, and deleting profiles.
///
/// Every mutation goes through the lifecycle and then reloads this list.
/// Reloading the practice loop is separate and deliberate: reopening a sitting
/// while an exercise is on screen leaves its decision pending, so the loop is
/// invalidated only when a change actually moves the ground under it, which
/// means a change to the active profile.
class ProfileRosterNotifier extends AsyncNotifier<List<ProfileSummary>> {
  /// Whether a write is already running, for the reason [PracticeLoopNotifier]
  /// keeps the same flag.
  bool _writing = false;

  /// A profile that was created and never selected, kept so the unfinished
  /// half can be retried against that identity.
  Profile? _unselected;

  @override
  Future<List<ProfileSummary>> build() async {
    final lifecycle = await ref.watch(profileLifecycleProvider.future);
    final repository = lifecycle.repository;
    final store = lifecycle.store;

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
  Future<ProfileMutation<Profile>> add(
    String displayName,
    PlacementTier placement,
  ) => _mutate(
    (lifecycle) async => _reportCreation(
      await lifecycle.create(
        displayName: displayName,
        placement: placement,
        // Told apart from whoever is already here, which is the whole reason
        // a second profile is being made.
        presentationHint: ProfileColor.unusedAmong(
          await lifecycle.repository.list(),
        ).name,
      ),
    ),
  );

  /// Places the learner this install has not asked about yet.
  ///
  /// The first-launch path, where the profile is conjured rather than named:
  /// what matters is that the tier it starts from is the one somebody chose,
  /// since nothing can change it afterwards.
  Future<ProfileMutation<Profile>> place(PlacementTier placement) => _mutate(
    (lifecycle) async => _reportCreation(
      await lifecycle.place(
        placement,
        presentationHint: ProfileColor.values.first.name,
      ),
    ),
  );

  /// Selects a profile that was created and never became the active one.
  ///
  /// The other half of an [add] or [place] that committed the identity and
  /// stopped. Running the whole thing again would make a second person with a
  /// history of their own.
  Future<ProfileMutation<Profile>> finishAdding() {
    final unselected = _unselected;
    if (unselected == null) {
      return _mutate(
        (_) async => throw StateError('no profile is waiting to be selected'),
      );
    }
    return _mutate(
      (lifecycle) async =>
          _reportCreation(await lifecycle.finishCreating(unselected)),
    );
  }

  /// Whether a profile exists that nothing has selected yet.
  bool get hasUnselectedProfile => _unselected != null;

  /// Turns a creation into a mutation, retaining an identity still owed a
  /// selection.
  (bool, ProfileMutation<Profile>) _reportCreation(ProfileCreation creation) =>
      switch (creation) {
        ProfileCreated(:final profile) => (
          true,
          ProfileChanged(_selected(profile)),
        ),
        ProfileSelectionPending(:final profile, :final cause) => (
          true,
          ProfilePartlyChanged(_unselected = profile, cause),
        ),
        ProfileNotCreated(:final cause) => (
          false,
          ProfileMutationFailed(cause),
        ),
      };

  Profile _selected(Profile profile) {
    _unselected = null;
    return profile;
  }

  /// Changes a profile's display name.
  Future<ProfileMutation<Profile>> rename(
    String profileId,
    String displayName,
  ) => _mutate((lifecycle) async {
    final renamed = await lifecycle.repository.rename(profileId, displayName);
    return (
      await _isActive(lifecycle.repository, profileId),
      ProfileChanged(renamed),
    );
  });

  /// Changes the color a profile is recognized by.
  Future<ProfileMutation<Profile>> recolor(
    String profileId,
    ProfileColor color,
  ) => _mutate((lifecycle) async {
    final restyled = await lifecycle.repository.restyle(profileId, color.name);
    return (
      await _isActive(lifecycle.repository, profileId),
      ProfileChanged(restyled),
    );
  });

  /// Makes [profileId] the profile the practice loop runs as.
  ///
  /// The result reports the profile that is actually selected afterwards, so a
  /// caller confirming a switch is confirming a committed one.
  Future<ProfileMutation<Profile>> select(String profileId) =>
      _mutate((lifecycle) async {
        await lifecycle.repository.select(profileId);
        final active = await lifecycle.repository.selected();
        if (active == null || active.id != profileId) {
          throw StateError('selecting $profileId did not take');
        }
        return (true, ProfileChanged(active));
      });

  /// Erases one profile's recorded practice, keeping the profile itself.
  ///
  /// The way to put a test profile back at placement without losing the name
  /// it is recognized by. The placement survives too: it is who this profile
  /// was when it was created, and starting from a different tier is a
  /// different profile.
  Future<ProfileMutation<void>> eraseHistory(String profileId) =>
      _mutate((lifecycle) async {
        final active = await _isActive(lifecycle.repository, profileId);
        await lifecycle.eraseHistory(profileId);
        return (active, const ProfileChanged<void>(null));
      });

  /// Deletes a profile and everything it recorded.
  ///
  /// Deleting the profile being practiced as leaves the selection on the
  /// oldest one left. Deleting the last one leaves the install with nobody on
  /// it, which puts the app back at the placement question rather than
  /// conjuring a replacement: a profile carries a prior nobody can change
  /// later, so one made on somebody's behalf is the thing to avoid rather
  /// than the tidy outcome.
  Future<ProfileMutation<void>> remove(String profileId) =>
      _mutate((lifecycle) async {
        final active = await _isActive(lifecycle.repository, profileId);
        await lifecycle.delete(profileId);
        return (active, const ProfileChanged<void>(null));
      });

  /// Runs [change], reloads this list, and reloads the practice loop when the
  /// change touched the active profile.
  ///
  /// The reload happens whether or not the change succeeded. Several of these
  /// commit part of their work before they fail, and leaving the screen on
  /// what it read beforehand would show a roster the storage disagrees with.
  Future<ProfileMutation<T>> _mutate<T>(
    Future<(bool, ProfileMutation<T>)> Function(ProfileLifecycle) change,
  ) async {
    if (_writing) return ProfileMutationBusy<T>();

    _writing = true;
    ref.read(profileMutationProvider.notifier)._running(true);
    var touchedActive = false;
    try {
      final lifecycle = await ref.read(profileLifecycleProvider.future);
      final (touched, result) = await change(lifecycle);
      touchedActive = touched;
      return result;
    } catch (error) {
      // What failed may have committed something first, and there is no
      // saying what from here, so everything reading profile state is asked
      // again.
      touchedActive = true;
      return ProfileMutationFailed<T>(error);
    } finally {
      _writing = false;
      ref.read(profileMutationProvider.notifier)._running(false);
      ref.invalidateSelf();
      if (touchedActive) {
        // The plan first: the loop reads it, and reopening a sitting against
        // the previous profile's scope would decide one slot under it.
        ref.invalidate(practicePlanProvider);
        ref.invalidate(practiceLoopProvider);
      }
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

  /// The incarnation this sitting writes as, or null while it has none.
  ///
  /// The sitting's own writes go through the bound store the session holds.
  /// This is for the observations recorded beside it, which reach storage from
  /// here rather than through the transaction.
  ProfileLifetime? _lifetime;

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
    _lifetime = null;
    _recovery = null;
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    // Deletions the last run did not finish are completed before anything
    // asks who is active, so no sitting opens as somebody this install has
    // already decided to forget.
    final ProfileLifecycle lifecycle;
    try {
      lifecycle = await ref.watch(profileLifecycleProvider.future);
    } on ProfileStorageException catch (error) {
      throw _classify(error);
    }
    final store = lifecycle.store;

    // Never conjures anybody. An install with no profile has not answered the
    // placement question, and answering it is what creates the learner; a
    // sitting opened before that would run as somebody started from a prior
    // nobody chose. The gate above this screen is what makes it unreachable.
    //
    // Each artifact is classified where it is read, so a recovery acts on the
    // file that actually failed rather than on whatever this notifier happens
    // to be holding.
    final Profile? profile;
    try {
      profile = await lifecycle.repository.selectedOrOldest();
    } on ProfileStorageException catch (error) {
      throw _classify(error);
    }
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
    // A plan naming something this build cannot read stops the sitting rather
    // than opening a wider one. What was stored is intent, and the failure a
    // learner can act on is being told their plan was not understood.
    final resolution = plan.resolve(catalog);
    if (resolution case UnresolvablePlan(:final failures)) {
      await scheduler.dispose();
      throw PracticeLoopFailure(
        PracticeFailure.plan,
        UnusablePracticePlan(
          PlanFault.unresolvable,
          'this practice plan names '
          '${failures.map((failure) => failure.reference).join(', ')}, '
          'which this version does not recognize',
        ),
        profileId: profile.id,
      );
    }
    final scope = resolution as ResolvedPlan;
    // Bound to the incarnation standing now. Everything this sitting writes
    // carries it, so an erase during the sitting refuses the writes rather
    // than letting them put the erased history back.
    final lifetime = await store.lifetimeOf(profile.id);
    final PracticeSession session;
    try {
      session = await PracticeSession.open(
        store: store.boundTo(lifetime),
        profile: profile,
        appBuildVersion: ref.watch(appBuildVersionProvider),
        materials: catalog,
        scheduler: scheduler,
        goal: scope.goal,
        focus: scope.focus,
      );
    } catch (error) {
      await scheduler.dispose();
      // This one is about the history, and it names whose: replaying it is
      // what failed, and the way out destroys exactly that profile's journal.
      throw PracticeLoopFailure(
        PracticeFailure.history,
        error,
        profileId: profile.id,
      );
    }

    final identity = PracticeSessionIdentity.next(profile.id);
    // Replaced or torn down while opening, which are two ways of no longer
    // being the sitting rather than one: a build with nothing after it is not
    // superseded, and is just as gone. Either way this result is discarded;
    // what it must not do is go on to decide, because deciding persists a
    // pending slot over whatever is presenting one now, and the attempt on
    // screen and the attempt a relaunch recovers then disagree.
    if (_disposed || build != _builds) {
      await scheduler.dispose();
      return PracticeLoopState(
        identity: identity,
        profile: profile,
        plan: plan,
        session: session,
        note: 'abandoned while opening',
      );
    }
    _owner = identity;
    _lifetime = lifetime;

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

  /// What a failed profile artifact means for the sitting that wanted it.
  ///
  /// Classified where the artifact is read, and carrying whose it was, so the
  /// recovery offered acts on the file that actually failed.
  static PracticeLoopFailure _classify(ProfileStorageException error) =>
      PracticeLoopFailure(
        switch (error.artifact) {
          ProfileArtifact.selection => PracticeFailure.selection,
          ProfileArtifact.genesis => PracticeFailure.roster,
          ProfileArtifact.deletionIntent => PracticeFailure.deletion,
        },
        error,
        profileId: error.profileId,
      );

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

    await _serialize(
      () => _close(attempt, () async {
        final record = await current.session.closeDeclined(
          transcript: transcript,
          presentation: completion.presentation,
          observedWallTime: DateTime.now().toUtc(),
        );
        return PracticeLoopState(
          identity: current.identity,
          profile: current.profile,
          plan: current.plan,
          session: current.session,
          lastCommitted: record,
        );
      }),
    );
  }

  /// Says the outstanding attempt has actually reached the learner.
  ///
  /// Deciding is not presenting: the next exercise is prepared while the last
  /// one's review is still on screen, and a prepared decision can be discarded
  /// before anybody sees it.
  ///
  /// Answers whether the sitting took it. A screen reporting an exposure does
  /// not get to conclude it was recorded: an attempt this sitting no longer
  /// holds is refused, and a write that failed is refused, so the surface can
  /// ask again rather than marking it done.
  Future<bool> acknowledgePresentation(PracticeAttemptOwner attempt) async {
    if (!_owns(attempt.session)) return false;
    final current = state.value;
    if (current == null || current.attempt != attempt) return false;
    try {
      await current.session.acknowledgePresentation(attempt.attemptId);
      return true;
    } catch (_) {
      return false;
    }
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

    await _serialize(
      () => _close(attempt, () async {
        final record = await current.session.closeAcquisition(
          completion.transcript,
          presentation: completion.presentation,
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
      }),
    );
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

    await _serialize(
      () => _close(attempt, () async {
        if (completion.isInterrupted) {
          final record = await current.session.closeUnmeasured(
            termination: AttemptTermination.inputInterrupted,
            reason: MeasurementUnavailableReason.inputInterrupted,
            presentation: completion.presentation,
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
            presentation: completion.presentation,
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
          presentation: completion.presentation,
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
      }),
    );
  }

  /// The sitting [attempt] belongs to, if it is still the one on screen and
  /// nothing else is being written.
  ///
  /// The ownership check is here rather than at the transaction, because a
  /// completion that names an attempt this sitting is not holding is evidence
  /// about somebody else's slot and there is nowhere to put it.
  ///
  /// Ownership is asked of the notifier first and of the state second. State
  /// is retained across a failure and a rebuild, so a value that still holds
  /// the right attempt is not on its own evidence that its sitting is current.
  PracticeLoopState? _answerable(PracticeAttemptOwner attempt) {
    if (_writing || !_owns(attempt.session)) return null;
    final current = state.value;
    if (current == null || !current.isAwaitingAnswer) return null;
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
        // A lost worker took its binding and nothing else, so the sitting
        // re-establishes where it decides before asking again. Deciding can
        // fail for reasons that say nothing about the host, such as the
        // pending slot not reaching storage, and rebinding for those would
        // diagnose a failure nobody observed.
        retry: () {
          if (error is SchedulerWorkerLost) closed.session.recoverScheduling();
          return _publish(closed);
        },
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
    // A recovery already running is what this exists to finish, not something
    // to start again. Reopening now would abandon a frozen commit mid-write
    // and leave the sitting on screen behind durable history.
    if (_writing) return;

    final recovery = _recovery;
    if (recovery == null || !_owns(recovery.session)) {
      _recovery = null;
      ref.invalidateSelf();
      return;
    }
    await _serialize(recovery.retry);
  }

  /// Runs [work] as the one thing this notifier is writing.
  ///
  /// The single-flight boundary for everything that closes, decides, or
  /// recovers. Held here rather than inside each of them so a recovery and the
  /// operation it is recovering cannot both be running.
  Future<void> _serialize(Future<void> Function() work) async {
    _writing = true;
    try {
      await work();
    } finally {
      _writing = false;
    }
  }

  /// Erases [profileId]'s history and starts over from its placement.
  ///
  /// Destroys recorded practice, which is what makes it a deliberate act
  /// rather than part of the loop: the journal exists so history is not
  /// rewritten, and this is the one operation that admits someone wants none
  /// of it. The profile and the tier it was placed at survive, because a
  /// different starting point is a different learner rather than a cleared
  /// one.
  Future<void> eraseHistory(String profileId) =>
      _repair((lifecycle) => lifecycle.eraseHistory(profileId));

  /// Forgets which profile is active, and opens again.
  ///
  /// The recovery for selection metadata this build cannot read. Everybody is
  /// still here, and reopening chooses among them: nothing anybody practiced
  /// is touched, which is the whole difference between this and erasing.
  Future<void> repairSelection() =>
      _repair((lifecycle) => lifecycle.repository.clearSelection());

  /// Runs a recovery and reopens everything that read what it changed.
  ///
  /// The target is passed in rather than resolved from state. The usual reason
  /// to be here is that the loop would not load, and inferring what to destroy
  /// from what this notifier happened to be holding is how an intact history
  /// gets erased to repair a file somewhere else.
  Future<void> _repair(Future<void> Function(ProfileLifecycle) recover) async {
    if (_writing) return;

    _writing = true;
    state = const AsyncValue.loading();
    try {
      // Through raw storage rather than the reconciled lifecycle. What is
      // usually broken here is metadata reconciliation itself reads, so
      // waiting for a clean start would make the repair need what it repairs.
      await recover(await ref.read(profileLifecycleRawProvider.future));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    } finally {
      _writing = false;
    }
    // Reconciliation runs again now that the artifact it stumbled on is
    // readable, and a deletion it could not finish before is finished now.
    ref.invalidate(profileLifecycleProvider);
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

  /// Storage for the observations recorded beside this sitting, or null when
  /// there is no sitting to record them for.
  ///
  /// Bound like everything else the sitting writes. An exposure is an
  /// observation of a review screen, and a review of an attempt that has been
  /// erased is describing something that no longer happened.
  Future<PracticeStore?> _observing() async {
    final lifetime = _lifetime;
    if (lifetime == null) return null;
    final lifecycle = await ref.read(profileLifecycleProvider.future);
    return lifecycle.store.boundTo(lifetime);
  }

  /// Records that one part of a review was actually in front of the learner.
  ///
  /// One row per part rather than one for the whole screen. A review scrolls,
  /// and what it holds is built whether or not it is ever reached, so a single
  /// row for all of it would claim exposure to feedback nobody scrolled to.
  ///
  /// Answers whether it was written, for the reason [acknowledgePresentation]
  /// does.
  Future<bool> recordFeedbackExposure({
    required AttemptRecord record,
    PostAttemptFeedback postAttemptFeedback = PostAttemptFeedback.none,
    List<ProgressEvent> progress = const [],
  }) async {
    try {
      final store = await _observing();
      if (store == null) return false;
      await store.appendFeedbackExposure(
        FeedbackExposure(
          profileId: record.profileId,
          attemptId: record.identity.attemptId,
          shownAt: DateTime.now().toUtc(),
          postAttemptFeedback: postAttemptFeedback,
          progressFeedback: progress.isEmpty
              ? ProgressFeedback.none
              : ProgressFeedback.personalProgress,
          progressEvents: progress.map((event) => event.type),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
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
      final store = await _observing();
      if (store == null) return;
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
