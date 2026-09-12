import 'package:meta/meta.dart';

/// Whether independent retrieval was tested, and what happened.
///
/// [notTested] is not a weak failure. It carries zero memory evidence and moves
/// neither factual clock, so repeated fully cued practice accumulates no false
/// evidence of remembering or forgetting.
enum FactualRetrieval {
  /// Retrieval was tested without concurrent answer-supplying cues, and the
  /// learner produced the material.
  succeeded,

  /// Retrieval was tested the same way, and the learner did not.
  failed,

  /// Retrieval was never tested, because concurrent cues supplied the
  /// material.
  notTested;

  /// Whether this attempt was a genuine retrieval test.
  bool get isTested => this != FactualRetrieval.notTested;

  /// `y_retrieval`: the observed retrieval score, `1` on success.
  double get score => this == FactualRetrieval.succeeded ? 1.0 : 0.0;

  /// The `true` / `false` / `null` JSON encoding.
  ///
  /// All three values must survive serialization exactly: collapsing
  /// [notTested] into [failed] manufactures evidence.
  bool? get jsonValue => switch (this) {
    FactualRetrieval.succeeded => true,
    FactualRetrieval.failed => false,
    FactualRetrieval.notTested => null,
  };

  /// The value for a `true` / `false` / `null` JSON encoding.
  static FactualRetrieval fromJson(bool? value) => switch (value) {
    true => FactualRetrieval.succeeded,
    false => FactualRetrieval.failed,
    null => FactualRetrieval.notTested,
  };
}

/// What actually happened on one attempt.
///
/// The quality scores are bounded in `[0, 1]`. [achievedTempoRatio] need only
/// be finite and nonnegative, since a learner can overshoot the requested
/// tempo.
///
/// Construction rejects anything else, because these values reach `log` and
/// `exp` in the update path and a NaN would propagate into learner state
/// rather than failing where it entered.
@immutable
class Outcome {
  /// Whether execution began at all. Cueing can make this true even when
  /// independent retrieval would have failed.
  final bool started;

  /// Whether independent retrieval was tested, and the result.
  final FactualRetrieval retrieval;

  /// Whether the exercise was played through.
  final bool completed;

  /// Continuous, cue-inclusive measure of how much of the material appeared.
  ///
  /// Recorded rather than consumed: the update path learns about memory from
  /// [retrieval], which knows whether retrieval was tested at all. This is the
  /// graded view of the same attempt, kept for calibration.
  final double materialRetrieval;

  /// How correct the sounded pitches were.
  final double pitchIntegrity;

  /// How unbroken the performance was, or null when nothing measured it.
  ///
  /// Absent when the attempt supplied too few intervals to judge one against
  /// the others, since zero would say the playing stopped.
  final double? continuity;

  /// How steady the timing was, or null when nothing measured it.
  ///
  /// Absent on the same evidence grounds as [continuity], and separately, since
  /// the two are independent readings of the same intervals.
  final double? temporalStability;

  /// Achieved tempo as a fraction of the requested tempo.
  ///
  /// Zero is the absence of a pace rather than a slow one, and the one channel
  /// here that says so with a sentinel instead of a null. Anything asking what
  /// pace was observed, including any statistic over several attempts, reads
  /// [measuredTempoRatio] rather than this.
  final double achievedTempoRatio;

  /// How correct the pitch/form structure was, independent of motor quality.
  final double topologyAccuracy;

  /// How together the hands were, or null when nothing measured it.
  ///
  /// Absent for a single-hand attempt and for a two-hand attempt where no
  /// moment had both hands, since zero would say the hands were as far apart as
  /// playing gets.
  ///
  /// Kept out of [motorScore] and [practiceQuality]:
  /// `HANDS_TOGETHER_COORDINATION` is the only competency that learns from
  /// it.
  final double? coordination;

  /// Throws [ArgumentError] for a score outside its documented range.
  Outcome({
    required this.started,
    required this.retrieval,
    required this.completed,
    required this.materialRetrieval,
    required this.pitchIntegrity,
    required this.continuity,
    required this.temporalStability,
    required this.achievedTempoRatio,
    required this.topologyAccuracy,
    this.coordination,
  }) {
    _requireScore(materialRetrieval, 'materialRetrieval');
    _requireScore(pitchIntegrity, 'pitchIntegrity');
    if (continuity != null) _requireScore(continuity!, 'continuity');
    if (temporalStability != null) {
      _requireScore(temporalStability!, 'temporalStability');
    }
    _requireScore(topologyAccuracy, 'topologyAccuracy');
    if (coordination != null) _requireScore(coordination!, 'coordination');
    if (!achievedTempoRatio.isFinite || achievedTempoRatio < 0) {
      throw ArgumentError.value(
        achievedTempoRatio,
        'achievedTempoRatio',
        'must be finite and nonnegative',
      );
    }
  }

  static void _requireScore(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be in the range 0 to 1');
    }
  }

  /// [achievedTempoRatio] when the attempt established a pace, else null.
  ///
  /// The one interpretation of the sentinel, since zero would otherwise read as
  /// a measured stop.
  double? get measuredTempoRatio =>
      achievedTempoRatio > 0 ? achievedTempoRatio : null;

  /// `y_motor`: the bounded motor score the execution channel learns from, or
  /// null when nothing measured the timing.
  ///
  /// Pitch integrity is excluded, since it blends retrieval and motor quality.
  ///
  /// Null and zero are different claims: zero says the playing was as poor as
  /// playing gets, null that the attempt carried no timing evidence. The
  /// execution channel learns from this, so a null carries no weight rather
  /// than a bad score.
  double? get motorScore {
    final measured = _measuredTiming;
    if (measured.isEmpty) return null;
    return measured.reduce((a, b) => a + b) / measured.length;
  }

  /// The timing scores this attempt actually established.
  List<double> get _measuredTiming => [?continuity, ?temporalStability];

  /// How productive the practice was, in `[0, 1]`.
  ///
  /// Drives the causal memory transitions. An attempt that never started or
  /// never completed contributes nothing.
  ///
  /// Averaged over the channels the attempt established, so an attempt too
  /// short to time is read on its pitch alone rather than as unproductive
  /// practice.
  double get practiceQuality {
    if (!started || !completed) return 0.0;
    final scores = [..._measuredTiming, pitchIntegrity];
    final quality = scores.reduce((a, b) => a + b) / scores.length;
    return quality.clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is Outcome &&
      other.started == started &&
      other.retrieval == retrieval &&
      other.completed == completed &&
      other.coordination == coordination &&
      other.materialRetrieval == materialRetrieval &&
      other.pitchIntegrity == pitchIntegrity &&
      other.continuity == continuity &&
      other.temporalStability == temporalStability &&
      other.achievedTempoRatio == achievedTempoRatio &&
      other.topologyAccuracy == topologyAccuracy;

  @override
  int get hashCode => Object.hash(
    started,
    retrieval,
    completed,
    materialRetrieval,
    pitchIntegrity,
    continuity,
    temporalStability,
    achievedTempoRatio,
    topologyAccuracy,
    coordination,
  );

  @override
  String toString() =>
      'Outcome(started: $started, retrieval: ${retrieval.name}, '
      'completed: $completed, '
      'motor: ${motorScore?.toStringAsFixed(3) ?? 'unmeasured'})';
}
