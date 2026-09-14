import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// A repository whose selection refuses once, the way a full disk would.
class _SelectionFailsOnce implements ProfileRepository {
  final ProfileRepository _repository;
  bool _refused = false;

  _SelectionFailsOnce(this._repository);

  @override
  Future<Profile> select(String profileId) async {
    if (_refused) return _repository.select(profileId);
    _refused = true;
    throw const FileSystemException('no space left on device');
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

/// A store whose erase refuses, the way an interrupted deletion behaves.
class _ForgetFails extends InMemoryPracticeStore {
  @override
  Future<void> forget(String profileId) async =>
      throw const FileSystemException('no space left on device');
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_lifecycle_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ProfileLifecycle inMemory({
    ProfileRepository? repository,
    PracticeStore? store,
  }) => ProfileLifecycle(
    repository: repository ?? InMemoryProfileRepository(now: () => t0),
    store: store ?? InMemoryPracticeStore(),
  );

  group('creating', () {
    test('reports both steps landing', () async {
      final lifecycle = inMemory();

      final created = await lifecycle.create(
        displayName: 'Alice',
        placement: PlacementTier.someExperience,
      );

      expect(created, isA<ProfileCreated>());
      final profile = (created as ProfileCreated).profile;
      expect((await lifecycle.repository.selected())?.id, profile.id);
    });

    test('keeps the identity when only the selection fails', () async {
      final repository = _SelectionFailsOnce(
        InMemoryProfileRepository(now: () => t0),
      );
      final lifecycle = inMemory(repository: repository);

      final attempted = await lifecycle.create(
        displayName: 'Bob',
        placement: PlacementTier.someExperience,
      );

      expect(attempted, isA<ProfileSelectionPending>());
      final pending = attempted as ProfileSelectionPending;
      expect((await repository.list()).single.id, pending.profile.id);

      // Finishing selects the profile that exists. Creating again would make a
      // second Bob with a history of his own.
      expect(
        await lifecycle.finishCreating(pending.profile),
        isA<ProfileCreated>(),
      );
      expect((await repository.list()).single.id, pending.profile.id);
      expect((await repository.selected())?.id, pending.profile.id);
    });

    test('placing an install that has somebody returns them', () async {
      final lifecycle = inMemory();
      final placed = await lifecycle.place(PlacementTier.someExperience);

      final again = await lifecycle.place(PlacementTier.advanced);

      expect(
        (again as ProfileCreated).profile.id,
        (placed as ProfileCreated).profile.id,
      );
      expect(again.profile.placement, PlacementTier.someExperience);
      expect(await lifecycle.repository.list(), hasLength(1));
    });
  });

  group('deleting', () {
    test('removes the profile and its practice together', () async {
      final lifecycle = inMemory();
      final created =
          (await lifecycle.create(
                displayName: 'Alice',
                placement: PlacementTier.someExperience,
              ))
              as ProfileCreated;
      await lifecycle.store.savePracticePlan(
        created.profile.id,
        PracticePlan.normal,
      );

      await lifecycle.delete(created.profile.id);

      expect(await lifecycle.repository.list(), isEmpty);
      expect(
        await lifecycle.store.loadPracticePlan(created.profile.id),
        isNull,
      );
      expect(await lifecycle.repository.pendingDeletions(), isEmpty);
    });

    test('an interrupted deletion leaves an intent and resumes', () async {
      final repository = InMemoryProfileRepository(now: () => t0);
      final broken = inMemory(repository: repository, store: _ForgetFails());
      final created =
          (await broken.create(
                displayName: 'Alice',
                placement: PlacementTier.someExperience,
              ))
              as ProfileCreated;

      await expectLater(
        broken.delete(created.profile.id),
        throwsA(isA<FileSystemException>()),
      );
      // Off the roster already: the decision is durable even though the
      // practice is still there.
      expect(await repository.list(), isEmpty);
      expect(await repository.pendingDeletions(), [created.profile.id]);

      final resumed = inMemory(repository: repository);
      expect(await resumed.resumeDeletions(), [created.profile.id]);
      expect(await repository.pendingDeletions(), isEmpty);
      expect(await repository.list(), isEmpty);
    });

    test('resuming finishes a deletion recorded before a restart', () async {
      final repository = FileProfileRepository(root, now: () => t0);
      final store = FilePracticeStore(root);
      final lifecycle = ProfileLifecycle(repository: repository, store: store);
      final created =
          (await lifecycle.create(
                displayName: 'Alice',
                placement: PlacementTier.someExperience,
              ))
              as ProfileCreated;
      await store.savePracticePlan(created.profile.id, PracticePlan.normal);
      await repository.beginDelete(created.profile.id);

      final reopened = ProfileLifecycle(
        repository: FileProfileRepository(root, now: () => t0),
        store: FilePracticeStore(root),
      );
      expect(await reopened.resumeDeletions(), [created.profile.id]);

      expect(await reopened.repository.list(), isEmpty);
      expect(await reopened.store.loadPracticePlan(created.profile.id), isNull);
      expect(
        repository.profileFileFor(created.profile.id).existsSync(),
        isFalse,
      );
    });

    test('resuming twice is no worse than resuming once', () async {
      final lifecycle = inMemory();
      final created =
          (await lifecycle.create(
                displayName: 'Alice',
                placement: PlacementTier.someExperience,
              ))
              as ProfileCreated;
      await lifecycle.repository.beginDelete(created.profile.id);

      expect(await lifecycle.resumeDeletions(), [created.profile.id]);
      expect(await lifecycle.resumeDeletions(), isEmpty);
    });
  });

  test('erasing keeps the profile and its placement', () async {
    final lifecycle = inMemory();
    final created =
        (await lifecycle.create(
              displayName: 'Alice',
              placement: PlacementTier.advanced,
            ))
            as ProfileCreated;
    await lifecycle.store.savePracticePlan(
      created.profile.id,
      PracticePlan.normal,
    );

    await lifecycle.eraseHistory(created.profile.id);

    final remaining = (await lifecycle.repository.list()).single;
    expect(remaining.id, created.profile.id);
    expect(remaining.placement, PlacementTier.advanced);
    expect(await lifecycle.store.loadPracticePlan(remaining.id), isNull);
  });
}
