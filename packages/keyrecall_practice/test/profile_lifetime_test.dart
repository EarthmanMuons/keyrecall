import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_lifetime_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Runs the same expectations against both stores, so the barrier is tested
  /// as a contract rather than as one implementation's file layout.
  void forEachStore(
    String description,
    Future<void> Function(PracticeStore store) body,
  ) {
    test('$description (in memory)', () => body(InMemoryPracticeStore()));
    test('$description (file backed)', () => body(FilePracticeStore(root)));
  }

  forEachStore('the incarnation is stable until something retires it', (
    store,
  ) async {
    final first = await store.lifetimeOf(alice.id);
    expect(await store.lifetimeOf(alice.id), first);

    final replacement = await store.retireLifetime(alice.id);
    expect(replacement, isNot(first));
    expect(await store.lifetimeOf(alice.id), replacement);
  });

  forEachStore('a bound view writes while its incarnation stands', (
    store,
  ) async {
    final bound = store.boundTo(await store.lifetimeOf(alice.id));
    await bound.savePracticePlan(alice.id, PracticePlan.normal);

    expect(await store.loadPracticePlan(alice.id), PracticePlan.normal);
  });

  forEachStore('erasing retires the incarnation that was writing', (
    store,
  ) async {
    final held = await store.lifetimeOf(alice.id);
    final bound = store.boundTo(held);
    await bound.savePracticePlan(alice.id, PracticePlan.normal);

    await store.erase(alice.id);

    await expectLater(
      bound.savePracticePlan(alice.id, PracticePlan.normal),
      throwsA(isA<RetiredProfileLifetime>()),
    );
    expect(await store.loadPracticePlan(alice.id), isNull);
  });

  forEachStore('a bound view refuses another profile outright', (store) async {
    final bound = store.boundTo(await store.lifetimeOf(alice.id));

    await expectLater(
      bound.savePracticePlan('somebody-else', PracticePlan.normal),
      throwsArgumentError,
    );
  });

  forEachStore('forgetting leaves no incarnation to reuse', (store) async {
    final held = await store.lifetimeOf(alice.id);
    await store.forget(alice.id);

    expect(await store.lifetimeOf(alice.id), isNot(held));
  });

  test(
    'an attempt accepted before an erase does not restore history',
    () async {
      final store = FilePracticeStore(root);
      final held = await store.lifetimeOf(alice.id);
      final session = await openSession(store.boundTo(held));
      final presented = await session.decide(at: t0.plusDays(0.5));

      // The learner has answered, and the profile is erased before the close
      // reaches storage. What was played may finish computing; what it may not
      // do is put the erased history back.
      await store.erase(alice.id);

      await expectLater(
        session.closeWithOutcome(outcomeFor(presented!.exercise)),
        throwsA(isA<RetiredProfileLifetime>()),
      );
      expect((await store.loadJournal(alice.id)).records, isEmpty);
      expect(
        File('${root.path}/${alice.id}/journal.jsonl').existsSync(),
        isFalse,
      );
    },
  );

  test('an incarnation survives the process that issued it', () async {
    final store = FilePracticeStore(root);
    final held = await store.lifetimeOf(alice.id);

    expect(await FilePracticeStore(root).lifetimeOf(alice.id), held);
  });

  test('a retirement survives the process that made it', () async {
    final store = FilePracticeStore(root);
    final held = await store.lifetimeOf(alice.id);
    await store.retireLifetime(alice.id);

    final reopened = FilePracticeStore(root);
    await expectLater(
      reopened.boundTo(held).savePracticePlan(alice.id, PracticePlan.normal),
      throwsA(isA<RetiredProfileLifetime>()),
    );
  });

  test('an unreadable incarnation fails rather than issuing another', () async {
    final store = FilePracticeStore(root);
    await store.lifetimeOf(alice.id);
    File('${root.path}/${alice.id}/lifetime.json').writeAsStringSync('{ nope');

    await expectLater(
      store.lifetimeOf(alice.id),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
