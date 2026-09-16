import 'clock_domain.dart';
import 'performance_timing.dart';

/// Reads a performance time off a transport's own clock, or refuses to.
///
/// It holds the three parts together and adds only the conversion: the
/// detector measures the shape, the policy says what that shape is authorized
/// for, and [PerformanceClockLifecycle] decides whether a timeline may exist.
/// Every sample is reclassified before it is converted, so a timeline never
/// continues under a premise the policy has stopped accepting.
///
/// Arrival time never supplies a performance time. It has two narrower jobs
/// and no others: choosing which epoch a wrapping counter is in, and vetoing a
/// transport interval that disagrees with it beyond what policy tolerates.
/// Within that tolerance the answer does not move by one microsecond however
/// far arrival wanders, which is what makes "arrival is not a fallback" a
/// property of the code rather than a branch nobody takes.
///
/// See `docs/decisions/performance-timing.md`.
class PerformanceClockMapper {
  final ClockDomainPolicy policy;

  /// How far a transport interval and observation elapsed time may disagree.
  ///
  /// A bound on what the system tolerates, not a measurement. It has to be
  /// wide enough for a late delivery and for the drift between two clocks over
  /// a long silence, and far enough inside half a modulus that two candidates
  /// cannot both fit. On the characterized counter, candidates stand 8192 ms
  /// apart and the worst recorded gap sat 0.496 of a modulus from an ambiguous
  /// rounding.
  final int arrivalUncertaintyMs;

  /// How far the two clocks may drift apart, as a fraction of the time since
  /// the timeline was anchored.
  ///
  /// The per-delivery allowance says each step is plausible on its own, which
  /// a clock that has stopped satisfies forever: every interval it reports is
  /// zero, and zero is within a second of any short wait. This one says the
  /// timeline as a whole is still keeping time with the observation. Across
  /// the recorded takes the two clocks parted by at most 0.6 per cent of the
  /// elapsed time, so this leaves room for several times that.
  final double maxDriftFraction;

  ClockDomainDetector _detector = ClockDomainDetector();
  final PerformanceClockLifecycle _lifecycle = PerformanceClockLifecycle();

  String? _session;
  PerformanceClockDefinition? _clock;
  int _generation = -1;
  int? _lastRaw;
  int? _lastArrivalMs;
  int? _anchorArrivalMs;
  int _unwrappedCounts = 0;

  PerformanceClockMapper({
    this.policy = ClockDomainPolicy.characterized,
    this.arrivalUncertaintyMs = 1000,
    this.maxDriftFraction = 0.02,
  });

  /// Starts over, for a new observation.
  ///
  /// A timeline belongs to the observation it was anchored in, and so does
  /// what was measured about the clock: the same adapter has produced two
  /// different shapes in two sessions with nothing reconnected between them.
  void restart() {
    _detector = ClockDomainDetector();
    _lifecycle.restart();
    _session = null;
    _forget();
  }

  /// Where the clock stands.
  PerformanceClockPhase get phase => _lifecycle.phase;

  /// What has been measured so far.
  ClockDomainObservation get observation => _detector.observation;

  /// The clock times are being read off, once one is.
  PerformanceClockDefinition? get clock => _clock;

  /// Times one delivery.
  ///
  /// [arrivalMs] is when the delivery reached the app, which is evidence about
  /// the clock's shape and never about when anybody played.
  ///
  /// [declaredShape] is the shape the timestamp's format defines, where the
  /// path that produced it says. It stands in for detection until the stream
  /// contradicts it, and policy authorizes it exactly as it would a measured
  /// one.
  PerformanceTiming map({
    required String? session,
    required int arrivalMs,
    int? timestamp,
    ClockDomainShape? declaredShape,
  }) {
    if (session != _session) {
      _session = session;
      _lifecycle.restart();
      _forget();
    }

    final observation = _detector.observe(
      session: session,
      arrivalMs: arrivalMs,
      timestamp: timestamp,
    );
    final declared = declaredShape != null && _consistent(declaredShape)
        ? declaredShape
        : null;
    final shape = declared ?? observation.shape;
    final phase = _lifecycle.reclassify(
      authorization: declared == null
          ? policy.classify(observation)
          : policy.clockFor(declared) != null
          ? ClockAuthorization.performance
          : ClockAuthorization.unavailable,
      shape: shape,
      refinesAnchored: _refines(_lifecycle.anchoredShape, shape),
    );
    if (phase != PerformanceClockPhase.active) {
      _forget();
      return TimingUnavailable(_lifecycle.unavailableReason!);
    }

    final clock = _clock = policy.clockFor(_lifecycle.anchoredShape!)!;
    // A delivery without a stamp is this event's absence and nothing more.
    // Moving the anchor or the last position for it would time the next
    // complete delivery against a sample that never happened.
    if (timestamp == null) {
      return const TimingUnavailable(
        TimingUnavailableReason.missingTransportTimestamp,
      );
    }
    final modulus = clock.modulus;
    // The counter cannot be outside the width that identified it. A reading
    // that is contradicts the shape the timeline was anchored to, which is
    // structural rather than a step nobody can place.
    if (modulus != null && (timestamp < 0 || timestamp >= modulus)) {
      return _fail(TimingUnavailableReason.continuityLost);
    }

    final last = _lastRaw;
    if (last == null) {
      _lastRaw = timestamp;
      _lastArrivalMs = arrivalMs;
      _anchorArrivalMs = arrivalMs;
      _unwrappedCounts = 0;
      _generation += 1;
      return TimingAvailable(0, generation: _generation);
    }

    final rawStep = timestamp - last;
    // A counter with no characterized wrap has no reading under which this
    // went forward, so there is nothing to infer and nothing to guess.
    if (modulus == null && rawStep < 0) {
      return _fail(TimingUnavailableReason.continuityLost);
    }

    final fit = _candidatesFitting(
      rawStep: rawStep,
      modulus: modulus,
      elapsedMs: arrivalMs - _lastArrivalMs!,
      countsPerMillisecond: clock.countsPerMillisecond,
    );
    // None means this interval is not one the two clocks can both be
    // describing. Several mean the epoch count would be a guess.
    if (fit.count == 0) {
      return _fail(TimingUnavailableReason.implausibleClockStep);
    }
    if (fit.count > 1) return _fail(TimingUnavailableReason.ambiguousWrap);
    final counts = fit.counts;

    final unwrapped = _unwrappedCounts + counts;
    // Every step being plausible on its own does not make the timeline
    // plausible: a clock that has stopped reports an interval of zero forever,
    // and zero is inside any short wait's window. Arrival still chooses
    // nothing here and supplies nothing.
    if (!_keepsTime(unwrapped, arrivalMs, clock.countsPerMillisecond)) {
      return _fail(TimingUnavailableReason.implausibleClockStep);
    }

    _lastRaw = timestamp;
    _lastArrivalMs = arrivalMs;
    _unwrappedCounts = unwrapped;

    // From the anchor rather than by accumulating converted intervals, so no
    // rounding can build up across an observation. The division is exact:
    // every step is a multiple of the anchored shape's granularity, which is
    // this clock's quantum, and a quantum is a whole number of microseconds.
    return TimingAvailable(
      _unwrappedCounts * 1000 ~/ clock.countsPerMillisecond,
      generation: _generation,
    );
  }

