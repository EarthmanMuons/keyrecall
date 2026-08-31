import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// A trace with a chosen rank key and everything else admitted.
///
/// Hand-built rather than produced by the pipeline: these tests are about the
/// guard and the ordering themselves, and a real prediction would make which
/// candidate "should" win impossible to control precisely.
CandidateTrace admittedTrace(
  Exercise exercise, {
  required double retention,
  required double information,
}) {
  const prediction = Prediction(
    independentRetrievalP: 0.7,
    materialAvailableP: 0.7,
    executionP: 0.9,
    topologyP: 0.8,
  );
  final terms = RankKey(
    tier: EligibilityTier.fullyEligible,
    retention: retention,
    information: information,
    diversity: 0.0,
    goals: 0.0,
  );
  return CandidateTrace(
    exercise: exercise,
    eligibility: const EligibilityDecision(EligibilityTier.fullyEligible, ''),
    safety: const SafetyDecision(true, ''),
    challengeStatus: StageStatus.reached,
    prediction: prediction,
    isWithinChallengeBand: true,
    challengeBypass: null,
    challengeSurvived: true,
    priorityStatus: StageStatus.reached,
    rankKey: terms,
  );
}

void main() {
  final materialA = materials[0];
  final materialB = materials[1];
  final exerciseA = exerciseFor(materialA);
  final exerciseB = exerciseFor(materialB);

  group('RankKey ordering', () {
    test('the tier decides before any other term', () {
      const provisional = RankKey(
        tier: EligibilityTier.provisionallyEligible,
        retention: 1.0,
        information: 1.0,
        diversity: 1.0,
        goals: 1.0,
      );
      const fully = RankKey(
        tier: EligibilityTier.fullyEligible,
        retention: 0.0,
        information: 0.0,
        diversity: -5.0,
        goals: 0.0,
      );
      expect(provisional.compareTo(fully), lessThan(0));
    });

    test('each term breaks the previous term ties in order', () {
      RankKey key({
        double retention = 0.0,
        double information = 0.0,
        double diversity = 0.0,
        double goals = 0.0,
      }) => RankKey(
        tier: EligibilityTier.fullyEligible,
        retention: retention,
        information: information,
        diversity: diversity,
        goals: goals,
      );

      expect(key(retention: 1).compareTo(key(information: 1)), greaterThan(0));
      expect(key(information: 1).compareTo(key(diversity: 1)), greaterThan(0));
      expect(key(diversity: 1).compareTo(key(goals: 1)), greaterThan(0));
      expect(key().compareTo(key()), 0);
    });
  });

  group('repetition guard', () {
    final cap = config.diversity.maxConsecutiveMaterialAttempts;

    test('excludes an over-repeated material when an alternative exists', () {
      // A dominates on retention, so it would win outright without the guard.
      final traceA = admittedTrace(exerciseA, retention: 0.9, information: 1.0);
      final traceB = admittedTrace(exerciseB, retention: 0.1, information: 0.5);
      expect(pipeline.selectBest([traceA, traceB]), same(traceA));

      final session = SessionState(
        recentMaterialIds: List.filled(cap, materialA.materialId),
      );
      final winner = pipeline.selectChoice([traceA, traceB], session);

      expect(winner, isNotNull);
      expect(winner, same(traceB));
    });

    test('never suppresses the only admitted material', () {
      final traceA = admittedTrace(exerciseA, retention: 0.9, information: 1.0);
      final session = SessionState(
        recentMaterialIds: List.filled(cap, materialA.materialId),
      );

      expect(pipeline.selectChoice([traceA], session), same(traceA));
    });

    test('counts a run, not a total, over the window', () {
      final traceA = admittedTrace(exerciseA, retention: 0.9, information: 1.0);
      final traceB = admittedTrace(exerciseB, retention: 0.1, information: 0.5);
      final interrupted = SessionState(
        recentMaterialIds: [
          ...List.filled(cap, materialA.materialId),
          materialB.materialId,
        ],
      );

      expect(
        pipeline.selectChoice([traceA, traceB], interrupted),
        same(traceA),
      );
    });
  });

  group('selection', () {
    test('returns nothing when nothing was admitted', () {
      expect(pipeline.selectBest(const []), isNull);
      expect(pipeline.selectChoice(const [], SessionState()), isNull);
    });

    test('breaks exact ties toward the earlier candidate', () {
      final first = admittedTrace(exerciseA, retention: 0.5, information: 0.5);
      final second = admittedTrace(exerciseB, retention: 0.5, information: 0.5);

      expect(pipeline.selectBest([first, second]), same(first));
      expect(pipeline.selectBest([second, first]), same(second));
    });
  });

  group('recovery target', () {
    test('changes guidance and nothing else', () {
      final failed = exerciseFor(
        materialA,
        hands: HandConfiguration.left,
        octaves: 2,
        tempoBpm: 100,
      );
      final target = recoveryTarget(failed)!;

      expect(target.guidance, GuidanceContext.notesPreviewedOnly);
      expect(target.conditions, failed.conditions);
      expect(target.material, failed.material);
      expect(target.hasSameRealizationAs(failed), isTrue);
    });

    test('steps one rung at a time toward more support', () {
      final unguided = exerciseFor(materialA);
      final previewed = recoveryTarget(unguided)!;
      final cued = recoveryTarget(previewed)!;

      expect(
        previewed.guidance.independence,
        unguided.guidance.independence - 1,
      );
      expect(cued.guidance, GuidanceContext.continuouslyCued);
      expect(recoveryTarget(cued), isNull);
    });
  });

  group('priority terms', () {
    test('a continuously cued candidate has no retrieval opportunity', () {
      expect(
        retrievalOpportunity(
          exerciseFor(materialA, guidance: GuidanceContext.continuouslyCued),
        ),
        0.0,
      );
      expect(retrievalOpportunity(exerciseFor(materialA)), greaterThan(0.0));
    });

    test('retention is zero for a candidate that cannot test retrieval', () {
      const urgent = Prediction(
        independentRetrievalP: 0.05,
        materialAvailableP: 0.95,
        executionP: 0.9,
        topologyP: 0.8,
      );
      expect(retentionNeed(urgent), closeTo(0.95, 1e-12));
      expect(
        retention(
          urgent,
          exerciseFor(materialA, guidance: GuidanceContext.continuouslyCued),
        ),
        0.0,
      );
      expect(retention(urgent, exerciseFor(materialA)), greaterThan(0.0));
    });

    test('diversity penalizes recent selections of the same material', () {
      final session = SessionState(
        recentMaterialIds: [materialA.materialId, materialA.materialId],
      );
      expect(diversity(exerciseA, session), -2.0);
      expect(diversity(exerciseB, session), 0.0);
    });

    test('goals stay explicitly zero until a goal model exists', () {
      expect(goals(exerciseA), 0.0);
      expect(goals(exerciseB), 0.0);
    });
  });

  group('session state', () {
    test('opens a recovery context only on a tested failure', () {
      final session = SessionState();

      session.recordSelection(
        exerciseA,
        retrievalObserved: true,
        retrievalFailed: true,
        config: config.diversity,
      );
      expect(session.lastFailedExercise, exerciseA);

      session.recordSelection(
        exerciseB,
        retrievalObserved: true,
        retrievalFailed: false,
        config: config.diversity,
      );
      expect(session.lastFailedExercise, isNull);
    });

    test('trims the recency window to its configured size', () {
      final session = SessionState();
      for (var i = 0; i < config.diversity.recentWindow + 5; i++) {
        session.recordSelection(
          exerciseA,
          retrievalObserved: true,
          retrievalFailed: false,
          config: config.diversity,
        );
      }
      expect(
        session.recentMaterialIds,
        hasLength(config.diversity.recentWindow),
      );
    });
  });
}
