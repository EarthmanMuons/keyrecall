import 'package:meta/meta.dart';

/// What the model expects from one upcoming attempt, on four separate
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
    required this.topologyP,
  });

  /// The challenge-admission probability: both hurdles cleared.
  ///
  /// The modeled conjunction of material availability and conditional motor
  /// execution, not a universal latent quality score.
  double get overallP => materialAvailableP * executionP;

  @override
  bool operator ==(Object other) =>
      other is Prediction &&
      other.independentRetrievalP == independentRetrievalP &&
      other.materialAvailableP == materialAvailableP &&
      other.executionP == executionP &&
      other.topologyP == topologyP;

  @override
  int get hashCode => Object.hash(
    independentRetrievalP,
    materialAvailableP,
    executionP,
    topologyP,
  );

  @override
  String toString() =>
      'Prediction(retrieval: ${independentRetrievalP.toStringAsFixed(3)}, '
      'available: ${materialAvailableP.toStringAsFixed(3)}, '
      'execution: ${executionP.toStringAsFixed(3)}, '
      'topology: ${topologyP.toStringAsFixed(3)})';
}
