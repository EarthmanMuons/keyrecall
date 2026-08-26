import 'dart:math' as math;

import '../elapsed_days.dart';
import '../params/learner_params.dart';

/// Whether one exact material is independently retrievable, and how durably.
///
/// Four distinct meanings are kept apart: when operative memory was last
/// anchored ([memoryAnchorAt]), how fast current availability decays
/// ([currentHalfLifeDays]), the slower durability held in reserve
/// ([consolidatedHalfLifeDays]), and when retrieval was actually tested
/// ([factualLastRetrievalAt], [lastRetrievalAttemptAt]).
///
/// Durability is stored in log-days because half-lives are positive and span
/// orders of magnitude. The envelope
/// `0 < current <= consolidated <= maxMemoryHalfLifeDays` is an invariant the
/// update path must preserve.
class MaterialMemoryState {
  /// Which material this memory is for.
  final String materialId;

  /// Natural log of the current half-life, in days.
  double logCurrentHalfLife;

  /// Uncertainty about current durability.
  ///
  /// A confidence scale, not a statistical variance; only informative
  /// retrieval evidence shrinks it.
  double currentHalfLifeUncertainty;

  /// Natural log of the retained-consolidation half-life, in days.
  double logConsolidatedHalfLife;

  /// Posterior variance of [logConsolidatedHalfLife].
  ///
  /// Unlike the current and cold-start uncertainty fields, this one has a
  /// statistical scale: it comes from the retained-durability inference.
  double consolidatedLogHalfLifeVariance;

  /// Logit of the time-independent cold-start retrieval probability.
  ///
  /// The operative prediction until a first success anchors the decay clock.
  double logitColdStart;

  /// Uncertainty about the cold-start belief.
  double coldStartUncertainty;

  /// When operative memory was last anchored, or null before any success.
  ///
  /// Productive supported practice can move this partway toward the present
  /// without recording a retrieval that never happened.
  DateTime? memoryAnchorAt;

  /// When factual retrieval last succeeded, or null if it never has.
  DateTime? factualLastRetrievalAt;

  /// Whether retrieval has ever succeeded.
  ///
  /// The whole of what a prerequisite may ask of this. Eligibility reads
  /// factual history and never an estimate, and the difference between "has
  /// this ever been retrieved" and "how long ago" is where that line would
  /// start to blur: an age is one comparison away from a durability, which
  /// belongs to prediction. Named so the boundary is in the vocabulary rather
  /// than only in a test.
  bool get hasFactualRetrieval => factualLastRetrievalAt != null;

  /// When retrieval was last factually tested, win or lose.
  ///
  /// Distinguishes "never successfully retrieved" from "never even tested",
  /// which the bootstrap probe depends on.
  DateTime? lastRetrievalAttemptAt;

  MaterialMemoryState({
    required this.materialId,
    required this.logCurrentHalfLife,
    required this.currentHalfLifeUncertainty,
    required this.logConsolidatedHalfLife,
    required this.consolidatedLogHalfLifeVariance,
    required this.logitColdStart,
    required this.coldStartUncertainty,
    this.memoryAnchorAt,
    this.factualLastRetrievalAt,
    this.lastRetrievalAttemptAt,
  });

  /// A memory state for a never-practiced material, at its configured priors.
  factory MaterialMemoryState.prior(
    String materialId,
    MaterialMemoryParams params,
  ) => MaterialMemoryState(
    materialId: materialId,
    logCurrentHalfLife: math.log(params.initialCurrentHalfLifeDays),
    currentHalfLifeUncertainty: params.priorUncertainty,
    logConsolidatedHalfLife: math.log(params.initialCurrentHalfLifeDays),
    consolidatedLogHalfLifeVariance: params.consolidationPriorLogVariance,
    logitColdStart: logit(params.priorRetrievability),
    coldStartUncertainty: params.priorUncertainty,
  );

  /// Current half-life in days: how fast availability is decaying now.
  double get currentHalfLifeDays => math.exp(logCurrentHalfLife);

  /// Retained half-life in days: durability held in reserve.
  ///
  /// Never enters prediction or ranking. It matters only when later practice
  /// restores current durability, making reacquisition faster than first
  /// acquisition.
  double get consolidatedHalfLifeDays => math.exp(logConsolidatedHalfLife);

  /// The time-independent cold-start retrieval probability.
  double get coldStartEstimate => 1.0 / (1.0 + math.exp(-logitColdStart));

  /// Whether a successful retrieval has anchored the decay clock.
  bool get isAnchored => memoryAnchorAt != null;

  /// The most recent instant this memory has recorded anything about, or null
  /// for a material with no history at all.
  DateTime? get lastObservedAt {
    DateTime? latest;
    for (final timestamp in [
      memoryAnchorAt,
      factualLastRetrievalAt,
      lastRetrievalAttemptAt,
    ]) {
      if (timestamp == null) continue;
      if (latest == null || timestamp.isAfter(latest)) latest = timestamp;
    }
    return latest;
  }

  /// `M(t)`: the modeled probability of unaided recall at [now].
  ///
  /// Throws [StateError] before any anchor exists, because elapsed time is
  /// undefined then; use [retrievabilityOrPrior] instead.
  double retrievabilityAt(DateTime now) {
    final anchor = memoryAnchorAt;
    if (anchor == null) {
      throw StateError(
        '$materialId: no anchored retrieval yet, so elapsed time is '
        'undefined; call retrievabilityOrPrior() instead',
      );
    }
    return math
        .pow(2.0, -anchor.daysUntil(now) / currentHalfLifeDays)
        .toDouble();
  }

  /// `M(t)`, falling back to the cold-start belief before any anchor.
  ///
  /// Using the cold-start belief rather than a fixed prior means a failed
  /// unguided attempt still moves the next prediction even though the
  /// half-life clock has not started.
  double retrievabilityOrPrior(DateTime now) =>
      isAnchored ? retrievabilityAt(now) : coldStartEstimate;

  /// An independent copy of this memory state.
  MaterialMemoryState copy() => MaterialMemoryState(
    materialId: materialId,
    logCurrentHalfLife: logCurrentHalfLife,
    currentHalfLifeUncertainty: currentHalfLifeUncertainty,
    logConsolidatedHalfLife: logConsolidatedHalfLife,
    consolidatedLogHalfLifeVariance: consolidatedLogHalfLifeVariance,
    logitColdStart: logitColdStart,
    coldStartUncertainty: coldStartUncertainty,
    memoryAnchorAt: memoryAnchorAt,
    factualLastRetrievalAt: factualLastRetrievalAt,
    lastRetrievalAttemptAt: lastRetrievalAttemptAt,
  );

  @override
  String toString() =>
      'MaterialMemoryState($materialId, '
      'current: ${currentHalfLifeDays.toStringAsFixed(2)}d, '
      'consolidated: ${consolidatedHalfLifeDays.toStringAsFixed(2)}d)';
}

/// The log-odds of probability [p].
double logit(double p) => math.log(p / (1.0 - p));
