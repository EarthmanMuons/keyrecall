import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

void main() {
  group('placement', () {
    test('shifts every competency mean without narrowing uncertainty', () {
      for (final tier in PlacementTier.values) {
        final state = model.placementState(tier, at: t0);
        for (final belief in state.competencies.values) {
          expect(belief.mean, tier.priorMean(params.placement));
          expect(belief.variance, params.placement.priorVarianceBroad);
        }
      }
    });

    test('leaves a self-reported beginner correctable by evidence', () {
      final beginner = model.placementState(PlacementTier.beginner, at: t0);
      final advanced = model.placementState(PlacementTier.advanced, at: t0);
      expect(
        beginner.competency(Competency.rhScaleExecution).mean,
        lessThan(advanced.competency(Competency.rhScaleExecution).mean),
      );
      expect(
        beginner.competency(Competency.rhScaleExecution).variance,
        advanced.competency(Competency.rhScaleExecution).variance,
      );
    });
  });

  group('propagation', () {
    test('long nonuse grows uncertainty and leaves the mean untouched', () {
      final state = model.newState(at: t0, competencyPriorMean: 0.7);
      final belief = state.competency(Competency.rhScaleExecution);
      final meanBefore = belief.mean;
      final varianceBefore = belief.variance;

      model.propagate(state, t0.plusDays(365));

      expect(belief.mean, meanBefore);
      expect(belief.variance, greaterThan(varianceBefore));
    });

    test(
      'fades an unreinforced residual back toward the shared prediction',
      () {
        final state = model.newState(at: t0);
        final residual = state.materialExecutionFor(
          (cMajor.materialId, HandConfiguration.right, HandMotion.parallel),
          t0,
          params,
        )..residualMean = -1.0;
        final varianceBefore = residual.residualVariance;

        model.propagate(state, t0.plusDays(28));

        expect(residual.residualMean, greaterThan(-1.0));
        expect(residual.residualMean, lessThan(0.0));
        expect(residual.residualVariance, greaterThan(varianceBefore));
      },
    );

    test('refuses to move backward in time', () {
      // Rewinding and later returning would diffuse the same interval twice,
      // which corrupts replay silently. Failing loudly is the point.
      final state = model.newState(at: t0);
      model.propagate(state, t0.plusDays(10));

      expect(() => model.propagate(state, t0.plusDays(5)), throwsArgumentError);
    });

    test('rejects a backward step before mutating anything', () {
      final state = model.newState(at: t0);
      model.propagate(state, t0.plusDays(10));
      // A later-created layer makes the state heterogeneous, so a naive
      // per-layer check would advance some layers before hitting the stale
      // one.
      state.materialExecutionFor(
        (cMajor.materialId, HandConfiguration.right, HandMotion.parallel),
        t0.plusDays(20),
        params,
      );
      expect(state.lastPropagatedAt, t0.plusDays(20));

      final variancesBefore = [
        for (final belief in state.competencies.values) belief.variance,
      ];
      expect(
        () => model.propagate(state, t0.plusDays(15)),
        throwsArgumentError,
      );

      expect(
        [for (final belief in state.competencies.values) belief.variance],
        variancesBefore,
        reason: 'a rejected propagation must leave every layer untouched',
      );
      expect(
        state.competencies.values.every(
          (belief) => belief.updatedAt == t0.plusDays(10),
        ),
        isTrue,
      );
    });

    test('standing still is allowed', () {
      final state = model.newState(at: t0);
      model.propagate(state, t0.plusDays(10));
      final variance = state.competency(Competency.rhScaleExecution).variance;

      model.propagate(state, t0.plusDays(10));

      expect(state.competency(Competency.rhScaleExecution).variance, variance);
    });
  });

  group('material memory', () {
    test('decays monotonically with elapsed time once anchored', () {
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);
      anchorMemory(memory, t0, currentHalfLifeDays: 4.0);

      final values = [
        for (final days in [0.0, 1.0, 5.0, 20.0])
          memory.retrievabilityAt(t0.plusDays(days)),
      ];

      expect(values.first, closeTo(1.0, 1e-12));
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThan(values[i - 1]));
      }
    });

    test('reaches exactly half its value after one half-life', () {
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);
      anchorMemory(memory, t0, currentHalfLifeDays: 4.0);

      expect(memory.retrievabilityAt(t0.plusDays(4)), closeTo(0.5, 1e-12));
    });

    test('refuses to report a decay curve before any anchor exists', () {
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);

      expect(memory.isAnchored, isFalse);
      expect(() => memory.retrievabilityAt(t0), throwsStateError);
      expect(
        memory.retrievabilityOrPrior(t0),
        closeTo(params.materialMemory.priorRetrievability, 1e-12),
      );
    });

    test('starts a new material inside its durability envelope', () {
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);

      expect(memory.currentHalfLifeDays, greaterThan(0));
      expect(
        memory.currentHalfLifeDays,
        lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
      );
      expect(
        memory.consolidatedHalfLifeDays,
        lessThanOrEqualTo(params.materialMemory.maxMemoryHalfLifeDays),
      );
    });
  });

  test('a copy is fully independent of the state it came from', () {
    final state = model.newState(at: t0);
    state.materialMemoryFor(cMajor.materialId, params);
    state.materialExecutionFor(
      (cMajor.materialId, HandConfiguration.right, HandMotion.parallel),
      t0,
      params,
    );

    final snapshot = state.copy();
    state.competency(Competency.rhScaleExecution).mean += 1.0;
    state.materialMemory[cMajor.materialId]!.logCurrentHalfLife += 1.0;
    state
            .materialExecution[(
              cMajor.materialId,
              HandConfiguration.right,
              HandMotion.parallel,
            )]!
            .residualMean +=
        1.0;

    expect(snapshot.competency(Competency.rhScaleExecution).mean, 0.0);
    expect(
      snapshot.materialMemory[cMajor.materialId]!.currentHalfLifeDays,
      closeTo(params.materialMemory.initialCurrentHalfLifeDays, 1e-12),
    );
    expect(
      snapshot
          .materialExecution[(
            cMajor.materialId,
            HandConfiguration.right,
            HandMotion.parallel,
          )]!
          .residualMean,
      0.0,
    );
  });
}
