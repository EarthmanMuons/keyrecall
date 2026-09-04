import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('a worker decides what deciding in process would have', () async {
    final onWorker = await openSession(
      InMemoryPracticeStore(createdAt: t0),
      scheduler: IsolateScheduler(),
    );
    final inProcess = await openSession(
      InMemoryPracticeStore(createdAt: t0),
      sessionId: 'session-2',
    );

    for (var slot = 0; slot < 4; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decided = await onWorker.decideOutcome(at: at);
      final directly = await inProcess.decideOutcome(at: at);

      expect(decided, isA<PresentedAttempt>());
      expect(
        (decided as PresentedAttempt).exercise,
        (directly as PresentedAttempt).exercise,
      );
      expect(
        onWorker.session.attemptsThisSession,
        inProcess.session.attemptsThisSession,
      );
      expect(
        onWorker.session.unservedGuidanceProbeSelections,
        inProcess.session.unservedGuidanceProbeSelections,
      );

      await onWorker.closeWithOutcome(outcomeOf(), observedWallTime: at);
      await inProcess.closeWithOutcome(outcomeOf(), observedWallTime: at);
    }

    await (onWorker.scheduler as IsolateScheduler).dispose();
  });

  test('a worker lost mid-decision leaves the session untouched', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final scheduler = IsolateScheduler();
    final session = await openSession(store, scheduler: scheduler);
    // Binding is what the first decision does, and it is the only await
    // before the request goes out. Past it, the worker can be lost with a
    // decision genuinely in flight.
    await session.decideOutcome(at: t0.plusDays(0.5));
    await session.closeWithOutcome(outcomeOf());

    // Listened to before the worker goes away, or the failure lands as an
    // unhandled error rather than as this test's expectation.
    final deciding = expectLater(
      session.decideOutcome(at: t0.plusDays(1)),
      throwsA(isA<SchedulerWorkerLost>()),
    );
    await scheduler.dispose();
    await deciding;
    expect(session.hasOutstandingAttempt, isFalse);
    expect(await store.loadPendingDecision(alice.id), isNull);
    expect(session.session.attemptsThisSession, 1);
  });

  test('a session that lost its worker decides again on a new one', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final scheduler = IsolateScheduler();
    final session = await openSession(store, scheduler: scheduler);
    await session.decideOutcome(at: t0.plusDays(0.5));
    await session.closeWithOutcome(outcomeOf());

    final deciding = expectLater(
      session.decideOutcome(at: t0.plusDays(1)),
      throwsA(isA<SchedulerWorkerLost>()),
    );
    await scheduler.dispose();
    await deciding;

    session.updateScope(goal: PracticeGoal.generalFluency);
    final decision = await session.decideOutcome(at: t0.plusDays(1.5));

    expect(decision, isA<PresentedAttempt>());
    expect(await store.loadPendingDecision(alice.id), isNotNull);
    await scheduler.dispose();
  });
}
