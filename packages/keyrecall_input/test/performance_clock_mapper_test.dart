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
  /// Feeds deliveries in and returns what each was timed as.
  ///
  /// Arrivals run one millisecond apart from [from] unless [arrivals] says
  /// otherwise, which is close enough to the transport intervals to be
  /// plausible and nowhere near equal to them.
  List<PerformanceTiming> feed(
    List<int?> timestamps, {
    int from = 0,
    int Function(int index)? arrivals,
  }) => [
    for (final (index, timestamp) in timestamps.indexed)
      map(
        session: 'a',
        arrivalMs: arrivals?.call(from + index) ?? from + index,
        timestamp: timestamp,
      ),
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
          arrivalMs: 722,
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
          arrivalMs: 8,
          timestamp: networkAnchor + 100000,
        ),
        const TimingAvailable(100),
      );
    });

    test('times are measured from the anchor, not accumulated', () {
      final timings = mapper.feed([
        for (var step = 1; step <= 4; step++) networkAnchor + step * 100000,
      ], from: networkWarmup.length);

      expect(timings, const [
        TimingAvailable(100),
        TimingAvailable(200),
        TimingAvailable(300),
        TimingAvailable(400),
      ]);
    });
  });

  // The property the layer exists for, as an experiment rather than a branch:
  // move arrival as far as it can go without being vetoed, and see whether any
  // answer moves by a microsecond.
  test('arrival time cannot change a performance time', () {
    final stamps = [
      ...networkWarmup,
      networkAnchor + 100000,
      networkAnchor + 900000,
      networkAnchor + 1000000,
    ];

    final steady = PerformanceClockMapper().feed(stamps);
    final jittered = PerformanceClockMapper().feed(
      stamps,
      arrivals: (index) => index + (index.isEven ? 400 : -400),
    );

    expect(jittered, steady);
    expect(steady.last, const TimingAvailable(1000));
  });

  // Arrival's other job. It does not correct the transport clock and does not
  // contribute to the answer; it refuses an interval the two clocks cannot
  // both be describing, which would otherwise be confidently wrong evidence.
  test('a transport interval arrival contradicts is terminal', () {
    final mapper = PerformanceClockMapper()..feed(networkWarmup);

    expect(
      mapper.map(
        session: 'a',
        arrivalMs: networkWarmup.length,
        timestamp: networkAnchor + 20000000000,
      ),
      const TimingUnavailable(TimingUnavailableReason.implausibleClockStep),
    );
    expect(mapper.phase, PerformanceClockPhase.failed);
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

  group('a counter that wraps', () {
    // The take that characterized this clock: a millisecond counter whose
    // width is established by a silence arrival puts at one whole modulus.
    setUp(() {
      mapper.feed(wrappingWarmup);
      mapper.map(session: 'a', arrivalMs: 8095, timestamp: 3);
    });

    test('the wrap that identifies it is where the timeline starts', () {
      expect(mapper.phase, PerformanceClockPhase.active);
      expect(mapper.clock?.modulus, 8192);
      expect(
        mapper.map(session: 'a', arrivalMs: 8195, timestamp: 103),
        const TimingAvailable(100000),
      );
    });

    test('an ordinary wrap is one epoch', () {
      expect(
        mapper.map(session: 'a', arrivalMs: 16095, timestamp: 8003),
        const TimingAvailable(8000000),
      );
      expect(
        mapper.map(session: 'a', arrivalMs: 16395, timestamp: 111),
        const TimingAvailable(8300000),
      );
    });

    // The regression this whole investigation came from.
    // `ios-jamcorder-pause` steps backward by 2,721 counts across a 13,667 ms
    // silence, which is two whole epochs and not one: 2 * 8192 - 2721 = 13,663
    // counts. Counting one wrap per backward step reads it as 5,471.
    test('a silence hiding two epochs is two epochs', () {
      expect(
        mapper.map(
          session: 'a',
          arrivalMs: 8095 + 13667,
          timestamp: 3 - 2721 + 8192,
        ),
        const TimingAvailable(13663000),
      );
    });

    // Chords arrive under one stamp, and nothing about that is a wrap.
    test('a step of nothing is no time at all', () {
      expect(
        mapper.map(session: 'a', arrivalMs: 8096, timestamp: 3),
        const TimingAvailable(0),
      );
    });

    // Half an epoch from either neighbor, so neither reading is one the two
    // clocks can both be describing.
    test('a silence no epoch count fits is terminal', () {
      expect(
        mapper.map(session: 'a', arrivalMs: 8095 + 4096, timestamp: 3),
        const TimingUnavailable(TimingUnavailableReason.implausibleClockStep),
      );
      expect(mapper.phase, PerformanceClockPhase.failed);
    });

    // Tolerating more disagreement than half a modulus is what makes two epoch
    // counts fit at once, which is the parameter's real cost.
    test('a silence two epoch counts fit is ambiguous', () {
      final loose = PerformanceClockMapper(arrivalUncertaintyMs: 5000)
        ..feed(wrappingWarmup)
        ..map(session: 'a', arrivalMs: 8095, timestamp: 3);

      expect(
        loose.map(session: 'a', arrivalMs: 8095 + 4096, timestamp: 3),
        const TimingUnavailable(TimingUnavailableReason.ambiguousWrap),
      );
    });
  });

  // Every step being plausible on its own is not the same as the timeline
  // keeping time. A clock that stops reports an interval of zero forever, and
  // zero fits inside any short wait's window.
  group('a timeline that stops keeping time', () {
    test(
      'a frozen clock does not report a minute of playing as one instant',
      () {
        final mapper = PerformanceClockMapper()..feed(networkWarmup);
        final timings = [
          for (var tick = 1; tick <= 120; tick++)
            mapper.map(
              session: 'a',
              arrivalMs: networkWarmup.length + tick * 500,
              timestamp: networkAnchor,
            ),
        ];

        expect(timings.first, const TimingAvailable(0));
        expect(
          timings.last,
          const TimingUnavailable(TimingUnavailableReason.implausibleClockStep),
        );
        expect(mapper.phase, PerformanceClockPhase.failed);
        expect(
          timings.whereType<TimingAvailable>(),
          hasLength(lessThan(10)),
          reason: 'it is caught within a few seconds, not eventually',
        );
      },
    );

    test('a clock running slow is caught however small each step is', () {
      final mapper = PerformanceClockMapper()..feed(networkWarmup);
      // Half speed: every delivery is individually well inside the window.
      final timings = [
        for (var tick = 1; tick <= 40; tick++)
          mapper.map(
            session: 'a',
            arrivalMs: networkWarmup.length + tick * 500,
            timestamp: networkAnchor + tick * 250 * 1000000,
          ),
      ];

      expect(
        timings.last,
        const TimingUnavailable(TimingUnavailableReason.implausibleClockStep),
      );
    });

    test('and ordinary playing is not', () {
      final mapper = PerformanceClockMapper()..feed(networkWarmup);
      final timings = [
        for (var tick = 1; tick <= 120; tick++)
          mapper.map(
            session: 'a',
            arrivalMs: networkWarmup.length + tick * 500,
            timestamp: networkAnchor + tick * 500 * 1000000,
          ),
      ];

      expect(timings, everyElement(isA<TimingAvailable>()));
      expect(timings.last, const TimingAvailable(60000000));
    });
  });

  // The counter cannot hold a value wider than the width that identified it.
  test('a reading outside the counter contradicts its shape', () {
    final mapper = PerformanceClockMapper()..feed(wrappingWarmup);
    mapper.map(session: 'a', arrivalMs: 8095, timestamp: 3);
    expect(mapper.clock?.modulus, 8192);

    expect(
      mapper.map(session: 'a', arrivalMs: 8195, timestamp: 8193),
      const TimingUnavailable(TimingUnavailableReason.continuityLost),
    );
    expect(mapper.phase, PerformanceClockPhase.failed);
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
