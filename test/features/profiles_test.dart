import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/placement.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

import '../support/scheduler_override.dart';

import 'package:keyrecall/features/practice/profiles_screen.dart';

void main() {
  late InMemoryProfileRepository profiles;
  late InMemoryPracticeStore practice;

  setUp(() {
    profiles = InMemoryProfileRepository();
    practice = InMemoryPracticeStore();
  });

  ProviderContainer containerOn() {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        inProcessScheduling,
        practiceStoreProvider.overrideWith((ref) async => practice),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpProfiles(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await container.read(profileRosterProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilesScreen()),
      ),
    );
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<(Profile, Profile)> seedTwo(ProviderContainer container) async {
    final repository = await container.read(profileRepositoryProvider.future);
    final alice = await repository.create(
      displayName: 'Alice',
      placement: PlacementTier.someExperience,
    );
    final bob = await repository.create(
      displayName: 'Bob',
      placement: PlacementTier.beginner,
    );
    // Creating writes a genesis and nothing else, so who is practicing is
    // said here rather than inferred from who was made first.
    await repository.select(alice.id);
    return (alice, bob);
  }

  testWidgets('shows everybody, marking the one being practiced as', (
    tester,
  ) async {
    final container = containerOn();
    await seedTwo(container);
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
      await tapAndSettle(tester, find.text(PlacementTier.beginner.headline));
      await tapAndSettle(tester, find.text('Continue'));

      final repository = await container.read(profileRepositoryProvider.future);
      final created = (await repository.list()).single;
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

      final repository = await container.read(profileRepositoryProvider.future);
      expect(
        await repository.list(),
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
    final (_, bob) = await seedTwo(container);
    await pumpProfiles(tester, container);

    await tapAndSettle(tester, find.text('Bob'));

    final loop = await container.read(practiceLoopProvider.future);
    expect(loop.profile.id, bob.id);
  });

  test(
    'a mutation asked for while one runs is refused, not confirmed',
    () async {
      final container = containerOn();
      await container.read(profileRosterProvider.future);
      final (alice, bob) = await seedTwo(container);
      final notifier = container.read(profileRosterProvider.notifier);

      final first = notifier.select(alice.id);
      final second = await notifier.select(bob.id);
      await first;

      expect(second, isA<ProfileMutationBusy<Profile>>());
      expect((await profiles.selected())?.id, alice.id);
    },
  );

  test('a selection confirms the profile storage actually holds', () async {
    final container = containerOn();
    await container.read(profileRosterProvider.future);
    final (alice, _) = await seedTwo(container);

    final switched = await container
        .read(profileRosterProvider.notifier)
        .select(alice.id);

    expect((switched as ProfileChanged<Profile>).value.id, alice.id);
    expect((await profiles.selected())?.id, alice.id);
  });

  test('a create whose selection fails is finished, not repeated', () async {
    final repository = _SelectionRefusesOnce(profiles);
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => repository),
        inProcessScheduling,
        practiceStoreProvider.overrideWith((ref) async => practice),
      ],
    );
    addTearDown(container.dispose);
    await container.read(profileRosterProvider.future);
    final notifier = container.read(profileRosterProvider.notifier);

    final added = await notifier.add('Bob', PlacementTier.someExperience);
    expect(added, isA<ProfilePartlyChanged<Profile>>());
    expect(notifier.hasUnselectedProfile, isTrue);
    final created = (added as ProfilePartlyChanged<Profile>).value;

    expect(await notifier.finishAdding(), isA<ProfileChanged<Profile>>());
    expect((await profiles.list()).map((profile) => profile.id), [created.id]);
    expect((await profiles.selected())?.id, created.id);
    expect(notifier.hasUnselectedProfile, isFalse);
  });

  test('erasing a history keeps the profile and its placement', () async {
    final container = containerOn();
    await container.read(profileRosterProvider.future);
    final created = await profiles.create(
      displayName: 'Alice',
      placement: PlacementTier.advanced,
    );
    await practice.savePracticePlan(created.id, PracticePlan.normal);

    final erased = await container
        .read(profileRosterProvider.notifier)
        .eraseHistory(created.id);

    expect(erased, isA<ProfileChanged<void>>());
    final remaining = (await profiles.list()).single;
    expect(remaining.id, created.id);
    expect(remaining.placement, PlacementTier.advanced);
    expect(await practice.loadPracticePlan(created.id), isNull);
  });

  test(
    'an interrupted deletion leaves an intent that can be finished',
    () async {
      final repository = InMemoryProfileRepository();
      final profile = await repository.create(
        displayName: 'Alice',
        placement: PlacementTier.someExperience,
      );
      final store = _FailingEraseStore(InMemoryPracticeStore());
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith((ref) async => repository),
          inProcessScheduling,
          practiceStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(container.dispose);
      await container.read(profileRosterProvider.future);
      final removed = await container
          .read(profileRosterProvider.notifier)
          .remove(profile.id);

      expect(removed, isA<ProfileMutationFailed<void>>());
      // Off the roster from the moment the intent was durable, so nothing
      // offers a profile this install has decided to forget. The history is
      // still there, and so is the intent that names it.
      expect(await repository.find(profile.id), isNull);
      expect(await repository.pendingDeletions(), [profile.id]);

      final resumed = ProfileLifecycle(
        repository: repository,
        store: InMemoryPracticeStore(),
      );
      expect(await resumed.resumeDeletions(), [profile.id]);
      expect(await repository.pendingDeletions(), isEmpty);
    },
  );
}

