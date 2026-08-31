import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

void main() {
  group('loadings', () {
    final exercise = exerciseFor(cMajor);

    test('split credit evenly and normalize each channel separately', () {
      final q = exercise.structuralQ;
      final motor = motorLoadings(q);
      final topology = topologyLoadings(q);

      expect(motor.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(topology.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(motor.keys, everyElement(isIn(motorCompetencies)));
      expect(topology.keys, everyElement(isIn(topologyCompetencies)));
    });

    test('a topology opportunity does not dilute the motor predictor', () {
      final motorOnly = motorLoadings(exercise.structuralQ);
      final withoutTopology = motorLoadings(
        exercise.structuralQ.difference(topologyCompetencies),
      );
      expect(motorOnly, withoutTopology);
    });
  });

  group('guidance', () {
    final state = model.placementState(PlacementTier.advanced, at: t0);
    final cued = exerciseFor(
      cMajor,
      guidance: GuidanceContext.continuouslyCued,
    );
    final unguided = exerciseFor(cMajor);

    test('changes availability but not retrieval or execution', () {
      final cuedPrediction = model.predict(state, cued, at: t0.plusDays(1));
      final unguidedPrediction = model.predict(
        state,
        unguided,
        at: t0.plusDays(1),
      );

      expect(
        cuedPrediction.independentRetrievalP,
        unguidedPrediction.independentRetrievalP,
      );
      expect(cuedPrediction.executionP, unguidedPrediction.executionP);
      expect(
        cuedPrediction.materialAvailableP,
        greaterThan(unguidedPrediction.materialAvailableP),
      );
    });

    test('leaves an unguided attempt at its unaided retrieval probability', () {
      final prediction = model.predict(state, unguided, at: t0.plusDays(1));
      expect(
        prediction.materialAvailableP,
        closeTo(prediction.independentRetrievalP, 1e-12),
      );
    });

    test('orders availability by how much support each level gives', () {
      final availability = [
        for (final guidance in GuidanceContext.ladder)
          model
              .predict(
                state,
                exerciseFor(cMajor, guidance: guidance),
                at: t0.plusDays(1),
              )
              .materialAvailableP,
      ];
      expect(availability[0], lessThan(availability[1]));
      expect(availability[1], lessThan(availability[2]));
    });
  });

  group('motor difficulty', () {
    final baseline = exerciseFor(
      cMajor,
      octaves: 1,
      direction: ScaleDirection.up,
      tempoBpm: params.difficulty.referenceTempoBpm,
    );

    test('is zero for a one-octave ascending exercise at reference tempo', () {
      expect(model.motorDifficulty(baseline), closeTo(0.0, 1e-12));
    });

    test('rises with tempo, octaves, hands together, and reversal', () {
      final harder = [
        exerciseFor(
          cMajor,
          octaves: 1,
          direction: ScaleDirection.up,
          tempoBpm: 120,
        ),
        exerciseFor(cMajor, octaves: 2, direction: ScaleDirection.up),
        exerciseFor(
          cMajor,
          hands: HandConfiguration.together,
          octaves: 1,
          direction: ScaleDirection.up,
        ),
        exerciseFor(cMajor, octaves: 1),
      ];
      for (final exercise in harder) {
        expect(
          model.motorDifficulty(exercise),
          greaterThan(model.motorDifficulty(baseline)),
        );
      }
    });

    test('ignores guidance entirely', () {
      for (final guidance in GuidanceContext.ladder) {
        expect(
          model.motorDifficulty(exerciseFor(cMajor, guidance: guidance)),
          model.motorDifficulty(exerciseFor(cMajor)),
        );
      }
    });
  });

  group('hand transfer', () {
    test('nudges an unobserved hand toward the observed one', () {
      final state = model.newState(at: t0);
      state.competency(Competency.rhScaleExecution).mean = 2.0;

      final adjusted = model.effectiveCompetencyMean(
        state,
        Competency.lhScaleExecution,
      );
      expect(adjusted, greaterThan(0.0));
      expect(adjusted, lessThan(2.0));
      expect(state.competency(Competency.lhScaleExecution).mean, 0.0);
    });

    test('shrinks as the target hand accumulates its own evidence', () {
      double adjustmentAtVariance(double variance) {
        final state = model.newState(at: t0);
        state.competency(Competency.rhScaleExecution).mean = 2.0;
        state.competency(Competency.lhScaleExecution).variance = variance;
        return model.effectiveCompetencyMean(
          state,
          Competency.lhScaleExecution,
        );
      }

      expect(adjustmentAtVariance(0.05), lessThan(adjustmentAtVariance(1.5)));
    });

    test('does not apply to competencies with no paired hand', () {
      final state = model.newState(at: t0);
      state.competency(Competency.rhScaleExecution).mean = 2.0;

      for (final competency in Competency.values) {
        if (competency.pairedHand != null) continue;
        expect(
          model.effectiveCompetencyMean(state, competency),
          state.competency(competency).mean,
        );
      }
    });
  });

  test('prediction never mutates the state it reads', () {
    final state = model.placementState(PlacementTier.advanced, at: t0);
    final exercise = exerciseFor(cMajor);

    model.predict(state, exercise, at: t0.plusDays(1));
    model.predict(state, exercise, at: t0.plusDays(1));

    expect(state.materialMemory, isEmpty);
    expect(state.materialExecution, isEmpty);
    for (final belief in state.competencies.values) {
      expect(belief.mean, params.placement.advancedMean);
      expect(belief.lastEvidenceAt, isNull);
    }
  });

  test('every channel stays a probability', () {
    final state = model.placementState(PlacementTier.beginner, at: t0);
    for (final guidance in GuidanceContext.ladder) {
      for (final hands in HandConfiguration.values) {
        final prediction = model.predict(
          state,
          exerciseFor(cMajor, hands: hands, guidance: guidance, tempoBpm: 120),
          at: t0.plusDays(30),
        );
        for (final probability in [
          prediction.independentRetrievalP,
          prediction.materialAvailableP,
          prediction.executionP,
          prediction.coordinationP,
          prediction.topologyP,
          prediction.overallP,
        ]) {
          expect(probability, inInclusiveRange(0.0, 1.0));
        }
      }
    }
  });
}
