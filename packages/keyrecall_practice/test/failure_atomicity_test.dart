import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// A store that can be made to fail on demand.
///
/// Models the failure a process crash does not cover: storage that throws and
/// leaves the program running, free to try again.
class FlakyPracticeStore implements PracticeStore {
  final PracticeStore inner;

  /// When true, the next [appendAttempt] throws instead of writing.
  bool failNextAppend = false;

  /// How many appends actually reached the inner store.
  int appendsPerformed = 0;

  FlakyPracticeStore(this.inner);

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    if (failNextAppend) {
      failNextAppend = false;
      throw const _StorageFailure();
    }
    appendsPerformed++;
    return inner.appendAttempt(record);
  }

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId) =>
      inner.loadFeedbackExposures(profileId);

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) =>
      inner.appendFeedbackExposure(exposure);

  @override
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt}) =>
      inner.loadJournal(profileId, createdAt: createdAt);

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) =>
      inner.loadPendingDecision(profileId);

  @override
  Future<void> savePendingDecision(PendingDecision decision) =>
      inner.savePendingDecision(decision);

  @override
  Future<void> clearPendingDecision(String profileId) =>
      inner.clearPendingDecision(profileId);

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) =>
      inner.loadCheckpoint(profileId);

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) =>
      inner.saveCheckpoint(checkpoint);

  @override
  Future<List<CoordinationSample>> loadCoordinationSamples(String profileId) =>
      inner.loadCoordinationSamples(profileId);

  @override
  Future<void> appendCoordinationSample(CoordinationSample sample) =>
      inner.appendCoordinationSample(sample);

  @override
  Future<PracticePlan?> loadPracticePlan(String profileId) =>
      inner.loadPracticePlan(profileId);

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) =>
      inner.savePracticePlan(profileId, plan);

  @override
  Future<void> erase(String profileId) => inner.erase(profileId);
}

/// A store that hands back a pending decision the caller did not file.
///
/// Models a misplaced or corrupted `pending.json`.
class MisfilingPracticeStore implements PracticeStore {
  final PracticeStore inner;

  /// Returned for any profile, whatever was actually saved.
  PendingDecision? misfiled;

  MisfilingPracticeStore(this.inner, {this.misfiled});

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) async =>
      misfiled ?? await inner.loadPendingDecision(profileId);

  @override
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt}) =>
      inner.loadJournal(profileId, createdAt: createdAt);

  @override
  Future<void> appendAttempt(AttemptRecord record) =>
      inner.appendAttempt(record);

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId) =>
      inner.loadFeedbackExposures(profileId);

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) =>
      inner.appendFeedbackExposure(exposure);

  @override
  Future<void> savePendingDecision(PendingDecision decision) =>
      inner.savePendingDecision(decision);

  @override
  Future<void> clearPendingDecision(String profileId) =>
      inner.clearPendingDecision(profileId);

  @override
  Future<LearnerStateCheckpoint?> loadCheckpoint(String profileId) =>
      inner.loadCheckpoint(profileId);

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) =>
      inner.saveCheckpoint(checkpoint);

  @override
  Future<List<CoordinationSample>> loadCoordinationSamples(String profileId) =>
      inner.loadCoordinationSamples(profileId);

  @override
  Future<void> appendCoordinationSample(CoordinationSample sample) =>
      inner.appendCoordinationSample(sample);

  @override
  Future<PracticePlan?> loadPracticePlan(String profileId) =>
      inner.loadPracticePlan(profileId);

  @override
  Future<void> savePracticePlan(String profileId, PracticePlan plan) =>
      inner.savePracticePlan(profileId, plan);

  @override
  Future<void> erase(String profileId) => inner.erase(profileId);
}

class _StorageFailure implements Exception {
  const _StorageFailure();

  @override
  String toString() => 'the disk said no';
}

