import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

const piano = InputSourceIdentity(deviceId: 'piano', transport: 'ble');
const other = InputSourceIdentity(deviceId: 'pad', transport: 'usb');

RawInputEnvelope noteOn(
  int note, {
  int velocity = 100,
  int at = 0,
  InputSourceIdentity source = piano,
}) => RawInputEnvelope(
  source: source,
  arrivalTimestampMs: at,
  message: RawInputMessage(
    kind: RawInputKind.noteOn,
    note: note,
    velocity: velocity,
  ),
);

RawInputEnvelope noteOff(
  int note, {
  int velocity = 0,
  int at = 0,
  InputSourceIdentity source = piano,
}) => RawInputEnvelope(
  source: source,
  arrivalTimestampMs: at,
  message: RawInputMessage(
    kind: RawInputKind.noteOff,
    note: note,
    velocity: velocity,
  ),
);

RawInputEnvelope sustain(
  int value, {
  int at = 0,
  InputSourceIdentity source = piano,
}) => RawInputEnvelope(
  source: source,
  arrivalTimestampMs: at,
  message: RawInputMessage(kind: RawInputKind.sustain, sustainValue: value),
);

RawInputEnvelope allNotesOff({int at = 0}) => RawInputEnvelope(
  source: piano,
  arrivalTimestampMs: at,
  message: const RawInputMessage(kind: RawInputKind.allNotesOff),
);

