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

  final ClockDomainDetector _detector = ClockDomainDetector();
  final PerformanceClockLifecycle _lifecycle = PerformanceClockLifecycle();

  String? _session;
  PerformanceClockDefinition? _clock;
  int? _lastRaw;
  int? _lastArrivalMs;
  int _unwrappedCounts = 0;

  PerformanceClockMapper({
    this.policy = ClockDomainPolicy.characterized,
    this.arrivalUncertaintyMs = 1000,
  });

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
  PerformanceTiming map({
    required String? session,
    required int arrivalMs,
    int? timestamp,
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
    final phase = _lifecycle.reclassify(
      authorization: policy.classify(observation),
      shape: observation.shape,
    );
    if (phase != PerformanceClockPhase.active) {
      _forget();
      return TimingUnavailable(_lifecycle.unavailableReason!);
    }

    final clock = _clock ??= policy.clockFor(_lifecycle.anchoredShape!)!;
    // A delivery without a stamp is this event's absence and nothing more.
    // Moving the anchor or the last position for it would time the next
    // complete delivery against a sample that never happened.
    if (timestamp == null) {
      return const TimingUnavailable(
        TimingUnavailableReason.missingTransportTimestamp,
      );
    }
    final last = _lastRaw;
    if (last == null) {
      _lastRaw = timestamp;
      _lastArrivalMs = arrivalMs;
      _unwrappedCounts = 0;
      return const TimingAvailable(0);
    }

    final rawStep = timestamp - last;
    final modulus = clock.modulus;
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

    _lastRaw = timestamp;
    _lastArrivalMs = arrivalMs;
    _unwrappedCounts += counts;

    // From the anchor rather than by accumulating converted intervals, so no
    // rounding can build up across an observation. The division is exact:
    // every step is a multiple of the anchored shape's granularity, which is
    // this clock's quantum, and a quantum is a whole number of microseconds.
    return TimingAvailable(
      _unwrappedCounts * 1000 ~/ clock.countsPerMillisecond,
    );
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
    _unwrappedCounts = 0;
  }

  static int _floorDiv(int a, int b) => a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);

  static int _ceilDiv(int a, int b) => -_floorDiv(-a, b);
}
