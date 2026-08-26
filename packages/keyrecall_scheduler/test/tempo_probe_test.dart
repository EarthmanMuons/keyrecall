import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Playing faster than asked changes what is asked next, and nothing else.
void main() {
  final probeConfig = config.probe;

  Exercise at(double tempoBpm) =>
      exerciseFor(materials.first, tempoBpm: tempoBpm);

  Outcome playedAt(
    double tempoRatio, {
    bool completed = true,
    FactualRetrieval retrieval = FactualRetrieval.succeeded,
    double quality = 1.0,
  }) => Outcome(
    started: true,
    retrieval: retrieval,
    completed: completed,
    materialRetrieval: quality,
    pitchIntegrity: quality,
    continuity: quality,
    temporalStability: quality,
    achievedTempoRatio: tempoRatio,
    topologyAccuracy: quality,
  );

  Exercise? probeFor(Exercise exercise, Outcome outcome) => tempoProbeTarget(
    exercise: exercise,
    outcome: outcome,
    config: probeConfig,
  );

  group('what counts as too easy', () {
    test('clean, steady, and comfortably faster than asked', () {
      expect(
        isUnderchallenged(
          exercise: at(60),
          outcome: playedAt(1.6),
          config: probeConfig,
        ),
        isTrue,
      );
    });

    test('rushing is not the same as finding it easy', () {
      // The same speed, and nothing else holding up.
      expect(
        isUnderchallenged(
          exercise: at(60),
          outcome: playedAt(1.6, quality: 0.5),
          config: probeConfig,
        ),
        isFalse,
      );
    });

    test('every condition is required, not most of them', () {
      for (final outcome in [
        playedAt(1.6, completed: false),
        playedAt(1.6, retrieval: FactualRetrieval.notTested),
        playedAt(1.6, retrieval: FactualRetrieval.failed),
        playedAt(1.0),
        playedAt(1.05),
      ]) {
        expect(
          isUnderchallenged(
            exercise: at(60),
            outcome: outcome,
            config: probeConfig,
          ),
          isFalse,
          reason: '$outcome',
        );
      }
    });

    test('reading the notes off the screen says nothing about the task', () {
      final cued = exerciseFor(
        materials.first,
        guidance: GuidanceContext.continuouslyCued,
        tempoBpm: 60,
      );

      expect(
        probeFor(cued, playedAt(1.6, retrieval: FactualRetrieval.notTested)),
        isNull,
      );
    });
  });

  group('what it asks for next', () {
    test('the fastest offered tempo the learner reached', () {
      // 60 played at 1.7 is about 102, so the 100 candidate and not the 120.
      expect(probeFor(at(60), playedAt(1.7))?.conditions.tempoBpm, 100);
    });

    test('nothing when the next offered tempo is out of reach', () {
      expect(probeFor(at(60), playedAt(1.3)), isNull);
      expect(probeFor(at(120), playedAt(2.0)), isNull);
    });

    test('only the tempo moves', () {
      final exercise = at(60);
      final probe = probeFor(exercise, playedAt(1.7))!;

      expect(probe.material, exercise.material);
      expect(probe.guidance, exercise.guidance);
      expect(probe.conditions.hands, exercise.conditions.hands);
      expect(probe.conditions.octaves, exercise.conditions.octaves);
      expect(probe.conditions.direction, exercise.conditions.direction);
    });
  });

  group('what the scheduler does with it', () {
    test('the probe takes the slot, and only the probe', () {
      final exercise = at(60);
      final probe = probeFor(exercise, playedAt(1.7))!;
      final session = SessionState(tempoProbe: probe);

      final traces = pipeline.evaluate(
        state: stateAt(PlacementTier.advanced),
        session: session,
        candidates: allCandidates(),
        at: t0,
      );
      final survivors = traces.where((trace) => trace.isRanked).toList();

      expect(survivors, hasLength(1));
      expect(survivors.single.exercise, probe);
      expect(survivors.single.challengeBypass, ChallengeBypass.tempoProbe);
    });

    test('recovery outranks it, because something went wrong', () {
      final easy = at(60);
      final failed = exerciseFor(materials[1]);
      final session = SessionState(
        lastFailedExercise: failed,
        tempoProbe: probeFor(easy, playedAt(1.7)),
      );

      final traces = pipeline.evaluate(
        state: stateAt(PlacementTier.advanced),
        session: session,
        candidates: allCandidates(),
        at: t0,
      );
      final survivors = traces.where((trace) => trace.isRanked).toList();

      expect(survivors, hasLength(1));
      expect(survivors.single.challengeBypass, ChallengeBypass.recovery);
    });

    test('it lasts exactly one decision', () {
      final session = SessionState(tempoProbe: at(100));

      session.recordSelection(
        at(100),
        retrievalObserved: true,
        retrievalFailed: false,
        config: config.diversity,
      );

      expect(session.tempoProbe, isNull);
    });

    test('the repetition guard does not swallow it', () {
      // Just played five times, which is the cap.
      final exercise = at(60);
      final probe = probeFor(exercise, playedAt(1.7))!;
      final session = SessionState(
        tempoProbe: probe,
        recentMaterialIds: List.filled(5, exercise.material.materialId),
      );

      final traces = pipeline.evaluate(
        state: stateAt(PlacementTier.advanced),
        session: session,
        candidates: allCandidates(),
        at: t0,
      );

      expect(pipeline.selectChoice(traces, session)?.exercise, probe);
    });
  });
}
