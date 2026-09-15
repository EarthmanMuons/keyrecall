import 'dart:convert';
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

    test('a genesis on disk is never reported as nothing created', () async {
      // The boundary the repository used to hide. Creating wrote the genesis
      // and, for the first profile, the selection, so a selection that failed
      // came back as a create that had not happened while profile.json was
      // already on disk.
      final repository = _SelectionFailsOnce(
        FileProfileRepository(root, now: () => t0),
      );
      final lifecycle = ProfileLifecycle(
        repository: repository,
        store: FilePracticeStore(root),
      );

      final attempted = await lifecycle.create(
        displayName: 'Alice',
        placement: PlacementTier.someExperience,
      );

      expect(attempted, isA<ProfileSelectionPending>());
      final created = (attempted as ProfileSelectionPending).profile;
      expect(
        FileProfileRepository(root).profileFileFor(created.id).existsSync(),
        isTrue,
        reason: 'the genesis landed, and the result has to say so',
      );
      expect(File('${root.path}/profiles.json').existsSync(), isFalse);

      // A restart finds that profile and finishes the half that is owed,
      // rather than placing the install again and making a second Alice.
      final reopened = FileProfileRepository(root, now: () => t0);
      expect((await reopened.list()).single.id, created.id);
      expect(
        await ProfileLifecycle(
          repository: reopened,
          store: FilePracticeStore(root),
        ).place(PlacementTier.advanced),
        isA<ProfileCreated>().having(
          (placed) => placed.profile.id,
          'profile',
          created.id,
        ),
      );
      expect((await reopened.list()).single.id, created.id);
      expect((await reopened.selected())?.id, created.id);
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

    group('an intent already on disk is read before anything is destroyed', () {
      /// A file-backed install with Alice on it and something recorded.
      Future<(ProfileLifecycle, Profile)> withPractice() async {
        final lifecycle = ProfileLifecycle(
          repository: FileProfileRepository(root, now: () => t0),
          store: FilePracticeStore(root),
        );
        final created =
            (await lifecycle.create(
                  displayName: 'Alice',
                  placement: PlacementTier.someExperience,
                ))
                as ProfileCreated;
        // An incarnation, the way opening a sitting establishes one, so the
        // deletion has all three of a profile's durable parts to destroy.
        await lifecycle.store.lifetimeOf(created.profile.id);
        await lifecycle.store.savePracticePlan(
          created.profile.id,
          PracticePlan.normal,
        );
        return (lifecycle, created.profile);
      }

      void markDeleting(String profileId, Object? contents) => File(
        '${root.path}/$profileId/deleting.json',
      ).writeAsStringSync(contents is String ? contents : jsonEncode(contents));

      /// Everything a deletion would have destroyed, still here.
      Future<void> expectUntouched(
        ProfileLifecycle lifecycle,
        Profile profile,
      ) async {
        expect(
          File('${root.path}/${profile.id}/profile.json').existsSync(),
          isTrue,
          reason: 'the genesis',
        );
        expect(
          File('${root.path}/${profile.id}/lifetime.json').existsSync(),
          isTrue,
          reason: 'the incarnation',
        );
        expect(
          await lifecycle.store.loadPracticePlan(profile.id),
          PracticePlan.normal,
          reason: 'what was recorded',
        );
        expect(
          File('${root.path}/${profile.id}/deleting.json').existsSync(),
          isTrue,
          reason: 'and the marker itself, for somebody to look at',
        );
      }

      Matcher failsOnDeletionIntent(String profileId) => throwsA(
        isA<ProfileStorageException>()
            .having(
              (failure) => failure.artifact,
              'artifact',
              ProfileArtifact.deletionIntent,
            )
            .having((failure) => failure.profileId, 'profileId', profileId),
      );

      test('a malformed one stops the deletion', () async {
        final (lifecycle, profile) = await withPractice();
        markDeleting(profile.id, '{not json');

        await expectLater(
          lifecycle.delete(profile.id),
          failsOnDeletionIntent(profile.id),
        );
        await expectUntouched(lifecycle, profile);
      });

      test("another profile's stops the deletion", () async {
        final (lifecycle, profile) = await withPractice();
        markDeleting(
          profile.id,
          const ProfileDeletionIntent('somebody-else').toJson(),
        );

        await expectLater(
          lifecycle.delete(profile.id),
          failsOnDeletionIntent(profile.id),
        );
        await expectUntouched(lifecycle, profile);
      });

      test('an unsupported one stops the deletion', () async {
        final (lifecycle, profile) = await withPractice();
        markDeleting(profile.id, {
          'schema_version': profileDeletionSchemaVersion + 1,
          'profile_id': profile.id,
        });

        await expectLater(
          lifecycle.delete(profile.id),
          failsOnDeletionIntent(profile.id),
        );
        await expectUntouched(lifecycle, profile);
      });

      test('a valid one is resumed rather than refused', () async {
        final (lifecycle, profile) = await withPractice();
        await lifecycle.repository.beginDelete(profile.id);

        await lifecycle.delete(profile.id);

        expect(await lifecycle.store.loadPracticePlan(profile.id), isNull);
        expect(
          File('${root.path}/${profile.id}/profile.json').existsSync(),
          isFalse,
        );
        expect(
          File('${root.path}/${profile.id}/deleting.json').existsSync(),
          isFalse,
        );
        expect(await lifecycle.repository.pendingDeletions(), isEmpty);
      });
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
