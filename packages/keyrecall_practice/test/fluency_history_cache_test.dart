import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

final _partition = DayPartition.utc;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_fluency_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File fluencyFile() => File('${root.path}/${alice.id}/fluency.json');

  Future<FluencyHistory> rebuilt(PracticeStore store) async =>
      FluencyHistory.rebuild(
        await store.loadJournal(alice.id),
        partition: _partition,
      );

  test('opening saves, and a later opening extends what was saved', () async {
    final store = FilePracticeStore(root);
    final session = await openSession(store);
    await practise(session, attempts: 6);

    final first = await openFluencyHistory(
      store,
      alice.id,
      partition: _partition,
    );
    expect(first.coveredRecords, 6);
    expect(
      await FilePracticeStore(
        root,
      ).loadFluencyHistory(alice.id, partition: _partition),
      first,
    );

    await practise(session, attempts: 5, startDay: 8);
    final extended = await openFluencyHistory(
      FilePracticeStore(root),
      alice.id,
      partition: _partition,
    );
    expect(extended.coveredRecords, 11);
    expect(extended, await rebuilt(store));
    expect(
      await store.loadFluencyHistory(alice.id, partition: _partition),
      extended,
    );
  });

  test('a profile without attempts saves nothing', () async {
    final store = FilePracticeStore(root);

    final history = await openFluencyHistory(
      store,
      alice.id,
      partition: _partition,
    );
    expect(history.coveredRecords, 0);
    expect(fluencyFile().existsSync(), isFalse);
  });

  group('an unusable saved projection is rebuilt and replaced', () {
    Future<void> expectRebuilt(PracticeStore store) async {
      final history = await openFluencyHistory(
        store,
        alice.id,
        partition: _partition,
      );
      expect(history, await rebuilt(store));
      expect(
        await store.loadFluencyHistory(alice.id, partition: _partition),
        history,
      );
    }

    test('when it cannot be read', () async {
      final store = FilePracticeStore(root);
      await practise(await openSession(store), attempts: 4);
      await fluencyFile().parent.create(recursive: true);
      fluencyFile().writeAsStringSync('{"schema_version": 1, "days": [');

      await expectRebuilt(store);
    });

    test('when it was built under another day partition', () async {
      final store = FilePracticeStore(root);
      await practise(await openSession(store), attempts: 4);
      final elsewhere = DayPartition('ELSEWHERE', _partition.dayOf);
      await openFluencyHistory(store, alice.id, partition: elsewhere);

      await expectRebuilt(store);
    });

    test('when it covers another history of the same length', () async {
      final store = FilePracticeStore(root);
      await practise(await openSession(store), attempts: 4);
      final stale = await openFluencyHistory(
        store,
        alice.id,
        partition: _partition,
      );
      await store.erase(alice.id);
      await practise(
        await openSession(store, ids: countingIds('replacement')),
        attempts: 4,
        succeed: false,
      );
      await store.saveFluencyHistory(stale);

      expect(stale.coversPrefixOf(await store.loadJournal(alice.id)), isFalse);
      await expectRebuilt(store);
    });

    test('when it covers more than the journal holds', () async {
      final store = FilePracticeStore(root);
      await practise(await openSession(store), attempts: 4);
      final longer = await openFluencyHistory(
        store,
        alice.id,
        partition: _partition,
      );
      await store.erase(alice.id);
      await practise(await openSession(store), attempts: 2);
      await store.saveFluencyHistory(longer);

      await expectRebuilt(store);
    });
  });

  group('a save that fails', () {
    Future<PracticeStore> retired() async {
      final store = FilePracticeStore(root);
      await practise(await openSession(store), attempts: 3);
      final held = await store.lifetimeOf(alice.id);
      await store.retireLifetime(alice.id);
      return store.boundTo(held);
    }

    test('fails opening', () async {
      final store = await retired();

      await expectLater(
        openFluencyHistory(store, alice.id, partition: _partition),
        throwsA(isA<RetiredProfileLifetime>()),
      );
    });

    test('is reported rather than failing a read', () async {
      final store = await retired();
      final failures = <Object>[];

      final history = await readFluencyHistory(
        store,
        alice.id,
        partition: _partition,
        onSaveFailure: (error, _) => failures.add(error),
      );

      expect(history, await rebuilt(store));
      expect(failures.single, isA<RetiredProfileLifetime>());
      expect(fluencyFile().existsSync(), isFalse);
    });
  });

  test('erasing a profile takes its fluency history along', () async {
    final store = FilePracticeStore(root);
    await practise(await openSession(store), attempts: 3);
    await openFluencyHistory(store, alice.id, partition: _partition);
    expect(fluencyFile().existsSync(), isTrue);

    await store.erase(alice.id);

    expect(fluencyFile().existsSync(), isFalse);
    expect(
      await store.loadFluencyHistory(alice.id, partition: _partition),
      isNull,
    );
  });

  test('a retired incarnation cannot save one', () async {
    final store = FilePracticeStore(root);
    await practise(await openSession(store), attempts: 3);
    final held = await store.lifetimeOf(alice.id);
    final history = FluencyHistory.rebuild(
      await store.loadJournal(alice.id),
      partition: _partition,
    );
    await store.retireLifetime(alice.id);

    await expectLater(
      store.boundTo(held).saveFluencyHistory(history),
      throwsA(isA<RetiredProfileLifetime>()),
    );
    expect(fluencyFile().existsSync(), isFalse);
  });

  test('a file under one profile naming another is refused', () async {
    final store = FilePracticeStore(root);
    await practise(await openSession(store), attempts: 3);
    final history = await openFluencyHistory(
      store,
      alice.id,
      partition: _partition,
    );
    final other = Directory('${root.path}/someone-else')
      ..createSync(recursive: true);
    File(
      '${other.path}/fluency.json',
    ).writeAsStringSync(canonicalJson(history.toJson()));

    await expectLater(
      store.loadFluencyHistory('someone-else', partition: _partition),
      throwsA(isA<JournalFormatException>()),
    );
  });

  test('the projection has no effect on what practice does', () async {
    final store = FilePracticeStore(root);
    await practise(await openSession(store), attempts: 8);
    final at = t0.plusDays(20);

    Future<(String, String?)> reopen() async {
      final session = await openSession(
        FilePracticeStore(root),
        sessionId: 'reopened',
        ids: countingIds('reopened'),
      );
      final state = learnerStateHash(session.state);
      final presented = await session.decide(at: at);
      await session.abandonPending();
      return (state, presented?.exercise.toString());
    }

    final without = await reopen();
    await openFluencyHistory(store, alice.id, partition: _partition);
    final withProjection = await reopen();
    fluencyFile().writeAsStringSync('not json');
    final withCorruptProjection = await reopen();

    expect(withProjection, without);
    expect(withCorruptProjection, without);
  });
}
