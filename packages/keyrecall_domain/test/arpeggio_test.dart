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
    expect(exercise.structuralQ, contains(Competency.arpeggioTransition));
    expect(
      exercise.structuralQ,
      isNot(contains(Competency.majorScaleTopology)),
    );
    expect(exercise.structuralQ, isNot(contains(Competency.rhScaleExecution)));
  });
}
