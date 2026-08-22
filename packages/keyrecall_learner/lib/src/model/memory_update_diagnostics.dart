import 'package:meta/meta.dart';

/// Where an attempt's change to retained consolidation came from.
///
/// Event-local attribution, not persistent learner state. The two sources are
/// reported separately because they answer different questions: inference
/// revises what the model believes was *already* retained, while formation
/// records durability the practice itself just created.
@immutable
class MemoryUpdateDiagnostics {
  /// Change in consolidated half-life from retained-durability inference, in
  /// days.
  ///
  /// Zero unless the attempt was a factual retrieval observation after a
  /// pre-existing anchor, over an interval long enough to be informative.
  final double consolidationDeltaFromRetrievalInference;

  /// Change in consolidated half-life from causal formation, in days.
  ///
  /// Nonzero only on a successful factual retrieval, and scaled by execution
  /// quality.
  final double consolidationDeltaFromCausalFormation;

  const MemoryUpdateDiagnostics({
    this.consolidationDeltaFromRetrievalInference = 0.0,
    this.consolidationDeltaFromCausalFormation = 0.0,
  });

  @override
  String toString() =>
      'MemoryUpdateDiagnostics(inference: '
      '${consolidationDeltaFromRetrievalInference.toStringAsFixed(4)}d, '
      'formation: '
      '${consolidationDeltaFromCausalFormation.toStringAsFixed(4)}d)';
}
