import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('allocation-lifecycle-');
  });
  tearDown(() => root.delete(recursive: true));

  Future<PracticeSession> open(
    PracticeStore store, {
    String sessionId = 'session-1',
    SchedulerPipeline? pipeline,
  }) {
    final resolved = pipeline ?? SchedulerPipeline(learner: learner);
    return openSession(
      store,
      sessionId: sessionId,
      ids: countingIds(sessionId),
      pipeline: resolved,
      scheduler: _EvidentHost(InProcessScheduler(resolved), sessionId),
    );
  }

  Future<PresentedAttempt> decide(PracticeSession session, double day) async =>
      await session.decideOutcome(at: t0.plusDays(day)) as PresentedAttempt;

  Future<AttemptRecord> commit(PracticeSession session, Exercise exercise) =>
      session.closeWithOutcome(outcomeFor(exercise));

  AllocationHistory history(PracticeSession session) =>
      AllocationHistory.of(session.journal, session.acquisitionJournal);

  test('a resumed decision commits the evidence it was made with', () async {
    final store = FilePracticeStore(root);
    final first = await open(store);
    final presented = await decide(first, 1);
    final made = presented.decision.allocation as AllocationObserved;
    expect(made.evidence.served, ['session-1-served-0']);
    expect(made.basis, AllocationBasis(attempts: 0, acquisitionAttempts: 0));

    final reopened = await open(FilePracticeStore(root), sessionId: 'later');
    expect(reopened.pending!.allocation, made);
    final record = await commit(reopened, reopened.pending!.exercise);

    expect(record.allocation, made);
    final folded = history(
      await open(FilePracticeStore(root), sessionId: 'audit'),
    );
    expect(folded.observed, 1);
    expect(folded.counters.asMap, {'missed': 1});
    expect(folded.staleDecisions, 0);
  });

  test('an abandoned decision advances nothing', () async {
    final store = InMemoryPracticeStore();
    final session = await open(store);
    await decide(session, 1);
    await session.abandonPending();

    expect(history(session).observed, 0);
    expect(history(session).basis.attempts, 0);
  });

  test('a retried commit is folded once', () async {
    final store = InMemoryPracticeStore();
    final session = await open(store);
    final presented = await decide(session, 1);
    final record = await commit(session, presented.exercise);
    await store.appendAttempt(record);

    final reopened = await open(store, sessionId: 'later');
    expect(reopened.journal.length, 1);
    expect(history(reopened).observed, 1);
  });

  test('a torn record takes its evidence with it', () async {
    final session = await open(FilePracticeStore(root));
    for (final day in [1.0, 2.0]) {
      await commit(session, (await decide(session, day)).exercise);
    }
    final file = File('${root.path}/${alice.id}/journal.jsonl');
    final lines = file.readAsLinesSync();
    final last = lines.removeLast();
    file.writeAsStringSync(
      '${lines.join('\n')}\n${last.substring(0, last.length ~/ 2)}',
    );

    final reopened = await open(FilePracticeStore(root), sessionId: 'later');
    expect(reopened.journal.length, 1);
    expect(history(reopened).observed, 1);
  });

  group('an acquisition attempt', () {
    test('commits its evidence where it was offered', () async {
      final session = await open(
        InMemoryPracticeStore(),
        pipeline: const AlwaysOffersAcquisition(),
      );
      final offer =
          await session.decideOutcome(at: t0.plusDays(1))
              as PresentedAcquisition;
      final record = await session.closeAcquisition(
        PerformanceTranscript.empty,
        at: t0.plusDays(1),
      );

      expect(offer.attemptsBefore, 0);
      expect(record.attemptsBefore, 0);
      expect(record.scope, offer.scope);
      expect(record.allocation, isA<AllocationObserved>());
      expect(history(session).observed, 1);
      expect(
        history(session).basis,
        AllocationBasis(attempts: 0, acquisitionAttempts: 1),
      );
    });

    test('offered before an attempt another session committed is kept, '
        'without its evidence', () async {
      final store = InMemoryPracticeStore();
      final offering = await open(
        store,
        pipeline: const AlwaysOffersAcquisition(),
      );
      await offering.decideOutcome(at: t0.plusDays(1));

      final other = await open(store, sessionId: 'switched');
      await commit(other, (await decide(other, 1)).exercise);

      final record = await recordedBeforeReopening(
        offering.closeAcquisition(
          PerformanceTranscript.empty,
          at: t0.plusDays(1),
        ),
      );
      await expectLater(
        offering.decideOutcome(at: t0.plusDays(2)),
        throwsA(isA<AcquisitionRecordedReopenRequired>()),
      );
      expect(record.attemptsBefore, 1);
      expect(
        record.allocation,
        AllocationUnobserved(
          AllocationGap.staleAcquisition,
          policy: AllocationPolicyIdentity(
            assigned: v1SchedulerConfig.modelVersion,
            effective: v1SchedulerConfig.modelVersion,
          ),
        ),
      );

      final folded = history(await open(store, sessionId: 'audit'));
      expect(folded.observed, 1);
      expect(folded.gaps, {AllocationGap.staleAcquisition: 1});
      expect(folded.counters.asMap, {'missed': 1});
    });
  });

  test('an acquisition attempt the log moved under is placed after what '
      'landed, kept, and its session reopened', () async {
    final store = InMemoryPracticeStore();
    final first = await open(store, pipeline: const AlwaysOffersAcquisition());
    final second = await open(
      store,
      sessionId: 'switched',
      pipeline: const AlwaysOffersAcquisition(),
    );
    await first.decideOutcome(at: t0.plusDays(1));
    await second.decideOutcome(at: t0.plusDays(1));
    await first.closeAcquisition(
      PerformanceTranscript.empty,
      at: t0.plusDays(1),
    );

    final record = await recordedBeforeReopening(
      second.closeAcquisition(PerformanceTranscript.empty, at: t0.plusDays(1)),
    );
    expect(record.journalSequence, 1);
    expect(record.allocation, isA<AllocationObserved>());
    final folded = history(await open(store, sessionId: 'audit'));
    expect(folded.observed, 2);
    expect(folded.staleDecisions, 1);
  });

  test('a decision made before an acquisition attempt landed is applied as '
      'committed, and counted stale', () async {
    final store = InMemoryPracticeStore();
    final offering = await open(
      store,
      pipeline: const AlwaysOffersAcquisition(),
    );
    await offering.decideOutcome(at: t0.plusDays(1));
    final other = await open(store, sessionId: 'switched');
    final presented = await decide(other, 1);

    await offering.closeAcquisition(
      PerformanceTranscript.empty,
      at: t0.plusDays(1),
    );
    final record = await commit(other, presented.exercise);

    expect(
      (record.allocation as AllocationObserved).basis,
      AllocationBasis(attempts: 0, acquisitionAttempts: 0),
    );
    final folded = history(await open(store, sessionId: 'audit'));
    expect(folded.observed, 2);
    expect(folded.staleDecisions, 1);
    expect(folded.counters.asMap, {'missed': 2});
  });

  test('a decision another session overtook is refused, and its session '
      'asks to be reopened', () async {
    final store = InMemoryPracticeStore();
    final overtaken = await open(store);
    final overtaking = await open(store, sessionId: 'switched');
    final late = await decide(overtaken, 1);
    final early = await decide(overtaking, 1);
    await commit(overtaking, early.exercise);

    await expectLater(
      commit(overtaken, late.exercise),
      throwsA(
        isA<DecisionOvertaken>()
            .having((e) => e.attemptId, 'attempt', late.decision.attemptId)
            .having((e) => e.recordedElsewhere, 'recorded elsewhere', false),
      ),
    );
    await expectLater(
      overtaken.decideOutcome(at: t0.plusDays(2)),
      throwsA(isA<DecisionOvertaken>()),
    );
    final reopened = await open(store, sessionId: 'reopened');
    expect(reopened.pending, isNull);
    expect(reopened.journal.length, 1);
    final folded = history(reopened);
    expect(folded.observed, 1);
    expect(folded.staleDecisions, 0);
    expect(folded.counters.asMap, {'missed': 1});
    expect(
      await reopened.decideOutcome(at: t0.plusDays(2)),
      isA<PresentedAttempt>(),
    );
  });

  test('a decision another session closed first is refused as recorded '
      'elsewhere', () async {
    final store = InMemoryPracticeStore();
    final first = await open(store);
    final presented = await decide(first, 1);
    final resuming = await open(store, sessionId: 'resumed');
    await resuming.closeWithOutcome(
      outcomeFor(resuming.pending!.exercise, succeeded: false),
    );

    await expectLater(
      commit(first, presented.exercise),
      throwsA(
        isA<DecisionOvertaken>().having(
          (e) => e.recordedElsewhere,
          'recorded elsewhere',
          true,
        ),
      ),
    );
    expect((await open(store, sessionId: 'audit')).journal.length, 1);
  });

  test(
    'a commit that landed before its answer was lost is still finished',
    () async {
      final store = _LosesAnswers();
      final session = await open(store);
      final presented = await decide(session, 1);
      store.loseNextAnswer = true;
      final record = await commit(session, presented.exercise);

      expect(record.identity.attemptId, presented.decision.attemptId);
      expect(session.journal.length, 1);
      expect(history(session).observed, 1);
    },
  );

  group('the store', () {
    AcquisitionAttemptRecord placedAt(int attemptsBefore, {int repairs = 0}) =>
        AcquisitionAttemptRecord(
          journalSequence: 0,
          identity: AttemptIdentity(
            profileId: alice.id,
            attemptId: 'acquisition',
            sessionId: 'session',
            indexInSession: 0,
            occurredAt: t0.plusDays(1),
          ),
          attemptsBefore: attemptsBefore,
          task: AcquisitionTask.unmeteredTraversal(_exercise),
          started: true,
          completion: AcquisitionCompletion.completedCleanly,
          repairs: repairs,
          repeats: 0,
          intrusions: 0,
          earnedProbe: false,
          sequence: CriterionVerdict.notMet,
          continuity: CriterionVerdict.unavailable,
          gaps: const [],
        );

    for (final (name, make) in [
      ('in memory', () => InMemoryPracticeStore()),
      ('on disk', () => FilePracticeStore(root)),
    ]) {
      group(name, () {
        test('refuses a stale placement and writes nothing', () async {
          final store = make();
          await store.loadJournal(alice.id, createdAt: t0);
          await store.appendAttempt(recordOf(_exercise));

          await expectLater(
            store.appendAcquisitionEntry(placedAt(0)),
            throwsA(
              isA<StaleAcquisitionPlacement>().having(
                (stale) => stale.attempts,
                'attempts',
                1,
              ),
            ),
          );
          expect((await store.loadAcquisitionJournal(alice.id)).length, 0);
        });

        test('accepts an identical retry after later attempts, and refuses '
            'new content under its id', () async {
          final store = make();
          await store.appendAcquisitionEntry(placedAt(0));
          await store.appendAttempt(recordOf(_exercise));

          await store.appendAcquisitionEntry(placedAt(0));
          expect((await store.loadAcquisitionJournal(alice.id)).length, 1);
          await expectLater(
            store.appendAcquisitionEntry(placedAt(0, repairs: 1)),
            throwsA(isA<JournalFormatException>()),
          );
        });
      });
    }
  });

  test('refuses history that places an acquisition attempt past its '
      'attempts', () {
    final journal = AttemptJournal(
      JournalHeader(profileId: alice.id, createdAt: t0),
    );
    final acquisition = AcquisitionJournal(
      AcquisitionJournalHeader(profileId: alice.id, createdAt: t0),
    );
    final offer = AcquisitionAttemptRecord(
      journalSequence: 0,
      identity: AttemptIdentity(
        profileId: alice.id,
        attemptId: 'acquisition',
        sessionId: 'session',
        indexInSession: 0,
        occurredAt: t0,
      ),
      attemptsBefore: 1,
      task: AcquisitionTask.unmeteredTraversal(_exercise),
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
    acquisition.append(offer);

    expect(
      () => AllocationHistory.of(journal, acquisition),
      throwsA(isA<JournalFormatException>()),
    );
  });
}

