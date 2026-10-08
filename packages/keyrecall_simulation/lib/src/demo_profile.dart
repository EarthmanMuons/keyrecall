import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'demo_history.dart';
import 'player_archetypes.dart';

/// Creates a demo profile in [staging] and practices it through [sessions],
/// ready for [publishDemoProfile].
///
/// [staging] is a storage root of its own, so the run is the only store
/// writing there and a failure leaves nothing a roster reads. Before returning,
/// the whole journal is replayed from placement without a checkpoint and has
/// to reproduce itself, and reopening it the way the app will, from the saved
/// checkpoint, has to reach the same state.
Future<Profile> prepareDemoProfile(
  Directory staging, {
  required List<DemoSession> sessions,
  String? presentationHint,
  void Function(int completed, int total)? onSession,
}) async {
  final player = PlayerArchetypes.developing;
  final profile = await FileProfileRepository(staging).create(
    displayName: 'Demo',
    placement: player.placement,
    createdAt: demoHistoryStart,
    presentationHint: presentationHint,
  );
  final store = FilePracticeStore(staging);
  await practiceDemoHistory(
    store: store.boundTo(await store.lifetimeOf(profile.id)),
    profile: profile,
    player: player,
    materials: allPracticeMaterials,
    sessions: sessions,
    onSession: onSession,
  );
  const learner = LearnerModel();
  final replayed = replayJournal(
    await store.loadJournal(profile.id),
    model: learner,
    initial: learner.placementState(profile.placement, at: profile.createdAt),
  );
  if (!replayed.isFaithful) {
    throw StateError(
      'the demo history does not replay: ${replayed.divergences.first}',
    );
  }
  final reopened = await PracticeSession.open(
    store: FilePracticeStore(staging),
    profile: profile,
    materials: allPracticeMaterials,
    learner: learner,
  );
  if (learnerStateHash(reopened.state) != learnerStateHash(replayed.state)) {
    throw StateError(
      'reopening the demo history from its checkpoint does not reach the '
      'state a full replay does',
    );
  }
  return profile;
}

/// Moves [profile], prepared in [staging], into the storage at [root].
///
/// One directory rename, so the profile appears whole or not at all: a profile
/// directory describes itself, and [FileProfileRepository] lists whatever holds
/// a valid record of itself. [staging] has to be on the same volume as [root]
/// for the rename to be atomic.
Future<void> publishDemoProfile(
  Profile profile, {
  required Directory staging,
  required Directory root,
}) async {
  final target = Directory('${root.path}/${profile.id}');
  if (target.existsSync()) {
    throw StateError('${target.path} already exists');
  }
  await root.create(recursive: true);
  await Directory('${staging.path}/${profile.id}').rename(target.path);
}

bool _staging = false;

/// Runs [run] with [staging] cleared before it and removed after it, refusing
/// to start while another run in this isolate holds it.
///
/// Every run shares the one directory, so a second clearing it would delete
/// the first one's history partway through. The refusal comes before anything
/// in [staging] is touched, and the hold is released only once it is removed.
Future<T> withDemoStaging<T>(
  Directory staging,
  Future<T> Function() run,
) async {
  if (_staging) {
    throw StateError('a demo profile is already being generated');
  }
  _staging = true;
  try {
    // Left by a run that never finished, and owned by nothing else.
    if (staging.existsSync()) await staging.delete(recursive: true);
    return await run();
  } finally {
    try {
      if (staging.existsSync()) await staging.delete(recursive: true);
    } finally {
      _staging = false;
    }
  }
}
