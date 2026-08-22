import 'package:keyrecall_domain/keyrecall_domain.dart';

import '../elapsed_days.dart';
import '../params/learner_params.dart';

/// The current belief about one transferable [Competency].
///
/// A normal distribution over capability: [mean] is the estimate, [variance]
/// is how unsure the model is about it. Mutable, because a practice attempt
/// revises the estimate in place as part of one attempt transaction.
class CompetencyState {
  /// Which competency this belief is about.
  final Competency competency;

  /// Current capability estimate.
  double mean;

  /// Uncertainty about [mean]; larger means less sure.
  double variance;

  /// When this belief was last propagated or updated.
  DateTime updatedAt;

  /// When informative evidence last arrived, or null if it never has.
  DateTime? lastEvidenceAt;

  CompetencyState({
    required this.competency,
    required this.mean,
    required this.variance,
    required this.updatedAt,
    this.lastEvidenceAt,
  });

  /// Advances this belief to [now] without evidence.
  ///
  /// Nonuse erodes confidence but does not imply decline: the variance grows
  /// while the mean is left exactly alone.
  void propagateTo(DateTime now, CompetencyParams params) {
    final elapsed = updatedAt.daysUntil(now);
    if (elapsed > 0) {
      variance += params.uncertaintyDiffusion * elapsed;
    }
    updatedAt = now;
  }

  /// An independent copy of this belief.
  CompetencyState copy() => CompetencyState(
    competency: competency,
    mean: mean,
    variance: variance,
    updatedAt: updatedAt,
    lastEvidenceAt: lastEvidenceAt,
  );

  @override
  String toString() =>
      'CompetencyState(${competency.id}, mean: ${mean.toStringAsFixed(3)}, '
      'variance: ${variance.toStringAsFixed(3)})';
}
