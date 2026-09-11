import 'package:keyrecall_domain/keyrecall_domain.dart';
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
  @override
  Future<Map<String, String>> loadSelectionDiagnostics(String profileId) =>
      inner.loadSelectionDiagnostics(profileId);

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) async {
    selectionWritesAttempted++;
    if (selectionFailure case final failure?) throw failure;
    await inner.appendSelectionDiagnostics(profileId, attemptId, diagnostics);
  }

  Object? selectionFailure;
  int selectionWritesAttempted = 0;

  final PracticeStore inner;

  /// When true, the next [appendAttempt] throws instead of writing.
  bool failNextAppend = false;

  /// When true, the next [appendAttempt] writes and then throws.
  ///
  /// The failure a caller cannot tell from one that wrote nothing.
  bool failNextAppendAfterWriting = false;

  /// When set, every [clearPendingDecision] throws instead of deleting.
  Object? clearFailure;

  /// When set, every [loadJournal] throws, so reconciliation cannot resolve
  /// an uncertain append either.
  Object? journalLoadFailure;

  /// When true, every [appendAcquisitionEntry] throws instead of writing.
  bool failAcquisitionAppends = false;

  /// When true, the next [appendAcquisitionEntry] writes and then throws.
  ///
  /// The failure a caller cannot tell from one that wrote nothing.
  bool failNextAcquisitionAppendAfterWriting = false;

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
    await inner.appendAttempt(record);
    if (failNextAppendAfterWriting) {
      failNextAppendAfterWriting = false;
      throw const _StorageFailure();
    }
  }

  @override
  Future<List<FeedbackExposure>> loadFeedbackExposures(String profileId) =>
      inner.loadFeedbackExposures(profileId);

  @override
  Future<void> appendFeedbackExposure(FeedbackExposure exposure) =>
      inner.appendFeedbackExposure(exposure);

  @override
  Future<AttemptJournal> loadJournal(String profileId, {DateTime? createdAt}) {
    if (journalLoadFailure case final failure?) throw failure;
    return inner.loadJournal(profileId, createdAt: createdAt);
  }

  @override
  Future<PendingDecision?> loadPendingDecision(String profileId) =>
      inner.loadPendingDecision(profileId);

  @override
  Future<void> savePendingDecision(PendingDecision decision) =>
      inner.savePendingDecision(decision);

  @override
  Future<void> clearPendingDecision(String profileId) {
    if (clearFailure case final failure?) throw failure;
    return inner.clearPendingDecision(profileId);
  }

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

  /// When set, every [loadAcquisitionJournal] throws, so an uncertain
  /// acquisition write cannot be settled either.
  Object? acquisitionLoadFailure;

  @override
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  }) {
    if (acquisitionLoadFailure case final failure?) throw failure;
    return inner.loadAcquisitionJournal(profileId, createdAt: createdAt);
  }

  /// How many acquisition appends were attempted, landing or not.
  int acquisitionAppendsAttempted = 0;

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) async {
    acquisitionAppendsAttempted++;
    if (failAcquisitionAppends) throw const _StorageFailure();
    await inner.appendAcquisitionEntry(entry);
    if (failNextAcquisitionAppendAfterWriting) {
      failNextAcquisitionAppendAfterWriting = false;
      throw const _StorageFailure();
    }
  }

  @override
  Future<void> erase(String profileId) => inner.erase(profileId);
}

/// A store that hands back a pending decision the caller did not file.
///
/// Models a misplaced or corrupted `pending.json`.
class MisfilingPracticeStore implements PracticeStore {
  @override
  Future<Map<String, String>> loadSelectionDiagnostics(String profileId) =>
      inner.loadSelectionDiagnostics(profileId);

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) => inner.appendSelectionDiagnostics(profileId, attemptId, diagnostics);

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
  Future<AcquisitionJournal> loadAcquisitionJournal(
    String profileId, {
    DateTime? createdAt,
  }) => inner.loadAcquisitionJournal(profileId, createdAt: createdAt);

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) =>
      inner.appendAcquisitionEntry(entry);

  @override
  Future<void> erase(String profileId) => inner.erase(profileId);
}

class _StorageFailure implements Exception {
  const _StorageFailure();

  @override
  String toString() => 'the disk said no';
}

