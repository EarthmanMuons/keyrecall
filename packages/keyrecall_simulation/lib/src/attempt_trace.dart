import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'synthetic_learner.dart';

/// The complete record of one simulated attempt.
///
/// Carries the whole transaction: the state the decision was made from, the
/// prediction, what the hidden learner actually did, how that was weighted as
/// evidence, and the state it produced. That is the same shape the production
/// attempt journal needs, which is what makes a simulated run replayable and a
/// real run inspectable by the same tools.
@immutable
class AttemptTrace {
  /// Position of this attempt in its simulation, counting from zero.
  final int attemptIndex;

  /// When the attempt happened.
  final DateTime at;

  /// Which hidden learner produced it.
  final SyntheticProfile profile;

  /// What was presented.
  final Exercise exercise;

  /// What the model expected.
  final Prediction prediction;

  /// What actually happened.
  final Outcome outcome;

  /// How informative the attempt was, per layer.
  final EvidenceWeights weights;

  /// Where the attempt's consolidation change came from.
  final MemoryUpdateDiagnostics memoryUpdate;

  /// A snapshot of learner state as the decision saw it.
  final LearnerState stateBefore;

  /// A snapshot of learner state once the evidence was applied.
  final LearnerState stateAfter;

  const AttemptTrace({
    required this.attemptIndex,
    required this.at,
    required this.profile,
    required this.exercise,
    required this.prediction,
    required this.outcome,
    required this.weights,
    required this.memoryUpdate,
    required this.stateBefore,
    required this.stateAfter,
  });

  /// `Q[e,k]` for the presented exercise.
  Set<Competency> get structuralQ => exercise.structuralQ;

  /// `q[e,k]` across all channels, as recorded for diagnostics.
  Map<Competency, double> get loadings => normalizedLoadings(structuralQ);

  @override
  String toString() =>
      'AttemptTrace(#$attemptIndex, ${exercise.material.materialId}, '
      'predicted: ${prediction.overallP.toStringAsFixed(3)}, '
      'retrieval: ${outcome.retrieval.name})';
}
