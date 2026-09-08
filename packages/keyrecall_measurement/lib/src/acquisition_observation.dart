import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';
import 'performance_measurement.dart';

/// What an acquisition attempt delivered against what it asked for.
///
/// Three values, not a score. Reaching the end after corrections is real work
/// and is recorded as such; it is simply not the same thing as reaching the
/// end without them.
enum AcquisitionCompletion {
  /// Something the task asked for never arrived.
  notCompleted('NOT_COMPLETED'),

  /// Everything arrived, with extra notes along the way.
  completedWithCorrections('COMPLETED_WITH_CORRECTIONS'),

  /// Everything arrived, right the first time.
  completedCleanly('COMPLETED_CLEANLY');

  const AcquisitionCompletion(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// Whether the task was played through.
  bool get isComplete => this != AcquisitionCompletion.notCompleted;
}

/// What was observed about one acquisition attempt.
///
/// The counterpart of [PerformanceMeasurement], and deliberately not that
/// type. The facts an acquisition attempt supports are narrower, and the ones
/// it does not support are the point:
///
/// - No retrieval verdict. The task carries its parent's cues, and V1 only
///   offers acquisition below a continuously cued floor, so the material was
///   supplied throughout.
/// - No tempo reading. An unmetered task asks for no tempo, so there is
///   nothing for a performed speed to be a fraction of.
/// - No outcome. There is no route from here into the learner model's
///   vocabulary: this keeps the facts it is entitled to and does not carry the
///   measurement that `outcomeFor` would accept.
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
  /// The shape a repair leaves behind. Whether it was hearing a mistake and
  /// fixing it or a bounced finger is not observable here.
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
  /// Localized rather than scored, and the threshold is the one continuity
  /// already uses, so a stall here and an interruption there are the same
  /// event read at two altitudes. An unmetered attempt has no beat to be late
  /// against, so this is a claim about the learner's own pacing only.
  List<MomentGap> get stalls => [
    for (final gap in gaps)
      if (gap.ratio >= policy.brokenIntervalRatio) gap,
  ];

  /// Whether this attempt makes the unchanged parent eligible for a probe.
  ///
  /// Criterion success, not completion: the sequence came out right the first
  /// time and the learner did not stop inside it. Completion through
  /// correction is practice and is recorded as practice; it is not a reason to
  /// ask the parent's question yet.
  ///
  /// Eligibility only. Whether to conduct the probe, and how many criterion
  /// successes it takes, are the scheduler's to decide.
  bool get earnsParentProbe =>
      completion == AcquisitionCompletion.completedCleanly && stalls.isEmpty;

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
    completion: !reading.isComplete
        ? AcquisitionCompletion.notCompleted
        : reading.isFirstPassClean
        ? AcquisitionCompletion.completedCleanly
        : AcquisitionCompletion.completedWithCorrections,
    repairs: reading.immediateRepairs,
    repeats: measurement.repeats,
    intrusions: measurement.intrusions,
    firstDeparture: reading.firstDeparture,
    firstAbsentPosition: reading.firstAbsentPosition,
    gaps: momentGapsOf(measurement.alignment),
    policy: policy,
  );
}
