import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_simulation/keyrecall_simulation.dart';

import 'practice_providers.dart';
import 'profile_color.dart';

/// Creates a profile with a fixed four months of synthetic practice behind
/// it, and practices as it.
///
/// For exploring how the app reads a long history. The practice is a
/// [PlayerArchetypes.developing] player run through the real session, so the
/// journal holds only what the app itself could have written. Filled on a
/// background isolate, since it schedules every slot of every session.
Future<Profile> createDemoProfile(
  WidgetRef ref, {
  void Function(int completed, int total)? onSession,
}) async {
  final lifecycle = await ref.read(profileLifecycleProvider.future);
  final root = await ref.read(storageRootProvider.future);
  final player = PlayerArchetypes.developing;
  final creation = await lifecycle.create(
    displayName: 'Demo',
    placement: player.placement,
    createdAt: demoHistoryStart,
    presentationHint: ProfileColor.unusedAmong(
      await lifecycle.repository.list(),
    ).name,
    selecting: false,
  );
  final profile = switch (creation) {
    ProfileCreated(:final profile) => profile,
    ProfileSelectionPending(:final profile) => profile,
    ProfileNotCreated(:final cause) => throw cause,
  };

  final sessions = demoSessions(from: demoHistoryStart, until: demoHistoryEnd);
  final progress = ReceivePort();
  progress.listen((message) {
    final (completed, total) = message as (int, int);
    onSession?.call(completed, total);
  });
  try {
    await Isolate.run(
      _practicing(root.path, profile, player, sessions, progress.sendPort),
    );
  } finally {
    progress.close();
  }

  final selection = await ref
      .read(profileRosterProvider.notifier)
      .select(profile.id);
  if (selection case ProfileMutationFailed(:final error)) throw error;
  return profile;
}

/// The isolate's work, closing over nothing but what it is given.
Future<void> Function() _practicing(
  String root,
  Profile profile,
  SyntheticPlayer player,
  List<DemoSession> sessions,
  SendPort progress,
) => () async {
  final store = FilePracticeStore(Directory(root));
  await practiceDemoHistory(
    store: store.boundTo(await store.lifetimeOf(profile.id)),
    profile: profile,
    player: player,
    materials: allPracticeMaterials,
    sessions: sessions,
    onSession: (completed, total) => progress.send((completed, total)),
  );
};
