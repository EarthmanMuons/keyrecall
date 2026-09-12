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

  /// How unbroken the performance was.
  final double continuity;

  /// How steady the timing was.
  final double temporalStability;

  /// Achieved tempo as a fraction of the requested tempo.
  ///
  /// Zero is the absence of a performance rather than a slow one. Read it
  /// through [measuredTempoRatio] rather than multiplying a requested tempo by
  /// it.
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
    _requireScore(continuity, 'continuity');
    _requireScore(temporalStability, 'temporalStability');
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

  /// `y_motor`: the bounded motor score the execution channel learns from.
  ///
  /// Pitch integrity is excluded, since it blends retrieval and motor
  /// quality.
  double get motorScore => (continuity + temporalStability) / 2.0;

  /// How productive the practice was, in `[0, 1]`.
  ///
  /// Drives the causal memory transitions. An attempt that never started or
  /// never completed contributes nothing.
  double get practiceQuality {
    if (!started || !completed) return 0.0;
    final quality = (continuity + temporalStability + pitchIntegrity) / 3.0;
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
      'motor: ${motorScore.toStringAsFixed(3)})';
}
