import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
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

  /// Why there is nothing to present, when there is nothing.
  final String? note;

  const PracticeLoopState({
    required this.profile,
    required this.session,
    this.presented,
    this.pending,
    this.lastCommitted,
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
final practiceLoopProvider =
    AsyncNotifierProvider<PracticeLoopNotifier, PracticeLoopState>(
      PracticeLoopNotifier.new,
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

    // No profile decision is asked of a first-time user: the install gets one
    // and only needs attention if a second is ever wanted.
    final profile = await repository.selectedOrDefault();
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

    _writing = true;
    state = const AsyncValue.loading();
    try {
      state = await AsyncValue.guard(() async {
        final record = await current.session.closeFromPerformance(
          transcript,
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
    final current = state.value;
    if (_writing || current == null) return;

    _writing = true;
    state = const AsyncValue.loading();
    try {
      final store = await ref.read(practiceStoreProvider.future);
      await store.erase(current.profile.id);
    } finally {
      _writing = false;
    }
    ref.invalidateSelf();
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
      note: presented == null
          ? 'the scheduler admitted nothing for this slot'
          : from.note,
    );
  }
}
