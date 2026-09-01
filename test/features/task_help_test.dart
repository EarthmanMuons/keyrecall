import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/practice/exercise_presentation.dart';
import 'package:keyrecall/features/practice/task_help.dart';

void main() {
  Exercise exerciseOf({
    HandConfiguration hands = HandConfiguration.right,
    ScaleDirection direction = ScaleDirection.up,
    int octaves = 1,
    double tempoBpm = 60,
  }) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: hands,
    octaves: octaves,
    direction: direction,
    tempoBpm: tempoBpm,
  );

  test('explains every term the task statement puts on screen', () {
    final exercise = exerciseOf(
      hands: HandConfiguration.together,
      direction: ScaleDirection.upDown,
      octaves: 2,
      tempoBpm: 72,
    );
    final conditions = exercise.conditions;

    expect(taskHelpEntries(exercise).map((entry) => entry.$1), [
      materialName(exercise.material),
      handsName(conditions.hands),
      directionName(conditions.direction),
      octavesName(conditions.octaves),
      '72 bpm',
    ]);
  });

  test('says what each condition asks for, not just what it is called', () {
    final upOnly = taskHelpEntries(exerciseOf());
    final andBack = taskHelpEntries(
      exerciseOf(direction: ScaleDirection.upDown),
    );

    expect(upOnly[2].$2, isNot(andBack[2].$2));
    expect(upOnly[1].$2, contains('right hand'));
  });

  test('says how far the scale runs in the terms this one runs in', () {
    expect(
      taskHelpEntries(exerciseOf(direction: ScaleDirection.up))[3].$2,
      isNot(contains('turns around')),
      reason: 'a scale that only goes up never turns around',
    );
    expect(
      taskHelpEntries(exerciseOf(direction: ScaleDirection.upDown))[3].$2,
      contains('turns around'),
    );
  });
}
