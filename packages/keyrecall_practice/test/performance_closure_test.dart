import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// The whole path, from what arrived on the wire to what the journal holds.
void main() {
  /// What [exercise] asks for, played [as] says.
  PerformanceTranscript performance(
    Exercise exercise, {
    List<int> Function(List<int> expected)? as,
    int gapMs = 500,
  }) {
    final realization = realize(exercise);
    final hand = realization.hands.first;
    final expected = [
      for (final moment in realization.moments)
        moment.noteFor(hand)?.midiNote ?? 60,
    ];
    final played = as == null ? expected : as(expected);

    var transcript = PerformanceTranscript.empty;
    for (final (index, midiNote) in played.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: exercise.material),
        timestampMs: index * gapMs,
      );
    }
    return transcript;
  }

  /// Presents until an exercise matching [wanted] comes up.
  Future<PresentedAttempt> presentUntil(
    PracticeSession session,
    bool Function(Exercise) wanted, {
    double startDay = 0.5,
  }) async {
    for (var slot = 0; slot < 200; slot++) {
      final presented = await session.decide(
        at: t0.plusDays(startDay + 0.5 * slot),
      );
      if (presented == null) continue;
      if (wanted(presented.exercise)) return presented;
      await session.commit(outcomeFor(presented.exercise));
    }
    throw StateError('no matching exercise was presented');
  }

  bool oneHand(Exercise exercise) =>
      exercise.conditions.hands != HandConfiguration.together;

  test('a clean single-hand attempt commits as a measured success', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    final presented = await presentUntil(session, oneHand);

    final record = await session.closeFromPerformance(
      performance(presented.exercise),
    );

    final measurement = record.closure.measurement;
    expect(measurement, isA<Measured>());
    expect(record.closure.termination, AttemptTermination.learnerStopped);
    final outcome = (measurement as Measured).outcome;
    expect(outcome.completed, isTrue);
    expect(outcome.motorScore, 1.0);
    expect(
      outcome.retrieval,
      presented.exercise.guidance.isRetrievalObserved
          ? FactualRetrieval.succeeded
          : FactualRetrieval.notTested,
    );
  });

  test('a poor attempt is still measured, not refused', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    final presented = await presentUntil(session, oneHand);

    final record = await session.closeFromPerformance(
      // Nothing like the exercise, at a stumbling pace.
      performance(
        presented.exercise,
        as: (_) => const [61, 66, 61, 70, 61],
        gapMs: 900,
      ),
    );

    final measurement = record.closure.measurement;
    expect(
      measurement,
      isA<Measured>(),
      reason:
          'measurement availability is about whether the observation model '
          'can read the attempt, never about how it went',
    );
    final outcome = (measurement as Measured).outcome;
    expect(outcome.started, isTrue);
    expect(outcome.completed, isFalse);
    expect(outcome.materialRetrieval, lessThan(0.5));
  });

  test('production never presents what it cannot read', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);

    for (var slot = 0; slot < 40; slot++) {
      final presented = await session.decide(at: t0.plusDays(0.5 * slot));
      if (presented == null) continue;
      expect(
        presented.exercise.conditions.hands,
        isNot(HandConfiguration.together),
        reason:
            'an exercise nothing can measure spends a practice slot and '
            'teaches the model nothing',
      );
      await session.closeFromPerformance(performance(presented.exercise));
    }
  });

  test('an unreadable attempt that reaches closure fails closed', () async {
    // Not the expected path: production does not present these. This is the
    // defensive case, such as a pending decision recovered from a build whose
    // supported set was wider.
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store, presentOnlyMeasurable: false);
    final presented = await presentUntil(
      session,
      (exercise) => exercise.conditions.hands == HandConfiguration.together,
    );
    final before = learnerStateHash(session.state);

    final record = await session.closeFromPerformance(
      performance(presented.exercise),
    );

    expect(
      record.closure.measurement,
      isA<MeasurementUnavailable>().having(
        (unavailable) => unavailable.reason,
        'reason',
        MeasurementUnavailableReason.handsTogetherCorrespondence,
      ),
      reason:
          'the missing capability is named, so it can disappear when '
          'observation grouping exists',
    );
    expect(
      learnerStateHash(session.state),
      before,
      reason: 'nothing was measured, so nothing about the learner may change',
    );
    expect(session.hasOutstandingAttempt, isFalse);
  });

  test('erasing a profile leaves nothing to replay', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    final presented = await presentUntil(session, oneHand);
    await session.closeFromPerformance(performance(presented.exercise));
    final practised = learnerStateHash(session.state);

    await store.erase(alice.id);
    final started = await openSession(store);

    expect(started.journal.length, 0);
    expect(started.pending, isNull);
    expect(
      learnerStateHash(started.state),
      isNot(practised),
      reason: 'a profile that started over is back at placement',
    );
  });

  test('a measured attempt survives a reopen', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final first = await openSession(store);
    final presented = await presentUntil(first, oneHand);
    await first.closeFromPerformance(performance(presented.exercise));
    final expected = learnerStateHash(first.state);

    final reopened = await openSession(store);

    expect(reopened.pending, isNull);
    expect(learnerStateHash(reopened.state), expected);
  });

  group('declining before a note is played', () {
    /// Presents until a single-hand exercise at a rung that tests retrieval.
    Future<PresentedAttempt> presentTested(PracticeSession session) =>
        presentUntil(
          session,
          (exercise) =>
              oneHand(exercise) && exercise.guidance.isRetrievalObserved,
        );

    test('records a retrieval failure with no execution beside it', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      await presentTested(session);

      final record = await session.closeDeclined(
        transcript: PerformanceTranscript.empty,
      );

      expect(record.closure.termination, AttemptTermination.learnerDeclined);
      final measurement = record.closure.measurement as Measured;
      expect(measurement.outcome.retrieval, FactualRetrieval.failed);
      expect(measurement.outcome.started, isFalse);
      expect(
        measurement.weights.materialExecution,
        0.0,
        reason: 'nothing was played, so nothing was shown about execution',
      );
      expect(measurement.weights.materialMemory, greaterThan(0.0));
      expect(
        measurement.weights.competencies.values,
        everyElement(0.0),
        reason: 'a competency is about execution, and there was none',
      );
    });

    test('offers the same exercise one rung more supportive', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await presentTested(session);
      final declined = presented.exercise;

      await session.closeDeclined(transcript: PerformanceTranscript.empty);
      final next = await session.decide(at: t0.plusDays(3));

      expect(next, isNotNull);
      final recovery = next!.exercise;
      expect(recovery.material, declined.material);
      expect(recovery.conditions, declined.conditions);
      expect(
        recovery.guidance,
        declined.guidance.oneStepMoreSupportive,
        reason:
            'exactly one rung, so the memory problem is the only thing '
            'that moved',
      );
    });

    test('is refused once anything has been played', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await presentTested(session);

      expect(
        () => session.closeDeclined(
          transcript: performance(
            presented.exercise,
            as: (expected) => expected.take(1).toList(),
          ),
        ),
        throwsA(isA<PracticeStateError>()),
        reason:
            'a note arrived, so what happened is measurement\'s question, and '
            'the guard is the session\'s rather than the screen\'s',
      );
    });

    test('is refused at a rung that supplies the material anyway', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store);
      final presented = await presentUntil(
        session,
        (exercise) =>
            oneHand(exercise) && !exercise.guidance.isRetrievalObserved,
      );
      expect(presented.exercise.guidance.isMaterialSupplied, isTrue);

      expect(
        () => session.closeDeclined(transcript: PerformanceTranscript.empty),
        throwsA(isA<PracticeStateError>()),
      );
    });
  });

  test('an attempt that was clearly too easy asks a faster one next', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await openSession(store);
    final presented = await presentUntil(
      session,
      (exercise) =>
          oneHand(exercise) &&
          exercise.guidance.isRetrievalObserved &&
          exercise.conditions.tempoBpm < 100,
    );
    final easy = presented.exercise;

    // Clean, steady, unbroken, from memory, and well above the tempo asked
    // for: the task was beneath the learner rather than played badly fast.
    await session.commit(
      Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1.0,
        pitchIntegrity: 1.0,
        continuity: 1.0,
        temporalStability: 1.0,
        achievedTempoRatio: 100 / easy.conditions.tempoBpm,
        topologyAccuracy: 1.0,
      ),
    );

    final next = await session.decide(at: t0.plusDays(1));

    expect(next, isNotNull);
    expect(next!.exercise.material, easy.material);
    expect(next.exercise.conditions.hands, easy.conditions.hands);
    expect(next.exercise.conditions.octaves, easy.conditions.octaves);
    expect(
      next.exercise.conditions.tempoBpm,
      greaterThan(easy.conditions.tempoBpm),
      reason:
          'the learner was already playing at this speed, so climbing toward '
          'it one step at a time would spend slots learning nothing',
    );
    expect(next.decision.decision.challengeBypass, ChallengeBypass.tempoProbe);
  });
}
