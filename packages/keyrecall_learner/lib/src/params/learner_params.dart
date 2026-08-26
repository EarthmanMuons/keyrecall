import 'package:meta/meta.dart';

/// Priors and update rates for the shared transferable competencies.
@immutable
class CompetencyParams {
  /// Starting mean for a competency with no evidence.
  final double priorMean;

  /// Starting variance for a competency with no evidence.
  final double priorVariance;

  /// Floor on competency variance, so evidence can never imply certainty.
  final double minVariance;

  /// `alpha_k`: how far one unit of evidence moves the mean.
  final double learningRate;

  /// Variance added per day of nonuse.
  final double uncertaintyDiffusion;

  /// `lambda_k`: fraction of variance removed by fully informative evidence.
  final double evidenceShrinkage;

  const CompetencyParams({
    required this.priorMean,
    required this.priorVariance,
    required this.minVariance,
    required this.learningRate,
    required this.uncertaintyDiffusion,
    required this.evidenceShrinkage,
  }) : assert(priorVariance > 0, 'a belief cannot start certain'),
       assert(minVariance > 0, 'evidence must never imply certainty'),
       assert(
         minVariance <= priorVariance,
         'the floor cannot exceed the prior',
       ),
       assert(
         learningRate >= 0,
         'evidence cannot move the mean away from itself',
       ),
       assert(uncertaintyDiffusion >= 0, 'nonuse cannot increase confidence'),
       assert(
         evidenceShrinkage >= 0 && evidenceShrinkage <= 1,
         'shrinkage is a fraction of the variance to remove',
       );
}

/// Priors, evidence rates, and transition doses for exact-material memory.
@immutable
class MaterialMemoryParams {
  /// Current half-life a never-practiced material starts with, in days.
  final double initialCurrentHalfLifeDays;

  /// `alpha_M`: how far retrieval surprise moves log current durability.
  final double alphaCurrentDurability;

  /// `lambda_M`: pull back toward the prior log half-life.
  final double reversionLambdaCurrentDurability;

  /// Lower bound on any half-life, in days.
  final double minHalfLifeDays;

  /// Upper bound on any half-life, in days.
  final double maxMemoryHalfLifeDays;

  /// Retrieval probability assumed before any evidence exists.
  final double priorRetrievability;

  /// Starting uncertainty for both the cold-start and current-durability
  /// beliefs.
  final double priorUncertainty;

  /// Prior variance of the retained-consolidation posterior, in log-days.
  final double consolidationPriorLogVariance;

  /// Floor on the retained-consolidation posterior variance.
  final double consolidationMinLogVariance;

  /// Shortest interval that can supply retained-durability evidence, in days.
  ///
  /// The calibrated value is one hour. Days is the unit every clock in the
  /// model uses, so it is stored in days rather than converted at each use.
  final double retainedInferenceMinIntervalDays;

  /// Weight applied to the retained-durability likelihood.
  final double retainedInferenceLikelihoodWeight;

  /// Grid resolution for the retained-durability posterior.
  final int retainedInferenceGridPoints;

  /// Floor on memory uncertainty.
  final double minUncertainty;

  /// Fraction of memory uncertainty removed by fully informative evidence.
  final double evidenceShrinkage;

  /// `alpha_c`: how far retrieval surprise moves the cold-start logit.
  final double alphaColdStart;

  /// `lambda_c`: pull back toward the cold-start prior.
  final double reversionLambdaColdStart;

  /// Lower bound on the cold-start probability.
  final double minColdStartProbability;

  /// Upper bound on the cold-start probability.
  final double maxColdStartProbability;

  /// Fraction of the gap to now that productive supported practice moves the
  /// activation anchor.
  final double supportedActivationRestorationRate;

  /// Fraction of the gap to consolidation that supported practice restores.
  final double supportedCurrentDurabilityRate;

  /// Fraction of the gap to consolidation that a successful retrieval adds.
  final double successCurrentDurabilityRate;

  /// Fraction of the remaining gap to target that a success consolidates.
  final double consolidationGrowthRate;

