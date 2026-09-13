import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/clock_domain.dart';

/// Replays a recorded trace through the detector, the way the live stream
/// would arrive.
ClockDomainReading readingOf(String take) {
  final trace = jsonDecode(
    File('analysis/transport-clocks/takes/$take.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  var reading = ClockDomainReading.none;
  for (final record in trace['records'] as List<dynamic>) {
    final row = record as Map<String, dynamic>;
    if (row['kind'] != 'delivery') continue;
    reading = reading.observing(
      session: row['session'] as String?,
      arrivalMs: row['arrival_ms'] as int,
      timestamp: row['transport_ts'] as int?,
    );
  }
  return reading;
}

void main() {
  // The detector is checked against the recorded takes rather than against
  // invented numbers, because what it has to recognize is what those
  // transports actually did. See analysis/transport-clocks/.
  group('the archived traces', () {
    test('a 1 ms counter that wraps is a performance clock', () {
      final reading = readingOf('ios-jamcorder-pulse');

      expect(reading.granularity, 1);
      expect(reading.modulus, 8192);
      expect(reading.label, '1 count/ms, modulo 8192');
      expect(reading.timingUse, ClockTimingUse.performance);
    });

    test('Android reads the same as iOS', () {
      final reading = readingOf('android-jamcorder-pulse');

      expect(reading.label, '1 count/ms, modulo 8192');
      expect(reading.timingUse, ClockTimingUse.performance);
    });

    // The same adapter, twenty-six minutes later, on a different clock. The
    // reason this is measured at all rather than looked up.
    test('the same adapter reads differently in another session', () {
      final earlier = readingOf('ios-jamcorder-stall-arpeggio');
      final later = readingOf('ios-jamcorder-stall-repeated');

      expect(earlier.label, '1 count/ms, modulo 8192');
      expect(earlier.timingUse, ClockTimingUse.performance);
      expect(later.label, '1,000,000 counts/ms');
      expect(later.timingUse, ClockTimingUse.nonPerformance);
    });

    test('the piano is recognized and not a performance clock', () {
      final reading = readingOf('ios-yamaha-pulse');

      expect(reading.granularity, 1000000);
      expect(reading.modulus, isNull, reason: 'it was never seen to wrap');
      expect(reading.timingUse, ClockTimingUse.nonPerformance);
    });

    test('the network session is finer, and carries playing', () {
      final reading = readingOf('ios-network-pulse');

      expect(reading.label, '100,000 counts/ms');
      expect(reading.timingUse, ClockTimingUse.performance);
    });

    test('a silence past the modulus does not read as a wider counter', () {
      // The pause take hides two whole moduli in one gap.
      final reading = readingOf('ios-jamcorder-pause');

      expect(reading.modulus, 8192);
    });
  });

  group('what it refuses to say', () {
    ClockDomainReading after(int count, {int step = 1, int spacing = 10}) {
      var reading = ClockDomainReading.none;
      for (var index = 0; index < count; index++) {
        reading = reading.observing(
          session: 'midi-1',
          arrivalMs: index * spacing,
          timestamp: index * step,
        );
      }
      return reading;
    }

    test('a short run names nothing', () {
      expect(after(4).timingUse, ClockTimingUse.detecting);
      expect(after(4).label, isNot(contains('count')));
    });

    test('a shape nothing has recorded is unavailable, not assumed', () {
      expect(after(20, step: 7).timingUse, ClockTimingUse.unavailable);
    });

    // A domain belongs to the session. Carrying one across a boundary is how
    // a take lands on a clock nobody expected.
    test('a new session starts over', () {
      var reading = after(20);
      expect(reading.timingUse, ClockTimingUse.performance);

      reading = reading.observing(
        session: 'midi-2',
        arrivalMs: 1000,
        timestamp: 500,
      );

      expect(reading.steps, 0);
      expect(reading.granularity, isNull);
      expect(reading.timingUse, ClockTimingUse.detecting);
    });
  });
}
