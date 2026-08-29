import 'package:meta/meta.dart';

/// The judgments measurement makes on top of what alignment observed.
///
/// Every number here is a decision about what an observation means, not a
/// tuning knob. The timing constants come from real playing on real hardware;
/// see `analysis/timing-calibration/`. They are provisional, and they are
/// engineering calibration rather than a pedagogical boundary: they say what
/// this input stack sees when someone plays comfortably.
@immutable
class MeasurementPolicy {
  /// Whether replaying the note just played breaks a clean retrieval.
  ///
  /// A non-progressing repetition of the previous matched note is the one kind
  /// of extra note that does not mean the learner produced the wrong material:
  /// they produced the right one, twice. What caused it, a double trigger, a
  /// bounced finger, a deliberate reiteration, a hesitation, is not observable
  /// here, so the classification stays structural and the judgment stays here.
  ///
  /// It still costs timing. Exempting a repeat from retrieval does not pretend
  /// it never happened.
  final bool repeatedMatchedPitchBreaksRetrieval;

  /// Dispersion at or below which timing reads as perfectly steady.
  ///
  /// The interquartile range of the inter-onset intervals over their median.
  /// Robust on purpose: one long pause must not read as unsteady playing, and
  /// a mean-based spread would say it was. Comfortable playing measures 0.07,
  /// and a later run of even playing across four tempi and two spans stayed
  /// between 0.04 and 0.08, so the margin here is real rather than nominal.
  final double steadyDispersion;

  /// Dispersion at or above which timing reads as entirely unsteady.
  ///
  /// Just under the rolled take, which is the mildest of the takes that are
  /// dispersed rather than interrupted and which measures 0.678 across its
  /// moments. The constant moved when quartiles became interpolated, because
  /// the reference point is the take rather than the number a particular
  /// estimator gave it.
  final double unsteadyDispersion;

  /// Longest interval, as a multiple of the slow end of ordinary playing, at
  /// or below which a performance reads as unbroken.
  ///
  /// Measured against the upper quartile rather than the median, so a
  /// performance that alternates fast and slow does not read as interrupted
  /// every time it slows down. Covers both comfortable takes, at 1.05x and
  /// 1.12x, and both hands of the stumble, at 1.06x and 1.14x.
  final double unbrokenIntervalRatio;

  /// Longest-interval ratio at or above which a performance reads as entirely
  /// broken. Between the out-of-phase take at 2.69x and the uneven D major at
  /// 2.94x.
  final double brokenIntervalRatio;

  /// Hand asynchrony at or below which a moment reads as together, in
  /// milliseconds.
  ///
  /// Comfortable playing in `analysis/onset-grouping/` kept every pair within
  /// 30 ms, most within 11.
  final double synchronizedAsynchronyMs;

  /// Hand asynchrony at or above which a moment reads as not together at all.
  ///
  /// Beyond the widest pair in the recorded takes, which reached 134 ms while
  /// stumbling. One player on one instrument, so this is where the evidence
  /// runs out rather than where coordination stops being acceptable.
  final double uncoordinatedAsynchronyMs;

  /// How much of the coordination score the upper tail carries.
  ///
  /// Two readings of the same series: the median says how the hands usually
  /// sat, the tail says how far apart they got. Kept apart so a performance
  /// that is mostly together with one bad moment scores differently from one
  /// that is evenly loose.
  final double coordinationTailWeight;

  const MeasurementPolicy({
    this.repeatedMatchedPitchBreaksRetrieval = false,
    this.steadyDispersion = 0.12,
    this.unsteadyDispersion = 0.67,
    this.unbrokenIntervalRatio = 1.15,
    this.brokenIntervalRatio = 3.00,
    this.synchronizedAsynchronyMs = 30,
    this.uncoordinatedAsynchronyMs = 150,
    this.coordinationTailWeight = 0.35,
  });

  /// The V1 policy.
  static const MeasurementPolicy standard = MeasurementPolicy();

  /// How steady [dispersion] reads, in `[0, 1]`.
  double steadinessOf(double dispersion) =>
      _between(dispersion, best: steadyDispersion, worst: unsteadyDispersion);

  /// How unbroken a performance whose longest interval is [ratio] times the
  /// upper quartile reads, in `[0, 1]`.
  double unbrokennessOf(double ratio) =>
      _between(ratio, best: unbrokenIntervalRatio, worst: brokenIntervalRatio);

  /// How together hands that sat [medianMs] apart typically, and [p90Ms] apart
  /// at their worst, read, in `[0, 1]`.
  double coordinationOf({required double medianMs, required double p90Ms}) =>
      (1 - coordinationTailWeight) * _togetherness(medianMs) +
      coordinationTailWeight * _togetherness(p90Ms);

  double _togetherness(double asynchronyMs) => _between(
    asynchronyMs,
    best: synchronizedAsynchronyMs,
    worst: uncoordinatedAsynchronyMs,
  );

  /// Linear between the two ends, since nothing yet justifies a curve.
  static double _between(
    double value, {
    required double best,
    required double worst,
  }) {
    if (!value.isFinite) return 0;
    if (value <= best) return 1;
    if (value >= worst) return 0;
    return (worst - value) / (worst - best);
  }
}
