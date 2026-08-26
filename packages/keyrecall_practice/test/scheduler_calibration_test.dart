import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// Three learners, told apart by how they answer rather than by what they were
/// asked to declare, driven through the real loop.
///
/// A calibration instrument, not a golden file. What it asserts is
/// architectural: that a capable learner is found out quickly, that a
/// struggling one is not handed material they have no base for, and that
/// nobody is left permanently on a support rung because every slot went to an
/// exception. The numbers it prints are outputs and are meant to move when
/// policy does; pinning them would make every deliberate change look like a
/// regression.
void main() {
  /// Runs [attempts] decisions, answering each one as a learner of [quality]
  /// who plays everything at [bpm] regardless of what was asked.
  Future<
    ({
      int slots,
      Map<int, int> rungs,
      Map<String, int> bypasses,
      int? firstTempoProbe,
      int? firstUnguided,
      int? firstAlteredMinor,
      int distinctMaterials,
    })
  >
  run(
    PlacementTier placement, {
    required double quality,
    required double bpm,
    int attempts = 60,
  }) async {
    final session = await openSession(
      InMemoryPracticeStore(createdAt: t0),
      placement: placement,
      materials: allScales,
    );

    final rungs = <int, int>{};
    final bypasses = <String, int>{};
    final seen = <String>{};
    int? firstTempoProbe;
    int? firstUnguided;
    int? firstAlteredMinor;
    var slots = 0;

    for (var i = 0; i < attempts; i++) {
      final presented = await session.decide(at: t0.plusDays(0.5 * i));
      if (presented == null) continue;
      slots++;
      final exercise = presented.exercise;
      final independence = exercise.guidance.independence;
      final bypass = presented.decision.decision.challengeBypass;

      seen.add(exercise.material.materialId);
      rungs[independence] = (rungs[independence] ?? 0) + 1;
      final label = bypass?.id ?? 'ordinary';
      bypasses[label] = (bypasses[label] ?? 0) + 1;
      if (bypass == ChallengeBypass.tempoProbe) firstTempoProbe ??= slots;
      if (independence == 2) firstUnguided ??= slots;
      if (!coreForms.contains(exercise.material.form)) {
        firstAlteredMinor ??= slots;
      }

      final observed = exercise.guidance.isRetrievalObserved;
      await session.commit(
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
      );
    }

    return (
      slots: slots,
      rungs: rungs,
      bypasses: bypasses,
      firstTempoProbe: firstTempoProbe,
      firstUnguided: firstUnguided,
      firstAlteredMinor: firstAlteredMinor,
      distinctMaterials: seen.length,
    );
  }

  void report(String label, dynamic r) {
    print(
      '$label slots=${r.slots} '
      'rungs(cued/prev/unguided)='
      '${r.rungs[0] ?? 0}/${r.rungs[1] ?? 0}/${r.rungs[2] ?? 0} '
      'firstTempoProbe=${r.firstTempoProbe} '
      'firstUnguided=${r.firstUnguided} '
      'firstAlteredMinor=${r.firstAlteredMinor} '
      'distinct=${r.distinctMaterials} '
      'bypasses=${r.bypasses}',
    );
  }

  test('a capable learner is found out quickly', () async {
    final r = await run(PlacementTier.advanced, quality: 1.0, bpm: 110);
    report('advanced ', r);

    expect(
      r.firstTempoProbe,
      isNotNull,
      reason: 'playing everything well above tempo has to be noticed',
    );
    expect(r.firstTempoProbe, lessThan(10));
    expect(
      r.firstUnguided,
      isNotNull,
      reason:
          'someone who retrieves everything cleanly must eventually be '
          'asked to do it without the notes first',
    );
  });

  test('a middling learner settles rather than being pushed', () async {
    final r = await run(PlacementTier.someExperience, quality: 0.8, bpm: 80);
    report('middle   ', r);

    expect(
      r.firstTempoProbe,
      isNull,
      reason: 'playing at the tempo asked for is not being underchallenged',
    );
    expect(r.firstUnguided, isNotNull);
  });

  test(
    'a struggling learner is not handed what they have no base for',
    () async {
      final r = await run(PlacementTier.beginner, quality: 0.45, bpm: 55);
      report('beginner ', r);

      expect(
        r.firstAlteredMinor,
        isNull,
        reason:
            'the breadth gate exists so an altered minor form does not '
            'arrive while ordinary scales are still unsettled',
      );
      expect(r.firstTempoProbe, isNull);
    },
  );

  test('the ladder moves in whichever direction the answers point', () async {
    // The failure this instrument was written to catch: every mechanism
    // behaving correctly on its own while nothing ever climbs, so the learner
    // spends a whole sitting on a support rung and the exceptional paths have
    // quietly become the only path.
    //
    // Being admitted by an exception is not itself the fault, and there is no
    // rule here that ordinary ranking must win every so often: a learner can
    // legitimately spend a long stretch in recovery. What must not happen is
    // that succeeding leaves the rung where it was.
    for (final (label, placement, quality, bpm) in [
      ('advanced', PlacementTier.advanced, 1.0, 110.0),
      ('middle', PlacementTier.someExperience, 0.8, 80.0),
    ]) {
      final r = await run(placement, quality: quality, bpm: bpm);
      expect(
        r.rungs[2] ?? 0,
        greaterThan(0),
        reason:
            '$label retrieved everything asked of it and was never once '
            'asked to play from memory unaided',
      );
    }

    // And the other direction. Someone failing everything should be met with
    // more support, not left to fail unaided.
    final struggling = await run(
      PlacementTier.beginner,
      quality: 0.45,
      bpm: 55,
    );
    expect(struggling.rungs[0] ?? 0, greaterThan(0));
  });
}
