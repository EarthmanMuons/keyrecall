import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

const LearnerModel _model = LearnerModel();

/// The state a session starts from, which is what replay has to be compared
/// against.
LearnerState placement() =>
    _model.placementState(PlacementTier.someExperience, at: alice.createdAt);

/// An attempt can end without anyone establishing how it went. That is a
/// complete lifecycle event and no evidence at all, and the difference has to
/// survive storage, reopening, and replay.
void main() {
  test('closing without a measurement moves no learner state', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    await session.decide(at: t0.plusDays(0.5));
    final before = learnerStateHash(session.state);

    final record = await session.closeUnmeasured(
      termination: AttemptTermination.inactivityTimeout,
    );

    expect(record.closure.termination, AttemptTermination.inactivityTimeout);
    expect(record.closure.measurement, isA<MeasurementUnavailable>());
    expect(
      learnerStateHash(session.state),
      before,
      reason: 'nothing was observed, so nothing about the learner may change',
    );
  });

  test('evidence and termination are recorded independently', () async {
    // A timeout that arrived with a performance behind it is measured like any
    // other. Reading the termination as a verdict on the evidence, or the
    // evidence as a claim about how the attempt ended, is exactly the
    // inference the two fields are kept apart to prevent.
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    final presented = await session.decide(at: t0.plusDays(0.5));
    final before = learnerStateHash(session.state);

    final record = await session.closeWithOutcome(
      outcomeFor(presented!.exercise),
      termination: AttemptTermination.durationLimit,
    );

    expect(record.closure.termination, AttemptTermination.durationLimit);
    expect(record.closure.measurement, isA<Measured>());
    expect(
      learnerStateHash(session.state),
      isNot(before),
      reason: 'the evidence applies whichever way the attempt ended',
    );
  });

  test('the attempt is over, not waiting to be answered', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    await session.decide(at: t0.plusDays(0.5));

    await session.closeUnmeasured(
      termination: AttemptTermination.inactivityTimeout,
    );

    expect(session.hasOutstandingAttempt, isFalse);
    expect(
      await store.loadPendingDecision(alice.id),
      isNull,
      reason: 'pending means the attempt has not ended, and this one has',
    );
    expect((await store.loadJournal(alice.id)).length, 1);
  });

  test('reopening finds a closed attempt rather than a pending one', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final first = await openSession(store);
    await first.decide(at: t0.plusDays(0.5));
    final before = learnerStateHash(first.state);
    await first.closeUnmeasured(
      termination: AttemptTermination.inactivityTimeout,
    );

    final reopened = await openSession(store);

    expect(reopened.pending, isNull);
    expect(reopened.journal.length, 1);
    expect(
      learnerStateHash(reopened.state),
      before,
      reason: 'replaying a closure with no measurement rebuilds the same state',
    );
  });

  test('replay counts it without applying it', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    await session.decide(at: t0.plusDays(0.5));
    final presented = (await store.loadPendingDecision(alice.id))!;
    await session.closeWithOutcome(outcomeFor(presented.exercise));
    await session.decide(at: t0.plusDays(1.5));
    final afterMeasured = learnerStateHash(session.state);
    await session.closeUnmeasured(
      termination: AttemptTermination.durationLimit,
    );

    final replayed = replayJournal(
      await store.loadJournal(alice.id),
      model: _model,
      initial: placement(),
    );

    expect(replayed.attemptsApplied, 1);
    expect(replayed.attemptsUnmeasured, 1);
    expect(replayed.stateHash, afterMeasured);
    expect(replayed.divergences, isEmpty);
  });

  test('a checkpoint taken after one resumes to the same place', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    await session.decide(at: t0.plusDays(0.5));
    await session.closeUnmeasured(
      termination: AttemptTermination.inactivityTimeout,
    );
    await session.saveCheckpoint();
    final expected = learnerStateHash(session.state);

    final resumed = await openSession(store);

    expect(learnerStateHash(resumed.state), expected);
    expect(
      replayJournal(
        await store.loadJournal(alice.id),
        model: _model,
        initial: placement(),
      ).stateHash,
      expected,
      reason:
          'a full replay and a checkpoint resume must agree about a '
          'closure that carries no evidence',
    );
  });
}
