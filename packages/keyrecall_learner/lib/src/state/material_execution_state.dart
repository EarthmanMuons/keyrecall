import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import '../elapsed_days.dart';
import '../params/learner_params.dart';
import 'monotonic_time.dart';

/// Identifies one material under one execution context.
///
/// Material identity excludes the hand, so the same scale carries a separate
/// residual for each hand configuration it is played under.
typedef ExecutionContext = (String materialId, HandConfiguration hands);

/// A persistent execution deviation this material and context show, beyond
/// what the shared competencies and task difficulty already explain.
///
/// Residuals start at zero with broad uncertainty, so sparse evidence stays
/// shrunk toward the shared prediction. A learner who is broadly strong but
/// repeatedly struggles with F major left hand acquires a negative residual
/// there instead of dragging down the global left-hand estimate.
class MaterialExecutionState {
  /// Which material this residual is for.
  final String materialId;

  /// Which hand configuration this residual is for.
  final HandConfiguration hands;

  /// The deviation, in logit units, added to the shared execution prediction.
  double residualMean;

  /// Uncertainty about [residualMean].
  double residualVariance;

  /// When this residual was last propagated or updated.
  DateTime updatedAt;

  /// When informative evidence last arrived, or null if it never has.
  DateTime? lastEvidenceAt;

  MaterialExecutionState({
    required this.materialId,
    required this.hands,
    required this.residualMean,
    required this.residualVariance,
    required this.updatedAt,
    this.lastEvidenceAt,
  });

  /// A residual for a never-observed material and context, at its priors.
  factory MaterialExecutionState.prior(
    ExecutionContext context,
    DateTime at,
    MaterialExecutionParams params,
  ) => MaterialExecutionState(
    materialId: context.$1,
    hands: context.$2,
    residualMean: 0.0,
    residualVariance: params.priorVariance,
    updatedAt: at,
  );

  /// This residual's key in the learner state's execution map.
  ExecutionContext get context => (materialId, hands);

  /// Advances this residual to [now] without evidence.
  ///
  /// An unreinforced exception fades back toward the shared prediction while
  /// the model grows less sure about it. Both the exponential reversion and
  /// the linear diffusion are explicit heuristic choices.
  ///
  /// Throws [ArgumentError] if [now] precedes [updatedAt]. Time may only move
  /// forward: rewinding and replaying an interval would revert it twice.
  void propagateTo(DateTime now, MaterialExecutionParams params) {
    requireForwardPropagation(
      now,
      updatedAt,
      '$materialId/${hands.id} residual',
    );
    final elapsed = updatedAt.daysUntil(now);
    if (elapsed > 0) {
      residualMean *= math.exp(-elapsed / params.meanReversionTauDays);
      residualVariance += params.uncertaintyDiffusion * elapsed;
    }
    updatedAt = now;
  }

  /// An independent copy of this residual.
  MaterialExecutionState copy() => MaterialExecutionState(
    materialId: materialId,
    hands: hands,
    residualMean: residualMean,
    residualVariance: residualVariance,
    updatedAt: updatedAt,
    lastEvidenceAt: lastEvidenceAt,
  );

  @override
  String toString() =>
      'MaterialExecutionState($materialId/${hands.id}, '
      'mean: ${residualMean.toStringAsFixed(3)}, '
      'variance: ${residualVariance.toStringAsFixed(3)})';
}
