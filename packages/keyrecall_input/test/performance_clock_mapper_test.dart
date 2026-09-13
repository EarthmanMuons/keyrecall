import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

/// Timestamps stepping the way the network session's clock was seen to: only
/// in whole units of 100,000 counts, on a counter running near a million to
/// the millisecond. Eight steps is what the policy asks for before it names a
/// shape, and the alternating sizes are what make the greatest common divisor
/// settle on 100,000 rather than on one take's step.
const networkWarmup = [
  0,
  300000,
  500000,
  800000,
  1000000,
  1300000,
  1500000,
  1800000,
  2000000,
];

/// Where the timeline is anchored once [networkWarmup] has been fed in.
const networkAnchor = 2000000;

/// A millisecond counter of the kind the BLE takes recorded, short of the wrap
/// that identifies it.
const wrappingWarmup = [100, 101, 102, 103, 104, 105, 106, 107, 108];

extension on PerformanceClockMapper {
  /// Feeds deliveries in, one arrival millisecond apart, and returns what each
  /// was timed as.
  ///
  /// The arrival spacing is deliberately uniform and deliberately wrong: no
  /// conversion may read it.
  List<PerformanceTiming> feed(
    List<int?> timestamps, {
    int arrivalStep = 1,
  }) => [
    for (final (index, timestamp) in timestamps.indexed)
      map(session: 'a', arrivalMs: index * arrivalStep, timestamp: timestamp),
  ];
}

void main() {
  late PerformanceClockMapper mapper;

  setUp(() => mapper = PerformanceClockMapper());

  group('before a domain is authorized', () {
    test('nothing is timed while the shape is still being measured', () {
      final timings = mapper.feed(networkWarmup.take(4).toList());

      expect(
        timings,
        everyElement(
          const TimingUnavailable(TimingUnavailableReason.detecting),
        ),
      );
      expect(mapper.phase, PerformanceClockPhase.detecting);
    });

    test('the first authorized delivery is the origin', () {
      final timings = mapper.feed(networkWarmup);

      expect(timings.last, const TimingAvailable(0));
      expect(mapper.phase, PerformanceClockPhase.active);
      expect(mapper.clock?.countsPerMillisecond, 1000000);
    });
  });

  group('converting an authorized domain that does not wrap', () {
    setUp(() => mapper.feed(networkWarmup));

    // The take this domain was characterized from, at the scale it was
    // recorded at.
    test('a delta converts at the clock rate', () {
      expect(
        mapper.map(
          session: 'a',
          arrivalMs: 1000,
          timestamp: networkAnchor + 714000000,
        ),
        const TimingAvailable(714000),
      );
    });

    // The small one. Converting by the quantum instead of the rate reads this
    // as 1,000 us, and reads every millisecond-counter take correctly.
    test('one quantum is a tenth of a millisecond', () {
      expect(
        mapper.map(
          session: 'a',
          arrivalMs: 1000,
          timestamp: networkAnchor + 100000,
        ),
        const TimingAvailable(100),
      );
    });

    test('times are measured from the anchor, not accumulated', () {
      final timings = mapper.feed([
        for (var step = 1; step <= 4; step++) networkAnchor + step * 100000,
      ]);

      expect(timings, const [
        TimingAvailable(100),
        TimingAvailable(200),
        TimingAvailable(300),
        TimingAvailable(400),
      ]);
    });
  });

  // The property the layer exists for, as an experiment rather than a branch:
  // move arrival as far as it will go and see whether any answer moves.
  test('arrival time cannot change a performance time', () {
    final stamps = [
      ...networkWarmup,
      networkAnchor + 100000,
      networkAnchor + 900000,
      networkAnchor + 1000000,
    ];

    final steady = PerformanceClockMapper().feed(stamps);
    final jittered = PerformanceClockMapper().feed(stamps, arrivalStep: 7919);

    expect(jittered, steady);
    expect(steady.last, const TimingAvailable(1000));
  });

  group('a delivery without a timestamp', () {
    setUp(() => mapper.feed(networkWarmup));

    test('is untimed without disturbing the timeline', () {
      expect(
        mapper.map(session: 'a', arrivalMs: 500, timestamp: null),
        const TimingUnavailable(
          TimingUnavailableReason.missingTransportTimestamp,
        ),
      );
      expect(
        mapper.map(
          session: 'a',
          arrivalMs: 600,
          timestamp: networkAnchor + 200000,
        ),
        const TimingAvailable(200),
      );
      expect(mapper.phase, PerformanceClockPhase.active);
    });
  });

  group('a timestamp that goes backward', () {
    setUp(() => mapper.feed(networkWarmup));

    // Nothing has characterized a wrap for this shape, so there is no reading
    // under which the counter went forward. A negative time is not an answer.
    test('ends timing on a domain with no characterized wrap', () {
      expect(
        mapper.map(
          session: 'a',
          arrivalMs: 500,
          timestamp: networkAnchor - 100000,
        ),
        const TimingUnavailable(TimingUnavailableReason.continuityLost),
      );
      expect(mapper.phase, PerformanceClockPhase.failed);
    });

    test('and deliveries that look fine do not bring it back', () {
      mapper.map(
        session: 'a',
        arrivalMs: 500,
        timestamp: networkAnchor - 100000,
      );

      expect(
        mapper.feed([
          for (var step = 1; step <= 3; step++) networkAnchor + step * 100000,
        ]),
        everyElement(
          const TimingUnavailable(TimingUnavailableReason.continuityLost),
        ),
      );
    });
  });

  // Placing a wrapping counter on a continuous timeline takes the arrival
  // bound and the unique-candidate arithmetic, which is not here. Recognizing
  // the clock is not the same as being able to read it.
  test('a wrapping domain is recognized and carries no time', () {
    mapper.feed(wrappingWarmup);

    // The wrap that establishes the counter's width: a step backward across a
    // silence that arrival time puts at one whole modulus.
    final timings = [mapper.map(session: 'a', arrivalMs: 8095, timestamp: 3)];

    expect(mapper.phase, PerformanceClockPhase.active);
    expect(mapper.clock?.modulus, 8192);
    expect(
      timings.last,
      const TimingUnavailable(TimingUnavailableReason.unresolvedWrap),
    );
  });

  test('a new session starts over with no timeline', () {
    mapper.feed(networkWarmup);

    expect(
      mapper.map(session: 'b', arrivalMs: 0, timestamp: networkAnchor),
      const TimingUnavailable(TimingUnavailableReason.detecting),
    );
    expect(mapper.phase, PerformanceClockPhase.detecting);
    expect(mapper.clock, isNull);
  });
}
