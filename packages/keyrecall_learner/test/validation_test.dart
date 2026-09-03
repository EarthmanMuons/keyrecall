import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// Where malformed values stop.
///
/// These types sit under a UI, a replay path, and eventually a deserializer,
/// and their values reach `log` and `exp` in the update path. A bad value must
/// fail where it enters rather than surfacing later as a nonsense half-life or
/// a NaN that has already been folded into learner state.
void main() {
  group('Outcome', () {
    Outcome withContinuity(double continuity) => Outcome(
      started: true,
      retrieval: FactualRetrieval.succeeded,
      completed: true,
      materialRetrieval: 1.0,
      pitchIntegrity: 1.0,
      continuity: continuity,
      temporalStability: 1.0,
      achievedTempoRatio: 1.0,
      topologyAccuracy: 1.0,
    );

    test('accepts both ends of the range', () {
      expect(withContinuity(0.0).continuity, 0.0);
      expect(withContinuity(1.0).continuity, 1.0);
    });

    test('rejects a score outside the range', () {
      expect(() => withContinuity(-0.01), throwsArgumentError);
      expect(() => withContinuity(1.01), throwsArgumentError);
    });

    test('rejects a score that is not a number', () {
      expect(() => withContinuity(double.nan), throwsArgumentError);
      expect(() => withContinuity(double.infinity), throwsArgumentError);
    });

    test('allows an overshot tempo but not a nonsensical one', () {
      Outcome withTempoRatio(double ratio) => Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1.0,
        pitchIntegrity: 1.0,
        continuity: 1.0,
        temporalStability: 1.0,
        achievedTempoRatio: ratio,
        topologyAccuracy: 1.0,
      );

      // Playing faster than asked is a real observation, and V1 records it
      // without consuming it.
      expect(withTempoRatio(1.4).achievedTempoRatio, 1.4);
      expect(() => withTempoRatio(-0.1), throwsArgumentError);
      expect(() => withTempoRatio(double.nan), throwsArgumentError);
    });
  });

  group('parameter bounds', () {
    test('the shipped registry satisfies its own assertions', () {
      // Both registries are const, so these assertions are checked when the
      // library is compiled. Naming the registry here keeps that visible.
      expect(v1PrototypeLearnerParams.modelVersion, isNotEmpty);
      expect(
        v1PrototypeLearnerParams.materialMemory.retainedInferenceGridPoints,
        greaterThanOrEqualTo(3),
      );
    });

    test('a parameter set that cannot mean anything is rejected', () {
      expect(
        () => CompetencyTransferParams(
          rhoHand: 1.5,
          rhoFamily: 0.35,
          shrinkageTau: 0.5,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'transfer cannot borrow more than the whole gap',
      );
      expect(
        () => CompetencyTransferParams(
          rhoHand: 0.3,
          rhoFamily: 0.35,
          shrinkageTau: 0.0,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PlacementParams(
          beginnerMean: 1.0,
          someExperienceMean: 0.0,
          advancedMean: -1.0,
          priorVarianceBroad: 1.5,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'the tiers must be ordered by self-reported experience',
      );
      expect(
        () => CompetencyParams(
          priorMean: 0.0,
          priorVariance: 1.0,
          minVariance: 0.0,
          learningRate: 0.15,
          uncertaintyDiffusion: 0.01,
          evidenceShrinkage: 0.3,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'evidence must never be able to imply certainty',
      );
      expect(
        () => DifficultyParams(
          tempoBeta: 0.4,
          octaveBeta: 0.3,
          handBeta: 0.2,
          directionBeta: 0.15,
          referenceTempoBpm: 0.0,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'the tempo term takes the log of a ratio to this tempo',
      );
    });

    test('the posterior grid is guarded in the model as well', () {
      // Belt and braces: the registry assertion is compile-time for const
      // values and debug-only otherwise, so the integration itself also
      // refuses a grid it cannot integrate over.
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);

      expect(
        () => updateRetainedConsolidationPosterior(
          memory: memory,
          retrievalSucceeded: true,
          elapsedDays: 14.0,
          evidenceWeight: 1.0,
          params: params.materialMemory,
        ),
        returnsNormally,
      );
    });
  });
}
