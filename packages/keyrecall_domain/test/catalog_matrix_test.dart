import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

/// Every material the domain supports, not the simulation's pinned fixture.
final List<TechnicalMaterial> supportedMaterials = [
  ...allScales,
  ...allRootPositionArpeggios,
];

List<HandMotion> motionsFor(HandConfiguration hands) =>
    hands == HandConfiguration.together
    ? HandMotion.values
    : const [HandMotion.parallel];

Iterable<Exercise> supportedExercises() sync* {
  for (final material in supportedMaterials) {
    for (final octaves in material.progression.octaveSpans) {
      for (final hands in HandConfiguration.values) {
        for (final motion in motionsFor(hands)) {
          for (final direction in ExerciseDirection.values) {
            yield Exercise.linear(
              material: material,
              hands: hands,
              octaves: octaves,
              direction: direction,
              handMotion: motion,
            );
          }
        }
      }
    }
  }
}

List<Hand> handsOf(HandConfiguration hands) => [
  if (hands.usesLeftHand) Hand.left,
  if (hands.usesRightHand) Hand.right,
];

void main() {
  test('the supported catalog is wider than the simulation fixture', () {
    expect(supportedMaterials.length, greaterThan(v1ScaleCatalog.length));
  });

  test('every supported exercise realizes', () {
    for (final exercise in supportedExercises()) {
      final realization = realize(exercise);
      final reason = exercise.toString();

      expect(realization.moments, isNotEmpty, reason: reason);
      expect(
        realization.hands,
        handsOf(exercise.conditions.hands).toSet(),
        reason: reason,
      );

      for (final moment in realization.moments) {
        expect(
          {for (final note in moment.notes) note.midiNote},
          hasLength(moment.notes.length),
          reason: '$reason at ${moment.position}',
        );
        for (final note in moment.notes) {
          expect(
            note.pitch.pitchClass,
            note.midiNote % 12,
            reason: '$reason at ${moment.position}',
          );
        }
      }
    }
  });

  test('every hand plays at every moment, in the asked-for direction', () {
    for (final exercise in supportedExercises()) {
      final realization = realize(exercise);
      final reason = exercise.toString();

      for (final hand in handsOf(exercise.conditions.hands)) {
        final line = [
          for (final moment in realization.moments) moment.noteFor(hand),
        ];
        expect(line, everyElement(isNotNull), reason: '$reason $hand');

        final pitches = [for (final note in line) note!.midiNote];
        // An up-down traversal plays the apex once, so its line is odd and
        // turns at the center.
        final apex = pitches.length ~/ 2;
        for (var step = 1; step < pitches.length; step++) {
          final climbs = switch (exercise.conditions.direction) {
            ExerciseDirection.up => _movesUp(exercise.conditions, hand),
            ExerciseDirection.upDown =>
              step <= apex
                  ? _movesUp(exercise.conditions, hand)
                  : !_movesUp(exercise.conditions, hand),
          };
          final delta = pitches[step] - pitches[step - 1];

          expect(
            climbs ? delta > 0 : delta < 0,
            isTrue,
            reason: '$reason $hand from ${step - 1} to $step, by $delta',
          );
        }
      }
    }
  });

  test('a canonical fingering covers the whole traversal', () {
    for (final exercise in supportedExercises()) {
      final moments = realize(exercise).moments.length;
      final reason = exercise.toString();

      for (final hand in handsOf(exercise.conditions.hands)) {
        final fingers = fingeringFor(exercise, hand);
        if (fingers == null) continue;
        expect(fingers, hasLength(moments), reason: '$reason $hand');
        expect(
          fingers,
          everyElement(inInclusiveRange(1, 5)),
          reason: '$reason $hand',
        );
      }
    }
  });

  test('a default instrument plays everything but the widest', () {
    final piano = InstrumentProfile();
    final rejected = [
      for (final exercise in supportedExercises())
        if (!piano.supportsRealizationWidth(realize(exercise))) exercise,
    ];

    expect(
      rejected,
      everyElement(
        isA<Exercise>().having(
          (exercise) => exercise.conditions.hands,
          'hands',
          HandConfiguration.together,
        ),
      ),
    );
    expect(
      rejected,
      everyElement(
        isA<Exercise>().having(
          (exercise) => exercise.conditions.octaves,
          'octaves',
          greaterThan(2),
        ),
      ),
    );
  });
}

/// Whether [hand] climbs on the first half of an ascending exercise.
///
/// Contrary motion sends the left hand the other way from the start.
bool _movesUp(ExecutionConditions conditions, Hand hand) =>
    conditions.handMotion == HandMotion.parallel || hand == Hand.right;
