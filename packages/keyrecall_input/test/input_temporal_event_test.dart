import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

void main() {
  group('a snapshot', () {
    test('describes what is sounding and how', () {
      final snapshot = InputTemporalSnapshot(
        pressedNoteNumbers: {60, 64},
        sustainedNoteNumbers: {55},
        pedalDown: true,
      );

      expect(snapshot.soundingNoteNumbers, {55, 60, 64});
      expect(snapshot.isSilent, isFalse);
      expect(InputTemporalSnapshot.silent.isSilent, isTrue);
    });

    test('refuses a note that is both held and sustained', () {
      // The pedal holds a note the player has let go of. A note cannot be in
      // both states at once.
      expect(
        () => InputTemporalSnapshot(
          pressedNoteNumbers: {60},
          sustainedNoteNumbers: {60},
          pedalDown: true,
        ),
        throwsArgumentError,
      );
    });

    test('refuses sustained notes with the pedal up', () {
      expect(
        () =>
            InputTemporalSnapshot(sustainedNoteNumbers: {60}, pedalDown: false),
        throwsArgumentError,
      );
    });

    test('refuses a note outside the keyboard', () {
      expect(
        () =>
            InputTemporalSnapshot(pressedNoteNumbers: {128}, pedalDown: false),
        throwsRangeError,
      );
      expect(
        () => InputTemporalSnapshot(pressedNoteNumbers: {-1}, pedalDown: false),
        throwsRangeError,
      );
    });

    test('cannot be modified after construction', () {
      final pressed = {60};
      final snapshot = InputTemporalSnapshot(
        pressedNoteNumbers: pressed,
        pedalDown: false,
      );

      pressed.add(64);

      expect(snapshot.pressedNoteNumbers, {
        60,
      }, reason: 'a snapshot must not follow the set it was built from');
      expect(() => snapshot.pressedNoteNumbers.add(67), throwsUnsupportedError);
    });
  });

  group('events', () {
    test('a note-on carries a real strike', () {
      final event = InputTemporalNoteOnEvent(
        timestampMs: 120,
        noteNumber: 60,
        velocity: 90,
      );

      expect(event.timestampMs, 120);
      expect(event.noteNumber, 60);
      expect(event.velocity, 90);
    });

    test('a note-on refuses zero velocity', () {
      // Instruments express a release that way, and normalization has already
      // turned those into note-offs. One arriving here means something
      // upstream skipped that step.
      expect(
        () => InputTemporalNoteOnEvent(
          timestampMs: 0,
          noteNumber: 60,
          velocity: 0,
        ),
        throwsRangeError,
      );
    });

    test('a note-off allows zero velocity, which is what most report', () {
      final event = InputTemporalNoteOffEvent(
        timestampMs: 10,
        noteNumber: 60,
        velocity: 0,
      );
      expect(event.velocity, 0);
    });

    test('a reset carries what was sounding at the boundary', () {
      final event = InputTemporalResetEvent(
        timestampMs: 5,
        snapshot: InputTemporalSnapshot(
          pressedNoteNumbers: {60},
          pedalDown: false,
        ),
      );

      expect(event.snapshot.pressedNoteNumbers, {60});
    });

    test('refuse a negative timestamp', () {
      expect(
        () => InputTemporalPedalEvent(timestampMs: -1, down: true),
        throwsRangeError,
      );
    });

    test('are exhaustively matchable', () {
      // The family is sealed, so a consumer that forgets a case fails to
      // compile rather than silently ignoring input.
      final events = <InputTemporalEvent>[
        InputTemporalNoteOnEvent(timestampMs: 0, noteNumber: 60, velocity: 90),
        InputTemporalNoteOffEvent(timestampMs: 1, noteNumber: 60, velocity: 0),
        InputTemporalPedalEvent(timestampMs: 2, down: true),
        InputTemporalResetEvent(
          timestampMs: 3,
          snapshot: InputTemporalSnapshot.silent,
        ),
      ];

      final described = [
        for (final event in events)
          switch (event) {
            InputTemporalNoteOnEvent() => 'on',
            InputTemporalNoteOffEvent() => 'off',
            InputTemporalPedalEvent() => 'pedal',
            InputTemporalResetEvent() => 'reset',
          },
      ];

      expect(described, ['on', 'off', 'pedal', 'reset']);
    });
  });

  group('the input clock', () {
    test('a manual clock only moves forward', () {
      final clock = ManualInputClock();

      expect(clock(), 0);
      clock.advance(250);
      expect(clock(), 250);
      clock.advance(0);
      expect(clock(), 250);
      expect(() => clock.advance(-1), throwsArgumentError);
    });

    test('a stopwatch clock never goes backward', () {
      final clock = StopwatchInputClock();
      var previous = clock();

      for (var i = 0; i < 1000; i++) {
        final now = clock();
        expect(now, greaterThanOrEqualTo(previous));
        previous = now;
      }
      clock.stop();
    });
  });

  group('a plain note event', () {
    test('compares by value', () {
      final first = InputNoteEvent(
        type: InputNoteEventType.noteOn,
        noteNumber: 60,
        velocity: 90,
      );
      final second = InputNoteEvent(
        type: InputNoteEventType.noteOn,
        noteNumber: 60,
        velocity: 90,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('refuses a note outside the keyboard', () {
      expect(
        () => InputNoteEvent(
          type: InputNoteEventType.noteOn,
          noteNumber: 200,
          velocity: 90,
        ),
        throwsRangeError,
      );
    });
  });
}
