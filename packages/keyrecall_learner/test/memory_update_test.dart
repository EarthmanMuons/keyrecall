import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// A state whose C major memory has the given history and durability.
(LearnerState, MaterialMemoryState) anchoredState({
  DateTime? anchorAt,
  double? currentHalfLifeDays,
  double? consolidatedHalfLifeDays,
}) {
  final state = model.newState(at: t0);
  final memory = state.materialMemoryFor(cMajor.materialId, params);
  if (anchorAt != null) {
    anchorMemory(
      memory,
      anchorAt,
      currentHalfLifeDays: currentHalfLifeDays,
      consolidatedHalfLifeDays: consolidatedHalfLifeDays,
    );
  }
  return (state, memory);
}

/// Repeats an unguided failure against an anchored memory and returns the
/// log current half-life after each attempt.
List<double> repeatedAnchoredFailures(int attempts) {
  final (state, memory) = anchoredState(anchorAt: t0);
  final exercise = exerciseFor(cMajor);
  var at = t0;
  return [
    for (var i = 0; i < attempts; i++) ...[
      () {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        applyAttempt(state, exercise, failedToStart(), at: at);
        return memory.logCurrentHalfLife;
      }(),
    ],
  ];
}

/// The same, for a memory that never anchors, so the cold-start belief stays
/// the operative quantity throughout.
List<double> repeatedColdStartFailures(int attempts) {
  final state = model.newState(at: t0);
  final exercise = exerciseFor(cMajor);
  var at = t0;
  return [
    for (var i = 0; i < attempts; i++) ...[
      () {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        applyAttempt(state, exercise, failedToStart(), at: at);
        return state.materialMemory[cMajor.materialId]!.coldStartEstimate;
      }(),
    ],
  ];
}

