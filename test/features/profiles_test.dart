import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/practice_providers.dart';
import 'package:keyrecall/features/practice/profiles_screen.dart';

/// The profile screen driven the way somebody maintaining several histories
/// would drive it.
///
/// Reading the roster and switching profiles only, which is the part of this
/// screen the practice loop depends on. Adding, renaming, erasing, and
/// deleting all run through a dialog, and driving a dialog that writes to disk
/// means taps under the fake clock and file I/O under the real one at the same
/// time; those tests spent longer fighting the harness than the code was worth.
/// The repository operations underneath them are covered directly in
/// keyrecall_practice, both in memory and on files.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_profiles_ui_test');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  ProviderContainer containerOn() {
    final container = ProviderContainer(
      overrides: [storageRootProvider.overrideWith((ref) async => root)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Pumps the screen with the roster already read from storage.
  ///
  /// Reading it is real file I/O, which the test binding's fake clock does not
  /// advance, so it has to happen in [WidgetTester.runAsync].
  Future<void> pumpProfiles(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => container.read(profileRosterProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilesScreen()),
      ),
    );
    await tester.pump();
  }

  /// Taps [finder] and lets the storage writes it starts actually finish.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  Future<(Profile, Profile)> seedTwo(ProviderContainer container) async {
    final repository = await container.read(profileRepositoryProvider.future);
    return (
      await repository.create(
        displayName: 'Alice',
        placement: PlacementTier.someExperience,
      ),
      await repository.create(
        displayName: 'Bob',
        placement: PlacementTier.beginner,
      ),
    );
  }

  testWidgets('shows everybody, marking the one being practiced as', (
    tester,
  ) async {
    final container = containerOn();
    await tester.runAsync(() => seedTwo(container));
    await pumpProfiles(tester, container);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Alice'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
      reason: 'the first profile created is the one being practiced as',
    );
    // The placement is on the row because nothing can change it, and Alice
    // and Bob were seeded at different tiers.
    expect(
      find.text('nothing played yet · some scales · added ${_today()}'),
      findsOneWidget,
    );
    expect(
      find.text('nothing played yet · new to scales · added ${_today()}'),
      findsOneWidget,
    );
  });

  group('adding a profile', () {
    /// Runs the add flow as far as the placement question.
    Future<void> nameAndContinue(WidgetTester tester, String name) async {
      await tapAndSettle(tester, find.byIcon(Icons.person_add));
      await tester.enterText(find.byType(TextField), name);
      await tapAndSettle(tester, find.text('Add'));
    }

    testWidgets('asks where to start, and records the answer', (tester) async {
      final container = containerOn();
      await pumpProfiles(tester, container);

      await nameAndContinue(tester, 'Cass');
      expect(find.text('Where should we start?'), findsOneWidget);
      await tapAndSettle(tester, find.text('I’m new to scales.'));

      final repository = await tester.runAsync(
        () => container.read(profileRepositoryProvider.future),
      );
      final created = (await tester.runAsync(() => repository!.list()))!.single;
      expect(created.displayName, 'Cass');
      expect(
        created.placement,
        PlacementTier.beginner,
        reason:
            'the prior the whole history will be computed from is the one '
            'the learner actually chose',
      );
    });

    testWidgets('creates nobody when the question goes unanswered', (
      tester,
    ) async {
      final container = containerOn();
      await pumpProfiles(tester, container);

      await nameAndContinue(tester, 'Cass');
      await tapAndSettle(tester, find.text('Cancel'));

      final repository = await tester.runAsync(
        () => container.read(profileRepositoryProvider.future),
      );
      expect(
        await tester.runAsync(() => repository!.list()),
        isEmpty,
        reason:
            'a placement nobody chose is not one to invent on their '
            'behalf, and it could never be corrected afterwards',
      );
    });
  });

  testWidgets('tapping a profile switches who the practice loop runs as', (
    tester,
  ) async {
    final container = containerOn();
    final (_, bob) =
        await tester.runAsync(() => seedTwo(container)) as (Profile, Profile);
    await pumpProfiles(tester, container);

    await tapAndSettle(tester, find.text('Bob'));

    final loop = await tester.runAsync(
      () => container.read(practiceLoopProvider.future),
    );
    expect(loop!.profile.id, bob.id);
  });

  test('profile authority is removed before history cleanup', () async {
    final repository = FileProfileRepository(root);
    final profile = await repository.create(
      displayName: 'Alice',
      placement: PlacementTier.someExperience,
    );
    final history = File('${root.path}/${profile.id}/journal.jsonl');
    final store = _FailingEraseStore(FilePracticeStore(root));
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => repository),
        practiceStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(profileRosterProvider.future);
    history.writeAsStringSync('orphaned history');

    await expectLater(
      container.read(profileRosterProvider.notifier).remove(profile.id),
      throwsStateError,
    );

    expect(await repository.find(profile.id), isNull);
    expect(history.existsSync(), isTrue);
  });
}

class _FailingEraseStore implements PracticeStore {
  final PracticeStore inner;

  _FailingEraseStore(this.inner);

  @override
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt}) =>
      inner.loadJournal(profileId, createdAt: createdAt);

  @override
  Future<void> appendAttempt(AttemptRecord record) =>
      inner.appendAttempt(record);

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId) =>
      inner.loadFeedbackExposures(profileId);

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) =>
      inner.appendFeedbackExposure(exposure);

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) =>
      inner.loadPendingDecision(profileId);

  @override
  Future<void> savePendingDecision(PendingDecision decision) =>
      inner.savePendingDecision(decision);

  @override
  Future<void> clearPendingDecision(String profileId) =>
      inner.clearPendingDecision(profileId);

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) =>
      inner.loadCheckpoint(profileId);

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) =>
      inner.saveCheckpoint(checkpoint);

  @override
  Future<void> erase(String profileId) =>
      throw StateError('history cleanup failed');
}

/// Today, formatted the way a profile row reports when it was added.
String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
