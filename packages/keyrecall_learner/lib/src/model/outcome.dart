import 'package:meta/meta.dart';

/// Whether independent retrieval was tested, and what happened.
///
/// [notTested] is not a weak failure. It carries exactly zero memory evidence
/// and moves neither factual clock, which is what stops repeated fully cued
/// practice from accumulating into false evidence of remembering or
/// forgetting.
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
  /// All three values must survive serialization exactly; collapsing
  /// [notTested] into [failed] silently manufactures evidence.
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
/// The observation pipeline preserves rich MIDI-derived detail; V1 reduces it
/// only where a particular state update needs a bounded target. Every score is
/// in `[0, 1]`.
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
  final double materialRetrieval;

  /// How correct the sounded pitches were.
  final double pitchIntegrity;

  /// How unbroken the performance was.
  final double continuity;

  /// How steady the timing was.
  final double temporalStability;

  /// Achieved tempo as a fraction of the requested tempo.
  final double achievedTempoRatio;

  /// How correct the pitch/form structure was, independent of motor quality.
  final double topologyAccuracy;

  const Outcome({
    required this.started,
    required this.retrieval,
    required this.completed,
    required this.materialRetrieval,
    required this.pitchIntegrity,
    required this.continuity,
    required this.temporalStability,
    required this.achievedTempoRatio,
    required this.topologyAccuracy,
  });

  /// `y_motor`: the bounded motor score the execution channel learns from.
  ///
  /// Pitch integrity is excluded on purpose: it blends retrieval and motor
  /// quality, so it is not purely motor evidence.
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
  );

  @override
  String toString() =>
      'Outcome(started: $started, retrieval: ${retrieval.name}, '
      'completed: $completed, '
      'motor: ${motorScore.toStringAsFixed(3)})';
}
