import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

const LearnerModel model = LearnerModel();
const LearnerParams params = v1PrototypeLearnerParams;

const TechnicalMaterial cMajor = TechnicalMaterial('C', ScaleForm.major);
const TechnicalMaterial dHarmonicMinor = TechnicalMaterial(
  'D',
  ScaleForm.harmonicMinor,
);
const TechnicalMaterial fSharpHarmonicMinor = TechnicalMaterial(
  'F#',
  ScaleForm.harmonicMinor,
);

Exercise exerciseFor(
  TechnicalMaterial material, {
  HandConfiguration hands = HandConfiguration.right,
}) => Exercise.linear(material: material, hands: hands);

void main() {
  group('over a long run, every quantity stays well formed', () {
    test('predictions, weights, and state remain in range', () {
      final simulation = PracticeSimulation.of(
        SyntheticProfile.advanced,
        seed: 0,
      );
      final traces = simulation.run(150);

      for (final trace in traces) {
        for (final probability in [
          trace.prediction.independentRetrievalP,
          trace.prediction.materialAvailableP,
          trace.prediction.executionP,
          trace.prediction.topologyP,
          trace.prediction.overallP,
          trace.outcome.materialRetrieval,
          trace.outcome.pitchIntegrity,
          trace.outcome.continuity,
          trace.outcome.temporalStability,
          trace.outcome.topologyAccuracy,
        ]) {
          expect(probability, inInclusiveRange(0.0, 1.0));
        }

        final loadings = trace.loadings;
        expect(trace.structuralQ, isNotEmpty);
        expect(
          loadings.values.reduce((a, b) => a + b),
          closeTo(1.0, 1e-9),
          reason: 'loadings must sum to one whenever Q is nonempty',
        );

        expect(trace.weights.materialExecution, inInclusiveRange(0.0, 1.0));
        expect(trace.weights.materialMemory, inInclusiveRange(0.0, 1.0));
        for (final weight in trace.weights.competencies.values) {
          expect(weight, inInclusiveRange(0.0, 1.0));
        }

        for (final state in [trace.stateBefore, trace.stateAfter]) {
          for (final belief in state.competencies.values) {
            expect(belief.variance, greaterThan(0.0));
          }
          for (final memory in state.materialMemory.values) {
            expect(memory.currentHalfLifeDays, greaterThan(0.0));
            expect(
              memory.currentHalfLifeDays,
              lessThanOrEqualTo(memory.consolidatedHalfLifeDays + 1e-12),
            );
            expect(
              memory.consolidatedHalfLifeDays,
              lessThanOrEqualTo(params.materialMemory.maxMemoryHalfLifeDays),
            );
            expect(memory.currentHalfLifeUncertainty, greaterThan(0.0));
            expect(memory.coldStartUncertainty, greaterThan(0.0));
            expect(memory.coldStartEstimate, inInclusiveRange(0.0, 1.0));
            expect(
              memory.consolidatedLogHalfLifeVariance,
              greaterThanOrEqualTo(
                params.materialMemory.consolidationMinLogVariance,
              ),
            );
          }
          for (final residual in state.materialExecution.values) {
            expect(residual.residualVariance, greaterThan(0.0));
          }
        }
      }
    });

    test('no memory timestamp claims to be in the future, and a factual '
        'success always has an anchor at or after it', () {
      final simulation = PracticeSimulation.of(
        SyntheticProfile.techniqueStrongMemoryWeak,
        seed: 2,
      );

      for (final trace in simulation.run(150)) {
        for (final state in [trace.stateBefore, trace.stateAfter]) {
          for (final memory in state.materialMemory.values) {
            for (final timestamp in [
              memory.memoryAnchorAt,
              memory.factualLastRetrievalAt,
              memory.lastRetrievalAttemptAt,
            ]) {
              if (timestamp == null) continue;
              expect(timestamp.isAfter(trace.at), isFalse);
            }
            final factual = memory.factualLastRetrievalAt;
            if (factual == null) continue;
            expect(memory.memoryAnchorAt, isNotNull);
            expect(factual.isAfter(memory.memoryAnchorAt!), isFalse);
          }
        }
      }
    });
  });

  test('practice never touches a competency outside the exercise', () {
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 1,
    );
    final exercise = exerciseFor(cMajor);
    final traces = simulation.run(80, chooser: fixedExercise(exercise));

    final untouched = Competency.values
        .where((competency) => !exercise.structuralQ.contains(competency))
        .toList();
    expect(untouched, isNotEmpty);

    for (final competency in untouched) {
      expect(
        traces.last.stateAfter.competency(competency).mean,
        traces.first.stateBefore.competency(competency).mean,
        reason: '${competency.id} was never an opportunity in this exercise',
      );
    }
  });

  test('hand transfer works through prediction, not cross-updating', () {
    final simulation = PracticeSimulation.of(
      SyntheticProfile.advanced,
      seed: 2,
    );
    final state = simulation.state;
    final leftProbe = exerciseFor(cMajor, hands: HandConfiguration.left);

    // Execution, not overall: transfer acts on the competency mean, which only
    // enters the execution channel. Overall success would also move with C
    // major's retrievability, which the hands share.
    final leftBefore = model
        .predict(state, leftProbe, at: simulation.at)
        .executionP;
    final leftMeanBefore = state.competency(Competency.lhScaleExecution).mean;

    simulation.run(60, chooser: fixedExercise(exerciseFor(cMajor)));

    final leftMeanAfterRight = state
        .competency(Competency.lhScaleExecution)
        .mean;
    final leftVarianceAfterRight = state
        .competency(Competency.lhScaleExecution)
        .variance;
    expect(
      leftMeanAfterRight,
      leftMeanBefore,
      reason: 'right-hand practice must not write the stored left-hand mean',
    );

    final leftAfterRight = model
        .predict(state, leftProbe, at: simulation.at)
        .executionP;
    expect(
      leftAfterRight,
      greaterThan(leftBefore),
      reason: 'the correlated prior should still improve the prediction',
    );

    simulation.run(
      60,
      chooser: fixedExercise(
        exerciseFor(cMajor, hands: HandConfiguration.left),
      ),
    );

    expect(
      state.competency(Competency.lhScaleExecution).mean,
      isNot(leftMeanAfterRight),
      reason: 'direct evidence should move the stored mean',
    );
    expect(
      state.competency(Competency.lhScaleExecution).variance,
      lessThan(leftVarianceAfterRight),
      reason: 'only direct evidence should narrow it',
    );
  });

  test('a material-specific difficulty does not contaminate the shared '
      'competency', () {
    // Compares the within-run gap between two harmonic minors rather than one
    // material against itself across runs: the generator and the estimator use
    // deliberately different coefficients, so even a control run's residuals
    // are not near zero, and an absolute threshold would measure the wrong
    // baseline.
    Exercise alternating(AttemptContext context) => exerciseFor(
      context.attemptIndex.isEven ? fSharpHarmonicMinor : dHarmonicMinor,
    );

    double residualGap(LearnerState state) =>
        state
            .materialExecution[(
              fSharpHarmonicMinor.materialId,
              HandConfiguration.right,
            )]!
            .residualMean -
        state
            .materialExecution[(
              dHarmonicMinor.materialId,
              HandConfiguration.right,
            )]!
            .residualMean;

    final control = PracticeSimulation.of(SyntheticProfile.advanced, seed: 0)
      ..run(120, chooser: alternating);
    final treatment = PracticeSimulation.of(
      SyntheticProfile.materialSpecificDifficulty,
      seed: 0,
    )..run(120, chooser: alternating);

    expect(
      residualGap(treatment.state),
      lessThan(residualGap(control.state) - 0.15),
      reason: 'the F sharp residual should be markedly worse in treatment',
    );

    for (final competency in [
      Competency.harmonicMinorTopology,
      Competency.rhScaleExecution,
    ]) {
      expect(
        (treatment.state.competency(competency).mean -
                control.state.competency(competency).mean)
            .abs(),
        lessThan(0.5),
        reason: '${competency.id} should barely move for one bad material',
      );
    }
  });

  test('a returning learner reacquires differently from a true beginner', () {
    final returningTruth = SyntheticProfile.returning.build(
      start: defaultSimulationEpoch,
    );
    expect(
      returningTruth
          .memoryFor(cMajor.materialId)
          .retrievabilityAt(defaultSimulationEpoch, returningTruth.memoryPrior),
      lessThan(0.3),
      reason: 'the profile should encode a real gap, not just a label',
    );

    List<double> startedPitch(SyntheticProfile profile) {
      final simulation = PracticeSimulation.of(profile, seed: 5);
      return simulation
          .run(30, chooser: fixedExercise(exerciseFor(cMajor)))
          .where((trace) => trace.outcome.started)
          .map((trace) => trace.outcome.pitchIntegrity)
          .toList();
    }

    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;

    final returning = startedPitch(SyntheticProfile.returning);
    final beginner = startedPitch(SyntheticProfile.beginner);
    expect(returning, isNotEmpty);
    expect(beginner, isNotEmpty);

    expect(
      mean(returning),
      greaterThan(mean(beginner) + 0.2),
      reason: 'retained technique should show even after a memory gap',
    );
  });

  test('the true and estimated memory transitions agree in shape', () {
    // The estimator and the hidden truth use different coefficients on
    // purpose, but a success must strengthen both durabilities and preserve
    // the envelope in each.
    final exercise = exerciseFor(cMajor);
    final epoch = defaultSimulationEpoch;

    final truth = TrueMaterialMemory(
      currentHalfLifeDays: 4.0,
      consolidatedHalfLifeDays: 20.0,
      memoryAnchorAt: epoch,
      factualLastRetrievalAt: epoch,
    );
    const outcome = Outcome(
      started: true,
      retrieval: FactualRetrieval.succeeded,
      completed: true,
      materialRetrieval: 1.0,
      pitchIntegrity: 1.0,
      continuity: 1.0,
      temporalStability: 1.0,
      achievedTempoRatio: 1.0,
      topologyAccuracy: 1.0,
    );

    for (final days in [2.0, 4.0, 8.0]) {
      applyTrueMemoryTransition(
        memory: truth,
        exercise: exercise,
        outcome: outcome,
        at: epoch.plusDays(days),
      );
    }

    expect(truth.currentHalfLifeDays, greaterThan(4.0));
    expect(truth.consolidatedHalfLifeDays, greaterThan(20.0));
    expect(
      truth.currentHalfLifeDays,
      lessThanOrEqualTo(truth.consolidatedHalfLifeDays),
    );

    final state = model.newState(at: epoch);
    final memory = state.materialMemoryFor(cMajor.materialId, params)
      ..memoryAnchorAt = epoch
      ..factualLastRetrievalAt = epoch
      ..lastRetrievalAttemptAt = epoch
      ..logCurrentHalfLife = math.log(4.0)
      ..logConsolidatedHalfLife = math.log(20.0);

    for (final days in [2.0, 4.0, 8.0]) {
      final at = epoch.plusDays(days);
      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );
    }

    expect(memory.currentHalfLifeDays, greaterThan(4.0));
    expect(memory.consolidatedHalfLifeDays, greaterThan(20.0));
    expect(
      memory.currentHalfLifeDays,
      lessThanOrEqualTo(memory.consolidatedHalfLifeDays),
    );
  });
}
