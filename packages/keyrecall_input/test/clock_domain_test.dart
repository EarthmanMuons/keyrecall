import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

/// Replays a recorded trace through the detector, the way a live stream would
/// arrive.
///
/// Checked against what transports actually did rather than against invented
/// numbers: these are the takes in `analysis/transport-clocks/`, and what the
/// detector has to recognize is exactly what is in them.
ClockDomainObservation readingOf(String take) {
  final trace =
      jsonDecode(
            File(
              '../../analysis/transport-clocks/takes/$take.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final detector = ClockDomainDetector();
  var observation = ClockDomainObservation.none;
  for (final record in trace['records'] as List<dynamic>) {
    final row = record as Map<String, dynamic>;
    if (row['kind'] != 'delivery') continue;
    observation = detector.observe(
      session: row['session'] as String?,
      arrivalMs: row['arrival_ms'] as int,
      timestamp: row['transport_ts'] as int?,
    );
  }
  return observation;
}

ClockAuthorization useOf(ClockDomainObservation observation) =>
    ClockDomainPolicy.characterized.classify(observation);

void main() {
  group('the archived traces', () {
    test('a 1 ms counter that wraps is a performance clock', () {
      final observation = readingOf('ios-jamcorder-pulse');

      expect(observation.granularity, 1);
      expect(observation.modulus, 8192);
      expect(useOf(observation), ClockAuthorization.performance);
    });

    test('Android reads the same as iOS', () {
      final observation = readingOf('android-jamcorder-pulse');

      expect(observation.granularity, 1);
      expect(observation.modulus, 8192);
      expect(useOf(observation), ClockAuthorization.performance);
    });

    // The same adapter, twenty-six minutes later, on a different clock. The
    // reason this is measured at all rather than looked up.
    test('the same adapter reads differently in another session', () {
      final earlier = readingOf('ios-jamcorder-stall-arpeggio');
      final later = readingOf('ios-jamcorder-stall-repeated');

      expect(earlier.granularity, 1);
      expect(useOf(earlier), ClockAuthorization.performance);
      expect(later.granularity, 1000000);
      expect(useOf(later), ClockAuthorization.nonPerformance);
    });

    test('the piano is recognized and not a performance clock', () {
      final observation = readingOf('ios-yamaha-pulse');

      expect(observation.granularity, 1000000);
      expect(observation.modulus, isNull, reason: 'it was never seen to wrap');
      expect(useOf(observation), ClockAuthorization.nonPerformance);
    });

    test('the network session is finer, and carries playing', () {
      final observation = readingOf('ios-network-pulse');

      expect(observation.granularity, 100000);
      expect(useOf(observation), ClockAuthorization.performance);
    });

    // The pause take hides two whole moduli in one gap. The wraps either side
    // of it establish the width; the long one contributes nothing.
    test('a silence past the modulus does not widen the counter', () {
      expect(readingOf('ios-jamcorder-pause').modulus, 8192);
    });
  });

  group('what it refuses to say', () {
    ClockDomainObservation after(
      int count, {
      int step = 1,
      int spacing = 10,
      ClockDomainDetector? into,
    }) {
      final detector = into ?? ClockDomainDetector();
      var observation = ClockDomainObservation.none;
      for (var index = 0; index < count; index++) {
        observation = detector.observe(
          session: 'midi-1',
          arrivalMs: index * spacing,
          timestamp: index * step,
        );
      }
      return observation;
    }

    test('a short run names nothing', () {
      final observation = after(4);

      expect(useOf(observation), ClockAuthorization.detecting);
    });

    test('a shape nothing has recorded is unavailable, not assumed', () {
      expect(useOf(after(20, step: 7)), ClockAuthorization.unavailable);
    });

    // A domain belongs to a session. Carrying one across a boundary is how a
    // take lands on a clock nobody expected.
    test('a new session starts over', () {
      final detector = ClockDomainDetector();
      expect(after(20, into: detector).granularity, 1);

      final observation = detector.observe(
        session: 'midi-2',
        arrivalMs: 1000,
        timestamp: 500,
      );

      expect(observation.steps, 0);
      expect(observation.granularity, isNull);
      expect(useOf(observation), ClockAuthorization.detecting);
    });

    // A wrap establishes a width; a silence that could have hidden several is
    // consistent with one without demonstrating it.
    test('an ambiguous silence establishes no modulus', () {
      final detector = ClockDomainDetector()
        ..observe(session: 'a', arrivalMs: 0, timestamp: 8000);
      final observation = detector.observe(
        session: 'a',
        arrivalMs: 20000,
        timestamp: 500,
      );

      expect(observation.modulus, isNull);
    });
  });

  group('policy is separable from arithmetic', () {
    test('another domain is authorized without touching the detector', () {
      const observation = ClockDomainObservation(
        session: 'a',
        steps: 20,
        granularity: 250,
      );

      expect(
        ClockDomainPolicy.characterized.classify(observation),
        ClockAuthorization.unavailable,
      );
      expect(
        const ClockDomainPolicy(
          performance: [
            PerformanceClockDefinition(quantum: 250, countsPerMillisecond: 250),
          ],
          nonPerformance: [],
        ).classify(observation),
        ClockAuthorization.performance,
      );
    });

    // The network clock only ever steps by 100,000 counts, on a counter
    // running near 1,000,000 counts to the millisecond. Converting by the
    // quantum would run it ten times fast, and every millisecond-counter test
    // would still pass.
    test('a quantum is not a rate', () {
      final network = ClockDomainPolicy.characterized.clockFor(
        const ClockDomainShape(granularity: 100000),
      );

      expect(network, isNotNull);
      expect(network!.quantum, 100000);
      expect(network.countsPerMillisecond, 1000000);

      final counter = ClockDomainPolicy.characterized.clockFor(
        const ClockDomainShape(granularity: 1, modulus: 8192),
      );

      expect(counter!.quantum, counter.countsPerMillisecond);
    });

    // The integer timeline can only hold a clock whose quantum is a whole
    // number of microseconds. Anything else needs a rounding rule, and there
    // is no trace to choose one against.
    test('a clock that does not convert exactly cannot be authorized', () {
      expect(
        () => PerformanceClockDefinition(quantum: 1, countsPerMillisecond: 3),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PerformanceClockDefinition(quantum: 1, countsPerMillisecond: 0),
        throwsA(isA<AssertionError>()),
      );

      for (final clock in ClockDomainPolicy.characterized.performance) {
        expect(clock.quantum * 1000 % clock.countsPerMillisecond, 0);
      }
      expect(
        ClockDomainPolicy.characterized.performance.map(
          (clock) => clock.quantumUs,
        ),
        [1000, 100],
      );
    });

    // A shape is granularity and wrap together, so the same counter width
    // under two different moduli is two domains.
    test('a shape is not its granularity', () {
      const wrapping = ClockDomainShape(granularity: 1, modulus: 8192);
      const unwrapped = ClockDomainShape(granularity: 1);

      expect(wrapping, isNot(unwrapped));
      expect(ClockDomainPolicy.characterized.clockFor(wrapping), isNotNull);
      expect(ClockDomainPolicy.characterized.clockFor(unwrapped), isNull);
    });
  });

  // A delivery carrying no timestamp is not half a sample. Advancing the
  // remembered arrival without one leaves the two halves describing different
  // deliveries, and a later backward step is then measured against an elapsed
  // time that never went with it.
  group('a delivery without a timestamp', () {
    test('does not break the pair the next step is measured against', () {
      final detector = ClockDomainDetector()
        ..observe(session: 'a', arrivalMs: 0, timestamp: 8000)
        ..observe(session: 'a', arrivalMs: 5000, timestamp: null);
      final observation = detector.observe(
        session: 'a',
        arrivalMs: 8100,
        timestamp: 100,
      );

      // From the last complete sample the wrap spans 8100 ms and -7900
      // counts, one turn of an 8192 counter. From the mismatched pair it
      // would span 3100 ms and the same counts, which is not.
      expect(observation.modulus, 8192);
    });
  });
}
