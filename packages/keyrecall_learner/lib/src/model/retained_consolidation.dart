import 'dart:math' as math;

import '../params/learner_params.dart';
import '../state/material_memory_state.dart';

/// `P(y = 1 | h_c, dt)`: how likely a retrieval success is after
/// [elapsedDays], if retained durability really were [halfLifeDays].
double _retainedProbability(double elapsedDays, double halfLifeDays) => math
    .pow(2.0, -elapsedDays / halfLifeDays)
    .toDouble()
    .clamp(1e-12, 1 - 1e-12);

/// `log(1 + x)`, accurate for small [x] where `log(1 + x)` would lose most of
/// its significant digits. The failure likelihood needs it: a well-retained
/// material makes `1 - probability` very small.
double _log1p(double x) {
  final sum = 1.0 + x;
  final rounded = sum - 1.0;
  return rounded == 0.0 ? x : math.log(sum) * x / rounded;
}

/// Folds one factual retrieval observation into the retained-consolidation
/// posterior, and returns the change in consolidated half-life, in days.
///
/// The posterior is a Gaussian approximation over log half-life. The Bernoulli
/// likelihood is evaluated on a grid spanning the configured memory bounds,
/// and the resulting mean is projected onto the current-durability envelope so
/// `current <= consolidated` holds. Projection error is folded back into the
/// posterior variance rather than disappearing as extra certainty.
///
/// This revises what the model believes was *already* retained. It never
/// claims the attempt caused that consolidation, so execution quality is
/// deliberately absent. Returns `0.0` without touching state when the
/// observation cannot be informative: zero evidence weight, a disabled
/// likelihood, or an interval shorter than the configured floor.
///
/// Throws [ArgumentError] if the configured grid is too coarse to integrate.
double updateRetainedConsolidationPosterior({
  required MaterialMemoryState memory,
  required bool retrievalSucceeded,
  required double elapsedDays,
  required double evidenceWeight,
  required MaterialMemoryParams params,
}) {
  if (evidenceWeight <= 0.0 ||
      params.retainedInferenceLikelihoodWeight <= 0.0 ||
      elapsedDays < params.retainedInferenceMinIntervalDays) {
    return 0.0;
  }

  final gridPoints = params.retainedInferenceGridPoints;
  if (gridPoints < 3) {
    throw ArgumentError.value(
      gridPoints,
      'retainedInferenceGridPoints',
      'must be at least 3',
    );
  }
  final lower = math.log(params.minHalfLifeDays);
  final upper = math.log(params.maxMemoryHalfLifeDays);
  if (lower >= upper) return 0.0;

  final priorMean = memory.logConsolidatedHalfLife;
  final priorVariance = math.max(
    params.consolidationMinLogVariance,
    memory.consolidatedLogHalfLifeVariance,
  );
  final gridStep = (upper - lower) / (gridPoints - 1);
  final effectiveWeight =
      evidenceWeight * params.retainedInferenceLikelihoodWeight;

  final grid = List<double>.filled(gridPoints, 0);
  final logWeights = List<double>.filled(gridPoints, 0);
  for (var index = 0; index < gridPoints; index++) {
    final logHalfLife = lower + index * gridStep;
    final probability = _retainedProbability(
      elapsedDays,
      math.exp(logHalfLife),
    );
    final logLikelihood = retrievalSucceeded
        ? math.log(probability)
        : _log1p(-probability);
    final priorDeviation = logHalfLife - priorMean;
    final logPrior = -0.5 * priorDeviation * priorDeviation / priorVariance;
    grid[index] = logHalfLife;
    logWeights[index] = logPrior + effectiveWeight * logLikelihood;
  }

  final maximum = logWeights.reduce(math.max);
  var totalWeight = 0.0;
  var weightedSum = 0.0;
  final weights = List<double>.filled(gridPoints, 0);
  for (var index = 0; index < gridPoints; index++) {
    final weight = math.exp(logWeights[index] - maximum);
    weights[index] = weight;
    totalWeight += weight;
    weightedSum += grid[index] * weight;
  }
  final posteriorMean = weightedSum / totalWeight;

  var varianceSum = 0.0;
  for (var index = 0; index < gridPoints; index++) {
    final deviation = grid[index] - posteriorMean;
    varianceSum += weights[index] * deviation * deviation;
  }
  final posteriorVariance = varianceSum / totalWeight;

  final consolidationBefore = memory.consolidatedHalfLifeDays;
  final projectedMean = math.max(memory.logCurrentHalfLife, posteriorMean);
  final projectionError = projectedMean - posteriorMean;
  memory.logConsolidatedHalfLife = projectedMean;
  memory.consolidatedLogHalfLifeVariance = math.max(
    params.consolidationMinLogVariance,
    posteriorVariance + projectionError * projectionError,
  );
  return memory.consolidatedHalfLifeDays - consolidationBefore;
}
