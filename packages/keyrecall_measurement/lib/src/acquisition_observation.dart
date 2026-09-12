import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';
import 'performance_measurement.dart';

/// Whether this attempt supplies enough evidence to judge continuity.
enum AcquisitionContinuity { unestablished, unbroken, interrupted }

/// The fewest intervals a judgment of continuity can rest on.
///
/// With fewer, the interpolated upper quartile includes the maximum, so the
/// longest interval is measured against itself and the absence of a stall means
/// nothing. A task short of it supplies more intervals rather than being read
/// against a lower bar.
const int fewestIntervalsForContinuity = 5;

/// The fewest complete traversals of [realization] continuity can be read from.
///
/// Each traversal supplies one fewer interval than it has moments, and the
/// reset between two supplies none, so this is the least data
/// [fewestIntervalsForContinuity] will accept.
int traversalsForContinuity(ExerciseRealization realization) {
  final intervals = realization.moments.length - 1;
  if (intervals < 1) {
    throw ArgumentError.value(
      realization,
      'realization',
      'a traversal of one moment has no intervals to repeat toward',
    );
  }
  return (fewestIntervalsForContinuity + intervals - 1) ~/ intervals;
}

/// What was observed about one acquisition attempt.
///
/// The counterpart of [PerformanceMeasurement], and not that type, because the
/// facts an acquisition attempt supports are narrower:
///
/// - No retrieval verdict. The task carries its parent's cues, and V1 only
///   offers acquisition below a continuously cued floor, so the material was
///   supplied throughout.
/// - No tempo reading. An unmetered task asks for no tempo, so there is
///   nothing for a performed speed to be a fraction of.
/// - No outcome. Nothing here carries the measurement `outcomeFor` accepts, so
///   there is no route into the learner model's vocabulary.
///
/// What it does support is local: whether the sequence came out, what it cost
/// to get there, and where the playing stopped.
@immutable
class AcquisitionObservation {
  /// The task this was an attempt at.
  final AcquisitionTask task;

  /// Whether anything was played at all.
  final bool started;

  /// Whether the sequence came out, and at what cost.
  final AcquisitionCompletion completion;

  /// Extra notes immediately followed by the expected one.
  ///
  /// The shape a repair leaves behind. Whether it was a correction or a bounced
  /// finger is not observable here.
  final int repairs;

  /// Extra notes that were the note the performance was already on.
  final int repeats;

  /// Extra notes that were something else.
  final int intrusions;

  /// Where the performance first departed from what was asked for, or null
  /// when it never did.
  final DepartureLocation? firstDeparture;

  /// The first moment nothing arrived for, or null when everything did.
  ///
  /// Where an attempt that did not finish ran out.
  final int? firstAbsentPosition;

  /// The wait before each moment that arrived, in the order they were played.
  final List<MomentGap> gaps;

  /// What the policy was.
  final MeasurementPolicy policy;

  AcquisitionObservation({
    required this.task,
    required this.started,
    required this.completion,
    required this.repairs,
    required this.repeats,
    required this.intrusions,
    required this.firstDeparture,
    required this.firstAbsentPosition,
    required List<MomentGap> gaps,
    required this.policy,
  }) : gaps = List.unmodifiable(gaps);

  /// The gaps long enough that the policy already calls the playing broken.
  ///
  /// Localized rather than scored, against the threshold continuity already
  /// uses. An unmetered attempt has no beat to be late against, so this is a
  /// claim about the learner's own pacing only.
  List<MomentGap> get stalls => [
    for (final gap in gaps)
      if (gap.ratio >= policy.brokenIntervalRatio) gap,
  ];

  /// Continuity needs a baseline that excludes the single longest interval.
  ///
  /// Absence of a detected stall establishes nothing below
  /// [fewestIntervalsForContinuity], because the quartile the stalls were read
  /// against included the longest interval itself. A task whose single
  /// traversal cannot reach that count asks for more traversals rather than
  /// moving the bar.
  AcquisitionContinuity get continuity => stalls.isNotEmpty
      ? AcquisitionContinuity.interrupted
      : gaps.length >= fewestIntervalsForContinuity && !_hasAmbiguousTraversal
      ? AcquisitionContinuity.unbroken
      : AcquisitionContinuity.unestablished;

  /// Pooling repetitions can hide a hesitation that recurs in each traversal.
  /// Large internal spread with no pooled stall leaves continuity unknown.
  bool get _hasAmbiguousTraversal {
    if (task.portion.traversals == 1) return false;
    final starts = acquisitionTraversalStarts(task);
    for (var index = 0; index < starts.length; index++) {
      final intervals = gaps.where(
        (gap) =>
            gap.fromPosition >= starts[index] &&
            (index + 1 == starts.length || gap.toPosition < starts[index + 1]),
      );
      int? shortest;
      var longest = 0;
      for (final gap in intervals) {
        if (shortest == null || gap.gapMs < shortest) shortest = gap.gapMs;
        if (gap.gapMs > longest) longest = gap.gapMs;
      }
      if (shortest != null &&
          longest > 0 &&
          longest >= shortest * policy.brokenIntervalRatio) {
        return true;
      }
    }
    return false;
  }

  /// Whether this attempt makes the unchanged parent eligible for a probe.
  ///
  /// Criterion success, not completion: the sequence came out right the first
  /// time and the learner did not stop inside it. Completion through correction
  /// is recorded as practice.
  ///
  /// Eligibility only. Whether to conduct the probe, and how many criterion
  /// successes it takes, are the scheduler's to decide.
  bool get earnsParentProbe =>
      completion == AcquisitionCompletion.completedCleanly &&
      continuity == AcquisitionContinuity.unbroken;

  @override
  String toString() =>
      'AcquisitionObservation(${completion.id}, $repairs repairs, '
      '${stalls.length} stalls)';
}

/// Observes [transcript] as an attempt at [task].
///
/// Throws [ArgumentError] for material alignment cannot handle; see [align].
AcquisitionObservation observeAcquisition({
  required AcquisitionTask task,
  required PerformanceTranscript transcript,
  MeasurementPolicy policy = MeasurementPolicy.standard,
  AlignmentPolicy alignmentPolicy = AlignmentPolicy.standard,
}) {
  final measurement = measure(
    realization: realizeAcquisition(task),
    transcript: transcript,
    policy: policy,
    alignmentPolicy: alignmentPolicy,
  );
  final reading = measurement.reading;

  return AcquisitionObservation(
    task: task,
    started: measurement.started,
    // Produced, not merely covered. Alignment accounts for a position with a
    // substitution, so arbitrary notes would otherwise satisfy every position
    // without any of the material having been played.
    completion: reading.substituted > 0 || reading.deleted > 0
        ? AcquisitionCompletion.notCompleted
        : reading.isFirstPassClean
        ? AcquisitionCompletion.completedCleanly
        : AcquisitionCompletion.completedWithCorrections,
    repairs: reading.immediateRepairs,
    repeats: measurement.repeats,
    intrusions: measurement.intrusions,
    firstDeparture: reading.firstDeparture,
    firstAbsentPosition: reading.firstAbsentPosition,
    // The reset the task asked for is not a wait inside a traversal, and the
    // positions the task begins each one at are what says so.
    gaps: momentGapsOf(
      measurement.alignment,
      restartPositions: acquisitionTraversalStarts(task).skip(1).toSet(),
    ),
    policy: policy,
  );
}