void main() {
  group('an append that fails without killing the process', () {
    test('leaves the session exactly where it was', () async {
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final stateBefore = learnerStateHash(session.state);

      store.failNextAppend = true;
      await expectLater(
        session.closeWithOutcome(outcomeFor(presented!.exercise)),
        throwsA(isA<_StorageFailure>()),
      );

      expect(
        learnerStateHash(session.state),
        stateBefore,
        reason: 'state must not run ahead of the journal',
      );
      expect(session.journal.length, 0);
      expect(
        await store.loadPendingDecision(alice.id),
        isNotNull,
        reason: 'the attempt is still outstanding, so the decision stands',
      );
      expect(session.hasOutstandingAttempt, isTrue);
    });

    test('a retry commits exactly once, reaching the clean answer', () async {
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final outcome = outcomeFor(presented!.exercise);

      store.failNextAppend = true;
      await expectLater(
        session.closeWithOutcome(outcome),
        throwsA(isA<_StorageFailure>()),
      );

      final record = await session.closeWithOutcome(outcome);

      expect(store.appendsPerformed, 1);
      expect(session.journal.length, 1);
      expect(record.identity.attemptId, presented.decision.attemptId);

      // The same run without the failure lands in the same place.
      final clean = InMemoryPracticeStore(createdAt: t0);
      final cleanSession = await openSession(clean);
      final cleanPresented = await cleanSession.decide(at: t0.plusDays(0.5));
      await cleanSession.closeWithOutcome(outcomeFor(cleanPresented!.exercise));

      expect(
        learnerStateHash(session.state),
        learnerStateHash(cleanSession.state),
      );
      expect(await store.loadPendingDecision(alice.id), isNull);
    });

    test(
      'reopening after the failure still shows the attempt as pending',
      () async {
        final inner = InMemoryPracticeStore(createdAt: t0);
        final store = FlakyPracticeStore(inner);
        final session = await openSession(store);
        final presented = await session.decide(at: t0.plusDays(0.5));

        store.failNextAppend = true;
        await expectLater(
          session.closeWithOutcome(outcomeFor(presented!.exercise)),
          throwsA(isA<_StorageFailure>()),
        );

        final reopened = await openSession(inner, sessionId: 'session-2');

        expect(reopened.pending, isNotNull);
        expect(reopened.pending!.attemptId, presented.decision.attemptId);
        expect(reopened.journal.length, 0);
      },
    );

    test('several failures in a row still commit once', () async {
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final outcome = outcomeFor(presented!.exercise);

      for (var i = 0; i < 3; i++) {
        store.failNextAppend = true;
        await expectLater(
          session.closeWithOutcome(outcome),
          throwsA(isA<_StorageFailure>()),
        );
      }
      await session.closeWithOutcome(outcome);

      expect(store.appendsPerformed, 1);
      expect(session.journal.length, 1);
    });

    test('but retrying is not the same as overlapping', () async {
      // The tests above make committing safe to run *again*. They say nothing
      // about running two at once, and the attempt id is easy to misread as
      // permission to do so. It is not: a session is single-writer, and an
      // overlapping second commit folds the same outcome in from state of a
      // different age, producing a different record under the same id. The
      // journal refuses that as a collision rather than absorbing it as a
      // retry, so the caller is handed a failure it cannot act on.
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final outcome = outcomeFor(presented!.exercise);

      final failures = <Object>[];
      await Future.wait([
        for (final observed in [t0.plusDays(0.5), t0.plusDays(0.6)])
          session
              .closeWithOutcome(outcome, observedWallTime: observed)
              .catchError((Object error) {
                failures.add(error);
                throw error;
              }),
      ], eagerError: false).catchError((Object _) => <AttemptRecord>[]);

      expect(
        failures,
        isNotEmpty,
        reason: 'overlapping commits must fail loudly, not quietly diverge',
      );
      expect(
        session.journal.length,
        1,
        reason: 'history holds the attempt once however the two interleaved',
      );
    });
  });

  group('a corrupted pending decision', () {
    test('belonging to another profile is refused', () async {
      // The one input that is neither replayed nor hash-checked. Committing it
      // would append one person's practice into another person's history.
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      final foreign = PendingDecision(
        attemptId: presented!.decision.attemptId,
        profileId: '3f2a6c18-0000-4000-8000-00000000b0b0',
        sessionId: presented.decision.sessionId,
        indexInSession: presented.decision.indexInSession,
        journalSequence: presented.decision.journalSequence,
        decidedAt: presented.decision.decidedAt,
        provenance: presented.decision.provenance,
        exercise: presented.decision.exercise,
        decision: presented.decision.decision,
        stateBeforeHash: presented.decision.stateBeforeHash,
      );
      // Filed where Alice's slot lives, but claiming to be Bob's.
      final misfiling = MisfilingPracticeStore(store, misfiled: foreign);

      await expectLater(
        openSession(misfiling, sessionId: 'session-2'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('targeting the wrong journal position is refused', () async {
      // An uncommitted attempt that does not target the end of history is
      // impossible transaction state.
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      await practise(session, attempts: 2);
      final presented = await session.decide(at: t0.plusDays(10));

      await store.savePendingDecision(
        PendingDecision(
          attemptId: presented!.decision.attemptId,
          profileId: alice.id,
          sessionId: presented.decision.sessionId,
          indexInSession: presented.decision.indexInSession,
          journalSequence: 99,
          decidedAt: presented.decision.decidedAt,
          provenance: presented.decision.provenance,
          exercise: presented.decision.exercise,
          decision: presented.decision.decision,
          stateBeforeHash: presented.decision.stateBeforeHash,
        ),
      );

      await expectLater(
        openSession(store, sessionId: 'session-2'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('predating the profile is refused', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      await store.savePendingDecision(
        PendingDecision(
          attemptId: presented!.decision.attemptId,
          profileId: alice.id,
          sessionId: presented.decision.sessionId,
          indexInSession: presented.decision.indexInSession,
          journalSequence: presented.decision.journalSequence,
          decidedAt: alice.createdAt.plusDays(-1),
          provenance: presented.decision.provenance,
          exercise: presented.decision.exercise,
          decision: presented.decision.decision,
          stateBeforeHash: presented.decision.stateBeforeHash,
        ),
      );

      await expectLater(
        openSession(store, sessionId: 'session-2'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test(
      'a stale slot behind the journal is still cleared, not refused',
      () async {
        // The legitimate case the sequence check must not catch: the attempt was
        // committed and the slot simply outlived it.
        final store = InMemoryPracticeStore(createdAt: t0);
        final session = await openSession(store);
        final presented = await session.decide(at: t0.plusDays(0.5));
        await session.closeWithOutcome(outcomeFor(presented!.exercise));
        await practise(session, attempts: 2, startDay: 5);

        await store.savePendingDecision(presented.decision);

        final reopened = await openSession(store, sessionId: 'session-2');

        expect(reopened.pending, isNull);
        expect(reopened.journal.length, 3);
      },
    );
  });
}
