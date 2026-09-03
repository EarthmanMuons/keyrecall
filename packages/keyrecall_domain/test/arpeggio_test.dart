import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final material = ArpeggioMaterial('C', ArpeggioQuality.major);

  test('identity includes family, quality, and inversion', () {
    expect(material.familyId, TechnicalMaterial.arpeggioFamilyId);
    expect(material.materialId, 'C_MAJOR_ROOT_ARPEGGIO');
    expect(material, isNot(TechnicalMaterial('C', ScaleForm.major)));
  });

  test('topology realizes chord tones rather than scale degrees', () {
    final exercise = Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
    );

    expect(
      realize(exercise).moments.map((moment) => moment.notes.single.pitch),
      [
        SpelledPitch(letter: NoteLetter.c, octave: 4),
        SpelledPitch(letter: NoteLetter.e, octave: 4),
        SpelledPitch(letter: NoteLetter.g, octave: 4),
        SpelledPitch(letter: NoteLetter.c, octave: 5),
      ],
    );
  });

  test('fingering and observations are arpeggio-specific', () {
    final exercise = Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
    );

    expect(fingeringFor(exercise, Hand.right), [1, 2, 3, 5]);
    expect(exercise.structuralQ, contains(Competency.majorArpeggioTopology));
    expect(exercise.structuralQ, contains(Competency.rhArpeggioExecution));
    expect(
      exercise.structuralQ,
      isNot(contains(Competency.arpeggioTransition)),
    );
    expect(
      exercise.structuralQ,
      isNot(contains(Competency.majorScaleTopology)),
    );
    expect(exercise.structuralQ, isNot(contains(Competency.rhScaleExecution)));
  });

  test('transition demand occurs only at a continuing fingering boundary', () {
    final exercise = Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      octaves: 2,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
    );

    expect(fingeringFor(exercise, Hand.right), [1, 2, 3, 1, 2, 3, 5]);
    expect(exercise.structuralQ, contains(Competency.arpeggioTransition));
    expect(exercise.opportunitySites, {
      const MotorOpportunitySite(
        opportunity: MotorOpportunity.multiOctaveContinuation,
        hand: Hand.right,
        momentIndex: 3,
      ),
      const MotorOpportunitySite(
        opportunity: MotorOpportunity.arpeggioTransition,
        hand: Hand.right,
        momentIndex: 3,
      ),
    });
  });

  test('left-hand transitions follow each authoritative fingering family', () {
    for (final (tonic, expectedFingers) in [
      ('C', [5, 4, 2, 1, 4, 2, 1]),
      ('G', [5, 4, 2, 1, 4, 2, 1]),
      ('D', [5, 3, 2, 1, 3, 2, 1]),
    ]) {
      final exercise = Exercise.linear(
        material: ArpeggioMaterial(tonic, ArpeggioQuality.major),
        hands: HandConfiguration.left,
        octaves: 2,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
      );

      expect(fingeringFor(exercise, Hand.left), expectedFingers);
      expect(
        exercise.opportunitySites,
        contains(
          const MotorOpportunitySite(
            opportunity: MotorOpportunity.arpeggioTransition,
            hand: Hand.left,
            momentIndex: 4,
          ),
        ),
        reason: tonic,
      );
    }
  });

  test(
    'an unsupported fingering does not acquire a family-wide transition',
    () {
      final exercise = Exercise.linear(
        material: ArpeggioMaterial('F', ArpeggioQuality.major),
        hands: HandConfiguration.right,
        octaves: 2,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
      );

      expect(fingeringFor(exercise, Hand.right), isNull);
      expect(
        exercise.opportunities,
        isNot(contains(MotorOpportunity.arpeggioTransition)),
      );
    },
  );

  test('proof fingerings preserve their left-hand families', () {
    final conditions = ExecutionConditions(
      hands: HandConfiguration.left,
      octaves: 1,
      direction: ExerciseDirection.up,
      handMotion: HandMotion.parallel,
      tempoBpm: 60,
    );

    expect(
      fingeringForConditions(
        material: ArpeggioMaterial('C', ArpeggioQuality.major),
        conditions: conditions,
        hand: Hand.left,
      ),
      [5, 4, 2, 1],
    );
    expect(
      fingeringForConditions(
        material: ArpeggioMaterial('G', ArpeggioQuality.major),
        conditions: conditions,
        hand: Hand.left,
      ),
      [5, 4, 2, 1],
    );
    expect(
      fingeringForConditions(
        material: ArpeggioMaterial('D', ArpeggioQuality.major),
        conditions: conditions,
        hand: Hand.left,
      ),
      [5, 3, 2, 1],
    );
  });
}
