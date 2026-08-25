import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
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
}
