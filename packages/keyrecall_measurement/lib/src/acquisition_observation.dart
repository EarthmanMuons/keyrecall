import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';
import 'performance_measurement.dart';
import 'timing_evidence.dart';

/// The fewest complete traversals of [realization] continuity can be read from.
///
/// Each traversal supplies one fewer interval than it has moments, and the
/// reset between two supplies none, so this is the least data
/// [fewestContiguousWaitsForContinuity] will accept.
int traversalsForContinuity(ExerciseRealization realization) {
  final intervals = realization.moments.length - 1;
  if (intervals < 1) {
    throw ArgumentError.value(
      realization,
      'realization',
      'a traversal of one moment has no intervals to repeat toward',
    );
  }
  return (fewestContiguousWaitsForContinuity + intervals - 1) ~/ intervals;
}

/// Every transition continuity is a claim about in [task], in order.
///
/// The transitions inside a traversal, and only those. The turnaround between
/// one traversal and the next is the reset the task asked for, so nothing is
/// owed there and nothing is judged there.
List<(int, int)> acquisitionContinuityTransitions(AcquisitionTask task) {
  final length = realize(task.parent).moments.length;
  return [
    for (var repetition = 0; repetition < task.portion.traversals; repetition++)
      for (var offset = 0; offset + 1 < length; offset++)
        (repetition * length + offset, repetition * length + offset + 1),
  ];
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

  /// How the attempt sat in time, and how much of that could be judged.
  final TimingEvidence timing;

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
    required this.timing,
    required this.policy,
  });

  /// The wait before each moment that arrived, in the order they were played.
  List<MomentGap> get gaps => timing.gaps;

  /// The waits long enough that the policy already calls the playing broken.
  ///
  /// Localized rather than scored, against the threshold continuity already
  /// uses. Only the waits the attempt established a baseline for can be called
  /// long at all. An unmetered attempt has no beat to be late against, so this
  /// is a claim about the learner's own pacing only.
  List<MomentGap> get stalls => [
    for (final gap in timing.assessableGaps)
      if (gap.ratio! >= policy.brokenIntervalRatio) gap,
  ];

  /// Whether every transition continuity is a claim about was timed.
  ///
  /// Coverage of the transitions themselves, not a count of waits. Six waits
  /// out of seven are enough arithmetic for a pace and are not enough evidence
  /// that the playing never stopped, because nothing was observed across the
  /// transition that is missing. A wait spanning a moment nothing arrived for
  /// covers a stretch rather than a transition, so it establishes none of the
  /// transitions inside it.
  bool get isFullyTimed {
    final observed = {
      for (final gap in gaps) (gap.fromPosition, gap.toPosition),
    };
    return acquisitionContinuityTransitions(task).every(observed.contains);
  }

  /// Whether the playing stopped inside a traversal.
  ///
  /// A detected stall is a stop, whatever else is missing: the wait was
  /// observed and judged, and the transitions nobody timed cannot take that
  /// back.
  ///
  /// Otherwise unbroken needs everything. Every transition the criterion
  /// covers has to have been timed, and there has to be a pace the longest
  /// wait cannot have set by itself, which is why a task whose single
  /// traversal supplies too few waits asks for more traversals rather than
  /// moving the bar.
  CriterionVerdict get continuity => stalls.isNotEmpty
      ? CriterionVerdict.notMet
      : isFullyTimed && timing.isContinuityAssessable && !_hasAmbiguousTraversal
      ? CriterionVerdict.met
      : CriterionVerdict.unavailable;

  /// Whether the material came out, right the first time.
  ///
  /// Always answerable from the notes that arrived: a substitution, a deletion
  /// and a repair are each something that was observed to happen. Whether the
  /// transcript is the whole of what happened is capture integrity's question,
  /// and closure folds it in.
  CriterionVerdict get sequence =>
      completion == AcquisitionCompletion.completedCleanly
      ? CriterionVerdict.met
      : CriterionVerdict.notMet;

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
  /// Every criterion met, and not merely none of them failed. An attempt that
  /// could not judge continuity has not shown the playing held together.
  ///
  /// Eligibility only. Whether to conduct the probe, and how many criterion
  /// successes it takes, are the scheduler's to decide.
  bool get earnsParentProbe =>
      sequence == CriterionVerdict.met && continuity == CriterionVerdict.met;

  /// Whether the attempt positively established that a criterion was not met.
  ///
  /// What supported work failing means, and the only reading of an attempt
  /// that says anything about the learner having fallen short. An attempt that
  /// judged nothing is not this.
  bool get showsCriterionFailure =>
      sequence == CriterionVerdict.notMet ||
      continuity == CriterionVerdict.notMet;

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
    timing: TimingEvidence.of(
      measurement.alignment,
      restartPositions: acquisitionTraversalStarts(task).skip(1).toSet(),
    ),
    policy: policy,
  );
}
