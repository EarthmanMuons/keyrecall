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

  /// What has been measured, as the thing a policy decides about.
  ///
  /// Null until a granularity is known, because there is no shape to judge
  /// before then.
  ClockDomainShape? get shape => granularity == null
      ? null
      : ClockDomainShape(granularity: granularity!, modulus: modulus);

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

/// A measured clock, as much of it as has been established.
///
/// The unit a policy decides about. A granularity on its own is not a domain:
/// a counter stepping in milliseconds that wraps at 8192 and one that steps in
/// milliseconds and has never been seen to wrap are different clocks, and only
/// one of them has been characterized.
///
/// A null [modulus] means no single wrap has established a width, which is not
/// the same as a counter that does not wrap. Nothing here can tell those
/// apart, so a policy that cares has to say which it requires.
@immutable
class ClockDomainShape {
  final int granularity;
  final int? modulus;

  const ClockDomainShape({required this.granularity, this.modulus});

  @override
  bool operator ==(Object other) =>
      other is ClockDomainShape &&
      other.granularity == granularity &&
      other.modulus == modulus;

  @override
  int get hashCode => Object.hash(granularity, modulus);

  @override
  String toString() =>
      'ClockDomainShape($granularity${modulus == null ? '' : ', mod $modulus'})';
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
    // A delivery without a stamp is not half a sample. Advancing the arrival
    // without it would leave the two remembered halves describing different
    // deliveries, and a later backward step would then be measured against an
    // elapsed time that never went with it.
    if (timestamp == null) return observation;
    _lastTimestamp = timestamp;
    _lastArrivalMs = arrivalMs;
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

/// An authorized clock, and what it takes to read a time off it.
///
/// Resolution and rate are two different things. [quantum] is what every
/// observed step is a multiple of, which is the clock's resolution.
/// [countsPerMillisecond] is the rate: how fast the counter runs. They coincide on the millisecond counter and differ by a
/// factor of ten on the network session, a quantum of 100,000 counts on a
/// counter running near 1,000,000 counts to the millisecond, so that clock
/// resolves to a tenth of a millisecond.
///
/// The rate is characterized rather than measured. The detector reports shape
/// and stops there.
@immutable
class PerformanceClockDefinition {
  /// The clock's resolution, in raw counts.
  final int quantum;

  /// The counter's width, where the takes established one.
  final int? modulus;

  /// How many raw counts the clock advances per millisecond.
  final int countsPerMillisecond;

  /// Asserts what the integer timeline requires.
  ///
  /// One quantum has to be a whole number of microseconds, because every
  /// interval this clock can report is a multiple of one. A clock that fails
  /// this cannot be converted without a rounding rule, and choosing one
  /// without a trace to choose it against would invent policy rather than
  /// record characterization. The assertion runs at compile time for the
  /// constant definitions a policy is built from.
  const PerformanceClockDefinition({
    required this.quantum,
    required this.countsPerMillisecond,
    this.modulus,
  }) : assert(countsPerMillisecond > 0, 'a clock has to advance'),
       assert(
         quantum * 1000 % countsPerMillisecond == 0,
         'a quantum has to be a whole number of microseconds',
       ),
       assert(
         modulus == null || modulus % quantum == 0,
         'a counter has to wrap on a whole number of quanta',
       );

  /// What has to be measured for this clock to be recognized.
  ClockDomainShape get shape =>
      ClockDomainShape(granularity: quantum, modulus: modulus);

  /// The clock's resolution, as time.
  int get quantumUs => quantum * 1000 ~/ countsPerMillisecond;

  @override
  bool operator ==(Object other) =>
      other is PerformanceClockDefinition &&
      other.quantum == quantum &&
      other.modulus == modulus &&
      other.countsPerMillisecond == countsPerMillisecond;

  @override
  int get hashCode => Object.hash(quantum, modulus, countsPerMillisecond);

  @override
  String toString() =>
      'PerformanceClockDefinition($shape at $countsPerMillisecond counts/ms)';
}

/// Which measured shapes KeyRecall believes about playing.
///
/// Policy, not arithmetic. Every entry rests on the recorded takes in
/// `analysis/transport-clocks/` and on nothing else, so authorizing another
/// domain is an edit here rather than a change to how a clock is measured.
///
/// It authorizes shapes rather than granularities, which is the difference
/// between "a counter stepping in milliseconds" and "the counter these takes
/// characterized". Recognizing a shape is also not the same as trusting it:
/// the 100,000-count domain carries the variation of playing that its own
/// arrival clock flattened away, and the 1,000,000-count domain is trusted
/// because deliveries that reached the app in the same millisecond carry
/// stamps several milliseconds apart, which no stamp applied on arrival can.
@immutable
class ClockDomainPolicy {
  /// Shapes that may contribute performance timing.
  ///
  /// A list rather than a set because these compare by value, and Dart will
  /// not hold such a thing in a constant set.
  final List<PerformanceClockDefinition> performance;

  /// Shapes that are understood and say nothing about playing.
  final List<ClockDomainShape> nonPerformance;

  /// How many steps to see before naming a shape.
  ///
  /// One step is a coincidence: a granularity is a common divisor, so a short
  /// run can share a large one by chance.
  final int minimumSteps;

  const ClockDomainPolicy({
    required this.performance,
    required this.nonPerformance,
    this.minimumSteps = 8,
  });

  /// What the recorded takes authorize.
  ///
  /// The millisecond counter is authorized only once its wrap has been seen,
  /// because that wrap is what identifies it: the takes characterized a
  /// counter modulo 8192, not every clock that happens to step in
  /// milliseconds. The other two are authorized without one, because neither
  /// was ever seen to wrap and nothing else distinguishes them.
  ///
  /// Nothing recorded is currently understood and refused, so the refused list
  /// is empty rather than absent.
  static const ClockDomainPolicy characterized = ClockDomainPolicy(
    performance: [
      PerformanceClockDefinition(
        quantum: 1,
        modulus: 8192,
        countsPerMillisecond: 1,
      ),
      PerformanceClockDefinition(
        quantum: 100000,
        countsPerMillisecond: 1000000,
      ),
      PerformanceClockDefinition(
        quantum: 1000000,
        countsPerMillisecond: 1000000,
      ),
    ],
    nonPerformance: [],
  );

  /// What [observation] may be used for.
  ///
  /// A shape nothing has recorded is unavailable rather than assumed to behave
  /// like one that has. A shape still short of the fact that would identify
  /// it, such as a millisecond counter whose wrap has not come round yet, is
  /// still being identified rather than rejected.
  ClockAuthorization classify(ClockDomainObservation observation) {
    final shape = observation.shape;
    if (shape == null || observation.steps < minimumSteps) {
      return ClockAuthorization.detecting;
    }
    if (clockFor(shape) != null) return ClockAuthorization.performance;
    if (nonPerformance.contains(shape)) {
      return ClockAuthorization.nonPerformance;
    }
    if (shape.modulus == null && _awaitsAWrap(shape.granularity)) {
      return ClockAuthorization.detecting;
    }
    return ClockAuthorization.unavailable;
  }

  /// The authorized clock of this shape, or null if none is.
  PerformanceClockDefinition? clockFor(ClockDomainShape shape) {
    for (final clock in performance) {
      if (clock.shape == shape) return clock;
    }
    return null;
  }

  /// Whether some authorized shape of this granularity is waiting on a wrap.
  bool _awaitsAWrap(int granularity) => [
    ...performance.map((clock) => clock.shape),
    ...nonPerformance,
  ].any((shape) => shape.granularity == granularity && shape.modulus != null);
}