  /// Saturating target for causal consolidation growth, in days.
  final double consolidationGrowthTargetDays;

  /// Practice dose under continuous cues.
  final double supportedPracticeFactorConcurrentCues;

  /// Practice dose under previewed notes.
  final double supportedPracticeFactorNotesPreviewed;

  /// Practice dose with no guidance.
  final double supportedPracticeFactorUnguided;

  /// Formation dose for a success under previewed notes.
  final double retrievalSuccessFactorNotesPreviewed;

  /// Formation dose for an unguided success.
  final double retrievalSuccessFactorUnguided;

  const MaterialMemoryParams({
    required this.initialCurrentHalfLifeDays,
    required this.alphaCurrentDurability,
    required this.reversionLambdaCurrentDurability,
    required this.minHalfLifeDays,
    required this.maxMemoryHalfLifeDays,
    required this.priorRetrievability,
    required this.priorUncertainty,
    required this.consolidationPriorLogVariance,
    required this.consolidationMinLogVariance,
    required this.retainedInferenceMinIntervalDays,
    required this.retainedInferenceLikelihoodWeight,
    required this.retainedInferenceGridPoints,
    required this.minUncertainty,
    required this.evidenceShrinkage,
    required this.alphaColdStart,
    required this.reversionLambdaColdStart,
    required this.minColdStartProbability,
    required this.maxColdStartProbability,
    required this.supportedActivationRestorationRate,
    required this.supportedCurrentDurabilityRate,
    required this.successCurrentDurabilityRate,
    required this.consolidationGrowthRate,
    required this.consolidationGrowthTargetDays,
    required this.supportedPracticeFactorConcurrentCues,
    required this.supportedPracticeFactorNotesPreviewed,
    required this.supportedPracticeFactorUnguided,
    required this.retrievalSuccessFactorNotesPreviewed,
    required this.retrievalSuccessFactorUnguided,
  }) : assert(minHalfLifeDays > 0, 'a half-life must be positive'),
       assert(
         minHalfLifeDays <= initialCurrentHalfLifeDays &&
             initialCurrentHalfLifeDays <= maxMemoryHalfLifeDays,
         'a new material must start inside the durability bounds',
       ),
       assert(
         priorRetrievability > 0 && priorRetrievability < 1,
         'the prior is a probability, and its logit must be finite',
       ),
       assert(
         minColdStartProbability > 0 &&
             minColdStartProbability < maxColdStartProbability &&
             maxColdStartProbability < 1,
         'the cold-start clamps must be orderable and have finite logits',
       ),
       assert(priorUncertainty > 0, 'a belief cannot start certain'),
       assert(minUncertainty > 0, 'evidence must never imply certainty'),
       assert(
         consolidationMinLogVariance > 0,
         'the posterior floor keeps projection error representable',
       ),
       assert(
         retainedInferenceGridPoints >= 3,
         'the posterior needs at least three grid points to integrate',
       ),
       assert(
         retainedInferenceMinIntervalDays >= 0,
         'the interval floor cannot be negative',
       ),
       assert(
         consolidationGrowthTargetDays > 0,
         'consolidation must saturate at a positive half-life',
       );
}

/// Priors and update rates for material- and context-specific execution
/// residuals.
@immutable
class MaterialExecutionParams {
  /// Starting variance for a residual with no evidence.
  final double priorVariance;

  /// Floor on residual variance.
  final double minVariance;

  /// `alpha_r`: how far execution surprise moves the residual mean.
  final double learningRate;

  /// `tau_r`: time constant of reversion toward the shared prediction.
  final double meanReversionTauDays;

  /// Variance added per day of nonuse.
  final double uncertaintyDiffusion;

  /// Fraction of variance removed by fully informative evidence.
  final double evidenceShrinkage;

