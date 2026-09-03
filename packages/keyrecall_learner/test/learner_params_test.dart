import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/registry_toml.dart';

void main() {
  group('v1PrototypeLearnerParams', () {
    const params = v1PrototypeLearnerParams;

    test('agrees with the authoritative TOML registry', () {
      final registry = readRegistry('analysis/learner-model/params.toml');
      if (registry == null) {
        markTestSkipped('analysis/learner-model/params.toml is not available');
        return;
      }

      expect(params.modelVersion, registry['']!['model_version']);

      final competency = registry['competency']!;
      expect(params.competency.priorMean, competency['prior_mean']);
      expect(params.competency.priorVariance, competency['prior_variance']);
      expect(params.competency.minVariance, competency['min_variance']);
      expect(params.competency.learningRate, competency['learning_rate']);
      expect(
        params.competency.uncertaintyDiffusion,
        competency['uncertainty_diffusion'],
      );
      expect(
        params.competency.evidenceShrinkage,
        competency['evidence_shrinkage'],
      );

      final memory = registry['material_memory']!;
      final actualMemory = params.materialMemory;
      expect(
        actualMemory.initialCurrentHalfLifeDays,
        memory['initial_current_half_life_days'],
      );
      expect(
        actualMemory.alphaCurrentDurability,
        memory['alpha_current_durability'],
      );
      expect(
        actualMemory.reversionLambdaCurrentDurability,
        memory['reversion_lambda_current_durability'],
      );
      expect(actualMemory.minHalfLifeDays, memory['min_half_life_days']);
      expect(
        actualMemory.maxMemoryHalfLifeDays,
        memory['max_memory_half_life_days'],
      );
      expect(actualMemory.priorRetrievability, memory['prior_retrievability']);
      expect(actualMemory.priorUncertainty, memory['prior_uncertainty']);
      expect(
        actualMemory.consolidationPriorLogVariance,
        memory['consolidation_prior_log_variance'],
      );
      expect(
        actualMemory.consolidationMinLogVariance,
        memory['consolidation_min_log_variance'],
      );
      expect(
        actualMemory.retainedInferenceMinIntervalDays,
        memory['retained_inference_min_interval_days'],
      );
      expect(
        actualMemory.retainedInferenceLikelihoodWeight,
        memory['retained_inference_likelihood_weight'],
      );
      expect(
        actualMemory.retainedInferenceGridPoints,
        memory['retained_inference_grid_points'],
      );
      expect(actualMemory.minUncertainty, memory['min_uncertainty']);
      expect(actualMemory.evidenceShrinkage, memory['evidence_shrinkage']);
      expect(actualMemory.alphaColdStart, memory['alpha_cold_start']);
      expect(
        actualMemory.reversionLambdaColdStart,
        memory['reversion_lambda_cold_start'],
      );
      expect(
        actualMemory.minColdStartProbability,
        memory['min_cold_start_probability'],
      );
      expect(
        actualMemory.maxColdStartProbability,
        memory['max_cold_start_probability'],
      );
      expect(
        actualMemory.supportedActivationRestorationRate,
        memory['supported_activation_restoration_rate'],
      );
      expect(
        actualMemory.supportedCurrentDurabilityRate,
        memory['supported_current_durability_rate'],
      );
      expect(
        actualMemory.successCurrentDurabilityRate,
        memory['success_current_durability_rate'],
      );
      expect(
        actualMemory.consolidationGrowthRate,
        memory['consolidation_growth_rate'],
      );
      expect(
        actualMemory.consolidationGrowthTargetDays,
        memory['consolidation_growth_target_days'],
      );
      expect(
        actualMemory.supportedPracticeFactorConcurrentCues,
        memory['supported_practice_factor_concurrent_cues'],
      );
      expect(
        actualMemory.supportedPracticeFactorNotesPreviewed,
        memory['supported_practice_factor_notes_previewed'],
      );
      expect(
        actualMemory.supportedPracticeFactorUnguided,
        memory['supported_practice_factor_unguided'],
      );
      expect(
        actualMemory.retrievalSuccessFactorNotesPreviewed,
        memory['retrieval_success_factor_notes_previewed'],
      );
      expect(
        actualMemory.retrievalSuccessFactorUnguided,
        memory['retrieval_success_factor_unguided'],
      );

      final execution = registry['material_execution']!;
      expect(
        params.materialExecution.priorVariance,
        execution['prior_variance'],
      );
      expect(params.materialExecution.minVariance, execution['min_variance']);
      expect(params.materialExecution.learningRate, execution['learning_rate']);
      expect(
        params.materialExecution.meanReversionTauDays,
        execution['mean_reversion_tau_days'],
      );
      expect(
        params.materialExecution.uncertaintyDiffusion,
        execution['uncertainty_diffusion'],
      );
      expect(
        params.materialExecution.evidenceShrinkage,
        execution['evidence_shrinkage'],
      );

      final handTransfer = registry['hand_transfer']!;
      expect(params.competencyTransfer.rhoHand, handTransfer['rho_hand']);
      expect(params.competencyTransfer.rhoFamily, 0);
      expect(
        params.competencyTransfer.shrinkageTau,
        handTransfer['shrinkage_tau'],
      );

      final difficulty = registry['difficulty']!;
      expect(params.difficulty.tempoBeta, difficulty['tempo_beta']);
      expect(params.difficulty.octaveBeta, difficulty['octave_beta']);
      expect(params.difficulty.handBeta, difficulty['hand_beta']);
      expect(params.difficulty.directionBeta, difficulty['direction_beta']);
      expect(
        params.difficulty.referenceTempoBpm,
        difficulty['reference_tempo_bpm'],
      );

      final placement = registry['placement']!;
      expect(params.placement.beginnerMean, placement['beginner_mean']);
      expect(
        params.placement.someExperienceMean,
        placement['some_experience_mean'],
      );
      expect(params.placement.advancedMean, placement['advanced_mean']);
      expect(
        params.placement.priorVarianceBroad,
        placement['prior_variance_broad'],
      );
    });

    test('keeps the durability bounds orderable', () {
      final memory = params.materialMemory;
      expect(memory.minHalfLifeDays, lessThan(memory.maxMemoryHalfLifeDays));
      expect(
        memory.initialCurrentHalfLifeDays,
        inInclusiveRange(memory.minHalfLifeDays, memory.maxMemoryHalfLifeDays),
      );
      expect(memory.retainedInferenceGridPoints, greaterThanOrEqualTo(3));
    });

    test('orders the placement tiers by self-reported experience', () {
      final placement = params.placement;
      expect(placement.beginnerMean, lessThan(placement.someExperienceMean));
      expect(placement.someExperienceMean, lessThan(placement.advancedMean));
    });
  });
}