void main() {
  for (final failure in [
    const _StorageFailure(),
    JournalFormatException('malformed selection log'),
  ]) {
    test(
      'selection logging failure does not cost a practice slot: $failure',
      () async {
        final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0))
          ..selectionFailure = failure;
        final session = await openSession(store);

        final presented = await session.decide(at: t0.plusDays(0.5));

        expect(store.selectionWritesAttempted, 1);
        expect(presented, isNotNull);
        expect(session.hasOutstandingAttempt, isTrue);
        expect(
          (await store.loadPendingDecision(alice.id))!.attemptId,
          presented!.decision.attemptId,
        );
        expect(await store.loadSelectionDiagnostics(alice.id), isEmpty);

        final record = await session.closeWithOutcome(
          outcomeFor(presented.exercise),
        );
        expect(record.identity.attemptId, presented.decision.attemptId);
        expect(session.journal.length, 1);
        expect(await store.loadPendingDecision(alice.id), isNull);
      },
    );
  }

  group('an acquisition service write that fails', () {
    /// Acquisition history that earned a probe of [parent].
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

    test('costs a redundant probe rather than the practice slot', () async {
      final inner = InMemoryPracticeStore(createdAt: t0);
      final store = FlakyPracticeStore(inner);
      final at = t0.plusDays(0.5);

      final first = await openSession(store);
      final parent = (await first.decide(at: at))!.exercise;
      await first.abandonPending();
      await inner.appendAcquisitionEntry(earnedFor(parent));

      store.failAcquisitionAppends = true;
      final session = await openSession(store, sessionId: 'session-2');
      final presented = await session.decide(at: at);
      await session.acknowledgePresentation(presented!.decision.attemptId);

      // The attempt is presented and outstanding: losing the discharge must
      // not cost the learner the work in front of them.
      expect(presented.exercise, parent);
      expect(session.hasOutstandingAttempt, isTrue);

      // The obligation is where it started, so a later presentation asks the
      // same question again rather than the probe being lost.
      final log = await inner.loadAcquisitionJournal(alice.id);
      expect(log.replay().probeOwed(parent), isTrue);
      expect(log.records.whereType<AcquisitionProbeServedRecord>(), isEmpty);
    });

    test('that landed before it threw is not written twice', () async {
      final inner = InMemoryPracticeStore(createdAt: t0);
      final store = FlakyPracticeStore(inner);
      final at = t0.plusDays(0.5);
      final session = await openSession(
        store,
        pipeline: const AlwaysOffersAcquisition(),
      );
      final offered =
          (await session.decideOutcome(at: at) as PresentedAcquisition)
              .attemptId;

      // No transcript at all, which is still an attempt: nothing was played
      // and the record says so. What is under test is the write.
      store.failNextAcquisitionAppendAfterWriting = true;
      final record = await session.closeAcquisition(
        PerformanceTranscript.empty,
        at: at,
      );

      // The record is on disk, so a retry must recognize it rather than
      // offering a second event under a fresh id at a sequence the file
      // already has.
      final log = await inner.loadAcquisitionJournal(alice.id);
      expect(log.attempts, hasLength(1));
      expect(record.identity.attemptId, offered);
      expect(log.attempts.single.identity.attemptId, offered);
    });

    test('that cannot be settled is reconciled before the next event', () async {
      // The service write landed, its answer was lost, and the read that would
      // have settled it failed too. The live log is now a record behind the
      // file, and building the next event from it proposes a sequence the file
      // already holds, under a new id every time.
      final inner = InMemoryPracticeStore(createdAt: t0);
      final store = FlakyPracticeStore(inner);
      final at = t0.plusDays(0.5);

      final first = await openSession(store);
      final parent = (await first.decide(at: at))!.exercise;
      await first.abandonPending();
      await inner.appendAcquisitionEntry(earnedFor(parent));

      final session = await openSession(store, sessionId: 'session-2');
      store.failNextAcquisitionAppendAfterWriting = true;
      store.acquisitionLoadFailure = const _StorageFailure();
      final presented = (await session.decide(at: at))!;
      expect(presented.exercise, parent);
      await session.acknowledgePresentation(presented.decision.attemptId);
      await session.abandonPending();

      // Disk recorded the service; the live log did not see it.
      expect(
        (await inner.loadAcquisitionJournal(
          alice.id,
        )).records.whereType<AcquisitionProbeServedRecord>(),
        hasLength(1),
      );
      expect(session.acquisitionProgress.probeOwed(parent), isTrue);

      // Storage returns. The next presentation reloads before building
      // anything, so it learns the obligation was already discharged instead
      // of proposing an event at an occupied sequence forever.
      store.acquisitionLoadFailure = null;
      final proposed = store.acquisitionAppendsAttempted;
      final again = (await session.decide(at: at))!;
      await session.acknowledgePresentation(again.decision.attemptId);

      expect(session.acquisitionProgress.probeOwed(parent), isFalse);
      expect(
        store.acquisitionAppendsAttempted,
        proposed,
        reason:
            'reconciling first means nothing is proposed at a sequence the '
            'file already holds',
      );
      expect(
        (await inner.loadAcquisitionJournal(
          alice.id,
        )).records.whereType<AcquisitionProbeServedRecord>(),
        hasLength(1),
        reason: 'and the service was never written a second time',
      );
    });

    test(
      'that reloads to a different record fails rather than passing',
      () async {
        // An id that comes back carrying different content is a collision, not
        // the write having succeeded. Calling it success would drop what was
        // actually recorded and leave memory describing an event nobody wrote.
        final inner = InMemoryPracticeStore(createdAt: t0);
        final store = FlakyPracticeStore(inner);
        final at = t0.plusDays(0.5);
        final session = await openSession(
          store,
          pipeline: const AlwaysOffersAcquisition(),
        );
        final offered =
            await session.decideOutcome(at: at) as PresentedAcquisition;

        // Something else already holds that id, with different content.
        await inner.appendAcquisitionEntry(
          AcquisitionProbeServedRecord(
            journalSequence: 0,
            identity: AttemptIdentity(
              profileId: alice.id,
              attemptId: offered.attemptId,
              sessionId: 'sitting-0',
              indexInSession: 0,
              occurredAt: at,
            ),
            parent: offered.task.parent,
          ),
        );
        store.failAcquisitionAppends = true;

        await expectLater(
          session.closeAcquisition(PerformanceTranscript.empty, at: at),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('says so rather than failing silently', () async {
      final inner = InMemoryPracticeStore(createdAt: t0);
      final store = FlakyPracticeStore(inner);
      final at = t0.plusDays(0.5);

      final first = await openSession(store);
      final parent = (await first.decide(at: at))!.exercise;
      await first.abandonPending();
      await inner.appendAcquisitionEntry(earnedFor(parent));

      store.failAcquisitionAppends = true;
      final session = await openSession(store, sessionId: 'session-2');
      final presented = await session.decide(at: at);
      await session.acknowledgePresentation(presented!.decision.attemptId);

      // Non-blocking is not the same as invisible. One lost write is a
      // redundant probe; a systematic one is storage quietly failing.
      final diagnostics = await store.loadSelectionDiagnostics(alice.id);
      final key = '${presented.decision.attemptId}:acquisition-service';
      expect(diagnostics, contains(key));
      expect(diagnostics[key], contains('the disk said no'));
      expect(diagnostics[key], contains('left owed'));
    });
  });

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

    test('an append that landed but was not acknowledged is settled', () async {
      // The failure a caller cannot tell from one that wrote nothing. Reading
      // durable history back says which it was, and finding this exact attempt
      // there means the append committed, so the close finishes rather than
      // reporting a failure for something already history.
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      store.failNextAppendAfterWriting = true;
      final record = await session.closeWithOutcome(
        outcomeFor(presented!.exercise),
      );

      expect(session.journal.length, 1);
      expect((await store.loadJournal(alice.id)).length, 1);
      expect(learnerStateHash(session.state), record.stateAfterHash);
      expect(session.hasOutstandingAttempt, isFalse);
      expect(await store.loadPendingDecision(alice.id), isNull);
    });

    test(
      'an uncertain append that cannot be settled stays retryable',
      () async {
        // Neither the append nor the reconciliation read answered. Nothing may
        // conclude the attempt committed, and the transaction has to survive to
        // be finished once storage returns.
        final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
        final session = await openSession(store);
        final presented = await session.decide(at: t0.plusDays(0.5));
        final outcome = outcomeFor(presented!.exercise);

        store.failNextAppend = true;
        store.journalLoadFailure = const _StorageFailure();
        await expectLater(
          session.closeWithOutcome(outcome),
          throwsA(isA<_StorageFailure>()),
        );
        expect(session.journal.length, 0);
        expect(session.hasOutstandingAttempt, isTrue);

        // The app reads its clock again on the retry, which is why rebuilding
        // the record would offer different content under the same id.
        store.journalLoadFailure = null;
        final record = await session.closeWithOutcome(
          outcome,
          observedWallTime: t0.plusDays(0.9),
        );

        expect(
          record.observedWallTime,
          isNull,
          reason: 'the frozen transaction is what was retried',
        );
        expect(session.journal.length, 1);
        expect((await store.loadJournal(alice.id)).length, 1);
        expect(record.stateAfterHash, learnerStateHash(session.state));
      },
    );

    test('a failed cleanup does not lose the committed attempt', () async {
      // The evidence is durable. Reporting that as a failed close, and then
      // refusing the retry because nothing is outstanding, would leave the
      // caller unable to finish an operation that already succeeded.
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final outcome = outcomeFor(presented!.exercise);

      store.clearFailure = const _StorageFailure();
      await expectLater(
        session.closeWithOutcome(outcome),
        throwsA(isA<_StorageFailure>()),
      );

      expect(session.journal.length, 1, reason: 'the attempt is history');
      expect(
        session.hasOutstandingAttempt,
        isTrue,
        reason: 'and the transaction is not finished',
      );
      await expectLater(
        session.decideOutcome(at: t0.plusDays(1)),
        throwsA(isA<PracticeStateError>()),
      );

      store.clearFailure = null;
      final record = await session.closeWithOutcome(outcome);

      expect(record.identity.attemptId, presented.decision.attemptId);
      expect(session.journal.length, 1, reason: 'applied exactly once');
      expect(session.hasOutstandingAttempt, isFalse);
      expect(await store.loadPendingDecision(alice.id), isNull);
      expect(await session.decideOutcome(at: t0.plusDays(1)), isNotNull);
    });

    test('a committed attempt cannot be abandoned', () async {
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      store.clearFailure = const _StorageFailure();
      await expectLater(
        session.closeWithOutcome(outcomeFor(presented!.exercise)),
        throwsA(isA<_StorageFailure>()),
      );

      await expectLater(
        session.abandonPending(),
        throwsA(isA<PracticeStateError>()),
      );
    });

    test('cleanup retries finish through the performance API too', () async {
      // The wrapper resolves the outstanding decision before committing, and
      // a finished commit has already cleared it. Looking that up before
      // resuming refused to finish a close whose evidence was durable.
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final played = playedFor(presented!.exercise);

      store.clearFailure = const _StorageFailure();
      await expectLater(
        session.closeFromPerformance(played),
        throwsA(isA<_StorageFailure>()),
      );

      store.clearFailure = null;
      final closed = await session.closeFromPerformance(played);

      expect(closed.record.identity.attemptId, presented.decision.attemptId);
      expect(session.journal.length, 1);
      expect(session.hasOutstandingAttempt, isFalse);
      expect(await store.loadPendingDecision(alice.id), isNull);
    });

    test('cleanup retries finish through the declined API too', () async {
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      PresentedAttempt? presented;
      for (var day = 0.5; presented == null && day < 12; day += 0.5) {
        final decided = await session.decide(at: t0.plusDays(day));
        if (decided!.exercise.guidance.isRetrievalObserved) {
          presented = decided;
        } else {
          await session.closeWithOutcome(outcomeFor(decided.exercise));
        }
      }
      final committed = session.journal.length;

      store.clearFailure = const _StorageFailure();
      await expectLater(
        session.closeDeclined(transcript: PerformanceTranscript.empty),
        throwsA(isA<_StorageFailure>()),
      );

      store.clearFailure = null;
      final record = await session.closeDeclined(
        transcript: PerformanceTranscript.empty,
      );

      expect(record.identity.attemptId, presented!.decision.attemptId);
      expect(session.journal.length, committed + 1);
      expect(session.hasOutstandingAttempt, isFalse);
    });

    test('a retried performance close cannot contradict itself', () async {
      // The record is frozen and the reading was not, so a retry with a
      // different transcript handed back a reading describing a performance
      // the record does not.
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      // Nothing was written, and the prepared transaction still survives, so
      // this retry finishes that same frozen result rather than reading the
      // transcript it was handed.
      store.failNextAppend = true;
      await expectLater(
        session.closeFromPerformance(PerformanceTranscript.empty),
        throwsA(isA<_StorageFailure>()),
      );

      final first = await session.closeFromPerformance(
        playedFor(presented!.exercise),
      );

      expect(first.reading.outcome.started, isFalse);
      expect(measuredOf(first.record).outcome.started, isFalse);

      // And the same holds once the attempt is already history and only the
      // cleanup is outstanding.
      final next = await session.decide(at: t0.plusDays(1));
      store.clearFailure = const _StorageFailure();
      await expectLater(
        session.closeFromPerformance(playedFor(next!.exercise)),
        throwsA(isA<_StorageFailure>()),
      );

      store.clearFailure = null;
      final resumed = await session.closeFromPerformance(
        PerformanceTranscript.empty,
      );

      expect(
        resumed.reading.outcome.started,
        measuredOf(resumed.record).outcome.started,
        reason: 'the reading and the record describe one performance',
      );
      expect(resumed.reading.outcome.started, isTrue);
    });

    test('abandoning is refused while durability is unknown', () async {
      // The append wrote and then threw, and the read that would settle it
      // failed too. Abandoning on the strength of not knowing leaves one
      // attempt in the file and none in the sitting.
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final outcome = outcomeFor(presented!.exercise);

      store.failNextAppendAfterWriting = true;
      store.journalLoadFailure = const _StorageFailure();
      await expectLater(
        session.closeWithOutcome(outcome),
        throwsA(isA<_StorageFailure>()),
      );

      await expectLater(
        session.abandonPending(),
        throwsA(isA<_StorageFailure>()),
        reason: 'settling it is what abandonment depends on',
      );

      // Storage returns, and abandoning now learns the attempt is history.
      store.journalLoadFailure = null;
      await expectLater(
        session.abandonPending(),
        throwsA(isA<PracticeStateError>()),
      );

      final record = await session.closeWithOutcome(outcome);
      expect(session.journal.length, 1);
      expect((await store.loadJournal(alice.id)).length, 1);
      expect(record.stateAfterHash, learnerStateHash(session.state));
    });

    test('abandoning is allowed once absence is established', () async {
      final store = FlakyPracticeStore(InMemoryPracticeStore(createdAt: t0));
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));

      store.failNextAppend = true;
      await expectLater(
        session.closeWithOutcome(outcomeFor(presented!.exercise)),
        throwsA(isA<_StorageFailure>()),
      );

      await session.abandonPending();

      expect(session.hasOutstandingAttempt, isFalse);
      expect(session.journal.length, 0);
      expect((await store.loadJournal(alice.id)).length, 0);
      expect(await store.loadPendingDecision(alice.id), isNull);

      // And the sitting carries on, aiming at the sequence storage expects.
      final next = await session.decide(at: t0.plusDays(1));
      await session.closeWithOutcome(outcomeFor(next!.exercise));
      expect((await store.loadJournal(alice.id)).length, 1);
    });

    test('and overlapping closes finish the one transaction', () async {
      // A session is still single-writer, and calling this twice at once is
      // still a caller error. What it can no longer be is a divergence: the
      // attempt is computed and frozen when the first close begins, so the
      // second finishes that transaction rather than folding the same outcome
      // in again from a later reading and offering different content under the
      // same id.
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final outcome = outcomeFor(presented!.exercise);

      final records = await Future.wait([
        for (final observed in [t0.plusDays(0.5), t0.plusDays(0.6)])
          session.closeWithOutcome(outcome, observedWallTime: observed),
      ]);

      expect(
        records.map((record) => contentHash(record.toJson())).toSet(),
        hasLength(1),
        reason: 'both calls describe the same attempt',
      );
      expect(
        session.journal.length,
        1,
        reason: 'history holds the attempt once however the two interleaved',
      );
      expect(
        records.first.observedWallTime,
        t0.plusDays(0.5),
        reason: 'the reading the transaction was prepared with is the one kept',
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
