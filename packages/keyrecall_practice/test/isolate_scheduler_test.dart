import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('a worker decides what deciding in process would have', () async {
    final workerStore = InMemoryPracticeStore(createdAt: t0);
    final directStore = InMemoryPracticeStore(createdAt: t0);
    final onWorker = await openSession(
      workerStore,
      scheduler: IsolateScheduler(),
    );
    final inProcess = await openSession(directStore, sessionId: 'session-2');

    for (var slot = 0; slot < 4; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decided = await onWorker.decideOutcome(at: at);
      final directly = await inProcess.decideOutcome(at: at);

      expect(decided, isA<PresentedAttempt>());
      final workerDiagnostics = await workerStore.loadSelectionDiagnostics(
        alice.id,
      );
      final directDiagnostics = await directStore.loadSelectionDiagnostics(
        alice.id,
      );
      expect(workerDiagnostics.values.last, directDiagnostics.values.last);
      expect(
        workerDiagnostics.values.last,
        contains('winner_vs_best_selectable_scale='),
      );
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

  /// A host bound to the fixture catalog, and the requirements it may choose
  /// between.
  Future<(IsolateScheduler, List<String>)> boundHost(
    LearnerModel learner,
  ) async {
    final resolved =
        PracticeScopeResolver().resolve(
              goal: PracticeGoal.generalFluency,
              focus: PracticeFocus.unrestricted,
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;
    final scheduler = IsolateScheduler();
    await scheduler.bind(
      scope: resolved.scope,
      entry: resolved.entryPolicy,
      learner: learner,
      config: v1SchedulerConfig,
    );
    return (
      scheduler,
      [
        for (final requirement in resolved.scope.requirements)
          requirement.requirement.id,
      ],
    );
  }

  test(
    'a worker that dies deciding fails the request it was answering',
    () async {
      // The class promises that a worker lost mid-decision fails that request
      // and nothing else. Disposal always did; an isolate that actually died
      // left the caller waiting for an answer nobody was going to send.
      final (scheduler, due) = await boundHost(const _ExplodingLearner());

      await expectLater(
        scheduler.decide(
          epoch: 0,
          state: const LearnerModel().placementState(
            PlacementTier.someExperience,
            at: t0,
          ),
          session: SessionState(),
          dueRequirementIds: due,
          at: t0.plusDays(0.5),
        ),
        throwsA(isA<SchedulerWorkerLost>()),
      );

      // And the dead worker is reported as gone rather than as a scope nobody
      // bound: one is a fault to recover from, the other a caller that forgot.
      await expectLater(
        scheduler.decide(
          epoch: 1,
          state: const LearnerModel().placementState(
            PlacementTier.someExperience,
            at: t0,
          ),
          session: SessionState(),
          dueRequirementIds: due,
          at: t0.plusDays(0.5),
        ),
        throwsA(isA<SchedulerWorkerLost>()),
      );
      await scheduler.dispose();
    },
  );

  test('a host disposed while binding does not install its worker', () async {
    // The binding is named before the first await. Taken afterwards it would
    // be whatever the lifecycle did during it, and a disposed host would come
    // back holding disposal's own number and bind itself anyway.
    final resolved =
        PracticeScopeResolver().resolve(
              goal: PracticeGoal.generalFluency,
              focus: PracticeFocus.unrestricted,
              catalog: fixtureMaterials,
              instrument: InstrumentProfile(),
            )
            as ValidPracticeScope;
    final scheduler = IsolateScheduler();

    final binding = scheduler.bind(
      scope: resolved.scope,
      entry: resolved.entryPolicy,
      learner: const LearnerModel(),
      config: v1SchedulerConfig,
    );
    await scheduler.dispose();
    await binding;

    await expectLater(
      scheduler.decide(
        epoch: 0,
        state: const LearnerModel().placementState(
          PlacementTier.someExperience,
          at: t0,
        ),
        session: SessionState(),
        dueRequirementIds: const [],
        at: t0.plusDays(0.5),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('a second decision in flight is refused, not misanswered', () async {
    // One verdict per request, matched by id. Before that, a worker answered
    // whatever it was last asked, so the second caller took the first one's
    // verdict and the first waited forever.
    final (scheduler, due) = await boundHost(const LearnerModel());
    addTearDown(scheduler.dispose);

    Future<SchedulerVerdict> ask(int epoch) => scheduler.decide(
      epoch: epoch,
      state: const LearnerModel().placementState(
        PlacementTier.someExperience,
        at: t0,
      ),
      session: SessionState(),
      dueRequirementIds: due,
      at: t0.plusDays(0.5),
    );

    final first = ask(7);
    // Listened to as it is made, or the refusal lands as an unhandled error
    // rather than as this test's expectation.
    final refused = expectLater(ask(8), throwsA(isA<StateError>()));

    expect((await first).epoch, 7);
    await refused;
  });
}

/// Dies where the pipeline asks it anything, which is inside the worker.
class _ExplodingLearner extends LearnerModel {
  const _ExplodingLearner();

  @override
  double executionProbability(LearnerState state, Exercise exercise) =>
      throw StateError('the worker died deciding this slot');
}
