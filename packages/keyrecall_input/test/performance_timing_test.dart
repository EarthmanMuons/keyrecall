import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

/// The characterized millisecond counter, once its wrap has been seen.
const authorized = ClockDomainShape(granularity: 1, modulus: 8192);

/// A shape a narrowing greatest common divisor can pass through on its way
/// somewhere characterized.
const unfamiliar = ClockDomainShape(granularity: 200000);

/// The characterized network clock, which the unfamiliar one can narrow into.
const alsoAuthorized = ClockDomainShape(granularity: 100000);

extension on PerformanceClockLifecycle {
  PerformanceClockPhase authorize([ClockDomainShape shape = authorized]) =>
      reclassify(authorization: ClockAuthorization.performance, shape: shape);

  PerformanceClockPhase unknown([ClockDomainShape shape = unfamiliar]) =>
      reclassify(authorization: ClockAuthorization.unavailable, shape: shape);

  PerformanceClockPhase detect() =>
      reclassify(authorization: ClockAuthorization.detecting, shape: null);

  PerformanceClockPhase quiet() => reclassify(
    authorization: ClockAuthorization.nonPerformance,
    shape: const ClockDomainShape(granularity: 1000000),
  );
}

void main() {
  late PerformanceClockLifecycle clock;

  setUp(() => clock = PerformanceClockLifecycle());

  group('before a timeline exists', () {
    test('it begins knowing nothing', () {
      expect(clock.phase, PerformanceClockPhase.detecting);
      expect(clock.unavailableReason, TimingUnavailableReason.detecting);
      expect(clock.isActive, isFalse);
    });

    test('detecting and unauthorized pass back and forth', () {
      expect(clock.unknown(), PerformanceClockPhase.unauthorized);
      expect(clock.unavailableReason, TimingUnavailableReason.unknownDomain);

      expect(clock.detect(), PerformanceClockPhase.detecting);
      expect(clock.quiet(), PerformanceClockPhase.unauthorized);
      expect(
        clock.unavailableReason,
        TimingUnavailableReason.nonPerformanceDomain,
      );
    });

    // A granularity is a running greatest common divisor, so a shape can
    // narrow from an unfamiliar 200,000 straight to a characterized 100,000.
    // A machine that only authorized out of detecting would leave that clock
    // unavailable for the rest of the observation.
    test('an unauthorized clock reaches active without passing through', () {
      expect(clock.unknown(), PerformanceClockPhase.unauthorized);

      expect(clock.authorize(alsoAuthorized), PerformanceClockPhase.active);
      expect(clock.anchoredShape, alsoAuthorized);
      expect(clock.unavailableReason, isNull);
    });

    test('refinement before a timeline costs nothing', () {
      clock
        ..unknown()
        ..detect()
        ..unknown(const ClockDomainShape(granularity: 400000));

      expect(clock.authorize(), PerformanceClockPhase.active);
    });
  });

  group('once a timeline is anchored', () {
    setUp(() => clock.authorize());

    // The times already emitted were computed against a premise now known to
    // be wrong, and nothing here may reinterpret them.
    test('a shape that narrows under it is a continuity loss', () {
      expect(clock.authorize(alsoAuthorized), PerformanceClockPhase.failed);
      expect(clock.unavailableReason, TimingUnavailableReason.continuityLost);
      expect(clock.anchoredShape, isNull);
    });

    test('the same shape again changes nothing', () {
      expect(clock.authorize(), PerformanceClockPhase.active);
      expect(clock.anchoredShape, authorized);
    });

    test('losing continuity keeps the reason it was lost for', () {
      expect(
        clock.loseContinuity(TimingUnavailableReason.ambiguousWrap),
        PerformanceClockPhase.failed,
      );
      expect(clock.unavailableReason, TimingUnavailableReason.ambiguousWrap);
    });
  });

  group('once it has failed', () {
    setUp(() {
      clock
        ..authorize()
        ..loseContinuity(TimingUnavailableReason.implausibleClockStep);
    });

    test('input that looks fine does not rehabilitate it', () {
      expect(clock.authorize(), PerformanceClockPhase.failed);
      expect(clock.detect(), PerformanceClockPhase.failed);
      expect(
        clock.unavailableReason,
        TimingUnavailableReason.implausibleClockStep,
      );
      expect(clock.anchoredShape, isNull);
    });

    test('a new observation is the only thing that clears it', () {
      clock.restart();

      expect(clock.phase, PerformanceClockPhase.detecting);
      expect(clock.unavailableReason, TimingUnavailableReason.detecting);
      expect(clock.isActive, isFalse);
    });

    test('a new observation does not inherit the old anchor', () {
      clock.restart();

      expect(clock.anchoredShape, isNull);
    });
  });

  // The property the whole layer exists for. No arrangement of states
  // produces a time without an authorized shape under it, so there is nowhere
  // for the arrival clock to leak in.
  group('nothing manufactures a time', () {
    test('no unauthorized phase is ever active', () {
      for (final drive in <void Function()>[
        clock.detect,
        clock.unknown,
        clock.quiet,
      ]) {
        drive();
        expect(clock.isActive, isFalse);
        expect(clock.unavailableReason, isNotNull);
      }
    });

    test('a failed clock is never active however it is driven', () {
      clock
        ..authorize()
        ..loseContinuity(TimingUnavailableReason.continuityLost);

      for (var attempt = 0; attempt < 5; attempt++) {
        clock.authorize();
        expect(clock.isActive, isFalse);
      }
    });
  });

  group('the two answers', () {
    test('a time carries the time and nothing else', () {
      expect(const TimingAvailable(120), const TimingAvailable(120));
      expect(const TimingAvailable(120), isNot(const TimingAvailable(121)));
    });

    test('an absence carries why', () {
      expect(
        const TimingUnavailable(TimingUnavailableReason.ambiguousWrap),
        isNot(const TimingUnavailable(TimingUnavailableReason.detecting)),
      );
    });

    test('every reason is reachable as an answer', () {
      for (final reason in TimingUnavailableReason.values) {
        expect(TimingUnavailable(reason).reason, reason);
      }
    });
  });
}
