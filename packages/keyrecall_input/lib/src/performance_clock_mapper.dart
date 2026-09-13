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
/// Arrival time reaches the detector and goes no further. Nothing in the
/// conversion can read it, which is what makes "arrival is not a fallback" a
/// property of the code rather than a branch nobody takes.
///
/// See `docs/decisions/performance-timing.md`.
class PerformanceClockMapper {
  final ClockDomainPolicy policy;

  final ClockDomainDetector _detector = ClockDomainDetector();
  final PerformanceClockLifecycle _lifecycle = PerformanceClockLifecycle();

  String? _session;
  PerformanceClockDefinition? _clock;
  int? _anchorRaw;
  int? _lastRaw;

  PerformanceClockMapper({this.policy = ClockDomainPolicy.characterized});

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
      _clock = null;
      _anchorRaw = null;
      _lastRaw = null;
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
      _clock = null;
      _anchorRaw = null;
      _lastRaw = null;
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
    if (clock.modulus != null) {
      return const TimingUnavailable(TimingUnavailableReason.unresolvedWrap);
    }

    final anchor = _anchorRaw;
    if (anchor == null) {
      _anchorRaw = timestamp;
      _lastRaw = timestamp;
      return const TimingAvailable(0);
    }
    // A counter with no characterized wrap has no reading under which this
    // went forward, so there is nothing to infer and nothing to guess.
    if (timestamp < _lastRaw!) {
      _lifecycle.loseContinuity(TimingUnavailableReason.continuityLost);
      return const TimingUnavailable(TimingUnavailableReason.continuityLost);
    }
    _lastRaw = timestamp;

    // From the anchor rather than by accumulating intervals, so no rounding
    // can build up across an observation. The division is exact: every step is
    // a multiple of the anchored shape's granularity, which is this clock's
    // quantum, and a quantum is a whole number of microseconds.
    return TimingAvailable(
      (timestamp - anchor) * 1000 ~/ clock.countsPerMillisecond,
    );
  }
}
