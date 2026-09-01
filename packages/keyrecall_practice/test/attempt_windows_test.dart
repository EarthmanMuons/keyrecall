import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

void main() {
  Exercise at(double tempoBpm, {int octaves = 1}) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: octaves,
    tempoBpm: tempoBpm,
    guidance: GuidanceContext.unguided,
  );

  test('the silence windows follow the tempo that was asked for', () {
    final slow = AttemptWindows.forExercise(at(40));
    final quick = AttemptWindows.forExercise(at(160));

    expect(
      slow.afterPlaying,
      greaterThan(quick.afterPlaying),
      reason: 'a bar is longer when the bar is longer',
    );
    expect(
      slow.beforePlaying,
      greaterThan(slow.afterPlaying),
      reason: 'getting to the keys takes longer than a gap inside a scale',
    );
  });

  test('a quick exercise still leaves room to think', () {
    final windows = AttemptWindows.forExercise(at(200));

    expect(windows.afterPlaying, const Duration(seconds: 3));
    expect(windows.beforePlaying, const Duration(seconds: 12));
  });

  test('the run limit grows with what was asked for, and has a floor', () {
    final short = AttemptWindows.forExercise(at(120));
    final long = AttemptWindows.forExercise(at(40, octaves: 4));

    expect(short.limit, const Duration(minutes: 2));
    expect(long.limit, greaterThan(const Duration(minutes: 2)));
  });

  test('an attempt is questioned long before it is closed', () {
    final windows = AttemptWindows.forExercise(at(120));

    expect(windows.abandon, greaterThan(windows.beforePlaying));
    expect(windows.abandon, lessThan(windows.limit));
  });
}
