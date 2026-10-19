import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  late _UnreliableAcquisition store;
  setUp(() => store = _UnreliableAcquisition());

  Future<PracticeSession> open(String sessionId, {bool offering = true}) =>
      openSession(
        store,
        sessionId: sessionId,
        ids: countingIds(sessionId),
        pipeline: offering ? const AlwaysOffersAcquisition() : null,
      );

  Future<PresentedAcquisition> offer(
    PracticeSession session,
    double day,
  ) async =>
      await session.decideOutcome(at: t0.plusDays(day)) as PresentedAcquisition;

  Future<AcquisitionAttemptRecord> close(PracticeSession session, double day) =>
      session.closeAcquisition(
        PerformanceTranscript.empty,
        at: t0.plusDays(day),
      );

  Future<void> expectRetired(PracticeSession session) => expectLater(
    session.decideOutcome(at: t0.plusDays(10)),
    throwsA(
      anyOf(isA<AcquisitionRecordedReopenRequired>(), isA<DecisionOvertaken>()),
    ),
  );

  Future<void> expectUsableReopened() async {
    final reopened = await open('reopened', offering: false);
    expect(
      await reopened.decideOutcome(at: t0.plusDays(10)),
      isA<PresentedAttempt>(),
    );
  }

  test('a save that wrote nothing, overtaken by a later supported attempt, '
      'is recorded after it in time and its session reopened', () async {
    final first = await open('first');
    await offer(first, 1);
    store.failBeforeWriting = true;
    await expectLater(close(first, 1), throwsA(isA<_StorageFailure>()));

    final later = await open('later');
    await offer(later, 2);
    final landed = await close(later, 2);

    final record = await recordedBeforeReopening(close(first, 1));
    expect(record.journalSequence, 1);
    expect(record.identity.occurredAt, landed.identity.occurredAt);
    expect(record.observedWallTime, t0.plusDays(1));
    expect(record.allocation, isA<AllocationObserved>());
    final log = await store.loadAcquisitionJournal(alice.id);
    expect(
      [for (final entry in log.attempts) entry.identity.attemptId],
      [landed.identity.attemptId, record.identity.attemptId],
    );
    await expectRetired(first);
    await expectUsableReopened();
  });

  test(
    'a supported attempt an ordinary attempt overtook is recorded without '
    'its evidence, and its session reopened rather than left behind',
    () async {
      final first = await open('first');
      await offer(first, 1);
      final ordinary = await open('ordinary', offering: false);
      final presented =
          await ordinary.decideOutcome(at: t0.plusDays(1)) as PresentedAttempt;
      await ordinary.closeWithOutcome(outcomeFor(presented.exercise));

      final record = await recordedBeforeReopening(close(first, 1));
      expect(record.attemptsBefore, 1);
      expect(
        record.allocation,
        isA<AllocationUnobserved>().having(
          (gap) => gap.gap,
          'gap',
          AllocationGap.staleAcquisition,
        ),
      );
      expect((await store.loadAcquisitionJournal(alice.id)).attempts, [record]);
      await expectRetired(first);
      await expectUsableReopened();
    },
  );

  test('a save that landed before its answer was lost is the attempt, and the '
      'session goes on', () async {
    final first = await open('first');
    final offered = await offer(first, 1);
    store.failAfterWriting = true;

    final record = await close(first, 1);
    expect(record.identity.attemptId, offered.attemptId);
    expect((await store.loadAcquisitionJournal(alice.id)).attempts, [record]);
    expect(first.acquisitionJournal.attempts, [record]);
    expect(
      await first.decideOutcome(at: t0.plusDays(2)),
      isA<PracticeDecision>(),
    );
  });

  test('another attempt under this one\'s id is another writer\'s, kept as '
      'written, and the session reopened', () async {
    final first = await open('first');
    final offered = await offer(first, 1);
    final elsewhere = AcquisitionAttemptRecord(
      journalSequence: 0,
      identity: AttemptIdentity(
        profileId: alice.id,
        attemptId: offered.attemptId,
        sessionId: 'elsewhere',
        indexInSession: 0,
        occurredAt: t0.plusDays(1),
      ),
      task: offered.task,
      started: false,
      completion: AcquisitionCompletion.values.firstWhere(
        (completion) => !completion.isComplete,
      ),
      repairs: 0,
      repeats: 0,
      intrusions: 0,
      earnedProbe: false,
      sequence: CriterionVerdict.unavailable,
      continuity: CriterionVerdict.unavailable,
      gaps: const [],
    );
    await store.appendAcquisitionEntry(elsewhere);

    await expectLater(
      close(first, 1),
      throwsA(
        isA<DecisionOvertaken>().having(
          (overtaken) => overtaken.recordedElsewhere,
          'recorded elsewhere',
          isTrue,
        ),
      ),
    );
    expect((await store.loadAcquisitionJournal(alice.id)).attempts, [
      elsewhere,
    ]);
    await expectRetired(first);
    await expectUsableReopened();
  });
}

class _StorageFailure implements Exception {
  const _StorageFailure();
}

/// Fails the next acquisition write once, before or after writing it.
class _UnreliableAcquisition extends InMemoryPracticeStore {
  var failBeforeWriting = false;
  var failAfterWriting = false;

  _UnreliableAcquisition() : super(createdAt: t0);

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) async {
    if (failBeforeWriting) {
      failBeforeWriting = false;
      throw const _StorageFailure();
    }
    await super.appendAcquisitionEntry(entry);
    if (failAfterWriting) {
      failAfterWriting = false;
      throw const _StorageFailure();
    }
  }
}
