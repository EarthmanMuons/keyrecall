import 'package:meta/meta.dart';

import 'clock_domain.dart';

/// Why a note carries no performance time.
///
/// Not for the learner model, which treats these alike, but so that
/// "unavailable" does not become a bucket whose recovery semantics nobody can
/// state. Three of these are terminal for an observation, one is event-local,
/// and the rest lift on their own.
enum TimingUnavailableReason {
  /// Not enough of the stream has been seen to name its clock. Transient.
  detecting,

  /// The clock is understood and says nothing about playing. Lifts if the
  /// measured shape refines into one that does.
  nonPerformanceDomain,

  /// Nothing has characterized this shape. Lifts the same way.
  unknownDomain,

  /// This delivery carried no timestamp. The next complete one is timed
  /// again, if continuity still holds.
  missingTransportTimestamp,

  /// More than one wrap count fits the tolerated arrival uncertainty, or none
  /// does. Terminal.
  ambiguousWrap,

  /// The clock moved by an amount it cannot have moved by. Terminal.
  implausibleClockStep,

  /// The shape changed under an anchored timeline, or a regression was not
  /// explained. Terminal.
  continuityLost,
}

/// When a note was played, if that is known.
@immutable
sealed class PerformanceTiming {
  const PerformanceTiming();
}

/// A time on the observation's own timeline, whose origin is arbitrary.
///
/// It carries the time and nothing else. Anything wanting to know why the
/// time is believed reads the mapper's own state, so that measurement gets
/// when and diagnostics get why, and neither has to know the other's answer.
final class TimingAvailable extends PerformanceTiming {
  final int performanceTimeMs;

  const TimingAvailable(this.performanceTimeMs);

  @override
  bool operator ==(Object other) =>
      other is TimingAvailable && other.performanceTimeMs == performanceTimeMs;

  @override
  int get hashCode => performanceTimeMs.hashCode;

  @override
  String toString() => 'TimingAvailable(${performanceTimeMs}ms)';
}

/// No time, and why.
final class TimingUnavailable extends PerformanceTiming {
  final TimingUnavailableReason reason;

  const TimingUnavailable(this.reason);

  @override
  bool operator ==(Object other) =>
      other is TimingUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'TimingUnavailable(${reason.name})';
}

/// Where a performance clock stands.
enum PerformanceClockPhase {
  /// Still measuring what the clock is.
  detecting,

  /// Measured, and not authorized to say when anybody played.
  unauthorized,

  /// Authorized, with a timeline anchored to it.
  active,

  /// Continuity was lost. Nothing recovers it but a new observation.
  failed,
}

/// What moves a performance clock between its states, and nothing else.
///
/// Arithmetic lives elsewhere on purpose. What is easy to get wrong here is
/// the difference between a shape refining before a timeline exists, which
/// costs nothing, and a shape changing under one that does, which invalidates
/// every time already emitted. That distinction is the semantic core of the
/// mapper and it needs no conversion to test.
///
/// The invariant it keeps:
///
/// > While neither active nor failed, reclassification moves freely between
/// > detecting and unauthorized, or enters active when the currently measured
/// > shape becomes authorized. Once active, a shape change or a continuity
/// > loss fails the observation, and only a new observation returns anything
/// > to detecting.
///
/// See `docs/decisions/performance-timing.md`.
class PerformanceClockLifecycle {
  PerformanceClockPhase _phase = PerformanceClockPhase.detecting;
  TimingUnavailableReason? _reason = TimingUnavailableReason.detecting;
  ClockDomainShape? _anchored;

  /// Where the clock stands.
  PerformanceClockPhase get phase => _phase;

  /// The shape the timeline was anchored to, once one is.
  ClockDomainShape? get anchoredShape => _anchored;

  /// Why there is no time, or null while there is one to be had.
  TimingUnavailableReason? get unavailableReason => _reason;

  /// Whether a time may be produced at all.
  bool get isActive => _phase == PerformanceClockPhase.active;

  /// Takes the newest reading of what the clock is.
  ///
  /// [authorization] and [shape] are what the detector and the policy make of
  /// the stream so far. A shape that narrows under an anchored timeline is a
  /// continuity loss rather than a refinement: the times already emitted were
  /// computed against a premise that is now known to be wrong, and nothing
  /// here may reinterpret them.
  PerformanceClockPhase reclassify({
    required ClockAuthorization authorization,
    required ClockDomainShape? shape,
  }) {
    if (_phase == PerformanceClockPhase.failed) return _phase;

    if (_phase == PerformanceClockPhase.active) {
      if (shape != _anchored) {
        return loseContinuity(TimingUnavailableReason.continuityLost);
      }
      return _phase;
    }

    switch (authorization) {
      case ClockAuthorization.performance:
        _anchored = shape;
        _reason = null;
        return _phase = PerformanceClockPhase.active;
      case ClockAuthorization.detecting:
        _reason = TimingUnavailableReason.detecting;
        return _phase = PerformanceClockPhase.detecting;
      case ClockAuthorization.nonPerformance:
        _reason = TimingUnavailableReason.nonPerformanceDomain;
        return _phase = PerformanceClockPhase.unauthorized;
      case ClockAuthorization.unavailable:
        _reason = TimingUnavailableReason.unknownDomain;
        return _phase = PerformanceClockPhase.unauthorized;
    }
  }

  /// Ends timing for this observation.
  ///
  /// Terminal, because once the unwrapped position is lost, later samples
  /// cannot recover it without assuming what happened across the interval that
  /// was missed, and that assumption is the fabrication this layer refuses.
  PerformanceClockPhase loseContinuity(TimingUnavailableReason reason) {
    _anchored = null;
    _reason = reason;
    return _phase = PerformanceClockPhase.failed;
  }

  /// Starts over, for a new observation or session.
  ///
  /// The only thing that clears a failure, and it clears an anchor too: a
  /// timeline belongs to the observation it was anchored in.
  void restart() {
    _phase = PerformanceClockPhase.detecting;
    _reason = TimingUnavailableReason.detecting;
    _anchored = null;
  }
}
