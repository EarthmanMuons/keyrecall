import 'dart:math' as math;

import 'package:meta/meta.dart';

/// What the model expects from one upcoming attempt, on five separate
/// channels.
///
/// Splitting the prediction is what makes an outcome attributable: a failure to
/// recall is a memory observation, a failure after starting is an execution
/// observation, and a clean cued performance is execution evidence only.
@immutable
class Prediction {
  /// `M(t)`: probability the learner could recall the material with no help.
  final double independentRetrievalP;

  /// Probability the material can be produced given this attempt's guidance.
  final double materialAvailableP;

  /// Probability the motor task is executed acceptably, given the material is
  /// available.
  final double executionP;

  /// Probability the hands stay together.
  ///
  /// One for a single-hand exercise, where bilateral coordination is not a
  /// required hurdle.
  final double coordinationP;

  /// Probability the learner knows the underlying pitch/form structure.
  ///
  /// An inference target with its own outcome channel, kept out of [overallP]
  /// because material availability already answers whether the notes can be
  /// produced.
  final double topologyP;

  /// Throws [ArgumentError] for a channel outside `[0, 1]`.
  ///
  /// Each channel is subtracted from an observed score to form the residual its
  /// layer learns from, and a prediction read back from a journal is untrusted
  /// input, so an impossible channel fails here.
  Prediction({
    required this.independentRetrievalP,
    required this.materialAvailableP,
    required this.executionP,
    required this.coordinationP,
    required this.topologyP,
  }) {
    _requireProbability(independentRetrievalP, 'independentRetrievalP');
    _requireProbability(materialAvailableP, 'materialAvailableP');
    _requireProbability(executionP, 'executionP');
    _requireProbability(coordinationP, 'coordinationP');
    _requireProbability(topologyP, 'topologyP');
  }

  static void _requireProbability(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be in the range 0 to 1');
    }
  }

  /// The challenge-admission probability: every required hurdle cleared.
  ///
  /// Motor execution and coordination are correlated views of one performance,
  /// so the weaker of the two is the bottleneck rather than their product.
  /// Material availability remains a separate hurdle.
  double get overallP =>
      materialAvailableP * math.min(executionP, coordinationP);

  @override
  bool operator ==(Object other) =>
      other is Prediction &&
      other.independentRetrievalP == independentRetrievalP &&
      other.materialAvailableP == materialAvailableP &&
      other.executionP == executionP &&
      other.coordinationP == coordinationP &&
      other.topologyP == topologyP;

  @override
  int get hashCode => Object.hash(
    independentRetrievalP,
    materialAvailableP,
    executionP,
    coordinationP,
    topologyP,
  );

  @override
  String toString() =>
      'Prediction(retrieval: ${independentRetrievalP.toStringAsFixed(3)}, '
      'available: ${materialAvailableP.toStringAsFixed(3)}, '
      'execution: ${executionP.toStringAsFixed(3)}, '
      'coordination: ${coordinationP.toStringAsFixed(3)}, '
      'topology: ${topologyP.toStringAsFixed(3)})';
}
