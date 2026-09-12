import 'package:meta/meta.dart';

/// The judgments measurement makes on top of what alignment observed.
///
/// Every number here is a decision about what an observation means. The timing
/// constants are engineering calibration rather than a pedagogical boundary:
/// they say what this input stack sees when someone plays comfortably. See
/// `analysis/timing-calibration/`.
@immutable
class MeasurementPolicy {
  /// Whether replaying the note just played breaks a clean retrieval.
  ///
  /// A non-progressing repetition of the previous matched note is the one kind
  /// of extra note that does not mean the wrong material was produced. What
  /// caused it is not observable here, so the classification stays structural.
  /// It still costs timing.
  final bool repeatedMatchedPitchBreaksRetrieval;

  /// Dispersion at or below which timing reads as perfectly steady.
  ///
  /// The interquartile range of the inter-onset intervals over their median,
  /// robust so one long pause does not read as unsteady playing. Comfortable
  /// playing measures between 0.04 and 0.08.
  final double steadyDispersion;

  /// Dispersion at or above which timing reads as entirely unsteady.
  ///
  /// Just under the rolled take, the mildest of the takes that are dispersed
  /// rather than interrupted, which measures 0.678 across its moments.
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
  /// Comfortable device takes included isolated 36 and 38 ms arrivals, with
  /// typical separation under 20 ms.
  final double synchronizedAsynchronyMs;

  /// Hand asynchrony at or above which a moment reads as not together at all.
  ///
  /// Beyond the widest pair in the recorded takes, which reached 134 ms while
  /// stumbling. One player on one instrument, so this is where the evidence
  /// runs out.
  final double uncoordinatedAsynchronyMs;

  /// How much of the coordination score the upper tail carries.
  ///
  /// Two readings of the same series: the median says how the hands usually
  /// sat and the tail how far apart they got, so a performance with one bad
  /// moment scores differently from one that is evenly loose.
  final double coordinationTailWeight;

  const MeasurementPolicy({
    this.repeatedMatchedPitchBreaksRetrieval = false,
    this.steadyDispersion = 0.12,
    this.unsteadyDispersion = 0.67,
    this.unbrokenIntervalRatio = 1.15,
    this.brokenIntervalRatio = 3.00,
    this.synchronizedAsynchronyMs = 40,
    this.uncoordinatedAsynchronyMs = 150,
    this.coordinationTailWeight = 0.35,
  }) : assert(
         steadyDispersion < unsteadyDispersion,
         'steadiness reads between its ends',
       ),
       assert(
         unbrokenIntervalRatio < brokenIntervalRatio,
         'continuity reads between its ends',
       ),
       assert(
         synchronizedAsynchronyMs < uncoordinatedAsynchronyMs,
         'coordination reads between its ends',
       ),
       assert(
         coordinationTailWeight >= 0 && coordinationTailWeight <= 1,
         'the tail carries a fraction of the coordination score',
       );

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
