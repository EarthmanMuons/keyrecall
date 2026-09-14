import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

const piano = InputSourceIdentity(
  deviceId: 'piano',
  transport: 'ble',
  sessionId: 'midi-1',
);

/// Stamps from a clock the takes characterized, stepping only in whole units
/// of 100,000 counts. Eight steps is what the policy asks for before it names
/// a shape, so the first deliveries of any observation are untimed.
const stamps = [
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

RawInputEnvelope noteOn(
  int note, {
  required int at,
  int? transportTimestamp,
  InputSourceIdentity source = piano,
}) => RawInputEnvelope(
  source: source,
  arrivalTimestampMs: at,
  transportTimestamp: transportTimestamp,
  message: RawInputMessage(
    kind: RawInputKind.noteOn,
    note: note,
    velocity: 100,
  ),
);

RawInputEnvelope sustain(
  int value, {
  required int at,
  int? transportTimestamp,
}) => RawInputEnvelope(
  source: piano,
  arrivalTimestampMs: at,
  transportTimestamp: transportTimestamp,
  message: RawInputMessage(kind: RawInputKind.sustain, sustainValue: value),
);

/// Plays enough of the characterized clock for it to be identified, and
/// returns what each delivery normalized to.
List<List<InputTemporalEvent>> identifyClock(InputReducer reducer) => [
  for (final (index, stamp) in stamps.indexed)
    reducer.receive(noteOn(60 + index, at: index, transportTimestamp: stamp)),
];

void main() {
  late InputReducer reducer;

  setUp(() {
    reducer = InputReducer()..adopt(piano);
    reducer.begin(timestampMs: 0);
  });

  test('nothing is timed while the clock is still being identified', () {
    final rounds = identifyClock(reducer);

    expect(
      rounds
          .take(8)
          .expand((events) => events)
          .map((event) => event.performanceTimeUs),
      everyElement(isNull),
    );
    expect(rounds.last.single.performanceTimeUs, 0);
  });

  test('a timed event carries the instrument clock, not the arrival clock', () {
    identifyClock(reducer);

    final events = reducer.receive(
      noteOn(72, at: 9, transportTimestamp: 2000000 + 714000000),
    );

    expect(events.single.timestampMs, 9);
    expect(events.single.performanceTimeUs, 714000);
  });

  // A transport that stamps nothing is the ordinary case, and it must stay
  // untimed rather than quietly becoming the arrival clock in microseconds.
  test('a transport with no timestamps times nothing', () {
    final events = [
      for (var index = 0; index < 12; index++)
        ...reducer.receive(noteOn(60 + index, at: index * 100)),
    ];

    expect(events, hasLength(12));
    expect(
      events.map((event) => event.performanceTimeUs),
      everyElement(isNull),
    );
    // Still detecting, and it always will be: a clock nothing stamps is a
    // clock nothing can name.
    expect(
      events.map((event) => event.timing),
      everyElement(const TimingUnavailable(TimingUnavailableReason.detecting)),
    );
  });

  test('the pedal is timed the same way playing is', () {
    identifyClock(reducer);

    final events = reducer.receive(
      sustain(127, at: 9, transportTimestamp: 2100000),
    );

    expect(events.single, isA<InputTemporalPedalEvent>());
    expect(events.single.performanceTimeUs, 100);
  });

  // An administrative boundary is not something somebody played, so it carries
  // no performance time even though the delivery that caused it was stamped.
  test('a boundary inside a timed observation still carries no time', () {
    identifyClock(reducer);

    final events = reducer.receive(
      RawInputEnvelope(
        source: piano,
        arrivalTimestampMs: 9,
        transportTimestamp: 2100000,
        message: const RawInputMessage(kind: RawInputKind.allNotesOff),
      ),
    );

    expect(events.single, isA<InputTemporalResetEvent>());
    expect(events.single.timing, isNull);
  });

  // A timeline belongs to the observation it was anchored in, so the next one
  // identifies the clock again rather than inheriting an anchor.
  test('a new observation starts a new timeline', () {
    identifyClock(reducer);
    reducer.begin(timestampMs: 20);

    final events = reducer.receive(
      noteOn(60, at: 21, transportTimestamp: 3000000),
    );

    expect(events.single.performanceTimeUs, isNull);
    expect(reducer.clock.phase, PerformanceClockPhase.detecting);
  });

  test('a boundary nobody played carries no time at all', () {
    final opened = reducer.begin(timestampMs: 30);

    expect(opened.single, isA<InputTemporalResetEvent>());
    expect(opened.single.timing, isNull);
    expect(opened.single.performanceTimeUs, isNull);
  });
}
