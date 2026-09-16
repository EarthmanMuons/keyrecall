import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

/// The recorded takes, replayed through the mapper exactly as they arrived.
///
/// These twelve files are the whole evidence base for what the policy
/// authorizes, so the mapper has to keep agreeing with them. Anything derived
/// here is derived from the deliveries themselves: no expected timeline is
/// stored alongside the takes, because a stored answer would only record what
/// the code did on the day it was written.
final takes = Directory('../../analysis/transport-clocks/takes');

/// What each take's clock was measured to be, and how much of it is timed.
///
/// A take is timed from the delivery that finishes identifying its clock, so
/// the untimed count at the front is the cost of identification, not a fault.
const expected = {
  'android-jamcorder-chords': (granularity: 1, modulus: 8192, timed: 41),
  'android-jamcorder-pulse': (granularity: 1, modulus: 8192, timed: 50),
  'ios-jamcorder-chords': (granularity: 1, modulus: 8192, timed: 35),
  'ios-jamcorder-pause': (granularity: 1, modulus: 8192, timed: 48),
  'ios-jamcorder-pulse': (granularity: 1, modulus: 8192, timed: 21),
  'ios-jamcorder-stall-arpeggio': (granularity: 1, modulus: 8192, timed: 97),
  'ios-jamcorder-stall-repeated': (
    granularity: 1000000,
    modulus: null,
    timed: 60,
  ),
  'ios-network-pulse': (granularity: 100000, modulus: null, timed: 50),
  'ios-yamaha-chords': (granularity: 1000000, modulus: null, timed: 89),
  'ios-yamaha-host-pulse': (granularity: 1000000, modulus: null, timed: 105),
  'ios-yamaha-pulse': (granularity: 1000000, modulus: null, timed: 105),
  'ios-yamaha-stall': (granularity: 1000000, modulus: null, timed: 229),
};

/// What replaying one take produced.
typedef Replay = ({
  ClockDomainObservation observation,
  List<PerformanceTiming> timings,
  int timed,
  int worstDriftMs,
});

Replay replay(String name) {
  final file = File('${takes.path}/$name.json');
  final records =
      (json.decode(file.readAsStringSync()) as Map<String, dynamic>)['records']
          as List;

  final mapper = PerformanceClockMapper();
  final timings = <PerformanceTiming>[];
  int? firstArrivalMs;
  var timed = 0;
  var worstDriftMs = 0;

  for (final record in records.cast<Map<String, dynamic>>()) {
    final arrivalMs = record['arrival_ms'] as int;
    final timing = mapper.map(
      session: record['session'] as String?,
      arrivalMs: arrivalMs,
      timestamp: record['transport_ts'] as int?,
    );
    timings.add(timing);
    if (timing case TimingAvailable(:final performanceTimeUs)) {
      timed += 1;
      firstArrivalMs ??= arrivalMs;
      final drift = performanceTimeUs ~/ 1000 - (arrivalMs - firstArrivalMs);
      if (drift.abs() > worstDriftMs.abs()) worstDriftMs = drift;
    }
  }

  return (
    observation: mapper.observation,
    timings: timings,
    timed: timed,
    worstDriftMs: worstDriftMs,
  );
}

void main() {
  test('every take is accounted for', () {
    final names = takes
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last.split('.').first)
        .toSet();

    expect(names, expected.keys.toSet());
  });

  for (final MapEntry(key: name, value: take) in expected.entries) {
    group(name, () {
      late final Replay replayed;

      setUpAll(() => replayed = replay(name));

      test('reads the clock the takes characterized', () {
        expect(replayed.observation.granularity, take.granularity);
        expect(replayed.observation.modulus, take.modulus);
      });

      test('times what it is entitled to and no more', () {
        expect(replayed.timed, take.timed);
      });

      // No recorded take is a clock failure. Every one of them is either a
      // domain that carries playing, timed from where it was identified, or a
      // domain that does not, timed nowhere.
      test('nothing in it is terminal', () {
        expect(
          replayed.timings.whereType<TimingUnavailable>().map(
            (timing) => timing.reason,
          ),
          everyElement(
            isNot(
              anyOf(
                TimingUnavailableReason.ambiguousWrap,
                TimingUnavailableReason.continuityLost,
                TimingUnavailableReason.implausibleClockStep,
              ),
            ),
          ),
        );
      });

      // The reconstructed timeline and arrival time are independent
      // measurements of the same silence, so they should not part company.
      // Arrival is only ever asked which epoch, never how long.
      test('its timeline does not drift away from arrival', () {
        expect(replayed.worstDriftMs.abs(), lessThan(150));
      });
    });
  }

  // The take this whole investigation came from. Its one silence is 13,667 ms
  // long and the counter steps backward by 2,721 across it, which is two whole
  // epochs rather than one: 2 * 8192 - 2721 = 13,663. That silence is also
  // what establishes the counter's width, so in this take the timeline starts
  // at the delivery that ends it. Resolving such a silence inside a timeline
  // that already exists is in the mapper's own tests.
  test('the pause take is identified by a silence hiding two epochs', () {
    final records =
        (json.decode(
                  File(
                    '${takes.path}/ios-jamcorder-pause.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['records']
            as List;

    var widest = 0;
    var identifying = 0;
    for (var index = 1; index < records.length; index++) {
      final elapsed =
          (records[index]['arrival_ms'] as int) -
          (records[index - 1]['arrival_ms'] as int);
      if (elapsed > widest) {
        widest = elapsed;
        identifying = index;
      }
    }

    final rawStep =
        (records[identifying]['transport_ts'] as int) -
        (records[identifying - 1]['transport_ts'] as int);

    expect(widest, 13667);
    expect(rawStep, -2721);
    expect((widest - rawStep) / 8192, closeTo(2, 0.01));

    final replayed = replay('ios-jamcorder-pause');
    expect(replayed.observation.modulus, 8192);
    expect(
      replayed.timings.indexWhere((timing) => timing is TimingAvailable),
      identifying,
    );
  });

  // The host route, recorded once the route was reported correctly. Its stamps
  // are the intervals, and arrival, which disagrees with them by up to a dozen
  // milliseconds a note, supplies none of them.
  test('the host take is timed by its stamps rather than its arrivals', () {
    final records =
        ((json.decode(
                      File(
                        '${takes.path}/ios-yamaha-host-pulse.json',
                      ).readAsStringSync(),
                    )
                    as Map<String, dynamic>)['records']
                as List)
            .cast<Map<String, dynamic>>();
    final replayed = replay('ios-yamaha-host-pulse');

    final notes = [
      for (final (index, record) in records.indexed)
        if (record['message'] == 'noteOn')
          if (replayed.timings[index] case TimingAvailable(
            :final performanceTimeUs,
          ))
            (
              performanceUs: performanceTimeUs,
              stampUs: (record['transport_ts'] as int) ~/ 1000,
              arrivalMs: record['arrival_ms'] as int,
            ),
    ];
    final performed = [
      for (var index = 1; index < notes.length; index++)
        notes[index].performanceUs - notes[index - 1].performanceUs,
    ];
    final stamped = [
      for (var index = 1; index < notes.length; index++)
        notes[index].stampUs - notes[index - 1].stampUs,
    ];
    final arrived = [
      for (var index = 1; index < notes.length; index++)
        (notes[index].arrivalMs - notes[index - 1].arrivalMs) * 1000,
    ];

    expect(records.every((record) => record['route'] == 'host'), isTrue);
    expect(notes, hasLength(26), reason: 'the first three notes identify it');
    expect(performed, stamped);
    expect(performed, isNot(arrived));
  });
}