  /// Whether [shape] is the [anchored] clock measured more finely.
  ///
  /// A greatest common divisor only ever narrows, so a clock can show a finer
  /// quantum after it was authorized on a coarser one. That is the same clock
  /// when both shapes are authorized at the same rate, wrap the same way, and
  /// the old quantum is a whole number of new ones: the counts already
  /// unwrapped keep their meaning, and the timeline has the same origin. Any
  /// other change is a different clock.
  bool _refines(ClockDomainShape? anchored, ClockDomainShape? shape) {
    if (anchored == null || shape == null || shape == anchored) return false;
    final from = policy.clockFor(anchored);
    final to = policy.clockFor(shape);
    return from != null &&
        to != null &&
        to.modulus == from.modulus &&
        to.countsPerMillisecond == from.countsPerMillisecond &&
        from.quantum % to.quantum == 0;
  }

  /// Whether what has been measured still fits [declared].
  ///
  /// Every step has to be a multiple of its quantum and any wrap has to be its
  /// width. A stream that breaks either is not in the declared format, and it
  /// falls back to the shape that was measured.
  bool _consistent(ClockDomainShape declared) {
    final measured = observation;
    final granularity = measured.granularity;
    final modulus = measured.modulus;
    return (granularity == null || granularity % declared.granularity == 0) &&
        (modulus == null || modulus == declared.modulus);
  }

  /// Whether the timeline is still keeping time with the observation.
  ///
  /// Measured from the anchor rather than delivery to delivery, so a
  /// disagreement that accumulates cannot hide by staying small each time. The
  /// allowance is what one delivery may be late by plus what the two clocks
  /// may drift apart over the time that has passed.
  bool _keepsTime(int unwrapped, int arrivalMs, int countsPerMillisecond) {
    final elapsedMs = arrivalMs - _anchorArrivalMs!;
    final performanceMs = unwrapped / countsPerMillisecond;
    final allowanceMs =
        arrivalUncertaintyMs + elapsedMs.abs() * maxDriftFraction;
    return (performanceMs - elapsedMs).abs() <= allowanceMs;
  }

  /// How many readings of this interval the two clocks can both be describing,
  /// and which one, when there is only one.
  ///
  /// A silence longer than the modulus hides whole epochs, and no sequence of
  /// stamps can say how many. Arrival elapsed time can, and that is all it is
  /// trusted with: choosing an integer, not supplying a time. A clock with no
  /// characterized wrap offers a single reading, which the same window either
  /// admits or rejects.
  ///
  /// The comparison is made in counts rather than in time because both bounds
  /// convert to counts by multiplication, which is exact, while converting a
  /// candidate to microseconds is a division that would have to round at the
  /// bounds. The tolerated disagreement is still stated in milliseconds.
  ({int count, int counts}) _candidatesFitting({
    required int rawStep,
    required int? modulus,
    required int elapsedMs,
    required int countsPerMillisecond,
  }) {
    final lowest = (elapsedMs - arrivalUncertaintyMs) * countsPerMillisecond;
    final highest = (elapsedMs + arrivalUncertaintyMs) * countsPerMillisecond;

    if (modulus == null) {
      final fits = rawStep >= lowest && rawStep <= highest;
      return (count: fits ? 1 : 0, counts: rawStep);
    }

    var first = _ceilDiv(lowest - rawStep, modulus);
    // Time does not run backward, whatever arrival says.
    final forward = _ceilDiv(-rawStep, modulus);
    if (forward > first) first = forward;
    final last = _floorDiv(highest - rawStep, modulus);

    return (
      count: last < first ? 0 : last - first + 1,
      counts: rawStep + first * modulus,
    );
  }

  PerformanceTiming _fail(TimingUnavailableReason reason) {
    _lifecycle.loseContinuity(reason);
    _forget();
    return TimingUnavailable(reason);
  }

  void _forget() {
    _clock = null;
    _lastRaw = null;
    _lastArrivalMs = null;
    _anchorArrivalMs = null;
    _unwrappedCounts = 0;
  }

  static int _floorDiv(int a, int b) => a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);

  static int _ceilDiv(int a, int b) => -_floorDiv(-a, b);
}
