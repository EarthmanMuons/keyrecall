import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/attempt_screen.dart';

/// A metronome through an attempt lasts as long as the attempt can.
void main() {
  final twoOctaves = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: 2,
    direction: ExerciseDirection.upDown,
    tempoBpm: 80,
  );
  const beat = Duration(milliseconds: 750);

  test('outlasts the traversal played well below the tempo asked', () {
    expect(realize(twoOctaves).moments, hasLength(29));
    final supplied = beat * metronomeBeatsFor(twoOctaves, beat: beat);

    // Its 28 intervals at 60 rather than 80.
    expect(supplied, greaterThanOrEqualTo(const Duration(seconds: 28)));
  });

  test('lasts out the longest the attempt may run', () {
    expect(
      beat * metronomeBeatsFor(twoOctaves, beat: beat),
      greaterThanOrEqualTo(AttemptWindows.forExercise(twoOctaves).limit),
    );
  });
}