void main() {
  final exercise = exerciseFor(cMajor);
  final cued = exerciseFor(cMajor, guidance: GuidanceContext.continuouslyCued);

  group('the first success', () {
    test('forms memory without manufacturing interval evidence', () {
      final (state, memory) = anchoredState();
      final currentBefore = memory.currentHalfLifeDays;
      final consolidationBefore = memory.consolidatedHalfLifeDays;
      final uncertaintyBefore = memory.currentHalfLifeUncertainty;
      final posteriorVarianceBefore = memory.consolidatedLogHalfLifeVariance;

      final diagnostics = applyAttempt(
        state,
        exercise,
        perfectOutcome(),
        at: t0.plusDays(1),
      );

      expect(memory.memoryAnchorAt, t0.plusDays(1));
      expect(memory.factualLastRetrievalAt, t0.plusDays(1));
      expect(memory.currentHalfLifeDays, greaterThan(currentBefore));
      expect(memory.consolidatedHalfLifeDays, greaterThan(consolidationBefore));

      // No anchored interval preceded it, so nothing was learned about the
      // forgetting rate, however well the attempt went.
      expect(memory.currentHalfLifeUncertainty, uncertaintyBefore);
      expect(memory.consolidatedLogHalfLifeVariance, posteriorVarianceBefore);
      expect(diagnostics.consolidationDeltaFromRetrievalInference, 0.0);
    });
  });

  group('retained-durability inference', () {
    test('does not run when retrieval was never tested', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 3.0,
        consolidatedHalfLifeDays: 20.0,
      );
      final varianceBefore = memory.consolidatedLogHalfLifeVariance;

      final diagnostics = applyAttempt(
        state,
        cued,
        cuedOutcome(),
        at: t0.plusDays(14),
      );

      expect(diagnostics.consolidationDeltaFromRetrievalInference, 0.0);
      expect(memory.consolidatedLogHalfLifeVariance, varianceBefore);
    });

    test('does not run over a near-zero interval', () {
      for (final retrieval in [
        FactualRetrieval.succeeded,
        FactualRetrieval.failed,
      ]) {
        final (state, _) = anchoredState(
          anchorAt: t0,
          currentHalfLifeDays: 3.0,
          consolidatedHalfLifeDays: 20.0,
        );
        final at = t0.plusDays(
          params.materialMemory.retainedInferenceMinIntervalDays / 2.0,
        );

        final diagnostics = applyAttempt(
          state,
          exercise,
          perfectOutcome(retrieval: retrieval),
          at: at,
        );
        expect(diagnostics.consolidationDeltaFromRetrievalInference, 0.0);
      }
    });

    test('lowers inferred consolidation after a long-interval failure', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 3.0,
        consolidatedHalfLifeDays: 20.0,
      );

      final diagnostics = applyAttempt(
        state,
        exercise,
        perfectOutcome(retrieval: FactualRetrieval.failed),
        at: t0.plusDays(14),
      );

      expect(
        diagnostics.consolidationDeltaFromRetrievalInference,
        lessThan(0.0),
      );
      expect(
        memory.currentHalfLifeDays,
        lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
      );
      expect(
        memory.consolidatedHalfLifeDays,
        lessThanOrEqualTo(params.materialMemory.maxMemoryHalfLifeDays),
      );
    });

    test('reads the interval, not how well the attempt was played', () {
      final inferenceDeltas = <double>[];
      final formationDeltas = <double>[];

      for (final quality in [0.2, 1.0]) {
        final (state, memory) = anchoredState(
          anchorAt: t0,
          currentHalfLifeDays: 3.0,
        );
        final diagnostics = applyAttempt(
          state,
          exercise,
          successOfQuality(quality),
          at: t0.plusDays(14),
        );
        inferenceDeltas.add(
          diagnostics.consolidationDeltaFromRetrievalInference,
        );
        formationDeltas.add(diagnostics.consolidationDeltaFromCausalFormation);
        expect(
          memory.currentHalfLifeDays,
          lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
        );
      }

      expect(inferenceDeltas[0], closeTo(inferenceDeltas[1], 1e-12));
      expect(formationDeltas[1], greaterThan(formationDeltas[0]));
      expect(formationDeltas[0], greaterThan(0.0));
    });

    test('keeps projection error as uncertainty, not as confidence', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 30.0,
        consolidatedHalfLifeDays: 30.0,
      );

      applyAttempt(
        state,
        exercise,
        perfectOutcome(retrieval: FactualRetrieval.failed),
        at: t0.plusDays(20),
      );

      expect(
        memory.consolidatedLogHalfLifeVariance,
        greaterThanOrEqualTo(params.materialMemory.consolidationMinLogVariance),
      );
      expect(
        memory.logConsolidatedHalfLife,
        greaterThanOrEqualTo(memory.logCurrentHalfLife),
      );
    });
  });

  group('causal formation', () {
    test('a success creates headroom beyond the prior envelope', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 20.0,
      );

      applyAttempt(state, exercise, perfectOutcome(), at: t0.plusDays(1));

      expect(memory.consolidatedHalfLifeDays, greaterThan(20.0));
      expect(memory.currentHalfLifeDays, greaterThan(20.0));
      expect(
        memory.currentHalfLifeDays,
        lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
      );
    });

    test('supported practice with no headroom inflates nothing', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 20.0,
      );

      applyAttempt(state, cued, cuedOutcome(), at: t0.plusDays(1));

      expect(memory.currentHalfLifeDays, closeTo(20.0, 1e-9));
      expect(memory.consolidatedHalfLifeDays, closeTo(20.0, 1e-9));
    });

    test('a success cannot end below its pre-attempt durability', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 20.0,
        consolidatedHalfLifeDays: 30.0,
      );
      final at = t0.plusDays(0.01);
      final outcome = perfectOutcome();
      final weights = evidenceWeightsFor(exercise, outcome);
      final prediction = model.predict(state, exercise, at: at);
      final currentBefore = memory.currentHalfLifeDays;

      // Confirm the setup really does produce a downward evidence-only
      // correction, so the guarantee is actually under test.
      final memoryParams = params.materialMemory;
      final corrected =
          memory.logCurrentHalfLife +
          weights.materialMemory *
              (memoryParams.alphaCurrentDurability *
                      (1.0 - prediction.independentRetrievalP) -
                  memoryParams.reversionLambdaCurrentDurability *
                      (memory.logCurrentHalfLife -
                          math.log(memoryParams.initialCurrentHalfLifeDays)));
      final correctedDays = math.exp(
        math.min(
          math.max(corrected, math.log(memoryParams.minHalfLifeDays)),
          memory.logConsolidatedHalfLife,
        ),
      );
      expect(correctedDays, lessThan(currentBefore));

      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: weights,
        prediction: prediction,
        at: at,
      );

      expect(
        memory.currentHalfLifeDays,
        greaterThanOrEqualTo(currentBefore - 1e-12),
      );
      expect(
        memory.currentHalfLifeDays,
        lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
      );
    });

    test('repeated spaced successes strengthen both durabilities', () {
      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 4.0,
        consolidatedHalfLifeDays: 20.0,
      );

      for (final days in [2.0, 4.0, 8.0]) {
        applyAttempt(state, exercise, perfectOutcome(), at: t0.plusDays(days));
      }

      expect(memory.currentHalfLifeDays, greaterThan(4.0));
      expect(memory.consolidatedHalfLifeDays, greaterThan(20.0));
      expect(
        memory.currentHalfLifeDays,
        lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
      );
    });

    test('supported practice never writes factual retrieval history', () {
      final (state, memory) = anchoredState(anchorAt: t0);
      final factualBefore = memory.factualLastRetrievalAt;
      final attemptBefore = memory.lastRetrievalAttemptAt;

      applyAttempt(state, cued, cuedOutcome(), at: t0.plusDays(10));

      expect(memory.factualLastRetrievalAt, factualBefore);
      expect(memory.lastRetrievalAttemptAt, attemptBefore);
      // It may still move activation partway toward the present.
      expect(memory.memoryAnchorAt!.isAfter(t0), isTrue);
      expect(memory.memoryAnchorAt!.isBefore(t0.plusDays(10)), isTrue);
    });
  });

  group('surprise', () {
    test('a surprising success increases retention', () {
      final (state, memory) = anchoredState(anchorAt: t0);
      final at = t0.plusDays(30);
      model.propagate(state, at);
      final before = memory.logCurrentHalfLife;

      applyAttempt(state, exercise, perfectOutcome(), at: at);

      expect(memory.logCurrentHalfLife, greaterThan(before));
    });

    test('a surprising failure decreases retention', () {
      final (state, memory) = anchoredState(anchorAt: t0);
      final at = t0.plusDays(0.1);
      model.propagate(state, at);
      final before = memory.logCurrentHalfLife;

      applyAttempt(state, exercise, failedToStart(), at: at);

      expect(memory.logCurrentHalfLife, lessThan(before));
    });
  });

  group('untested retrieval', () {
    test('never moves durability, however often it repeats', () {
      for (final initial in [100.0, 0.5]) {
        final (state, memory) = anchoredState(
          anchorAt: t0,
          currentHalfLifeDays: initial,
        );
        final before = memory.logCurrentHalfLife;

        var at = t0;
        for (var i = 0; i < 50; i++) {
          at = at.plusDays(0.5);
          model.propagate(state, at);
          expect(evidenceWeightsFor(cued, cuedOutcome()).materialMemory, 0.0);
          applyAttempt(state, cued, cuedOutcome(), at: at);
        }

        expect(memory.logCurrentHalfLife, before);
      }
    });

    test('a genuinely observed low-demand failure still accumulates', () {
      final previewed = exerciseFor(
        cMajor,
        guidance: GuidanceContext.notesPreviewedOnly,
      );
      final outcome = Outcome(
        started: true,
        retrieval: FactualRetrieval.failed,
        completed: true,
        materialRetrieval: 0.0,
        pitchIntegrity: 0.0,
        continuity: 1.0,
        temporalStability: 1.0,
        achievedTempoRatio: 1.0,
        topologyAccuracy: 1.0,
      );

      final (state, memory) = anchoredState(
        anchorAt: t0,
        currentHalfLifeDays: 100.0,
      );
      final before = memory.logCurrentHalfLife;

      var at = t0;
      for (var i = 0; i < 20; i++) {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        expect(
          evidenceWeightsFor(previewed, outcome).materialMemory,
          greaterThan(0.0),
        );
        applyAttempt(state, previewed, outcome, at: at);
      }

      expect(memory.logCurrentHalfLife, lessThan(before));
    });
  });

  group('stability under repeated failure', () {
    test('log current half-life stays finite and inside its bounds', () {
      final trajectory = repeatedAnchoredFailures(500);
      final last = trajectory.last;

      expect(last.isFinite, isTrue);
      expect(
        last,
        inInclusiveRange(
          math.log(params.materialMemory.minHalfLifeDays) - 1e-9,
          math.log(params.materialMemory.maxMemoryHalfLifeDays) + 1e-9,
        ),
      );
    });

    test('expected failures settle at an interior equilibrium', () {
      final trajectory = repeatedAnchoredFailures(200);
      final tail = trajectory.sublist(trajectory.length - 20);
      final steps = [
        for (var i = 1; i < tail.length; i++) (tail[i] - tail[i - 1]).abs(),
      ];

      expect(steps.reduce(math.max), lessThan(0.05));
      expect(
        trajectory.last,
        greaterThan(math.log(params.materialMemory.minHalfLifeDays) + 1e-6),
      );
    });

    test('the cold-start belief stays finite and inside its bounds', () {
      final trajectory = repeatedColdStartFailures(500);
      expect(trajectory.last.isFinite, isTrue);
      expect(
        trajectory.last,
        inInclusiveRange(
          params.materialMemory.minColdStartProbability - 1e-9,
          params.materialMemory.maxColdStartProbability + 1e-9,
        ),
      );
    });

    test('expected cold-start failures settle at an interior belief', () {
      final trajectory = repeatedColdStartFailures(200);
      final tail = trajectory.sublist(trajectory.length - 20);
      final steps = [
        for (var i = 1; i < tail.length; i++) (tail[i] - tail[i - 1]).abs(),
      ];

      expect(steps.reduce(math.max), lessThan(0.01));
      expect(
        trajectory.last,
        greaterThan(params.materialMemory.minColdStartProbability + 1e-6),
      );
    });
  });

  group('the cold-start phase', () {
    test('an unguided failure lowers the next prediction', () {
      final state = model.newState(at: t0);
      final before = model
          .predict(state, exercise, at: t0.plusDays(1))
          .independentRetrievalP;

      applyAttempt(state, exercise, failedToStart(), at: t0.plusDays(1));

      final after = model
          .predict(state, exercise, at: t0.plusDays(2))
          .independentRetrievalP;
      expect(after, lessThan(before));
    });

    test('evidence informs cold-start uncertainty, never durability', () {
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);
      final halfLifeUncertaintyBefore = memory.currentHalfLifeUncertainty;
      final coldStartUncertaintyBefore = memory.coldStartUncertainty;

      var at = t0;
      for (var i = 0; i < 100; i++) {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        applyAttempt(state, exercise, failedToStart(), at: at);
      }

      expect(memory.coldStartUncertainty, lessThan(coldStartUncertaintyBefore));
      expect(
        memory.currentHalfLifeUncertainty,
        halfLifeUncertaintyBefore,
        reason: 'no observation has spoken to durability yet',
      );

      // The first success anchors the clock, but is still no interval
      // evidence about the forgetting rate.
      at = at.plusDays(0.5);
      model.propagate(state, at);
      applyAttempt(state, exercise, perfectOutcome(), at: at);
      expect(memory.currentHalfLifeUncertainty, halfLifeUncertaintyBefore);

      // A genuinely spaced observation after the anchor finally does.
      at = at.plusDays(5);
      model.propagate(state, at);
      applyAttempt(state, exercise, perfectOutcome(), at: at);
      expect(
        memory.currentHalfLifeUncertainty,
        lessThan(halfLifeUncertaintyBefore),
      );
    });
  });
}