  const MaterialExecutionParams({
    required this.priorVariance,
    required this.minVariance,
    required this.learningRate,
    required this.meanReversionTauDays,
    required this.uncertaintyDiffusion,
    required this.evidenceShrinkage,
  }) : assert(priorVariance > 0, 'a residual cannot start certain'),
       assert(minVariance > 0, 'evidence must never imply certainty'),
       assert(
         minVariance <= priorVariance,
         'the floor cannot exceed the prior',
       ),
       assert(
         learningRate >= 0,
         'evidence cannot move the mean away from itself',
       ),
       assert(
         meanReversionTauDays > 0,
         'a zero time constant would erase the residual instantly',
       ),
       assert(uncertaintyDiffusion >= 0, 'nonuse cannot increase confidence'),
       assert(
         evidenceShrinkage >= 0 && evidenceShrinkage <= 1,
         'shrinkage is a fraction of the variance to remove',
       );
}

/// Strength of the prediction-only adjustment between the two hands.
@immutable
class HandTransferParams {
  /// `rho_hand`: how much of the gap to the paired hand is borrowed at most.
  final double rhoHand;

  /// `tau_hand`: variance scale at which the adjustment is half strength.
  final double shrinkageTau;

  const HandTransferParams({required this.rhoHand, required this.shrinkageTau})
    : assert(
        rhoHand >= 0 && rhoHand <= 1,
        'transfer borrows a fraction of the gap, never more than all of it',
      ),
      assert(shrinkageTau > 0, 'the shrinkage scale must be positive');
}

/// Coefficients of the motor-difficulty score.
@immutable
class DifficultyParams {
  /// `beta_t`: weight on log tempo relative to the reference.
  final double tempoBeta;

  /// `beta_o`: weight per octave beyond the first.
  final double octaveBeta;

  /// `beta_h`: weight for playing hands together.
  final double handBeta;

  /// `beta_d`: weight for reversing direction mid-exercise.
  final double directionBeta;

  /// `b_0`: tempo at which the tempo term is zero.
  final double referenceTempoBpm;

  const DifficultyParams({
    required this.tempoBeta,
    required this.octaveBeta,
    required this.handBeta,
    required this.directionBeta,
    required this.referenceTempoBpm,
  }) : assert(
         referenceTempoBpm > 0,
         'the tempo term takes the log of a ratio to this tempo',
       );
}

/// Competency means each self-report tier starts from.
@immutable
class PlacementParams {
  /// Starting mean for a self-reported beginner.
  final double beginnerMean;

  /// Starting mean for a self-reported intermediate learner.
  final double someExperienceMean;

  /// Starting mean for a self-reported advanced learner.
  final double advancedMean;

  /// Starting variance in every tier: self-report shifts the mean but never
  /// makes the model confident.
  final double priorVarianceBroad;

  const PlacementParams({
    required this.beginnerMean,
    required this.someExperienceMean,
    required this.advancedMean,
    required this.priorVarianceBroad,
  }) : assert(
         beginnerMean <= someExperienceMean &&
             someExperienceMean <= advancedMean,
         'the tiers must be ordered by self-reported experience',
       ),
       assert(
         priorVarianceBroad > 0,
         'self-report shifts the mean but never makes the model confident',
       );
}

/// One versioned set of learner-model constants.
///
/// Every value is a heuristic V1 choice, not a research-established
/// coefficient. `analysis/learner-model/params.toml` is the authoritative
/// registry; [v1PrototypeLearnerParams] mirrors it, and a test reconciles the
/// two. Attempt records must persist [modelVersion] so replay does not
/// reinterpret old evidence under new constants.
@immutable
class LearnerParams {
  /// Identifier of this parameter set, recorded with every attempt.
  final String modelVersion;

  /// Transferable competency priors and update rates.
  final CompetencyParams competency;

  /// Exact-material memory priors, evidence rates, and transition doses.
  final MaterialMemoryParams materialMemory;

  /// Execution-residual priors and update rates.
  final MaterialExecutionParams materialExecution;

  /// Prediction-only hand-transfer strength.
  final HandTransferParams handTransfer;

  /// Motor-difficulty coefficients.
  final DifficultyParams difficulty;

  /// Self-report placement means.
  final PlacementParams placement;

  const LearnerParams({
    required this.modelVersion,
    required this.competency,
    required this.materialMemory,
    required this.materialExecution,
    required this.handTransfer,
    required this.difficulty,
    required this.placement,
  });

