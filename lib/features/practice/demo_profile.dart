import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_simulation/keyrecall_simulation.dart';

import 'practice_providers.dart';
import 'profile_color.dart';

/// Creates a profile with a fixed four months of synthetic practice behind
/// it, and practices as it.
///
/// For exploring how the app reads a long history. The practice is a
/// developing player run through the real session, so the journal holds only
/// what the app itself could have written. It is generated on a background
/// isolate into a staging root beside the app's own, verified to replay, and
/// only then moved into place, so a run that fails leaves nothing on the
/// roster and the app's store is never written by a second one.
Future<Profile> createDemoProfile(
  WidgetRef ref, {
  void Function(int completed, int total)? onSession,
}) async {
  final lifecycle = await ref.read(profileLifecycleProvider.future);
  final root = await ref.read(storageRootProvider.future);
  final staging = Directory('${root.parent.path}/keyrecall-demo');
  final hint = ProfileColor.unusedAmong(await lifecycle.repository.list()).name;
  final sessions = demoSessions(from: demoHistoryStart, until: demoHistoryEnd);

  final progress = ReceivePort();
  progress.listen((message) {
    final (completed, total) = message as (int, int);
    onSession?.call(completed, total);
  });
  try {
    return await withDemoStaging(staging, () async {
      final profile = await Isolate.run(
        _preparing(staging.path, sessions, hint, progress.sendPort),
      );
      await publishDemoProfile(profile, staging: staging, root: root);
      final selection = await ref
          .read(profileRosterProvider.notifier)
          .select(profile.id);
      return switch (selection) {
        ProfileChanged() => profile,
        ProfileMutationFailed(:final error) => throw error,
        _ => throw StateError('the demo profile was created and not selected'),
      };
    });
  } finally {
    progress.close();
  }
}

/// The isolate's work, closing over nothing but what it is given.
Future<Profile> Function() _preparing(
  String staging,
  List<DemoSession> sessions,
  String hint,
  SendPort progress,
) =>
    () => prepareDemoProfile(
      Directory(staging),
      sessions: sessions,
      presentationHint: hint,
      onSession: (completed, total) => progress.send((completed, total)),
    );
