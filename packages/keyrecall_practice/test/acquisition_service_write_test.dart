import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  /// Acquisition history that earned a probe of [parent] before this sitting.
  AcquisitionAttemptRecord earnedFor(Exercise parent) =>
      AcquisitionAttemptRecord(
        journalSequence: 0,
        identity: AttemptIdentity(
          profileId: alice.id,
          attemptId: 'acquisition-1',
          sessionId: 'sitting-0',
          indexInSession: 0,
          occurredAt: t0,
        ),
        task: AcquisitionTask.unmeteredTraversal(parent),
        started: true,
        completion: AcquisitionCompletion.completedCleanly,
        repairs: 0,
        repeats: 0,
        intrusions: 0,
        earnedProbe: true,
        gaps: const [],
      );

  test('presenting the parent discharges the obligation durably', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final at = t0.plusDays(0.5);

    // What this sitting presents first, so the history below is about the
    // exercise the learner will actually be shown.
    final first = await openSession(store);
    final presented = await first.decideOutcome(at: at) as PresentedAttempt;
    final parent = presented.exercise;
    await first.abandonPending();

    await store.appendAcquisitionEntry(earnedFor(parent));
    expect(
      (await store.loadAcquisitionJournal(alice.id)).replay().probeOwed(parent),
      isTrue,
    );

    // A fresh sitting over the same store decides the same way, and presenting
    // that exercise is the question acquisition earned being asked.
    final reopened = await openSession(store, sessionId: 'session-2');
    expect(reopened.acquisitionProgress.probeOwed(parent), isTrue);
    final again = await reopened.decideOutcome(at: at) as PresentedAttempt;
    expect(again.exercise, parent);

    final log = await store.loadAcquisitionJournal(alice.id);
    expect(log.replay().probeOwed(parent), isFalse);
    expect(log.replay().recordFor(parent)!.probesServed, 1);
    expect(log.records.last, isA<AcquisitionProbeServedRecord>());
    expect(log.records.last.identity.attemptId, again.decision.attemptId);
  });

  test('survives a restart with the obligation already discharged', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final at = t0.plusDays(0.5);
    final first = await openSession(store);
    final parent =
        (await first.decideOutcome(at: at) as PresentedAttempt).exercise;
    await first.abandonPending();
    await store.appendAcquisitionEntry(earnedFor(parent));
    final second = await openSession(store, sessionId: 'session-2');
    await second.decideOutcome(at: at);
    await second.abandonPending();

    // A third sitting rebuilds progress from the log and finds nothing owed,
    // so the same question is not asked twice.
    final later = await openSession(store, sessionId: 'session-3');
    expect(later.acquisitionProgress.probeOwed(parent), isFalse);
    expect(later.acquisitionProgress.earnsParentProbe(parent), isTrue);
  });

  test('writes nothing for a profile with no acquisition history', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);

    await session.decideOutcome(at: t0.plusDays(0.5));

    expect((await store.loadAcquisitionJournal(alice.id)).records, isEmpty);
  });
}
