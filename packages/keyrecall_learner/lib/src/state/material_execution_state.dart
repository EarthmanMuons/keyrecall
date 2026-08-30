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

  /// The fastest tempo this learner has managed at each span, for this
  /// material and this hand.
  ///
  /// The execution frontier, and a learner fact rather than scheduler
  /// bookkeeping: it says what has been demonstrated here, which is the same
  /// kind of claim the residual beside it makes. It belongs at this key
  /// because a right hand that has played two octaves says nothing about a
  /// left hand that has not, and hands together is a third frontier again.
  ///
  /// A tempo per span rather than a widest span and a fastest tempo, because
  /// those are two maxima and the pair of them is not a place anybody has
  /// been. One octave at 96 and two at 60 would read as two octaves at 96,
  /// and a step on from there would be asking for something a step past
  /// nothing. Execution conditions are a small lattice and this is its shape.
  ///
  /// Demonstrated rather than attempted, so a span or a tempo somebody could
  /// not get through does not become the place they are asked to go on from.
  final Map<int, double> demonstratedTempoByOctaves;

  /// The fastest tempo this learner has actually played this cleanly, whatever
  /// they were asked for.
  ///
  /// A separate question from the frontier beside it, and deliberately not
  /// folded into it. The frontier answers what this learner has been asked for
  /// and managed, which is the only thing a step goes on from; this answers how
  /// fast they play when nobody is holding them back, which is what an unseen
  /// scale should arrive near.
  ///
  /// Keeping them apart is what preserves the rule that evidence at a tempo is
  /// earned by being asked for that tempo. Somebody who plays a sixty-beat
  /// exercise at a hundred and twenty has shown a pace, not a demonstrated
  /// rung, and the next scale they meet should start nearer that pace without
  /// their frontier claiming a tempo nobody posed.
  double pacedTempoBpm;

  MaterialExecutionState({
    required this.materialId,
    required this.hands,
    required this.residualMean,
    required this.residualVariance,
    required this.updatedAt,
    this.lastEvidenceAt,
    Map<int, double>? demonstratedTempoByOctaves,
    this.pacedTempoBpm = 0,
  }) : demonstratedTempoByOctaves = demonstratedTempoByOctaves ?? {};

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
    demonstratedTempoByOctaves: {...demonstratedTempoByOctaves},
    pacedTempoBpm: pacedTempoBpm,
  );

  /// The widest span anything has been demonstrated at, or zero when nothing
  /// has.
  int get demonstratedOctaves => demonstratedTempoByOctaves.keys.fold(
    0,
    (widest, octaves) => octaves > widest ? octaves : widest,
  );

  /// The fastest tempo demonstrated at [octaves], or zero when that span has
  /// never been managed.
  double demonstratedTempoAt(int octaves) =>
      demonstratedTempoByOctaves[octaves] ?? 0;

  /// Records that [octaves] was managed at [tempoBpm].
  void demonstrate({required int octaves, required double tempoBpm}) {
    final best = demonstratedTempoByOctaves[octaves];
    if (best == null || tempoBpm > best) {
      demonstratedTempoByOctaves[octaves] = tempoBpm;
    }
  }

  /// Records that this was played cleanly at [tempoBpm], snapped to the ladder.
  void paced(double tempoBpm) {
    final rung = metronomeLadder[tempoRungOf(tempoBpm)];
    if (rung > pacedTempoBpm) pacedTempoBpm = rung;
  }

  @override
  String toString() =>
      'MaterialExecutionState($materialId/${hands.id}, '
      'mean: ${residualMean.toStringAsFixed(3)}, '
      'variance: ${residualVariance.toStringAsFixed(3)})';
}
