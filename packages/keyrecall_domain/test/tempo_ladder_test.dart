import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

/// The tempi a mechanical metronome offers, used as an adjacency relation.
void main() {
  test('the ladder is Maelzel\'s, and its steps grow with the tempo', () {
    expect(metronomeLadder.first, 40);
    expect(metronomeLadder.last, 208);

    int stepAfter(double bpm) => (tempoAfter(bpm) - bpm).round();

    expect(stepAfter(48), 2, reason: 'two apart below 60');
    expect(stepAfter(60), 3, reason: 'three from 60 to 72');
    expect(stepAfter(80), 4, reason: 'four from 72 to 120');
    expect(stepAfter(120), 6, reason: 'six from 120 to 144');
    expect(stepAfter(160), 8, reason: 'eight above 144');
  });

  test('it rises without repeating', () {
    for (var rung = 1; rung < metronomeLadder.length; rung++) {
      expect(
        metronomeLadder[rung],
        greaterThan(metronomeLadder[rung - 1]),
        reason: 'rung $rung',
      );
    }
  });

  test('a tempo between rungs reads as the nearer one', () {
    expect(metronomeLadder[tempoRungOf(61)], 60);
    expect(metronomeLadder[tempoRungOf(65)], 66);
    expect(metronomeLadder[tempoRungOf(200)], 200);
  });

  test('a step is one rung, not one interval of beats', () {
    // The point of the ladder. Sixty to sixty-three is a step and so is a
    // hundred and twenty to a hundred and twenty-six, because what a step
    // means is a proportion rather than a count.
    expect(tempoAfter(60), 63);
    expect(tempoAfter(120), 126);
    expect(tempoBefore(60), 58);
    expect(tempoBefore(120), 116);
  });

  test('the ends of the ladder are still tempi', () {
    // A learner at the bottom is asked for the slowest again rather than for
    // nothing, and the same at the top.
    expect(tempoBefore(40), 40);
    expect(tempoAfter(208), 208);
    expect(tempoStepped(40, -5), 40);
  });

  test('several steps land where the same steps one at a time do', () {
    var walked = 60.0;
    for (var step = 0; step < 4; step++) {
      walked = tempoAfter(walked);
    }

    expect(walked, tempoStepped(60, 4));
    expect(walked, 72, reason: '60, 63, 66, 69, 72');
  });

  test('every generated tempo is a rung', () {
    // What the generator offers has to be sayable on the ladder, or stepping
    // from it would land somewhere the learner never played.
    for (final bpm in [60.0, 80.0, 100.0, 120.0]) {
      expect(isTempoRung(bpm), isTrue, reason: '$bpm');
    }
  });
}
