import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'demo_history.dart';
import 'player_archetypes.dart';

/// Creates a demo profile in [staging] and practices it through [sessions],
/// ready for [publishDemoProfile].
///
/// [staging] is a storage root of its own, so the run is the only store
/// writing there and a failure leaves nothing a roster reads. The finished
/// history is opened once before returning, which replays it, so what gets
/// published is known to reopen.
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
  await PracticeSession.open(
    store: FilePracticeStore(staging),
    profile: profile,
    materials: allPracticeMaterials,
  );
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