  /// This registry with some sections replaced.
  ///
  /// For counterfactual replay, which re-estimates recorded attempts under an
  /// alternative parameter set to compare models. Requiring [modelVersion]
  /// rather than defaulting it is deliberate: a variant that kept the original
  /// version string would be recorded as the original, and the next replay
  /// would silently reinterpret history under constants that were never used.
  LearnerParams copyWith({
    required String modelVersion,
    CompetencyParams? competency,
    MaterialMemoryParams? materialMemory,
    MaterialExecutionParams? materialExecution,
    HandTransferParams? handTransfer,
    DifficultyParams? difficulty,
    PlacementParams? placement,
  }) => LearnerParams(
    modelVersion: modelVersion,
    competency: competency ?? this.competency,
    materialMemory: materialMemory ?? this.materialMemory,
    materialExecution: materialExecution ?? this.materialExecution,
    handTransfer: handTransfer ?? this.handTransfer,
    difficulty: difficulty ?? this.difficulty,
    placement: placement ?? this.placement,
  );
}

/// The provisional V1 learner-model constants.
///
/// Mirrors `analysis/learner-model/params.toml` at registry version
/// `v1-prototype-2`. The architecture these values sit in is frozen for
/// initial production; the numbers themselves are versioned starting points
/// awaiting validation against real learner data.
const LearnerParams v1PrototypeLearnerParams = LearnerParams(
  modelVersion: 'v1-prototype-2',
  competency: CompetencyParams(
    priorMean: 0.0,
    priorVariance: 1.0,
    minVariance: 0.05,
    learningRate: 0.15,
    uncertaintyDiffusion: 0.01,
    evidenceShrinkage: 0.3,
  ),
  materialMemory: MaterialMemoryParams(
    initialCurrentHalfLifeDays: 3.0,
    alphaCurrentDurability: 0.7,
    reversionLambdaCurrentDurability: 0.05,
    minHalfLifeDays: 0.001,
    maxMemoryHalfLifeDays: 1000.0,
    priorRetrievability: 0.4,
    priorUncertainty: 1.0,
    consolidationPriorLogVariance: 2.0,
    consolidationMinLogVariance: 0.2,
    retainedInferenceMinIntervalDays: 0.041666666666666664,
    retainedInferenceLikelihoodWeight: 1.0,
    retainedInferenceGridPoints: 301,
    minUncertainty: 0.05,
    evidenceShrinkage: 0.3,
    alphaColdStart: 0.7,
    reversionLambdaColdStart: 0.05,
    minColdStartProbability: 0.001,
    maxColdStartProbability: 0.999,
    supportedActivationRestorationRate: 0.05,
    supportedCurrentDurabilityRate: 0.022556390977443608,
    successCurrentDurabilityRate: 0.022556390977443608,
    consolidationGrowthRate: 0.05,
    consolidationGrowthTargetDays: 60.0,
    supportedPracticeFactorConcurrentCues: 0.3,
    supportedPracticeFactorNotesPreviewed: 0.7,
    supportedPracticeFactorUnguided: 1.0,
    retrievalSuccessFactorNotesPreviewed: 0.7,
    retrievalSuccessFactorUnguided: 1.0,
  ),
  materialExecution: MaterialExecutionParams(
    priorVariance: 0.5,
    minVariance: 0.05,
    learningRate: 0.2,
    meanReversionTauDays: 14.0,
    uncertaintyDiffusion: 0.02,
    evidenceShrinkage: 0.3,
  ),
  handTransfer: HandTransferParams(rhoHand: 0.3, shrinkageTau: 0.5),
  difficulty: DifficultyParams(
    tempoBeta: 0.4,
    octaveBeta: 0.3,
    handBeta: 0.2,
    directionBeta: 0.15,
    referenceTempoBpm: 80.0,
  ),
  placement: PlacementParams(
    beginnerMean: -1.0,
    someExperienceMean: 0.0,
    advancedMean: 1.0,
    priorVarianceBroad: 1.5,
  ),
);
