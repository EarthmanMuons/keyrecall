import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:path_provider/path_provider.dart';

import 'attempt_transcript.dart';
import 'reported_result.dart';

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
    return [
      for (final profile in profiles)
        await _summarize(profile, store, isActive: profile.id == activeId),
    ];
  }

  /// Adds a profile and practices as it.
  ///
  /// The repository deliberately does not switch when a profile is created,
  /// because a profile can be made for reasons that have nothing to do with
  /// who is at the instrument. Made from this screen it does: somebody adding
  /// a profile is somebody about to use it, and the list they are already
  /// looking at is how they get back.
  /// [placement] is fixed here for the life of the profile. Nothing offers to
  /// change it later, because it is the prior the whole history is computed
  /// from: a different answer would reinterpret every attempt rather than
  /// update a skill level, and erasing the history is the honest route to a
  /// different starting point.
  Future<Profile?> add(String displayName, PlacementTier placement) =>
      _mutate((repository, store) async {
        final created = await repository.create(
          displayName: displayName,
          placement: placement,
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
  /// would be one the history cannot honour.
  Future<Profile?> place(PlacementTier placement) =>
      _mutate((repository, store) async {
        final existing = await repository.selectedOrOldest();
        if (existing != null) return (true, existing);

        return (
          true,
          await repository.create(
            displayName: defaultProfileName,
            placement: placement,
          ),
        );
      });

  /// Changes a profile's display name.
  Future<Profile?> rename(String profileId, String displayName) =>
      _mutate((repository, store) async {
        final renamed = await repository.rename(profileId, displayName);
        return (await _isActive(repository, profileId), renamed);
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
  /// History first, then the index entry. A directory no index entry names is
  /// clutter that can be swept up later; an index entry whose history is
  /// already gone is a person the app would try to open and could not.
  ///
  /// Deleting the profile being practiced as leaves the selection on the
  /// oldest one left. Deleting the last one leaves the install with nobody on
  /// it, which puts the app back at the placement question rather than
  /// conjuring a replacement: a profile carries a prior nobody can change
  /// later, so one made on somebody's behalf is the thing to avoid rather
  /// than the tidy outcome.
  Future<void> remove(String profileId) => _mutate((repository, store) async {
    final active = await _isActive(repository, profileId);
    await store.erase(profileId);
    await repository.delete(profileId);
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
      if (touchedActive) ref.invalidate(practiceLoopProvider);
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

/// Everything the panel needs to show about the loop's current position.
@immutable
class PracticeLoopState {
  /// Whose sitting this is.
  final Profile profile;

  /// The open sitting.
  final PracticeSession session;

  /// What is on screen waiting to be answered, if anything.
  final PresentedAttempt? presented;

  /// A decision from an earlier run that was never answered.
  final PendingDecision? pending;

  /// The last attempt committed in this sitting.
  final AttemptRecord? lastCommitted;

  /// What [lastCommitted] was read from, when it was read from a performance.
  ///
  /// Absent for a decline, for a hand-entered report, and after a reopen, all
  /// of which produce a record without a correspondence behind it. Nothing
  /// persists this, so it lives exactly as long as the review that reads it.
  final PerformanceReading? lastReading;

  /// Why there is nothing to present, when there is nothing.
  final String? note;

  const PracticeLoopState({
    required this.profile,
    required this.session,
    this.presented,
    this.pending,
    this.lastCommitted,
    this.lastReading,
    this.note,
  });

  /// Whether an answer is being waited on, from either source.
  bool get isAwaitingAnswer => presented != null || pending != null;

  /// The exercise awaiting an answer, whichever way it got here.
  Exercise? get exercise => presented?.exercise ?? pending?.exercise;

  /// How many attempts this profile has recorded, ever.
  int get attemptsRecorded => session.journal.records.length;
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

  @override
  Future<PracticeLoopState> build() async {
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
    final session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: allScales,
    );

    // An unresolved decision is not quietly discarded and not quietly
    // answered. It was shown to someone; only a person can say what happened.
    if (session.pending != null) {
      return PracticeLoopState(
        profile: profile,
        session: session,
        pending: session.pending,
        note: 'an attempt from an earlier run was never answered',
      );
    }
    return _decide(PracticeLoopState(profile: profile, session: session));
  }

  /// Records that the learner could not retrieve the material, and moves on.
  ///
  /// Not a skip: it commits a real retrieval failure, which is what opens the
  /// recovery context that offers the same exercise with the material shown.
  ///
  /// Single-flight for the same reason [finish] is.
  Future<void> decline() async {
    final current = state.value;
    if (_writing || current == null || !current.isAwaitingAnswer) return;
    // Presented rather than assumed: the session refuses a decline once
    // anything has been played, and it can only check that if it is shown.
    final transcript = ref.read(attemptTranscriptProvider);

    // No loading state: committing is an append and a scheduler decision, and
    // replacing the screen with a spinner for that is how an app teaches
    // someone to wait for it.
    _writing = true;
    try {
      state = await AsyncValue.guard(() async {
        final record = await current.session.closeDeclined(
          transcript: transcript,
          observedWallTime: DateTime.now().toUtc(),
        );
        return _decide(
          PracticeLoopState(
            profile: current.profile,
            session: current.session,
            lastCommitted: record,
          ),
        );
      });
    } finally {
      _writing = false;
    }
  }

  /// Commits what was played and moves to the next exercise.
  ///
  /// The production path: what arrived on the wire becomes the evidence,
  /// without anyone being asked how it went. An attempt the observation model
  /// cannot read commits as unmeasured rather than being scored by hand, which
  /// production should never reach, since it does not present material it
  /// cannot read.
  ///
  /// Single-flight for the same reason [report] is.
  Future<void> finish() async {
    final current = state.value;
    if (_writing || current == null || !current.isAwaitingAnswer) return;
    final transcript = ref.read(attemptTranscriptProvider);

    // No loading state: committing is an append and a scheduler decision, and
    // replacing the screen with a spinner for that is how an app teaches
    // someone to wait for it.
    _writing = true;
    try {
      state = await AsyncValue.guard(() async {
        final closed = await current.session.closeFromPerformance(
          transcript,
          observedWallTime: DateTime.now().toUtc(),
        );
        return _decide(
          PracticeLoopState(
            profile: current.profile,
            session: current.session,
            lastCommitted: closed.record,
            lastReading: closed.reading,
          ),
        );
      });
    } finally {
      _writing = false;
    }
  }

  /// Records what the person reported and moves to the next exercise.
  ///
  /// Scaffolding from before measurement existed, kept for the dev panel so
  /// learner-state transitions can still be driven by hand. Not a product
  /// path: a self-report is not a second kind of evidence.
  ///
  /// One write at a time. Two quick taps must not both reach
  /// [PracticeSession.commit] with the same decision: the transaction below is
  /// safe to *retry*, which is a different guarantee than being safe to enter
  /// twice at once, and nothing down there was built to serialize concurrent
  /// writers. A second pass folds the same outcome in from an already-advanced
  /// state and produces a different record under the same attempt id, which
  /// the journal then rejects as a collision.
  Future<void> report(ReportedResult result) async {
    final current = state.value;
    if (_writing || current == null || !current.isAwaitingAnswer) return;
    final exercise = current.exercise!;

    _writing = true;
    state = const AsyncValue.loading();
    try {
      state = await AsyncValue.guard(() async {
        final record = await current.session.commit(
          result.toOutcome(exercise),
          observedWallTime: DateTime.now().toUtc(),
        );
        return _decide(
          PracticeLoopState(
            profile: current.profile,
            session: current.session,
            lastCommitted: record,
          ),
        );
      });
    } finally {
      _writing = false;
    }
  }

  /// Discards an unresolved decision without recording anything.
  ///
  /// Single-flight for the same reason [report] is.
  Future<void> abandonPending() async {
    final current = state.value;
    if (_writing || current?.pending == null) return;

    _writing = true;
    state = const AsyncValue.loading();
    try {
      state = await AsyncValue.guard(() async {
        await current!.session.abandonPending();
        return _decide(
          PracticeLoopState(
            profile: current.profile,
            session: current.session,
            note: 'the unanswered attempt was abandoned, recording nothing',
          ),
        );
      });
    } finally {
      _writing = false;
    }
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
      final profile =
          state.value?.profile ?? await repository.selectedOrOldest();
      if (profile != null) await store.erase(profile.id);
    } finally {
      _writing = false;
    }
    ref.invalidateSelf();
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

  /// Asks the scheduler for the next exercise.
  ///
  /// A slot that admits nothing is a real answer rather than an error, and it
  /// still consumes a slot, so the loop reports it instead of retrying.
  Future<PracticeLoopState> _decide(PracticeLoopState from) async {
    final presented = await from.session.decide(at: DateTime.now().toUtc());
    return PracticeLoopState(
      profile: from.profile,
      session: from.session,
      presented: presented,
      lastCommitted: from.lastCommitted,
      lastReading: from.lastReading,
      note: presented == null
          ? 'the scheduler admitted nothing for this slot'
          : from.note,
    );
  }
}