/// Writes every attempt, and can throw after one as if its answer was lost.
class _LosesAnswers extends InMemoryPracticeStore {
  var loseNextAnswer = false;

  @override
  Future<void> appendAttempt(AttemptRecord record) async {
    await super.appendAttempt(record);
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw StateError('the answer was lost');
    }
  }
}

final Exercise _exercise = Exercise.linear(
  material: fixtureMaterials.first,
  hands: HandConfiguration.right,
  octaves: 1,
  direction: ExerciseDirection.up,
  tempoBpm: 60,
  guidance: GuidanceContext.continuouslyCued,
);

/// Decides in process, and says every decision served one requirement named
/// for it and missed another.
class _EvidentHost implements SchedulerHost {
  final InProcessScheduler inner;
  final String name;
  var _decisions = 0;

  _EvidentHost(this.inner, this.name);

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
    Map<String, Set<HandConfiguration>> liveSupportHands = const {},
    List<String> uncoveredTargetIds = const [],
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    AllocationRequest? allocation,
  }) async {
    final verdict = await inner.decide(
      epoch: epoch,
      state: state,
      session: session,
      dueRequirementIds: dueRequirementIds,
      liveSupportHands: liveSupportHands,
      uncoveredTargetIds: uncoveredTargetIds,
      at: at,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
    );
    final evidence = AllocationVerdict(
      evidence: AllocationEvidence(
        served: ['$name-served-${_decisions++}'],
        missed: const ['missed'],
      ),
      basis: allocation!.basis,
    );
    if (verdict.chosen case final chosen?) {
      return SchedulerVerdict.selected(
        chosen,
        epoch: verdict.epoch,
        effect: verdict.effect,
        result: verdict.result,
        allocation: evidence,
      );
    }
    if (verdict.acquisitionTask case final task?) {
      return SchedulerVerdict.acquisition(
        task,
        epoch: verdict.epoch,
        effect: verdict.effect,
        result: verdict.result,
        displacedByAcquisition: verdict.displacedByAcquisition,
        allocation: evidence,
      );
    }
    return verdict;
  }
}