void main() {
  late InputReducer reducer;
  late List<InputTemporalEvent> emitted;

  void feed(RawInputEnvelope envelope) =>
      emitted.addAll(reducer.receive(envelope));

  /// What replaying everything emitted says is sounding.
  InputTemporalState replayed() {
    var state = InputTemporalState.silent;
    for (final event in emitted) {
      state = state.applying(event);
    }
    return state;
  }

  setUp(() {
    reducer = InputReducer();
    emitted = [...reducer.begin(timestampMs: 0)];
  });

  group('normalization', () {
    test('opens with a reset that claims nothing is sounding', () {
      final reset = emitted.single as InputTemporalResetEvent;
      expect(reset.snapshot.isSilent, isTrue);
      expect(reducer.isObserving, isTrue);
    });

    test('a repeated note-on for a held key is not an event', () {
      feed(noteOn(60, at: 1));
      feed(noteOn(60, velocity: 120, at: 2));

      expect(emitted.whereType<InputTemporalNoteOnEvent>(), hasLength(1));
      expect(reducer.snapshot.pressedNoteNumbers, {60});
    });

    test('velocity-zero note-on is a release', () {
      feed(noteOn(60, at: 1));
      feed(noteOn(60, velocity: 0, at: 2));

      expect(emitted.last, isA<InputTemporalNoteOffEvent>());
      expect(reducer.snapshot.isSilent, isTrue);
    });

    test('the pedal catches a released note and lifting it damps them', () {
      feed(sustain(127, at: 1));
      feed(noteOn(60, at: 2));
      feed(noteOff(60, at: 3));

      expect(reducer.snapshot.sustainedNoteNumbers, {60});

      feed(sustain(0, at: 4));

      expect(reducer.snapshot.isSilent, isTrue);
      expect(emitted.last, isA<InputTemporalPedalEvent>());
    });

    test('a reattack takes the note back from the pedal', () {
      feed(sustain(127, at: 1));
      feed(noteOn(60, at: 2));
      feed(noteOff(60, at: 3));
      feed(noteOn(60, at: 4));

      expect(reducer.snapshot.pressedNoteNumbers, {60});
      expect(reducer.snapshot.sustainedNoteNumbers, isEmpty);
    });

    test('all-notes-off is a reset that keeps the pedal where it is', () {
      feed(sustain(127, at: 1));
      feed(noteOn(60, at: 2));
      feed(allNotesOff(at: 3));

      final reset = emitted.last as InputTemporalResetEvent;
      expect(reset.snapshot.isSilent, isTrue);
      expect(reset.snapshot.pedalDown, isTrue);
      expect(reducer.snapshot.pedalDown, isTrue);
    });

    // The divergence that proved two representations were disagreeing: an
    // orphan release used to reach sustained state while the event stream
    // reported nothing at all.
    test('a release of a key nobody pressed cannot create a sounding note', () {
      feed(sustain(127, at: 1));
      feed(noteOff(60, at: 2));

      expect(emitted.whereType<InputTemporalNoteOffEvent>(), isEmpty);
      expect(reducer.snapshot.soundingNoteNumbers, isEmpty);
    });
  });

  group('integrity', () {
    test('a backward timestamp faults instead of dropping the note', () {
      feed(noteOn(60, at: 100));
      feed(noteOn(62, at: 90));

      expect(reducer.isObserving, isFalse);
      expect(reducer.fault, InputIntegrityFault.timestampRegression);
      expect(emitted.last, isA<InputTemporalFaultEvent>());
    });

    test('a faulted observation admits nothing further', () {
      feed(noteOn(60, at: 100));
      feed(noteOn(62, at: 90));
      final atFault = emitted.length;

      feed(noteOn(64, at: 200));
      feed(noteOff(64, at: 300));

      expect(emitted, hasLength(atFault));
    });

    test('a malformed payload faults rather than clamping into range', () {
      feed(noteOn(200, at: 1));

      expect(reducer.fault, InputIntegrityFault.malformedInput);
      expect(emitted.whereType<InputTemporalNoteOnEvent>(), isEmpty);
    });

    test('an out-of-range velocity is malformed too', () {
      reducer.begin(timestampMs: 0);
      expect(
        reducer.receive(noteOn(60, velocity: 200, at: 1)).single,
        isA<InputTemporalFaultEvent>(),
      );
    });

    test('a source failure ends the observation once', () {
      feed(noteOn(60, at: 1));
      emitted.addAll(
        reducer.fail(InputIntegrityFault.sourceFailure, timestampMs: 2),
      );
      final atFault = emitted.length;
      emitted.addAll(
        reducer.fail(InputIntegrityFault.sourceClosed, timestampMs: 3),
      );

      expect(emitted, hasLength(atFault));
      expect(reducer.fault, InputIntegrityFault.sourceFailure);
    });

    test('a fault timestamp never runs backward', () {
      feed(noteOn(60, at: 100));
      final events = reducer.fail(
        InputIntegrityFault.observationGap,
        timestampMs: 10,
      );

      expect(events.single.timestampMs, 100);
    });

    test('beginning again discards what the faulted observation believed', () {
      feed(noteOn(60, at: 1));
      reducer.fail(InputIntegrityFault.observationGap, timestampMs: 2);
      final opening = reducer.begin(timestampMs: 3).single;

      expect(reducer.isObserving, isTrue);
      expect(reducer.fault, isNull);
      expect((opening as InputTemporalResetEvent).snapshot.isSilent, isTrue);
    });
  });

  group('admission', () {
    test('every source is admitted while none is adopted', () {
      feed(noteOn(60, at: 1, source: other));

      expect(reducer.snapshot.pressedNoteNumbers, {60});
      expect(reducer.rejectedForeignCount, 0);
    });

    test('an adopted instrument turns other sources away', () {
      reducer.adopt(piano);
      feed(noteOn(60, at: 1, source: other));
      feed(allNotesOff(at: 2));

      expect(reducer.rejectedForeignCount, 1);
      expect(reducer.isObserving, isTrue, reason: 'not this stream breaking');
    });

    test(
      'a foreign release cannot end a note the adopted instrument holds',
      () {
        reducer.adopt(piano);
        feed(noteOn(60, at: 1));
        feed(noteOff(60, at: 2, source: other));

        expect(reducer.snapshot.pressedNoteNumbers, {60});
      },
    );

    test('a reconnect to the same device is a different source', () {
      const first = InputSourceIdentity(
        deviceId: 'piano',
        transport: 'ble',
        sessionId: '1',
      );
      const second = InputSourceIdentity(
        deviceId: 'piano',
        transport: 'ble',
        sessionId: '2',
      );
      reducer.adopt(first);
      feed(noteOn(60, at: 1, source: second));

      expect(reducer.rejectedForeignCount, 1);
    });
  });

  group('the two representations agree', () {
    test('replaying the stream reproduces the live snapshot', () {
      reducer.adopt(piano);
      feed(noteOn(60, at: 1));
      feed(sustain(127, at: 2));
      feed(noteOff(60, at: 3));
      feed(noteOn(62, at: 4));
      feed(noteOff(99, at: 5));
      feed(noteOn(64, at: 6, source: other));
      feed(sustain(0, at: 7));
      feed(noteOn(60, at: 8));

      final replay = replayed();
      expect(replay.pressedNoteNumbers, reducer.snapshot.pressedNoteNumbers);
      expect(
        replay.sustainedNoteNumbers,
        reducer.snapshot.sustainedNoteNumbers,
      );
      expect(replay.pedalDown, reducer.snapshot.pedalDown);
    });

    test('a fault leaves both representations silent', () {
      feed(noteOn(60, at: 1));
      feed(sustain(127, at: 2));
      feed(noteOff(60, at: 3));
      emitted.addAll(
        reducer.fail(InputIntegrityFault.observationGap, timestampMs: 4),
      );

      expect(replayed().soundingNoteNumbers, isEmpty);
      expect(replayed().fault, InputIntegrityFault.observationGap);
      expect(reducer.snapshot.soundingNoteNumbers, isEmpty);
    });

    test('every emitted event is in nondecreasing time', () {
      reducer.adopt(piano);
      for (var i = 1; i <= 20; i++) {
        feed(noteOn(60 + (i % 5), at: i));
        feed(noteOff(60 + (i % 5), at: i));
      }

      var last = 0;
      for (final event in emitted) {
        expect(event.timestampMs, greaterThanOrEqualTo(last));
        last = event.timestampMs;
      }
    });
  });

  group('resync', () {
    test('hands a late consumer the whole snapshot', () {
      feed(sustain(127, at: 1));
      feed(noteOn(60, at: 2));
      feed(noteOff(60, at: 3));
      feed(noteOn(62, at: 4));

      final reset = reducer.resync(timestampMs: 5) as InputTemporalResetEvent;

      expect(reset.snapshot.pressedNoteNumbers, {62});
      expect(reset.snapshot.sustainedNoteNumbers, {60});
      expect(reset.snapshot.pedalDown, isTrue);
    });

    test('refuses when no observation is open', () {
      reducer.fail(InputIntegrityFault.sourceClosed, timestampMs: 1);

      expect(() => reducer.resync(timestampMs: 2), throwsStateError);
    });
  });
}
