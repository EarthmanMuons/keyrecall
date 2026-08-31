import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import '../elapsed_days.dart';
import '../params/learner_params.dart';
import 'monotonic_time.dart';

/// Identifies one material under one execution context.
///
/// Material identity excludes the hand, so the same scale carries a separate
/// residual for each hand configuration it is played under.
///
/// Hand motion is part of the key because parallel and contrary hands-together
/// work are different coordination patterns: a frontier reached one way should
/// not certify execution the learner has never demonstrated the other way. A
/// single hand is always [HandMotion.parallel], which keeps the key uniform
/// rather than nullable.
typedef ExecutionContext = (
  String materialId,
  HandConfiguration hands,
  HandMotion handMotion,
);

/// The context [exercise] reads its execution evidence from and writes it to.
///
/// The one place a context is derived from an exercise, so an axis added to the
/// key reaches every caller at once instead of being remembered at each of
/// them.
ExecutionContext executionContextOf(Exercise exercise) => (
  exercise.material.materialId,
  exercise.conditions.hands,
  exercise.conditions.handMotion,
);

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

  /// Which hand motion this residual is for.
  final HandMotion handMotion;

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
  /// The execution frontier, keyed per material and hand because a right hand
  /// that has played two octaves says nothing about a left hand that has not,
  /// and hands together is a third frontier again.
  ///
  /// A tempo per span rather than a widest span and a fastest tempo, because
  /// those are two maxima and the pair of them is not a place anybody has been:
  /// one octave at 96 and two at 60 would read as two octaves at 96.
  ///
  /// Demonstrated rather than attempted, so a span or a tempo somebody could
  /// not get through does not become the place they are asked to go on from.
  final Map<int, double> demonstratedTempoByOctaves;

  /// The fastest tempo this learner has actually played this cleanly, whatever
  /// they were asked for.
  ///
  /// Deliberately not folded into the frontier beside it. The frontier answers
  /// what this learner has been asked for and managed, which is the only thing
  /// a step goes on from; this answers how fast they play unprompted, which is
  /// what an unseen scale should arrive near.
  ///
  /// Keeping them apart preserves the rule that evidence at a tempo is earned
  /// by being asked for that tempo: playing a sixty-beat exercise at a hundred
  /// and twenty shows a pace, not a demonstrated rung.
  double pacedTempoBpm;

  /// The spans at which this hand has played this material well enough for the
  /// other hand to join it, and the tempo it was actually played at there.
  ///
  /// Not the execution frontier, and deliberately kept beside it rather than
  /// derived from it. The frontier says where this hand can be asked to go on
  /// from and moves only on an attempt played rather than endured; this says
  /// the hand produced the right pitches here, which makes no claim about
  /// factual retrieval and is what a weak hand can satisfy while its frontier
  /// stays empty.
  ///
  /// The tempo recorded here is the performed one, where the frontier records
  /// the requested one. A rung is earned by being asked for it, which is what
  /// the frontier is for; this decides where coordination work begins, so it
  /// has to say where the hand actually is.
  final Map<int, double> coordinationReadyTempoByOctaves;

  MaterialExecutionState({
    required this.materialId,
    required this.hands,
    this.handMotion = HandMotion.parallel,
    required this.residualMean,
    required this.residualVariance,
    required this.updatedAt,
    this.lastEvidenceAt,
    Map<int, double>? demonstratedTempoByOctaves,
    this.pacedTempoBpm = 0,
    Map<int, double>? coordinationReadyTempoByOctaves,
  }) : demonstratedTempoByOctaves = demonstratedTempoByOctaves ?? {},
       coordinationReadyTempoByOctaves = coordinationReadyTempoByOctaves ?? {};

  /// A residual for a never-observed material and context, at its priors.
  factory MaterialExecutionState.prior(
    ExecutionContext context,
    DateTime at,
    MaterialExecutionParams params,
  ) => MaterialExecutionState(
    materialId: context.$1,
    hands: context.$2,
    handMotion: context.$3,
    residualMean: 0.0,
    residualVariance: params.priorVariance,
    updatedAt: at,
  );

  /// This residual's key in the learner state's execution map.
  ExecutionContext get context => (materialId, hands, handMotion);

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
    handMotion: handMotion,
    residualMean: residualMean,
    residualVariance: residualVariance,
    updatedAt: updatedAt,
    lastEvidenceAt: lastEvidenceAt,
    demonstratedTempoByOctaves: {...demonstratedTempoByOctaves},
    pacedTempoBpm: pacedTempoBpm,
    coordinationReadyTempoByOctaves: {...coordinationReadyTempoByOctaves},
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

  /// The tempo this hand knows [octaves] of the material at, or zero when the
  /// other hand cannot yet join it there.
  double coordinationReadyTempoAt(int octaves) =>
      coordinationReadyTempoByOctaves[octaves] ?? 0;

  /// Records that [octaves] was played with the notes known, at [tempoBpm].
  void readyForHandsTogether({required int octaves, required double tempoBpm}) {
    final best = coordinationReadyTempoByOctaves[octaves];
    if (best == null || tempoBpm > best) {
      coordinationReadyTempoByOctaves[octaves] = tempoBpm;
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
