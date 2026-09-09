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

  /// The task a sitting that always offers one presents.
  Future<AcquisitionTask> offeredTask(
    PracticeSession session, {
    required DateTime at,
  }) async {
    final offered = await session.decideOutcome(at: at);
    return (offered as PresentedAcquisition).task;
  }

  /// A performance of [task], with one note per [gapMs].
  PerformanceTranscript playedThrough(
    AcquisitionTask task, {
    int notes = 1 << 30,
    int gapMs = 900,
    int? longGapBefore,
  }) {
    final moments = realizeAcquisition(task).moments;
    final hand = task.parent.conditions.hands == HandConfiguration.left
        ? Hand.left
        : Hand.right;
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (var index = 0; index < moments.length && index < notes; index++) {
      if (index > 0) at += index == longGapBefore ? 6000 : gapMs;
      transcript = transcript.appending(
        pitch: moments[index].noteFor(hand)!.pitch,
        timestampMs: at,
      );
    }
    return transcript;
  }

  test('a clean acquisition attempt earns the parent a probe', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final at = t0.plusDays(0.5);
    final session = await openSession(
      store,
      pipeline: const AlwaysOffersAcquisition(),
    );
    final task = await offeredTask(session, at: at);

    final record = await session.closeAcquisition(playedThrough(task), at: at);

    expect(record.completion, AcquisitionCompletion.completedCleanly);
    expect(record.earnedProbe, isTrue);
    expect(session.acquisitionProgress.probeOwed(task.parent), isTrue);
    expect(
      (await store.loadAcquisitionJournal(
        alice.id,
      )).replay().probeOwed(task.parent),
      isTrue,
    );
  });

  test(
    'an attempt the learner stopped partway is kept, not discarded',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final at = t0.plusDays(0.5);
      final session = await openSession(
        store,
        pipeline: const AlwaysOffersAcquisition(),
      );
      final task = await offeredTask(session, at: at);

      final record = await session.closeAcquisition(
        playedThrough(task, notes: 4),
        at: at,
      );

      // Where it ran out and what it cost to get there are the observations the
      // task was offered for. Throwing them away because the traversal is
      // incomplete would discard the reading of the learner it was offered for.
      expect(record.completion, AcquisitionCompletion.notCompleted);
      expect(record.started, isTrue);
      expect(record.firstAbsentPosition, 4);
      expect(record.earnedProbe, isFalse);
      expect(session.acquisitionProgress.recordFor(task.parent)!.attempts, 1);
      expect(session.acquisitionProgress.probeOwed(task.parent), isFalse);
    },
  );

  test('a long wait does not stop the attempt earning nothing else', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final at = t0.plusDays(0.5);
    final session = await openSession(
      store,
      pipeline: const AlwaysOffersAcquisition(),
    );
    final task = await offeredTask(session, at: at);

    final record = await session.closeAcquisition(
      playedThrough(task, longGapBefore: 4),
      at: at,
    );

    // Every note arrived and none of them was wrong, so the sequence came out.
    // The wait is why it earns no probe, and it is kept where it happened.
    expect(record.completion, AcquisitionCompletion.completedCleanly);
    expect(record.earnedProbe, isFalse);
    expect(record.gaps.where((gap) => gap.gapMs == 6000).single.toPosition, 4);
  });

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

    // Deciding is not presenting. Nothing is discharged until the exercise
    // actually reaches the learner.
    expect(reopened.acquisitionProgress.probeOwed(parent), isTrue);
    await reopened.acknowledgePresentation(again.decision.attemptId);

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
    final shown = await second.decideOutcome(at: at) as PresentedAttempt;
    await second.acknowledgePresentation(shown.decision.attemptId);
    await second.abandonPending();

    // A third sitting rebuilds progress from the log and finds nothing owed,
    // so the same question is not asked twice.
    final later = await openSession(store, sessionId: 'session-3');
    expect(later.acquisitionProgress.probeOwed(parent), isFalse);
    expect(later.acquisitionProgress.earnsParentProbe(parent), isTrue);
  });

  test('two offers of one task are two attempts at it', () async {
    // A screen keyed on the task alone would hand the second offer the first
    // one's finished state, and the learner would meet a screen with no way
    // to start.
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(
      store,
      pipeline: const AlwaysOffersAcquisition(),
    );
    final first =
        await session.decideOutcome(at: t0.plusDays(0.5))
            as PresentedAcquisition;
    await session.closeAcquisition(
      playedThrough(first.task, notes: 3),
      at: t0.plusDays(0.5),
    );
    final second =
        await session.decideOutcome(at: t0.plusDays(1)) as PresentedAcquisition;

    expect(second.task, first.task);
    expect(second.attemptId, isNot(first.attemptId));
  });

  test('acknowledging twice discharges once', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final at = t0.plusDays(0.5);
    final first = await openSession(store);
    final parent =
        (await first.decideOutcome(at: at) as PresentedAttempt).exercise;
    await first.abandonPending();
    await store.appendAcquisitionEntry(earnedFor(parent));

    final session = await openSession(store, sessionId: 'session-2');
    final shown = await session.decideOutcome(at: at) as PresentedAttempt;
    await session.acknowledgePresentation(shown.decision.attemptId);
    await session.acknowledgePresentation(shown.decision.attemptId);

    final log = await store.loadAcquisitionJournal(alice.id);
    expect(log.records.whereType<AcquisitionProbeServedRecord>(), hasLength(1));
  });

  test('writes nothing for a profile with no acquisition history', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);

    await session.decideOutcome(at: t0.plusDays(0.5));

    expect((await store.loadAcquisitionJournal(alice.id)).records, isEmpty);
  });
}
