import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// One attempt against a fresh state, with the two channels' signals set
/// independently.
LearnerState afterAttempt({
  required double topologyAccuracy,
  required double motorQuality,
}) {
  final state = model.newState(at: t0);
  final exercise = exerciseFor(cMajor);
  final outcome = Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 1.0,
    pitchIntegrity: 1.0,
    continuity: motorQuality,
    temporalStability: motorQuality,
    achievedTempoRatio: 1.0,
    topologyAccuracy: topologyAccuracy,
  );
  applyAttempt(state, exercise, outcome, at: t0.plusDays(1));
  return state;
}

void main() {
  group('channel independence', () {
    test('varying topology accuracy never moves a motor competency', () {
      final low = afterAttempt(topologyAccuracy: 0.1, motorQuality: 1.0);
      final high = afterAttempt(topologyAccuracy: 0.9, motorQuality: 1.0);

      expect(
        low.competency(Competency.rhScaleExecution).mean,
        high.competency(Competency.rhScaleExecution).mean,
      );
    });

    test('varying motor quality never moves a topology competency', () {
      final low = afterAttempt(topologyAccuracy: 0.5, motorQuality: 0.1);
      final high = afterAttempt(topologyAccuracy: 0.5, motorQuality: 0.9);

      expect(
        low.competency(Competency.majorScaleTopology).mean,
        high.competency(Competency.majorScaleTopology).mean,
      );
      expect(
        low.competency(Competency.rhScaleExecution).mean,
        isNot(high.competency(Competency.rhScaleExecution).mean),
      );
    });
  });

  group('what an attempt may touch', () {
    test('leaves every competency outside its Q exactly alone', () {
      final exercise = exerciseFor(cMajor);
      final untouched = Competency.values
          .where((competency) => !exercise.structuralQ.contains(competency))
          .toList();
      expect(untouched, isNotEmpty);

      final state = model.newState(at: t0);
      final before = {
        for (final competency in untouched)
          competency: state.competency(competency).mean,
      };

      var at = t0;
      for (var i = 0; i < 20; i++) {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        applyAttempt(state, exercise, perfectOutcome(), at: at);
      }

      for (final competency in untouched) {
        expect(state.competency(competency).mean, before[competency]);
        expect(state.competency(competency).lastEvidenceAt, isNull);
      }
    });

    test('right-hand practice never writes the stored left-hand state', () {
      final state = model.newState(at: t0);
      final leftBefore = state.competency(Competency.lhScaleExecution).mean;
      final leftVarianceBefore = state
          .competency(Competency.lhScaleExecution)
          .variance;

      var at = t0;
      for (var i = 0; i < 20; i++) {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        applyAttempt(state, exerciseFor(cMajor), perfectOutcome(), at: at);
      }

      expect(state.competency(Competency.lhScaleExecution).mean, leftBefore);
      // Propagation still widens it; only evidence may narrow it.
      expect(
        state.competency(Competency.lhScaleExecution).variance,
        greaterThan(leftVarianceBefore),
      );
      expect(
        state.competency(Competency.rhScaleExecution).mean,
        greaterThan(0.0),
      );
    });
  });

  group('evidence', () {
    test('moves the mean toward the surprise and narrows uncertainty', () {
      final state = model.newState(at: t0);
      final belief = state.competency(Competency.rhScaleExecution);
      final varianceBefore = belief.variance;

      applyAttempt(
        state,
        exerciseFor(cMajor),
        perfectOutcome(),
        at: t0.plusDays(1),
      );

      expect(belief.mean, greaterThan(0.0));
      expect(belief.variance, lessThan(varianceBefore));
      expect(belief.lastEvidenceAt, t0.plusDays(1));
    });

    test('never drives variance below its floor', () {
      final state = model.newState(at: t0);
      var at = t0;
      for (var i = 0; i < 500; i++) {
        at = at.plusDays(0.01);
        model.propagate(state, at);
        applyAttempt(state, exerciseFor(cMajor), perfectOutcome(), at: at);
      }
      for (final belief in state.competencies.values) {
        expect(
          belief.variance,
          greaterThanOrEqualTo(params.competency.minVariance),
        );
      }
    });

    test('builds a material-specific residual rather than moving the shared '
        'competency by the whole discrepancy', () {
      final state = model.newState(at: t0);
      final poor = Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1.0,
        pitchIntegrity: 0.2,
        continuity: 0.05,
        temporalStability: 0.05,
        achievedTempoRatio: 0.2,
        topologyAccuracy: 1.0,
      );

      var at = t0;
      for (var i = 0; i < 30; i++) {
        at = at.plusDays(0.5);
        model.propagate(state, at);
        applyAttempt(state, exerciseFor(fSharpHarmonicMinor), poor, at: at);
      }

      final residual =
          state.materialExecution[(
            fSharpHarmonicMinor.materialId,
            HandConfiguration.right,
            HandMotion.parallel,
          )]!;
      expect(residual.residualMean, lessThan(0.0));
      expect(
        residual.residualMean,
        lessThan(state.competency(Competency.rhScaleExecution).mean),
      );
    });
  });
}
