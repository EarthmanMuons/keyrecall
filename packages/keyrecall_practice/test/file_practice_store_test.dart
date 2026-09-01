import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_practice_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File journalFile() => File('${root.path}/${alice.id}/journal.jsonl');
  File pendingFile() => File('${root.path}/${alice.id}/pending.json');
  File checkpointFile() => File('${root.path}/${alice.id}/checkpoint.json');
  File eraseMarker() => File('${root.path}/${alice.id}/practice-erasing');

  test('a profile id cannot escape the storage root', () async {
    final store = FilePracticeStore(root);
    final escapedName = 'keyrecall-escape-${root.path.hashCode.abs()}';
    final escaped = Directory('${root.parent.path}/$escapedName');

    expect(escaped.existsSync(), isFalse);
    await expectLater(
      store.loadJournal('../$escapedName'),
      throwsArgumentError,
    );
    expect(escaped.existsSync(), isFalse);
  });

  group('durability', () {
    test('a committed attempt survives the process', () async {
      final session = await openSession(FilePracticeStore(root));
      final committed = await practise(session, attempts: 4);
      final reached = learnerStateHash(session.state);

      // Nothing carried over in memory: a fresh store, reading the files.
      final reopened = await openSession(
        FilePracticeStore(root),
        sessionId: 'session-2',
      );

      expect(reopened.journal.length, 4);
      expect(learnerStateHash(reopened.state), reached);
      expect(
        reopened.journal.records.map((r) => r.identity.attemptId),
        committed.map((r) => r.identity.attemptId),
      );
    });

    test('the journal is one readable line per record', () async {
      final session = await openSession(FilePracticeStore(root));
      await practise(session, attempts: 3);

      final lines = journalFile()
          .readAsStringSync()
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

      expect(lines, hasLength(4), reason: 'a header plus three attempts');
      expect(lines.first, contains('"record_type":"journal_header"'));
      expect(journalFile().readAsStringSync(), endsWith('\n'));
    });

    test('a pending decision survives, and clearing removes it', () async {
      final session = await openSession(FilePracticeStore(root));
      final presented = await session.decide(at: t0.plusDays(0.5));

      expect(pendingFile().existsSync(), isTrue);
      final reloaded = await FilePracticeStore(
        root,
      ).loadPendingDecision(alice.id);
      expect(reloaded!.attemptId, presented!.decision.attemptId);
      expect(reloaded.exercise, presented.exercise);

      await session.closeWithOutcome(outcomeFor(presented.exercise));
      expect(pendingFile().existsSync(), isFalse);
    });

    test('a checkpoint round-trips through the file', () async {
      final store = FilePracticeStore(root);
      final session = await openSession(store);
      await practise(session, attempts: 4);
      final saved = await session.saveCheckpoint();

      final reloaded = await store.loadCheckpoint(alice.id);

      expect(reloaded, isNotNull);
      expect(reloaded!.contentHash, saved!.contentHash);
      expect(reloaded.throughJournalSequence, saved.throughJournalSequence);
      expect(learnerStateHash(reloaded.state), learnerStateHash(session.state));
    });

    // Valid JSON that is not an object is the other half of the same failure:
    // `as Map` would raise a TypeError, which escapes the format contract the
    // session catches to replay from the journal.
    for (final shape in ['[]', '42', 'null']) {
      test(
        'a checkpoint holding $shape falls back to journal replay',
        () async {
          final store = FilePracticeStore(root);
          final session = await openSession(store);
          await practise(session, attempts: 4);
          final reached = learnerStateHash(session.state);
          await session.saveCheckpoint();
          checkpointFile().writeAsStringSync(shape);

          await expectLater(
            store.loadCheckpoint(alice.id),
            throwsA(isA<JournalFormatException>()),
          );
          final reopened = await openSession(store, sessionId: 'session-2');

          expect(reopened.journal.length, 4);
          expect(learnerStateHash(reopened.state), reached);
        },
      );
    }

    test('a checkpoint covering history the journal lost is a miss', () async {
      // What an erase between a commit and a checkpoint save leaves: the
      // cache stands in for attempts that no longer exist, and starting from
      // it would restore erased history as learner state.
      final store = FilePracticeStore(root);
      final session = await openSession(store);
      await practise(session, attempts: 4);
      final saved = await session.saveCheckpoint();
      await store.erase(alice.id);
      await store.saveCheckpoint(saved!);

      final reopened = await openSession(store, sessionId: 'session-2');

      expect(reopened.journal.isEmpty, isTrue);
      expect(
        learnerStateHash(reopened.state),
        learnerStateHash(learner.placementState(alice.placement, at: t0)),
        reason: 'an erased profile starts from placement, not from the cache',
      );
    });

    test('a malformed checkpoint falls back to journal replay', () async {
      final store = FilePracticeStore(root);
      final session = await openSession(store);
      await practise(session, attempts: 4);
      final reached = learnerStateHash(session.state);
      await session.saveCheckpoint();
      checkpointFile().writeAsStringSync('{"incomplete"');

      final reopened = await openSession(store, sessionId: 'session-2');

      expect(reopened.journal.length, 4);
      expect(learnerStateHash(reopened.state), reached);
    });
  });

  group('a torn write', () {
    test('drops an incomplete final line, which was never committed', () async {
      final session = await openSession(FilePracticeStore(root));
      await practise(session, attempts: 3);

      // A crash mid-append: the last line never got its newline, so that
      // attempt was never committed.
      final contents = journalFile().readAsStringSync();
      journalFile().writeAsStringSync(
        '$contents{"record_type":"attempt","schema_version":1,"partial',
      );

      final reopened = await openSession(
        FilePracticeStore(root),
        sessionId: 'session-2',
      );

      expect(
        reopened.journal.length,
        3,
        reason: 'the torn tail is not history',
      );
    });

    test('a corrupt line in the middle fails loudly instead', () async {
      // Only the tail can be a torn write. Damage anywhere else is real
      // corruption of history, and quietly skipping it would lose evidence.
      final session = await openSession(FilePracticeStore(root));
      await practise(session, attempts: 3);

      final lines = journalFile().readAsStringSync().split('\n');
      lines[2] = '{"record_type":"attempt","schema_version":1,"broken":true}';
      journalFile().writeAsStringSync(lines.join('\n'));

      await expectLater(
        openSession(FilePracticeStore(root), sessionId: 'session-2'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('the next attempt appends cleanly after a torn tail', () async {
      final session = await openSession(FilePracticeStore(root));
      await practise(session, attempts: 2);
      final contents = journalFile().readAsStringSync();
      journalFile().writeAsStringSync('$contents{"partial');

      final reopened = await openSession(
        FilePracticeStore(root),
        sessionId: 'session-2',
        ids: countingIds('resumed'),
      );
      await practise(reopened, attempts: 1, startDay: 20);

      final again = await openSession(
        FilePracticeStore(root),
        sessionId: 'session-3',
      );
      expect(again.journal.length, 3);
      expect(again.journal.records.map((r) => r.journalSequence), [0, 1, 2]);
    });
  });

  group('separation', () {
    test('each profile gets its own directory', () async {
      final store = FilePracticeStore(root);
      final bob = Profile(
        id: '3f2a6c18-0000-4000-8000-00000000b0b0',
        displayName: 'Bob',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );

      final aliceSession = await openSession(store);
      await practise(aliceSession, attempts: 3);
      final bobSession = await openSession(
        store,
        profile: bob,
        ids: countingIds('bob'),
      );
      await practise(bobSession, attempts: 2);

      expect(Directory('${root.path}/${alice.id}').existsSync(), isTrue);
      expect(Directory('${root.path}/${bob.id}').existsSync(), isTrue);
      expect((await store.loadJournal(alice.id)).length, 3);
      expect((await store.loadJournal(bob.id)).length, 2);
    });

    test('a first run on an empty directory is not an error', () async {
      final store = FilePracticeStore(root);

      final journal = await store.loadJournal(alice.id);

      expect(journal.isEmpty, isTrue);
      expect(journal.header.profileId, alice.id);
      expect(await store.loadPendingDecision(alice.id), isNull);
      expect(await store.loadCheckpoint(alice.id), isNull);
    });
  });

  // The marker protects writers as well as readers: a new generation must not
  // land beside the one that was being deleted.
  test('an interrupted erase finishes before storage is written', () async {
    final store = FilePracticeStore(root);
    final session = await openSession(store);
    await practise(session, attempts: 3);
    await session.saveCheckpoint();
    await session.decide(at: t0.plusDays(10));
    final decision = await store.loadPendingDecision(alice.id);
    eraseMarker().writeAsStringSync('');

    await store.savePendingDecision(decision!);

    expect(journalFile().existsSync(), isFalse);
    expect(checkpointFile().existsSync(), isFalse);
    expect(eraseMarker().existsSync(), isFalse);
    expect(pendingFile().existsSync(), isTrue);
    expect(
      (await store.loadPendingDecision(alice.id))?.attemptId,
      decision.attemptId,
    );
  });

  test('an interrupted erase finishes before storage is read', () async {
    final store = FilePracticeStore(root);
    final session = await openSession(store);
    await practise(session, attempts: 3);
    await session.saveCheckpoint();
    await session.decide(at: t0.plusDays(10));
    final profile = File('${root.path}/${alice.id}/profile.json')
      ..writeAsStringSync('{}');
    eraseMarker().writeAsStringSync('');

    final journal = await store.loadJournal(alice.id);

    expect(journal.isEmpty, isTrue);
    expect(profile.existsSync(), isTrue);
    expect(journalFile().existsSync(), isFalse);
    expect(pendingFile().existsSync(), isFalse);
    expect(checkpointFile().existsSync(), isFalse);
    expect(eraseMarker().existsSync(), isFalse);
  });
}
