import 'package:meta/meta.dart';

/// What a transport's timestamps were found to look like.
///
/// Measured, never asked for. The same adapter has produced two different
/// shapes in two sessions with nothing reconnected between them, so a domain
/// belongs to the session and has to be read off the stream every time.
///
/// This names no origin. Calling a shape "the BLE clock" or "the host clock"
/// is how an earlier reading of the same evidence went wrong.
@immutable
class ClockDomainObservation {
  /// The observation this was measured within.
  final String? session;

  /// How many steps between timestamps have been seen.
  final int steps;

  /// What every step so far is a multiple of, or null before any.
  final int? granularity;

  /// Where the counter was seen to wrap, or null if no single wrap has
  /// established it.
  final int? modulus;

  const ClockDomainObservation({
    this.session,
    this.steps = 0,
    this.granularity,
    this.modulus,
  });

  /// Nothing observed yet.
  static const ClockDomainObservation none = ClockDomainObservation();

  @override
  bool operator ==(Object other) =>
      other is ClockDomainObservation &&
      other.session == session &&
      other.steps == steps &&
      other.granularity == granularity &&
      other.modulus == modulus;

  @override
  int get hashCode => Object.hash(session, steps, granularity, modulus);

  @override
  String toString() =>
      'ClockDomainObservation(session: $session, steps: $steps, '
      'granularity: $granularity, modulus: $modulus)';
}

/// How close a backward step must come to a candidate width to establish it.
const double _modulusTolerance = 0.05;

/// The counter widths a wrap is matched against.
const List<int> _candidateModuli = [8192, 16384, 32768, 65536];

/// Reads the shape of a transport's clock from the stream itself.
///
/// It measures two things and claims nothing else: the granularity every step
/// is a multiple of, and the width of the counter when a single wrap
/// establishes it. Whether the shape it finds may be believed about playing is
/// [ClockDomainPolicy]'s question, kept separate so that authorizing a new
/// domain is a change of policy rather than a change to the arithmetic.
class ClockDomainDetector {
  String? _session;
  int _steps = 0;
  int? _granularity;
  int? _modulus;
  int? _lastTimestamp;
  int? _lastArrivalMs;
  int _highestTimestamp = 0;

  /// What has been found so far.
  ClockDomainObservation get observation => ClockDomainObservation(
    session: _session,
    steps: _steps,
    granularity: _granularity,
    modulus: _modulus,
  );

  /// Folds one delivery in, and returns what is known after it.
  ///
  /// A delivery from another session starts over, because that is the unit a
  /// domain belongs to. Carrying one across a boundary is how a recording
  /// lands on a clock nobody expected.
  ClockDomainObservation observe({
    required String? session,
    required int arrivalMs,
    int? timestamp,
  }) {
    if (session != _session) {
      _session = session;
      _steps = 0;
      _granularity = null;
      _modulus = null;
      _lastTimestamp = timestamp;
      _lastArrivalMs = arrivalMs;
      _highestTimestamp = timestamp ?? 0;
      return observation;
    }

    final previous = _lastTimestamp;
    final previousArrival = _lastArrivalMs;
    _lastArrivalMs = arrivalMs;
    if (timestamp == null) return observation;
    _lastTimestamp = timestamp;
    if (timestamp > _highestTimestamp) _highestTimestamp = timestamp;
    if (previous == null || previousArrival == null) return observation;

    final step = timestamp - previous;
    if (step == 0) return observation;
    _steps += 1;
    _granularity = _gcd(_granularity, step.abs());
    if (step < 0) {
      _modulus ??= _establishedModulus(
        arrivalMs - previousArrival - step,
        above: _highestTimestamp,
      );
    }
    return observation;
  }

  /// The counter width a backward step establishes, if it establishes one.
  ///
  /// The narrowest width the counter has room for, given everything it has
  /// emitted. A silence that hid several wraps still supports that width,
  /// while a gap consistent with no whole number of wraps of any candidate
  /// supports none and contributes nothing.
  ///
  /// Deciding how many epochs a particular silence hid is a different job,
  /// under a stated uncertainty bound, and it does not belong to a detector
  /// whose only claim is what the counter looks like.
  static int? _establishedModulus(int estimate, {required int above}) {
    for (final candidate in _candidateModuli) {
      // A counter cannot be narrower than a value it has emitted. Without
      // this, one silence hiding two wraps of a narrow counter is
      // indistinguishable from one wrap of a counter twice as wide, because
      // every candidate here is a multiple of the smallest.
      if (candidate <= above) continue;
      final wraps = (estimate / candidate).round();
      if (wraps < 1) continue;
      if ((estimate - wraps * candidate).abs() <=
          candidate * _modulusTolerance) {
        return candidate;
      }
    }
    return null;
  }

  static int _gcd(int? a, int b) {
    var x = a ?? b;
    var y = b;
    while (y != 0) {
      (x, y) = (y, x % y);
    }
    return x;
  }
}

/// Whether a clock may contribute performance timing.
enum ClockAuthorization {
  /// Not enough of the stream has been seen to say.
  detecting,

  /// Carries timing evidence about playing.
  performance,

  /// Understood, and not evidence about playing.
  nonPerformance,

  /// Nothing has characterized this shape. Timing is unavailable.
  unavailable,
}

/// Which measured shapes KeyRecall believes about playing.
///
/// Policy, not arithmetic. Every entry rests on the recorded takes in
/// `analysis/transport-clocks/` and on nothing else, so authorizing a fourth
/// domain is an edit here rather than a change to how a clock is measured.
///
/// Recognizing a shape is not the same as trusting it, which is why these are
/// two decisions. The 100,000-count domain carries the variation of playing
/// that its own arrival clock flattened away; the 1,000,000-count domain is
/// thoroughly recognized and has added nothing over arrival time on any take,
/// idle or loaded.
@immutable
class ClockDomainPolicy {
  /// Shapes that may contribute performance timing.
  final Set<int> performanceGranularities;

  /// Shapes that are understood and say nothing about playing.
  final Set<int> nonPerformanceGranularities;

  /// How many steps to see before naming a shape.
  ///
  /// One step is a coincidence: a granularity is a common divisor, so a short
  /// run can share a large one by chance.
  final int minimumSteps;

  const ClockDomainPolicy({
    required this.performanceGranularities,
    required this.nonPerformanceGranularities,
    this.minimumSteps = 8,
  });

  /// What the recorded takes authorize.
  static const ClockDomainPolicy characterized = ClockDomainPolicy(
    // A 1 ms counter modulo 8192, which preserves onsets delivery collapses,
    // and a 100,000-count clock seen once over a network session.
    performanceGranularities: {1, 100000},
    nonPerformanceGranularities: {1000000},
  );

  /// What [observation] may be used for.
  ///
  /// A shape nothing has recorded is unavailable rather than assumed to behave
  /// like one that has.
  ClockAuthorization classify(ClockDomainObservation observation) {
    final granularity = observation.granularity;
    if (granularity == null || observation.steps < minimumSteps) {
      return ClockAuthorization.detecting;
    }
    if (performanceGranularities.contains(granularity)) {
      return ClockAuthorization.performance;
    }
    if (nonPerformanceGranularities.contains(granularity)) {
      return ClockAuthorization.nonPerformance;
    }
    return ClockAuthorization.unavailable;
  }
}
