import 'package:collection/collection.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'alignment_policy.dart';

/// Where timing stops being confident about two adjacent observations.
///
/// Both edges come from the recorded takes in `analysis/onset-grouping/`:
/// comfortable pairs arrived within 30 ms of each other, and consecutive
/// moments no closer than 254 ms. Playing that is faster, uneven, or stumbling
/// falls between them, which is the region grouping declines to settle.
@immutable
class ObservationGroupingPolicy {
  /// At or below this gap, timing leans as hard as it may toward one moment.
  final int confidentlySameMs;

  /// At or above this gap, timing leans as hard as it may toward two.
  final int confidentlySeparateMs;

  const ObservationGroupingPolicy({
    this.confidentlySameMs = 30,
    this.confidentlySeparateMs = 250,
  }) : assert(
         confidentlySameMs < confidentlySeparateMs,
         'the confident edges must leave a region between them',
       );

  /// The V1 policy.
  static const ObservationGroupingPolicy standard = ObservationGroupingPolicy();

  @override
  String toString() =>
      'ObservationGroupingPolicy(same $confidentlySameMs, '
      'separate $confidentlySeparateMs)';
}

/// Which reading of a boundary timing prefers.
enum BoundaryLean {
  /// One performed moment.
  sameMoment('SAME_MOMENT'),

  /// Timing says nothing either way.
  ambiguous('AMBIGUOUS'),

  /// Two performed moments.
  separateMoments('SEPARATE_MOMENTS');

  const BoundaryLean(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// What timing says about the gap between two adjacent observations.
///
/// Both costs are finite, so both readings stay available to alignment however
/// the gap fell. The preference between them is what timing contributes and is
/// bounded by [AlignmentPolicy.maxGroupingPreference].
@immutable
class ObservationBoundary {
  /// The observation before the gap.
  final int beforeSequence;

  /// The observation after it.
  final int afterSequence;

  /// How long the gap was.
  final int gapMs;

  /// What reading the two observations as one performed moment costs.
  final int sameMomentCost;

  /// What reading them as two costs.
  final int splitMomentCost;

  const ObservationBoundary({
    required this.beforeSequence,
    required this.afterSequence,
    required this.gapMs,
    required this.sameMomentCost,
    required this.splitMomentCost,
  });

  /// Which reading costs less, if either.
  BoundaryLean get lean => switch (sameMomentCost.compareTo(splitMomentCost)) {
    < 0 => BoundaryLean.sameMoment,
    > 0 => BoundaryLean.separateMoments,
    _ => BoundaryLean.ambiguous,
  };

  @override
  bool operator ==(Object other) =>
      other is ObservationBoundary &&
      other.beforeSequence == beforeSequence &&
      other.afterSequence == afterSequence &&
      other.gapMs == gapMs &&
      other.sameMomentCost == sameMomentCost &&
      other.splitMomentCost == splitMomentCost;

  @override
  int get hashCode => Object.hash(
    beforeSequence,
    afterSequence,
    gapMs,
    sameMomentCost,
    splitMomentCost,
  );

  @override
  String toString() =>
      'ObservationBoundary($beforeSequence|$afterSequence, ${gapMs}ms, '
      'same $sameMomentCost, split $splitMomentCost)';
}

const _boundaryEquality = ListEquality<ObservationBoundary>();

/// What timing says about every gap in a transcript.
///
/// Candidate temporal structure over the observations, not the moments
/// themselves: which observations belong together is settled by alignment,
/// against what the exercise asked for.
@immutable
class ObservationGrouping {
  /// One boundary per adjacent pair, in arrival order.
  final List<ObservationBoundary> boundaries;

  ObservationGrouping(List<ObservationBoundary> boundaries)
    : boundaries = List.unmodifiable(boundaries);

  @override
  bool operator ==(Object other) =>
      other is ObservationGrouping &&
      _boundaryEquality.equals(other.boundaries, boundaries);

  @override
  int get hashCode => _boundaryEquality.hash(boundaries);

  @override
  String toString() => 'ObservationGrouping(${boundaries.length} boundaries)';
}

/// What timing suggests about how [transcript] was grouped into moments.
///
/// Proposals, priced. A gap inside [ObservationGroupingPolicy.confidentlySameMs]
/// makes one moment the cheaper reading and two the dearer one; a gap beyond
/// [ObservationGroupingPolicy.confidentlySeparateMs] reverses that; in between
/// the preference slides between the two. Neither reading is ever priced out of
/// the search, because recorded playing puts notes 23 ms apart in different
/// moments and notes a second apart in the same one.
///
/// Knows nothing about keys, hands, scale degrees, or what the exercise asked
/// for. It sees arrival times and nothing else, which is what stops
/// correspondence knowledge from reaching backward into observation.
ObservationGrouping groupObservations({
  required PerformanceTranscript transcript,
  ObservationGroupingPolicy policy = ObservationGroupingPolicy.standard,
  AlignmentPolicy alignmentPolicy = AlignmentPolicy.standard,
}) {
  final preference = alignmentPolicy.maxGroupingPreference;
  final span = policy.confidentlySeparateMs - policy.confidentlySameMs;

  return ObservationGrouping([
    for (var i = 1; i < transcript.length; i++)
      _boundaryBetween(
        transcript.notes[i - 1],
        transcript.notes[i],
        policy: policy,
        preference: preference,
        span: span,
      ),
  ]);
}

ObservationBoundary _boundaryBetween(
  PlayedNote before,
  PlayedNote after, {
  required ObservationGroupingPolicy policy,
  required int preference,
  required int span,
}) {
  final gapMs = after.timestampMs - before.timestampMs;
  final beyondConfidence = (gapMs - policy.confidentlySameMs).clamp(0, span);
  final splitCost = preference - (preference * beyondConfidence / span).round();

  return ObservationBoundary(
    beforeSequence: before.sequence,
    afterSequence: after.sequence,
    gapMs: gapMs,
    sameMomentCost: preference - splitCost,
    splitMomentCost: splitCost,
  );
}
