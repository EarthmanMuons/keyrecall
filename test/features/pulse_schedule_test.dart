import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/audio/pulse_schedule.dart';

/// Every reader of a pulse asks one schedule where the beat is.
void main() {
  const beat = Duration(milliseconds: 500);
  var now = Duration.zero;
  PulseSchedule metronome() => PulseSchedule(
    beat: beat,
    countInBeats: 4,
    continuingBeats: 8,
    elapsed: () => now,
  );

  test('counts down to one on the last beat of the count-in', () {
    final schedule = metronome();
    final counts = [
      for (var index = 0; index < 4; index++)
        (() {
          now = beat * index + const Duration(milliseconds: 10);
          return schedule.beatsLeftInCountIn;
        })(),
    ];

    expect(counts, [4, 3, 2, 1]);
    expect(schedule.countedIn, isFalse);
  });

  test('begins the attempt on the downbeat after the count-in', () {
    final schedule = metronome();
    now = beat * 4 - const Duration(microseconds: 1);
    expect(schedule.countedIn, isFalse);

    now = beat * 4;
    expect(schedule.countedIn, isTrue);
    expect(PulseSchedule.placeInBar(schedule.currentBeat), 0);
  });

  test('puts every beat in the same place however late it is read', () {
    final schedule = metronome();
    now = beat * 6 + const Duration(milliseconds: 499);

    expect(schedule.currentBeat, 6);
    expect(PulseSchedule.placeInBar(schedule.currentBeat), 2);
  });

  test('is over once its last beat has passed', () {
    final schedule = metronome();
    now = beat * 11;
    expect(schedule.isOver, isFalse);

    now = beat * 12;
    expect(schedule.isOver, isTrue);
  });
}
