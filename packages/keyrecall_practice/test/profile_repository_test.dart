import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_profiles_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Runs the same expectations against both implementations, so the file one
  /// is tested as a repository rather than only as a file format.
  void forEachRepository(
    String description,
    Future<void> Function(ProfileRepository repository) body,
  ) {
    test('$description (in memory)', () async {
      await body(InMemoryProfileRepository(now: () => t0));
    });
    test('$description (file backed)', () async {
      await body(FileProfileRepository(root, now: () => t0));
    });
  }

  group('creating', () {
    forEachRepository('chooses an identity once and keeps it', (
      repository,
    ) async {
      final created = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );

      expect(created.displayName, 'Alice');
      expect(created.createdAt, t0);
      expect(created.id, isNotEmpty);

      final found = await repository.find(created.id);
      expect(found, created);
    });

    forEachRepository('gives each person a distinct identity', (
      repository,
    ) async {
      final first = await repository.create(displayName: 'Sam', createdAt: t0);
      final second = await repository.create(displayName: 'Sam', createdAt: t0);

      expect(first.id, isNot(second.id));
      expect(await repository.list(), hasLength(2));
    });

    forEachRepository('selects the first profile but not the second', (
      repository,
    ) async {
      expect(await repository.selected(), isNull);

      final first = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      expect(
        (await repository.selected())?.id,
        first.id,
        reason: 'an install with one person should not need a selection step',
      );

      await repository.create(displayName: 'Bob', createdAt: t0.plusDays(1));
      expect(
        (await repository.selected())?.id,
        first.id,
        reason: 'adding somebody must not switch who is practicing',
      );
    });
  });

  group('listing', () {
    forEachRepository('is ordered oldest first, deterministically', (
      repository,
    ) async {
      await repository.create(displayName: 'Third', createdAt: t0.plusDays(3));
      await repository.create(displayName: 'First', createdAt: t0);
      await repository.create(displayName: 'Second', createdAt: t0.plusDays(1));

      expect((await repository.list()).map((profile) => profile.displayName), [
        'First',
        'Second',
        'Third',
      ]);
    });
  });

  group('renaming', () {
    forEachRepository('changes the display name and nothing else', (
      repository,
    ) async {
      final created = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
        presentationHint: 'teal',
      );

      final renamed = await repository.rename(created.id, 'Alice B.');

      expect(renamed.id, created.id);
      expect(renamed.createdAt, created.createdAt);
      expect(renamed.presentationHint, created.presentationHint);
      expect(renamed.displayName, 'Alice B.');
      expect((await repository.find(created.id))!.displayName, 'Alice B.');
    });

    forEachRepository('keeps the selection', (repository) async {
      final created = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      await repository.rename(created.id, 'Renamed');

      expect((await repository.selected())?.id, created.id);
    });

    forEachRepository('refuses an unknown profile', (repository) async {
      expect(() => repository.rename('nobody', 'Ghost'), throwsArgumentError);
    });
  });

  group('selecting', () {
    forEachRepository('switches the active profile', (repository) async {
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      final bob = await repository.create(
        displayName: 'Bob',
        createdAt: t0.plusDays(1),
      );

      expect((await repository.selected())?.id, alice.id);
      await repository.select(bob.id);
      expect((await repository.selected())?.id, bob.id);
    });

    forEachRepository('refuses a profile that does not exist', (
      repository,
    ) async {
      await repository.create(displayName: 'Alice', createdAt: t0);

      expect(() => repository.select('nobody'), throwsArgumentError);
    });
  });

  group('deleting', () {
    forEachRepository('removes only the profile asked for', (repository) async {
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      final bob = await repository.create(
        displayName: 'Bob',
        createdAt: t0.plusDays(1),
      );

      final removed = await repository.delete(bob.id);

      expect(removed.id, bob.id);
      expect((await repository.list()).map((profile) => profile.id), [
        alice.id,
      ]);
      expect(await repository.find(bob.id), isNull);
    });

    forEachRepository('leaves the selection alone when somebody else goes', (
      repository,
    ) async {
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      final bob = await repository.create(
        displayName: 'Bob',
        createdAt: t0.plusDays(1),
      );

      await repository.delete(bob.id);

      expect((await repository.selected())?.id, alice.id);
    });

    forEachRepository('hands the selection on when the active profile goes', (
      repository,
    ) async {
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      final bob = await repository.create(
        displayName: 'Bob',
        createdAt: t0.plusDays(1),
      );

      await repository.delete(alice.id);

      expect(
        (await repository.selected())?.id,
        bob.id,
        reason: 'the app has to be running as somebody',
      );
    });

    forEachRepository('hands it to the oldest of those left', (
      repository,
    ) async {
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      final bob = await repository.create(
        displayName: 'Bob',
        createdAt: t0.plusDays(1),
      );
      await repository.create(displayName: 'Cass', createdAt: t0.plusDays(2));
      await repository.select(alice.id);

      await repository.delete(alice.id);

      expect((await repository.selected())?.id, bob.id);
    });

    forEachRepository('invents nobody when the last profile goes', (
      repository,
    ) async {
      final only = await repository.selectedOrDefault();

      await repository.delete(only.id);

      expect(await repository.list(), isEmpty);
      expect(
        await repository.selected(),
        isNull,
        reason: 'an empty install is a fact, not a slot to fill',
      );

      // Somebody has to be asked for. A caller that wants one says so.
      final fresh = await repository.selectedOrDefault();
      expect(fresh.id, isNot(only.id));
      expect((await repository.selected())?.id, fresh.id);
    });

    forEachRepository('refuses a profile that does not exist', (
      repository,
    ) async {
      expect(() => repository.delete('nobody'), throwsArgumentError);
    });
  });

  group('the default profile', () {
    forEachRepository('is created on a first launch, without asking', (
      repository,
    ) async {
      expect(await repository.list(), isEmpty);

      final profile = await repository.selectedOrDefault();

      expect(profile.displayName, defaultProfileName);
      expect((await repository.selected())?.id, profile.id);
      expect(await repository.list(), hasLength(1));
    });

    forEachRepository('is only created once', (repository) async {
      final first = await repository.selectedOrDefault();
      final second = await repository.selectedOrDefault();

      expect(second.id, first.id);
      expect(await repository.list(), hasLength(1));
    });

    forEachRepository('never displaces a profile that already exists', (
      repository,
    ) async {
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );

      final active = await repository.selectedOrDefault();

      expect(active.id, alice.id);
      expect(await repository.list(), hasLength(1));
    });

    forEachRepository('takes a caller-supplied name', (repository) async {
      final profile = await repository.selectedOrDefault(displayName: 'Yo');

      expect(profile.displayName, 'Yo');
    });

    test('selects the oldest rather than inventing another person', () async {
      // Profiles exist but none is selected. That should not arise, but
      // creating somebody new to resolve it would be the worse repair.
      final repository = FileProfileRepository(root, now: () => t0);
      final alice = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      await repository.create(displayName: 'Bob', createdAt: t0.plusDays(1));

      final json =
          jsonDecode(repository.indexFile.readAsStringSync())
              as Map<String, Object?>;
      json['selected_profile_id'] = null;
      repository.indexFile.writeAsStringSync(jsonEncode(json));

      final active = await repository.selectedOrDefault();

      expect(active.id, alice.id);
      expect(await repository.list(), hasLength(2));
    });
  });

  group('the index file', () {
    test('survives a restart', () async {
      final first = FileProfileRepository(root, now: () => t0);
      final alice = await first.create(displayName: 'Alice', createdAt: t0);
      final bob = await first.create(
        displayName: 'Bob',
        createdAt: t0.plusDays(1),
      );
      await first.select(bob.id);

      final second = FileProfileRepository(root, now: () => t0);

      expect((await second.list()).map((profile) => profile.id), [
        alice.id,
        bob.id,
      ]);
      expect((await second.selected())?.id, bob.id);
    });

    test('is written whole, never half', () async {
      final repository = FileProfileRepository(root, now: () => t0);
      await repository.create(displayName: 'Alice', createdAt: t0);

      expect(repository.indexFile.existsSync(), isTrue);
      expect(File('${repository.indexFile.path}.tmp').existsSync(), isFalse);
      expect(
        jsonDecode(repository.indexFile.readAsStringSync()),
        isA<Map<String, Object?>>(),
      );
    });

    test('an install nobody has used is empty, not broken', () async {
      final repository = FileProfileRepository(root, now: () => t0);

      expect(await repository.list(), isEmpty);
      expect(await repository.selected(), isNull);
      expect(await repository.find('anyone'), isNull);
    });

    test('corrupt metadata fails loudly', () async {
      final repository = FileProfileRepository(root, now: () => t0);
      await repository.create(displayName: 'Alice', createdAt: t0);

      repository.indexFile.writeAsStringSync('{not json');

      await expectLater(
        repository.list(),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('an unreadable schema version fails rather than guessing', () async {
      final repository = FileProfileRepository(root, now: () => t0);
      await repository.create(displayName: 'Alice', createdAt: t0);

      final json =
          jsonDecode(repository.indexFile.readAsStringSync())
              as Map<String, Object?>;
      json['schema_version'] = profileIndexSchemaVersion + 1;
      repository.indexFile.writeAsStringSync(jsonEncode(json));

      await expectLater(
        repository.list(),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test(
      'a selection pointing at nobody fails rather than being ignored',
      () async {
        final repository = FileProfileRepository(root, now: () => t0);
        await repository.create(displayName: 'Alice', createdAt: t0);

        final json =
            jsonDecode(repository.indexFile.readAsStringSync())
                as Map<String, Object?>;
        json['selected_profile_id'] = 'nobody';
        repository.indexFile.writeAsStringSync(jsonEncode(json));

        await expectLater(
          repository.selected(),
          throwsA(isA<JournalFormatException>()),
        );
      },
    );

    test('an orphaned practice directory is not a profile', () async {
      // The index is the authority on who exists. Rebuilding people from
      // directory names would attach somebody to a history that is not theirs.
      final repository = FileProfileRepository(root, now: () => t0);
      Directory(
        '${root.path}/3f2a6c18-0000-4000-8000-00000000dead',
      ).createSync(recursive: true);

      expect(await repository.list(), isEmpty);
      expect(await repository.selected(), isNull);

      final created = await repository.create(
        displayName: 'Alice',
        createdAt: t0,
      );
      expect((await repository.list()).single.id, created.id);
    });
  });

  group('with practice storage', () {
    test('a renamed profile keeps its history', () async {
      // The whole point of an opaque id: history follows identity, not name.
      final profiles = FileProfileRepository(root, now: () => t0);
      final store = FilePracticeStore(root);
      final created = await profiles.create(
        displayName: 'Alice',
        createdAt: t0,
      );

      final session = await openSession(store, profile: created);
      await practise(session, attempts: 3);

      final renamed = await profiles.rename(created.id, 'Alice B.');
      final reopened = await openSession(
        store,
        profile: renamed,
        sessionId: 'session-2',
      );

      expect(renamed.id, created.id);
      expect(reopened.journal.length, 3);
    });

    test('each profile practices into its own directory', () async {
      final profiles = FileProfileRepository(root, now: () => t0);
      final store = FilePracticeStore(root);
      final alice = await profiles.create(displayName: 'Alice', createdAt: t0);
      final bob = await profiles.create(displayName: 'Bob', createdAt: t0);

      await practise(await openSession(store, profile: alice), attempts: 3);
      await practise(
        await openSession(store, profile: bob, ids: countingIds('bob')),
        attempts: 1,
      );

      expect((await store.loadJournal(alice.id)).length, 3);
      expect((await store.loadJournal(bob.id)).length, 1);
      expect(Directory('${root.path}/${alice.id}').existsSync(), isTrue);
      expect(await profiles.list(), hasLength(2));
    });
  });
}
