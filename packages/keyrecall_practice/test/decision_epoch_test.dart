import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  group('a verdict that arrives late', () {
    test('is discarded when the inputs it answers have moved', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      late PracticeSession session;
      final host = _InterceptingScheduler(
        InProcessScheduler(SchedulerPipeline(learner: learner)),
        whileDeciding: () =>
            session.updateScope(goal: PracticeGoal.generalFluency),
      );
      session = await openSession(store, scheduler: host);

      final decision = await session.decideOutcome(at: t0.plusDays(0.5));

      expect(decision, isA<PracticeSuperseded>());
      expect(session.pending, isNull);
      expect(session.hasOutstandingAttempt, isFalse);
      expect(await store.loadPendingDecision(alice.id), isNull);
      expect(session.session.attemptsThisSession, 0);
    });

    test('is applied exactly once while the inputs still hold', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);

      final decision = await session.decideOutcome(at: t0.plusDays(0.5));

      expect(decision, isA<PresentedAttempt>());
      expect(session.hasOutstandingAttempt, isTrue);
      expect(await store.loadPendingDecision(alice.id), isNotNull);
      expect(session.session.attemptsThisSession, 1);
    });
  });

  group('what advances the epoch', () {
    test('a committed attempt does', () async {
      final session = await openSession(InMemoryPracticeStore(createdAt: t0));
      final before = session.decisionEpoch;

      await session.decideOutcome(at: t0.plusDays(0.5));
      await session.closeWithOutcome(outcomeOf());

      expect(session.decisionEpoch, greaterThan(before));
    });

    test('an abandoned decision does', () async {
      final session = await openSession(InMemoryPracticeStore(createdAt: t0));
      await session.decideOutcome(at: t0.plusDays(0.5));
      final before = session.decisionEpoch;

      await session.abandonPending();

      expect(session.decisionEpoch, greaterThan(before));
    });

    test('a scope change does', () async {
      final session = await openSession(InMemoryPracticeStore(createdAt: t0));
      final before = session.decisionEpoch;

      session.updateScope(goal: PracticeGoal.generalFluency);

      expect(session.decisionEpoch, greaterThan(before));
    });
  });

  group('the sitting effect', () {
    test('leaves the sitting where deciding in process leaves it', () async {
      final direct = SessionState();
      final pipeline = SchedulerPipeline(learner: learner);
      final state = learner.placementState(
        PlacementTier.someExperience,
        at: t0,
      );
      final candidates = generateCandidates(
        InstrumentProfile(),
        fixtureMaterials,
      );

      pipeline.decide(
        state: state,
        session: direct,
        candidates: candidates,
        at: t0.plusDays(0.5),
      );

      final applied = SessionState();
      final slot = pipeline.evaluateSlot(
        state: learner.placementState(PlacementTier.someExperience, at: t0),
        session: applied,
        candidates: candidates,
        at: t0.plusDays(0.5),
      );
      SittingDecisionEffect(
        guidanceProbeAvailable: slot.guidanceProbeAvailable,
        guidanceProbeSelected: slot.guidanceProbeSelected,
      ).applyTo(applied);

      expect(applied.attemptsThisSession, direct.attemptsThisSession);
      expect(
        applied.unservedGuidanceProbeSelections,
        direct.unservedGuidanceProbeSelections,
      );
    });
  });
}

/// A host that lets a test change the session while a decision is in flight.
class _InterceptingScheduler implements SchedulerHost {
  final SchedulerHost inner;
  final void Function()? whileDeciding;

  _InterceptingScheduler(this.inner, {this.whileDeciding});

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) =>
      inner.bind(scope: scope, entry: entry, learner: learner, config: config);

  @override
  Future<void> dispose() => inner.dispose();

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
  }) async {
    final verdict = await inner.decide(
      epoch: epoch,
      state: state,
      session: session,
      dueRequirementIds: dueRequirementIds,
      at: at,
      acquisitionFloor: acquisitionFloor,
    );
    whileDeciding?.call();
    return verdict;
  }
}
