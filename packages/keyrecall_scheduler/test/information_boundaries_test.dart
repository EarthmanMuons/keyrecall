import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// These tests prove the four-stage information-boundary contract holds
/// mechanically: that an input a stage may not read cannot move its decision,
/// and that the trace distinguishes a real decision from a diagnostic value.
///
/// They say nothing about whether the resulting behavior is good. That is what
/// the longitudinal scenarios in keyrecall_simulation are for.
void main() {
  group('stage 1, generation', () {
    test('depends only on domain and instrument inputs', () {
      final beginner = stateAt(PlacementTier.beginner);
      final advanced = stateAt(PlacementTier.advanced);
      final busySession = SessionState(
        attemptsThisSession: 30,
        recentMaterialIds: ['C_MAJOR', 'C_MAJOR'],
        lastFailedExercise: exerciseFor(materials.first),
      );

      final fromBeginner = pipeline.evaluate(
        state: beginner,
        session: SessionState(),
        candidates: allCandidates(),
        at: t0,
      );
      final fromAdvanced = pipeline.evaluate(
        state: advanced,
        session: busySession,
        candidates: allCandidates(),
        at: t0,
      );

      expect(
        fromBeginner.map((trace) => trace.exercise).toSet(),
        fromAdvanced.map((trace) => trace.exercise).toSet(),
      );
    });

    test('never offers an exercise the instrument cannot play', () {
      final tiny = generateCandidates(
        InstrumentProfile(keyCount: 12),
        materials,
      );
      expect(tiny, isNotEmpty);
      expect(
        tiny.every((exercise) => exercise.conditions.octaves == 1),
        isTrue,
      );
    });
  });

  group('stage 2a, eligibility', () {
    test('reads competencies and factual history, never an estimate', () {
      final state = stateAt(PlacementTier.advanced);
      final exercise = exerciseFor(
        materials.first,
        hands: HandConfiguration.together,
      );
      final materialId = materials.first.materialId;
      final memory = state.materialMemoryFor(materialId, learnerParams);
      final before = pipeline.eligibilityFor(state, exercise);

      memory
        ..logCurrentHalfLife = math.log(0.001)
        ..logConsolidatedHalfLife = math.log(0.001);
      state
              .materialExecutionFor(
                (materialId, HandConfiguration.together, HandMotion.parallel),
                t0,
                learnerParams,
              )
              .residualMean =
          -5.0;

      expect(pipeline.eligibilityFor(state, exercise).tier, before.tier);

      state.competency(Competency.rhScaleExecution).mean = -5.0;
      state.competency(Competency.lhScaleExecution).mean = -5.0;
      expect(
        pipeline.eligibilityFor(state, exercise).tier,
        EligibilityTier.provisionallyEligible,
      );
    });

    test('breaks a drought of unobserved retrieval whatever the odds', () {
      // The loop this exists to cut: support raises predicted success, so as
      // memory weakens the ordinary band prefers the rung that observes
      // nothing, and the preference then rests on evidence that can never
      // arrive.
      final state = stateAt(PlacementTier.beginner);
      final previewed = exerciseFor(
        materials.first,
        guidance: GuidanceContext.notesPreviewedOnly,
        // A probe holds every axis but the one it asks about, and this learner
        // has no frontier, so the tempo it holds is the gentle one.
        tempoBpm: config.eligibility.gentleTempoBpm,
      );

      final quiet = SessionState(
        supportedAttemptsSinceObservation:
            config.probe.supportedAttemptsBeforeObservation,
      );
      final busy = SessionState(supportedAttemptsSinceObservation: 0);

      List<CandidateTrace> tracesUnder(SessionState session) =>
          pipeline.evaluate(
            state: state,
            session: session,
            candidates: [previewed],
            at: t0,
          );

      final duringDrought = tracesUnder(quiet).single;
      expect(duringDrought.challengeBypass, ChallengeBypass.observationProbe);
      expect(duringDrought.isRanked, isTrue);
      expect(
        duringDrought.isWithinChallengeBand,
        isFalse,
        reason:
            'the point is that it is admitted despite the odds, so a test '
            'where it would have been admitted anyway proves nothing',
      );

      expect(
        tracesUnder(busy).single.challengeBypass,
        isNot(ChallengeBypass.observationProbe),
        reason: 'one supported attempt is not a drought',
      );
    });

    test('reads whether a material was ever retrieved, not how well', () {
      // The form-introduction rule counts retrieved core scales, which is
      // observation history rather than belief: what the learner has actually
      // produced, not how durable the model thinks it is. Estimates stay on
      // prediction's side of the stage boundary.
      final state = stateAt(PlacementTier.someExperience);
      state.competency(Competency.naturalMinorTopology).mean = 0.5;
      // The foundation conditions are about which channels have been
      // observed, and are satisfied here so that what is left to decide it is
      // the retrieval history this test is about.
      for (final competency in [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
        Competency.handsTogetherCoordination,
      ]) {
        state.competency(competency).lastEvidenceAt = t0;
      }
      final harmonic = exerciseFor(
        TechnicalMaterial('A', ScaleForm.harmonicMinor),
        guidance: GuidanceContext.notesPreviewedOnly,
      );

      final before = pipeline.eligibilityFor(state, harmonic);
      expect(before.code, EligibilityReason.harmonicMinorRepertoireBreadth);

      for (final material in allScales) {
        if (!coreForms.contains(material.form)) continue;
        final memory = state.materialMemoryFor(
          material.materialId,
          learnerParams,
        );
        // Every core scale retrieved once by both hands, and every one of them
        // believed to be on the point of being forgotten.
        memory
          ..factualLastRetrievalAt = t0
          ..logCurrentHalfLife = math.log(0.001)
          ..logConsolidatedHalfLife = math.log(0.001);
        for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
          state
                  .materialExecutionFor(
                    (material.materialId, hands, HandMotion.parallel),
                    t0,
                    learnerParams,
                  )
                  .lastEvidenceAt =
              t0;
        }
      }

      expect(
        pipeline.eligibilityFor(state, harmonic).tier,
        EligibilityTier.fullyEligible,
        reason:
            'the base is what was played, and how durable it is now is a '
            'question for the stage that predicts',
      );
    });

    test('reads the presence of history, which is a rung question', () {
      final state = stateAt(PlacementTier.advanced);
      final material = materials.first;

      // The same capable learner, the same exercise: only whether this app has
      // ever seen the material separates the two answers.
      expect(
        pipeline.eligibilityFor(state, exerciseFor(material)).code,
        EligibilityReason.unseenMaterialRequiresCue,
      );
      state.materialMemoryFor(material.materialId, learnerParams);
      expect(
        pipeline.eligibilityFor(state, exerciseFor(material)).code,
        isNot(EligibilityReason.unseenMaterialRequiresCue),
      );
    });

    test('applies no prerequisite to single-hand work at one octave', () {
      final state = stateAt(PlacementTier.beginner);
      seedAllMaterials(state);
      for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
        expect(
          pipeline
              .eligibilityFor(state, exerciseFor(materials.first, hands: hands))
              .tier,
          EligibilityTier.fullyEligible,
        );
      }
    });
  });

  group('stage 2b, safety', () {
    test('depends only on session state', () {
      final session = SessionState(attemptsThisSession: 5);
      final fromBeginner = pipeline.evaluate(
        state: stateAt(PlacementTier.beginner),
        session: session,
        candidates: allCandidates().take(50).toList(),
        at: t0,
      );
      final fromAdvanced = pipeline.evaluate(
        state: stateAt(PlacementTier.advanced),
        session: session,
        candidates: allCandidates().take(50).toList(),
        at: t0,
      );

      for (var i = 0; i < fromBeginner.length; i++) {
        expect(fromBeginner[i].safety, fromAdvanced[i].safety);
      }
    });

    test('suppresses exactly at the session cap', () {
      const cap = 40;
      final bounded = SchedulerPipeline(
        learner: learner,
        config: boundedTo(cap),
      );
      expect(
        bounded.safetyFor(SessionState(attemptsThisSession: cap - 1)).isAllowed,
        isTrue,
      );
      expect(
        bounded.safetyFor(SessionState(attemptsThisSession: cap)).isAllowed,
        isFalse,
      );
    });

    test('an unbounded sitting is never suppressed by its length', () {
      expect(config.safety.maxSessionAttempts, isNull);
      expect(
        pipeline.safetyFor(SessionState(attemptsThisSession: 1000)).isAllowed,
        isTrue,
        reason: 'a sitting ends when the player stops, not at a constant',
      );
    });
  });

  group('stage 3, challenge admission', () {
    test('ignores the priority terms', () {
      final state = stateAt(PlacementTier.beginner);
      seedAllMaterials(state);
      final candidates = allCandidates();

      final quiet = pipeline.evaluate(
        state: state,
        session: SessionState(),
        candidates: candidates,
        at: t0,
      );
      final withHistory = pipeline.evaluate(
        state: state,
        session: SessionState(
          attemptsThisSession: 3,
          recentMaterialIds: List.filled(5, 'C_MAJOR'),
        ),
        candidates: candidates,
        at: t0,
      );

      final byExercise = tracesByExercise(withHistory);
      for (final trace in quiet) {
        expect(
          trace.isWithinChallengeBand,
          byExercise[trace.exercise]!.isWithinChallengeBand,
        );
      }
    });

    test('is unmoved by what the information term reads', () {
      final low = stateAt(PlacementTier.beginner);
      final high = stateAt(PlacementTier.beginner);
      for (final competency in Competency.values) {
        high.competency(competency).variance =
            low.competency(competency).variance * 50.0;
      }
      seedAllMaterials(low);
      seedAllMaterials(high);

      final candidates = allCandidates();
      final lowTraces = pipeline.evaluate(
        state: low,
        session: SessionState(),
        candidates: candidates,
        at: t0,
      );
      final highTraces = tracesByExercise(
        pipeline.evaluate(
          state: high,
          session: SessionState(),
          candidates: candidates,
          at: t0,
        ),
      );

      var sawInformationDifference = false;
      for (final trace in lowTraces) {
        final other = highTraces[trace.exercise]!;
        if ((trace.terms.information - other.terms.information).abs() > 1e-9) {
          sawInformationDifference = true;
        }
        expect(trace.isWithinChallengeBand, other.isWithinChallengeBand);
        expect(trace.challengeBypass, other.challengeBypass);
      }
      expect(sawInformationDifference, isTrue);
    });

    test('bypasses are independent of the band decision', () {
      final fresh = stateAt(PlacementTier.beginner);
      final seeded = stateAt(PlacementTier.beginner);
      seedAllMaterials(seeded);
      final candidates = allCandidates();

      final freshTraces = pipeline.evaluate(
        state: fresh,
        session: SessionState(),
        candidates: candidates,
        at: t0,
      );
      final seededTraces = tracesByExercise(
        pipeline.evaluate(
          state: seeded,
          session: SessionState(),
          candidates: candidates,
          at: t0,
        ),
      );

      var sawBypassChange = false;
      for (final trace in freshTraces) {
        final other = seededTraces[trace.exercise]!;
        expect(trace.isWithinChallengeBand, other.isWithinChallengeBand);
        if (trace.challengeBypass != other.challengeBypass) {
          sawBypassChange = true;
        }
      }
      expect(sawBypassChange, isTrue);
    });

    test('activation movement does not reset factual probe history', () {
      final state = stateAt(PlacementTier.advanced);
      final memory = state.materialMemoryFor(
        materials.first.materialId,
        learnerParams,
      );
      memory
        ..memoryAnchorAt = t0
        ..factualLastRetrievalAt = t0
        ..lastRetrievalAttemptAt = t0
        // Established with the notes previewed, so the rung above it is what
        // a probe would ask for next.
        ..establishedIndependence =
            GuidanceContext.notesPreviewedOnly.independence
        ..establishedIndependenceAt = t0;

      final probe = exerciseFor(
        materials.first,
        tempoBpm: config.eligibility.gentleTempoBpm,
      );
      final at = t0.plusDays(config.probe.minDaysSinceLastRetrieval + 1.0);
      expect(pipeline.isGuidanceProbe(state, probe, at), isTrue);

      // Supported practice restores activation without changing the factual
      // success. If probe timing read the anchor, this would make the same
      // candidate look too recent.
      memory.memoryAnchorAt = at.plusDays(-0.1);
      expect(pipeline.isGuidanceProbe(state, probe, at), isTrue);
    });
  });

  group('stage 4, priority ranking', () {
    test('ranks only candidates that really reached it', () {
      final state = stateAt(PlacementTier.advanced);
      seedAllMaterials(state);
      final candidates = allCandidates();

      // A bounded sitting is the one deterministic way to suppress every
      // candidate at stage 2b, which is what this needs to observe.
      const cap = 40;
      final suppressed =
          SchedulerPipeline(learner: learner, config: boundedTo(cap)).evaluate(
            state: state,
            session: SessionState(attemptsThisSession: cap),
            candidates: candidates,
            at: t0,
          );
      expect(
        suppressed.any((trace) => trace.priorityStatus.isReached),
        isFalse,
      );
      expect(suppressed.any((trace) => trace.rankKey != null), isFalse);
      expect(pipeline.selectBest(suppressed), isNull);
      // The diagnostic prediction survives suppression.
      expect(
        suppressed.every((trace) => trace.prediction.overallP >= 0.0),
        isTrue,
      );

      final open = pipeline.evaluate(
        state: state,
        session: SessionState(),
        candidates: candidates,
        at: t0,
      );
      final rejected = open
          .where(
            (trace) =>
                trace.challengeBypass == null && !trace.isWithinChallengeBand,
          )
          .toList();
      expect(rejected, isNotEmpty);
      for (final trace in rejected) {
        expect(trace.priorityStatus.isReached, isFalse);
        expect(trace.rankKey, isNull);
        expect(trace.challengeSurvived, isFalse);
      }
      expect(pipeline.selectBest(open)?.priorityStatus.isReached, isTrue);
    });

    test('a provisional tier never outranks a fully eligible one', () {
      // The provisional candidate is stacked to dominate every secondary
      // criterion, so a pass can only mean the tier decided it.
      final provisionalExercise = exerciseFor(
        materials[0],
        hands: HandConfiguration.together,
      );
      final fullyExercise = exerciseFor(materials[3]);

      final state = stateAt(PlacementTier.beginner);
      // Both candidates are unguided, so both need history here for the tier
      // to be about the prerequisite under test.
      seedAllMaterials(state);
      for (final competency in Competency.values) {
        state.competency(competency).variance = 0.05;
      }
      for (final competency in [
        Competency.majorScaleTopology,
        Competency.lhScaleExecution,
        Competency.handsTogetherCoordination,
      ]) {
        state.competency(competency).variance = 100.0;
      }

      final session = SessionState(
        recentMaterialIds: List.filled(5, materials[3].materialId),
      );
      final traces = pipeline.evaluate(
        state: state,
        session: session,
        candidates: [provisionalExercise, fullyExercise],
        at: t0,
        overrides: {
          provisionalExercise: ChallengeBypass.override,
          fullyExercise: ChallengeBypass.override,
        },
      );
      final byExercise = tracesByExercise(traces);
      final provisional = byExercise[provisionalExercise]!;
      final fully = byExercise[fullyExercise]!;

      expect(
        provisional.eligibility.tier,
        EligibilityTier.provisionallyEligible,
      );
      expect(fully.eligibility.tier, EligibilityTier.fullyEligible);
      expect(
        provisional.terms.retention,
        greaterThanOrEqualTo(fully.terms.retention),
      );
      expect(
        provisional.terms.information,
        greaterThan(fully.terms.information),
      );
      expect(provisional.terms.diversity, greaterThan(fully.terms.diversity));

      expect(pipeline.selectBest(traces), same(fully));
    });

    test('does not re-consume challenge difficulty', () {
      final exercise = exerciseFor(materials.first);
      final low = stateAt(PlacementTier.beginner);
      final high = stateAt(PlacementTier.beginner);
      high.competency(Competency.rhScaleExecution).mean = 20.0;
      seedAllMaterials(low);
      seedAllMaterials(high);

      List<CandidateTrace> evaluate(LearnerState state) => pipeline.evaluate(
        state: state,
        session: SessionState(),
        candidates: [exercise],
        at: t0,
        overrides: {exercise: ChallengeBypass.override},
      );

      final lowTrace = evaluate(low).single;
      final highTrace = evaluate(high).single;

      expect(
        (lowTrace.prediction.overallP - highTrace.prediction.overallP).abs(),
        greaterThan(0.1),
      );
      expect(lowTrace.rankKey, highTrace.rankKey);
    });
  });

  group('named exceptions', () {
    test('new material bypasses the band and reaches ranking', () {
      final traces = pipeline.evaluate(
        state: stateAt(PlacementTier.beginner),
        session: SessionState(),
        candidates: allCandidates(),
        at: t0,
      );
      final introduced = traces
          .where(
            (trace) => trace.challengeBypass == ChallengeBypass.newMaterial,
          )
          .toList();

      expect(introduced, isNotEmpty);
      for (final trace in introduced) {
        expect(trace.challengeSurvived, isTrue);
        expect(trace.priorityStatus.isReached, isTrue);
      }
    });

    test('recovery admits the exact target and nothing else', () {
      final state = stateAt(PlacementTier.beginner);
      seedAllMaterials(state);
      final failed = exerciseFor(materials.first);
      final target = recoveryTarget(failed);

      final traces = pipeline.evaluate(
        state: state,
        session: SessionState(lastFailedExercise: failed),
        candidates: allCandidates(),
        at: t0,
      );
      final survivors = traces
          .where((trace) => trace.challengeSurvived)
          .toList();

      expect(survivors, hasLength(1));
      expect(survivors.single.exercise, target);
      expect(survivors.single.challengeBypass, ChallengeBypass.recovery);
      expect(survivors.single.priorityStatus.isReached, isTrue);
    });

    test('an override admits a candidate the state would not', () {
      final state = stateAt(PlacementTier.beginner);
      seedAllMaterials(state);
      final candidate = allCandidates().first;

      final trace = pipeline
          .evaluate(
            state: state,
            session: SessionState(),
            candidates: [candidate],
            at: t0,
            overrides: {candidate: ChallengeBypass.override},
          )
          .single;

      expect(trace.challengeBypass, ChallengeBypass.override);
      expect(trace.challengeSurvived, isTrue);
      expect(trace.priorityStatus.isReached, isTrue);
    });
  });

  test('consolidation alone has no immediate scheduler effect', () {
    final withoutHeadroom = stateAt(PlacementTier.advanced);
    final withHeadroom = stateAt(PlacementTier.advanced);
    seedAllMaterials(withoutHeadroom);
    seedAllMaterials(withHeadroom);
    for (final memory in withHeadroom.materialMemory.values) {
      memory.logConsolidatedHalfLife = math.log(30.0);
    }

    final candidates = allCandidates();
    final baseline = pipeline.evaluate(
      state: withoutHeadroom,
      session: SessionState(),
      candidates: candidates,
      at: t0,
    );
    final consolidated = tracesByExercise(
      pipeline.evaluate(
        state: withHeadroom,
        session: SessionState(),
        candidates: candidates,
        at: t0,
      ),
    );

    for (final trace in baseline) {
      final other = consolidated[trace.exercise]!;
      expect(trace.eligibility, other.eligibility);
      expect(trace.safety, other.safety);
      expect(trace.prediction, other.prediction);
      expect(trace.isWithinChallengeBand, other.isWithinChallengeBand);
      expect(trace.challengeBypass, other.challengeBypass);
      expect(trace.challengeSurvived, other.challengeSurvived);
      expect(trace.terms, other.terms);
      expect(trace.rankKey, other.rankKey);
    }
  });

  test('cached pipeline predictions match the direct learner model', () {
    final state = stateAt(PlacementTier.advanced);
    final at = t0.plusDays(17);
    final traces = pipeline.evaluate(
      state: state,
      session: SessionState(),
      candidates: generateCandidates(instrument, materials.take(3).toList()),
      at: at,
    );

    for (final trace in traces) {
      expect(
        trace.prediction,
        learner.predict(state, trace.exercise, at: at),
        reason: 'cached prediction differs for ${trace.exercise}',
      );
    }
  });
}
