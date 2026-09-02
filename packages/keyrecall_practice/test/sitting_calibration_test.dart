import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// The same three learners as `scheduler_calibration_test.dart`, over days
/// rather than over slots.
///
/// The other harness advances half a day per attempt inside one session, which
/// is fine for asking whether a mechanism can fire at all and useless for
/// asking when. Anything paced by elapsed time or by session boundaries has to
/// be asked here: a sitting is a session, the attempt cap is per sitting, and
/// coming back tomorrow is a new one.
///
/// Like its sibling, it asserts shape rather than numbers. The table it prints
/// is for a person to read across runs.
void main() {
  /// Twenty attempts a sitting, ninety seconds apart, on these days.
  const perSitting = 20;
  const sittingDays = [0.0, 1.0, 3.0, 7.0];

  /// What each sitting asked for, in order.
  Future<List<Map<int, int>>> practise(
    PlacementTier placement, {
    required double quality,
    required double bpm,
    String label = '',
  }) async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final sittings = <Map<int, int>>[];

    for (final (index, day) in sittingDays.indexed) {
      final session = await openSession(
        store,
        placement: placement,
        materials: allScales,
        sessionId: 'sitting-$index',
        ids: countingIds('sitting-$index-attempt'),
      );
      final rungs = <int, int>{};
      final bypasses = <String, int>{};
      for (var i = 0; i < perSitting; i++) {
        final at = t0.plusDays(day + i * 90 / Duration.secondsPerDay);

        final presented = await session.decide(at: at);
        if (presented == null) continue;

        final exercise = presented.exercise;
        final independence = exercise.guidance.independence;
        rungs[independence] = (rungs[independence] ?? 0) + 1;
        final bypass =
            presented.decision.decision.challengeBypass?.id ?? 'ordinary';
        bypasses[bypass] = (bypasses[bypass] ?? 0) + 1;

        final observed = exercise.guidance.isRetrievalObserved;
        await session.closeWithOutcome(
          Outcome(
            started: quality > 0.2,
            retrieval: !observed
                ? FactualRetrieval.notTested
                : (quality >= 0.7
                      ? FactualRetrieval.succeeded
                      : FactualRetrieval.failed),
            completed: quality >= 0.6,
            materialRetrieval: quality,
            pitchIntegrity: quality,
            continuity: quality,
            temporalStability: quality,
            achievedTempoRatio: bpm / exercise.conditions.tempoBpm,
            topologyAccuracy: quality,
          ),
          observedWallTime: at,
        );
      }

      sittings.add(rungs);
      print(
        '$label sitting $index (day ${day.toInt()}): '
        'cued/previewed/unguided='
        '${rungs[0] ?? 0}/${rungs[1] ?? 0}/${rungs[2] ?? 0} '
        'bypasses=$bypasses',
      );
    }
    return sittings;
  }

  test('someone who retrieves everything stops being shown it', () async {
    final sittings = await practise(
      PlacementTier.advanced,
      quality: 1.0,
      bpm: 110,
      label: 'advanced',
    );

    // The failure this harness exists to catch. Support removal used to be
    // paced by the retention clock, which every successful retrieval pushed
    // forward, so a learner who never missed a note stayed on the preview and
    // the harder they practised the longer it took. Independence arrived only
    // once a material had gone untouched long enough to look forgotten.
    final firstUnguided = sittings.indexWhere((rungs) => (rungs[2] ?? 0) > 0);

    expect(firstUnguided, isNot(-1), reason: 'never asked to play unaided');
    expect(
      firstUnguided,
      0,
      reason:
          'an independence question was ranked and waiting through the whole '
          'first sitting and lost every free contest to novelty, which is '
          'exploration dominating rather than merely leading',
    );
    expect(
      sittingDays[firstUnguided],
      lessThan(v1SchedulerConfig.probe.minDaysSinceLastRetrieval),
      reason:
          'removing a preview is not the same question as proving retention, '
          'and waiting out the retention clock to ask it means someone who '
          'practises daily is never asked at all',
    );
  });

  test('someone who is still learning keeps their support', () async {
    final sittings = await practise(
      PlacementTier.beginner,
      quality: 0.45,
      bpm: 55,
      label: 'beginner',
    );

    expect(
      sittings.fold<int>(0, (total, rungs) => total + (rungs[2] ?? 0)),
      0,
      reason: 'failing every retrieval is not how independence is earned',
    );
  });

  test('no sitting teaches the scheduler nothing about retrieval', () async {
    // Support raises predicted success, so as memory weakened the ordinary
    // band came to prefer continuous cueing, which observes no retrieval at
    // all. A whole sitting went by without one attempt that could have said
    // whether the support was still needed, and the preference persisted on
    // evidence that could never arrive.
    final sittings = await practise(
      PlacementTier.someExperience,
      quality: 0.8,
      bpm: 80,
      label: 'middle  ',
    );

    for (final (index, rungs) in sittings.indexed) {
      final observing = (rungs[1] ?? 0) + (rungs[2] ?? 0);
      expect(
        observing,
        greaterThan(0),
        reason:
            'sitting $index was practised entirely under continuous cueing, '
            'so it produced no evidence about the question the scheduler was '
            'implicitly answering when it chose that support',
      );
    }
  });
}
