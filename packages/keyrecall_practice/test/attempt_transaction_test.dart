import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// The transaction has to survive being interrupted anywhere in it. These
/// tests stop it at each point and reopen, which is what a crash looks like
/// from the next run's side.
void main() {
  group('the ordinary path', () {
    test('decides, presents, and commits', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);

      final presented = await session.decide(at: t0.plusDays(0.5));
      expect(presented, isNotNull);
      expect(session.hasOutstandingAttempt, isTrue);
      expect(
        await store.loadPendingDecision(alice.id),
        isNotNull,
        reason: 'the decision must be durable before the exercise is shown',
      );

      final record = await session.commit(outcomeFor(presented!.exercise));

      expect(record.identity.attemptId, presented.decision.attemptId);
      expect(record.exercise, presented.exercise);
      expect(session.hasOutstandingAttempt, isFalse);
      expect(await store.loadPendingDecision(alice.id), isNull);
      expect((await store.loadJournal(alice.id)).length, 1);
    });

    test('advances canonical state only on commit', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final before = learnerStateHash(session.state);

      final presented = await session.decide(at: t0.plusDays(0.5));
      expect(
        learnerStateHash(session.state),
        before,
        reason: 'deciding evaluates a copy; it must not move canonical state',
      );

      await session.commit(outcomeFor(presented!.exercise));
      expect(learnerStateHash(session.state), isNot(before));
    });

    test(
      'records the decision time, not the time the outcome arrived',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        final session = await openSession(store);

        final decidedAt = t0.plusDays(0.5);
        final presented = await session.decide(at: decidedAt);
        final record = await session.commit(outcomeFor(presented!.exercise));

        expect(
          record.identity.occurredAt,
          decidedAt,
          reason:
              'the prediction was conditioned on the state at decision time',
        );
      },
    );

    test('a slot that admits nothing presents and records nothing', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store, pipeline: pipelineCappedAt(4));

      var admitted = 0;
      var refused = 0;
      for (var i = 0; i < 10; i++) {
        final presented = await session.decide(at: t0.plusDays(0.5 * (i + 1)));
        if (presented == null) {
          refused++;
          continue;
        }
        admitted++;
        await session.commit(outcomeFor(presented.exercise));
      }

      expect(refused, greaterThan(0), reason: 'setup: expected a dry slot');
      expect((await store.loadJournal(alice.id)).length, admitted);
      expect(await store.loadPendingDecision(alice.id), isNull);
    });
  });

  group('a crash after presenting', () {
    test('surfaces the decision instead of inventing an outcome', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      // The process dies here. Nothing observed what the learner did.
      final reopened = await openSession(store);

      expect(reopened.pending, isNotNull);
      expect(reopened.pending!.attemptId, presented!.decision.attemptId);
      expect(reopened.pending!.exercise, presented.exercise);
      expect(
        reopened.journal.length,
        0,
        reason: 'an attempt nobody observed is not history',
      );
    });

    test('refuses to decide again while one is unresolved', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      await session.decide(at: t0.plusDays(0.5));

      final reopened = await openSession(store);
      expect(
        () => reopened.decide(at: t0.plusDays(1)),
        throwsA(isA<PracticeStateError>()),
      );
    });

    test('can be completed later with a real outcome', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      final reopened = await openSession(store);
      final record = await reopened.commit(
        outcomeFor(reopened.pending!.exercise),
      );

      expect(record.identity.attemptId, presented!.decision.attemptId);
      expect(
        record.identity.occurredAt,
        presented.decision.decidedAt,
        reason: 'the attempt happened when it was presented',
      );
      expect(reopened.pending, isNull);
      expect((await store.loadJournal(alice.id)).length, 1);
    });

    test('can be abandoned, leaving no evidence behind', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      await session.decide(at: t0.plusDays(0.5));

      final reopened = await openSession(store);
      final stateBefore = learnerStateHash(reopened.state);
      await reopened.abandonPending();

      expect(reopened.pending, isNull);
      expect(reopened.journal.length, 0);
      expect(
        learnerStateHash(reopened.state),
        stateBefore,
        reason: 'an abandoned attempt moved no state',
      );
      expect(await store.loadPendingDecision(alice.id), isNull);

      // And the sitting carries on normally.
      final presented = await reopened.decide(at: t0.plusDays(1));
      expect(presented, isNotNull);
    });
  });

  group('a crash during commit', () {
    test(
      'after the append, the stale decision is recognized and cleared',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        final session = await openSession(store);
        final presented = await session.decide(at: t0.plusDays(0.5));
        final record = await session.commit(outcomeFor(presented!.exercise));

        // The append landed and then the process died before the slot was
        // cleared, which looks exactly like this from the next run's side.
        await store.savePendingDecision(presented.decision);
        expect(await store.loadPendingDecision(alice.id), isNotNull);

        final reopened = await openSession(store);

        expect(
          reopened.pending,
          isNull,
          reason: 'the attempt is already history; the slot was merely stale',
        );
        expect(reopened.journal.length, 1);
        expect(
          reopened.journal.records.single.identity.attemptId,
          record.identity.attemptId,
        );
        expect(await store.loadPendingDecision(alice.id), isNull);
      },
    );

    test('the update is never applied twice', () async {
      // Learner state is not stored, it is replayed, and the journal holds each
      // attempt exactly once. So a retried commit cannot double-count.
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      await practise(session, attempts: 3);
      final once = learnerStateHash(session.state);

      final reopened = await openSession(store);
      expect(learnerStateHash(reopened.state), once);

      // Replaying the same journal again from scratch reaches the same place.
      final again = await openSession(store);
      expect(learnerStateHash(again.state), once);
    });

    test('re-appending the identical record is a no-op', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final record = await session.commit(outcomeFor(presented!.exercise));

      await store.appendAttempt(record);

      expect((await store.loadJournal(alice.id)).length, 1);
    });
  });

  group('reopening', () {
    test('reproduces the state the previous run reached', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final first = await openSession(store);
      await practise(first, attempts: 5);
      final reached = learnerStateHash(first.state);

      final second = await openSession(store, sessionId: 'session-2');

      expect(learnerStateHash(second.state), reached);
      expect(second.journal.length, 5);
    });

    test('a checkpoint is an accelerator, not a different answer', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final first = await openSession(store);
      await practise(first, attempts: 5);
      final reached = learnerStateHash(first.state);
      await first.saveCheckpoint();

      final withCheckpoint = await openSession(store, sessionId: 'session-2');
      expect(learnerStateHash(withCheckpoint.state), reached);

      // And the same is true once the checkpoint is thrown away.
      final store2 = InMemoryPracticeStore(createdAt: t0);
      final other = await openSession(store2);
      await practise(other, attempts: 5);
      final withoutCheckpoint = await openSession(
        store2,
        sessionId: 'session-2',
      );
      expect(learnerStateHash(withoutCheckpoint.state), reached);
    });

    test(
      'a checkpoint from another model version is ignored, not trusted',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        final first = await openSession(store);
        final committed = await practise(first, attempts: 4);
        final reached = learnerStateHash(first.state);

        await store.saveCheckpoint(
          LearnerStateCheckpoint.after(
            committed.last,
            state: first.state,
            learnerModelVersion: 'v1-prototype-99',
          ),
        );

        final reopened = await openSession(store, sessionId: 'session-2');
        expect(
          learnerStateHash(reopened.state),
          reached,
          reason: 'the journal still holds what the checkpoint stood in for',
        );
      },
    );

    test(
      'carries the recency window forward but not the attempt cap',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        final first = await openSession(store);
        await practise(first, attempts: 4);

        final second = await openSession(store, sessionId: 'session-2');

        expect(second.session.recentMaterialIds, isNotEmpty);
        expect(
          second.session.attemptsThisSession,
          0,
          reason: 'a restart is a new sitting',
        );
        expect(
          second.session.lastFailedExercise,
          isNull,
          reason: 'a recovery context must not outlive the failure it answered',
        );
      },
    );

    test('two profiles on one install stay separate', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final bob = Profile(
        id: '3f2a6c18-0000-4000-8000-00000000b0b0',
        displayName: 'Bob',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );

      final aliceSession = await openSession(store);
      await practise(aliceSession, attempts: 4);

      final bobSession = await openSession(
        store,
        profile: bob,
        ids: countingIds('bob'),
      );
      expect(bobSession.journal.length, 0);
      await practise(bobSession, attempts: 2, succeed: false);

      expect((await store.loadJournal(alice.id)).length, 4);
      expect((await store.loadJournal(bob.id)).length, 2);
      expect(
        learnerStateHash(aliceSession.state),
        isNot(learnerStateHash(bobSession.state)),
      );
    });
  });

  group('ordering', () {
    test('refuses to decide while an attempt is outstanding', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      await session.decide(at: t0.plusDays(0.5));

      expect(
        () => session.decide(at: t0.plusDays(1)),
        throwsA(isA<PracticeStateError>()),
      );
    });

    test('refuses to commit with nothing outstanding', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);

      expect(
        () => session.commit(outcomeOf()),
        throwsA(isA<PracticeStateError>()),
      );
    });

    test('records attempts in a forward timeline', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final committed = await practise(session, attempts: 5);

      for (var i = 1; i < committed.length; i++) {
        expect(
          committed[i].identity.occurredAt.isBefore(
            committed[i - 1].identity.occurredAt,
          ),
          isFalse,
        );
        expect(
          committed[i].journalSequence,
          committed[i - 1].journalSequence + 1,
        );
      }
    });
  });
}
