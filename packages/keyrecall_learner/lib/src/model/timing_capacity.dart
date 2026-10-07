import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'outcome.dart';

/// The fewest waits a pace can be read from.
///
/// One wait is an interval, not a pace. Two supply no center either one
/// cannot dominate. Three are the first that let a median set one of them
/// aside.
const int fewestWaitsForPace = 3;

/// The fewest waits a spread can be read from.
///
/// Below this a single wait carries too much of the deviation for the result
/// to describe the playing rather than that wait.
const int fewestWaitsForSpread = 5;

/// The fewest waits in one unbroken stretch a continuity claim needs.
///
/// Continuity is a claim about playing that did not stop, so it asks for a
/// stretch that did not stop rather than for waits gathered from wherever they
/// survived. Eight waits in one run and in four runs of two are the same
/// arithmetic and not the same evidence, and only the first can support this.
const int fewestContiguousWaitsForContinuity = 5;

/// What timing one traversal of an exercise can establish at best.
///
/// A ceiling set by structure alone: a performance can establish less, through
/// holes or stops, and never more. Measurement applies the same thresholds to
/// what was played, so asking this in advance gives the answer measurement
/// would give a clean traversal.
@immutable
class TimingCapacity {
  /// Waits between consecutive moments in one traversal.
  final int waits;

  const TimingCapacity(this.waits);

  /// The capacity of one traversal of [exercise].
  TimingCapacity.of(Exercise exercise) : waits = exercise.transitionCount;

  /// Whether a pace can be read.
  bool get supportsPace => waits >= fewestWaitsForPace;

  /// Whether a spread can be read, which [Outcome.temporalStability] needs.
  bool get supportsSpread => waits >= fewestWaitsForSpread;

  /// Whether an unbroken stretch can be long enough for
  /// [Outcome.continuity].
  bool get supportsContinuity => waits >= fewestContiguousWaitsForContinuity;

  /// Whether an attempt can carry an [Outcome.motorScore], the only evidence
  /// the motor competencies and the execution residual learn from.
  bool get supportsMotorScore => supportsContinuity || supportsSpread;

  @override
  bool operator ==(Object other) =>
      other is TimingCapacity && other.waits == waits;

  @override
  int get hashCode => waits.hashCode;

  @override
  String toString() => 'TimingCapacity($waits waits)';
}