class _FailingEraseStore with UnretiredLifetimes implements PracticeStore {
  @override
  Future<Map<String, String>> loadSelectionDiagnostics(String profileId) =>
      inner.loadSelectionDiagnostics(profileId);

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) => inner.appendSelectionDiagnostics(profileId, attemptId, diagnostics);

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
  Future<FluencyHistory?> loadFluencyHistory(
    String profileId, {
    required DayPartition partition,
  }) => inner.loadFluencyHistory(profileId, partition: partition);

  @override
  Future<void> saveFluencyHistory(FluencyHistory history) =>
      inner.saveFluencyHistory(history);

  @override
  Future<List<CoordinationSample>> loadCoordinationSamples(String profileId) =>
      inner.loadCoordinationSamples(profileId);

  @override
  Future<void> appendCoordinationSample(CoordinationSample sample) =>
      inner.appendCoordinationSample(sample);

  @override
  Future<PracticePlan?> loadPracticePlan(String profileId) =>
      inner.loadPracticePlan(profileId);

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) =>
      inner.savePracticePlan(profileId, plan);

  @override
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  }) => inner.loadAcquisitionJournal(profileId, createdAt: createdAt);

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) =>
      inner.appendAcquisitionEntry(entry);

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

/// A repository whose first selection refuses, the way a full disk would.
class _SelectionRefusesOnce implements ProfileRepository {
  final ProfileRepository _repository;
  bool _refused = false;

  _SelectionRefusesOnce(this._repository);

  @override
  Future<Profile> select(String profileId) async {
    if (_refused) return _repository.select(profileId);
    _refused = true;
    throw StateError('the selection could not be written');
  }

  @override
  Future<Profile> create({
    required String displayName,
    required PlacementTier placement,
    DateTime? createdAt,
    String? presentationHint,
  }) => _repository.create(
    displayName: displayName,
    placement: placement,
    createdAt: createdAt,
    presentationHint: presentationHint,
  );

  @override
  Future<List<Profile>> list() => _repository.list();

  @override
  Future<Profile?> selected() => _repository.selected();

  @override
  Future<Profile?> selectedOrOldest() => _repository.selectedOrOldest();

  @override
  Future<Profile?> find(String profileId) => _repository.find(profileId);

  @override
  Future<Profile> rename(String profileId, String displayName) =>
      _repository.rename(profileId, displayName);

  @override
  Future<Profile> restyle(String profileId, String? presentationHint) =>
      _repository.restyle(profileId, presentationHint);

  @override
  Future<void> clearSelection() => _repository.clearSelection();

  @override
  Future<void> beginDelete(String profileId) =>
      _repository.beginDelete(profileId);

  @override
  Future<List<String>> pendingDeletions() => _repository.pendingDeletions();

  @override
  Future<void> finishDelete(String profileId) =>
      _repository.finishDelete(profileId);

  @override
  Future<Profile> delete(String profileId) => _repository.delete(profileId);
}
