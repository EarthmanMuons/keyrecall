import 'dart:math' as math;

import 'package:meta/meta.dart';

/// What the model expects from one upcoming attempt, on five separate
/// channels.
///
/// Splitting the prediction is the interpretability boundary the whole model
/// rests on: a failure to recall is primarily a memory observation, a failure
/// after starting is primarily an execution observation, and a clean cued
/// performance is useful execution evidence but no retrieval evidence at all.
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
  /// An inference target with its own outcome channel. It is deliberately not
  /// multiplied into [overallP]: material availability already answers whether
  /// the notes can be produced on this attempt.
  final double topologyP;

  const Prediction({
    required this.independentRetrievalP,
    required this.materialAvailableP,
    required this.executionP,
    required this.coordinationP,
    required this.topologyP,
  });

  /// The challenge-admission probability: every required hurdle cleared.
  ///
  /// Motor execution and coordination are correlated views of the same
  /// performance, so their weaker probability is the motor-control bottleneck
  /// rather than multiplying them as though they were independent. Material
  /// availability remains the separate hurdle.
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
