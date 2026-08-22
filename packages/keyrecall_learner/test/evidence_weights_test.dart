import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

void main() {
  final unguided = exerciseFor(cMajor);
  final cued = exerciseFor(cMajor, guidance: GuidanceContext.continuouslyCued);
  final previewed = exerciseFor(
    cMajor,
    guidance: GuidanceContext.notesPreviewedOnly,
  );

  group('bounds', () {
    test('every weight is a fraction', () {
      final outcomes = [
        perfectOutcome(),
        perfectOutcome(retrieval: FactualRetrieval.failed),
        cuedOutcome(),
        failedToStart(),
        successOfQuality(0.4),
      ];
      for (final exercise in [unguided, previewed, cued]) {
        for (final outcome in outcomes) {
          final weights = evidenceWeightsFor(exercise, outcome);
          expect(weights.materialExecution, inInclusiveRange(0.0, 1.0));
          expect(weights.materialMemory, inInclusiveRange(0.0, 1.0));
          for (final weight in weights.competencies.values) {
            expect(weight, inInclusiveRange(0.0, 1.0));
          }
        }
      }
    });

    test('says nothing about competencies the exercise cannot reveal', () {
      final weights = evidenceWeightsFor(unguided, perfectOutcome());
      for (final competency in Competency.values) {
        if (unguided.structuralQ.contains(competency)) continue;
        expect(weights[competency], 0.0);
      }
    });
  });

  group('an attempt that never started', () {
    test('is memory evidence and almost nothing else', () {
      final weights = evidenceWeightsFor(unguided, failedToStart());
      expect(weights.materialMemory, greaterThan(0.0));
      expect(weights.materialExecution, 0.0);
      expect(weights.competencies, isEmpty);
    });

    test('is not even memory evidence when retrieval was never tested', () {
      final never = const Outcome(
        started: false,
        retrieval: FactualRetrieval.notTested,
        completed: false,
        materialRetrieval: 0.0,
        pitchIntegrity: 0.0,
        continuity: 0.0,
        temporalStability: 0.0,
        achievedTempoRatio: 0.0,
        topologyAccuracy: 0.0,
      );
      expect(evidenceWeightsFor(cued, never).materialMemory, 0.0);
    });
  });

  group('continuous cueing', () {
    test('gives no memory evidence at all, not merely a little', () {
      expect(evidenceWeightsFor(cued, cuedOutcome()).materialMemory, 0.0);
    });

    test('gives little topology evidence but full motor evidence', () {
      final cuedWeights = evidenceWeightsFor(cued, cuedOutcome());
      final unguidedWeights = evidenceWeightsFor(unguided, perfectOutcome());

      expect(
        cuedWeights[Competency.majorScaleTopology],
        lessThan(0.2 * unguidedWeights[Competency.majorScaleTopology]),
      );
      expect(cuedWeights[Competency.rhScaleExecution], greaterThan(0.0));
      expect(
        cuedWeights[Competency.rhScaleExecution],
        unguidedWeights[Competency.rhScaleExecution],
      );
    });
  });

  test('previewed notes are real but weaker retrieval evidence', () {
    final previewedWeight = evidenceWeightsFor(
      previewed,
      perfectOutcome(),
    ).materialMemory;
    final unguidedWeight = evidenceWeightsFor(
      unguided,
      perfectOutcome(),
    ).materialMemory;

    expect(previewedWeight, greaterThan(0.0));
    expect(previewedWeight, lessThan(unguidedWeight));
  });

  test('an incomplete attempt is weaker evidence than a completed one', () {
    final incomplete = Outcome(
      started: true,
      retrieval: FactualRetrieval.succeeded,
      completed: false,
      materialRetrieval: 1.0,
      pitchIntegrity: 0.5,
      continuity: 0.5,
      temporalStability: 0.5,
      achievedTempoRatio: 0.5,
      topologyAccuracy: 0.5,
    );
    final partial = evidenceWeightsFor(unguided, incomplete);
    final full = evidenceWeightsFor(unguided, perfectOutcome());

    expect(partial.materialExecution, lessThan(full.materialExecution));
    expect(partial.materialMemory, lessThan(full.materialMemory));
  });

  group('FactualRetrieval', () {
    test('round-trips through its true, false, and null encoding', () {
      for (final retrieval in FactualRetrieval.values) {
        expect(FactualRetrieval.fromJson(retrieval.jsonValue), retrieval);
      }
      expect(FactualRetrieval.succeeded.jsonValue, isTrue);
      expect(FactualRetrieval.failed.jsonValue, isFalse);
      expect(FactualRetrieval.notTested.jsonValue, isNull);
    });

    test('keeps "not tested" distinct from "tested and failed"', () {
      expect(FactualRetrieval.notTested.isTested, isFalse);
      expect(FactualRetrieval.failed.isTested, isTrue);
      expect(FactualRetrieval.notTested.score, FactualRetrieval.failed.score);
    });
  });
}
