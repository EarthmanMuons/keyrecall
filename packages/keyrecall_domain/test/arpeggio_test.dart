import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final material = ArpeggioMaterial('C', ArpeggioQuality.major);

  test('identity includes family, quality, and inversion', () {
    expect(material.familyId, TechnicalMaterial.arpeggioFamilyId);
    expect(material.materialId, 'C_MAJOR_ROOT_ARPEGGIO');
    expect(material, isNot(TechnicalMaterial('C', ScaleForm.major)));
  });

  test('quality and inversion each produce distinct material identity', () {
    expect(
      ArpeggioMaterial(
        'C',
        ArpeggioQuality.major,
        inversion: ArpeggioInversion.first,
      ).materialId,
      'C_MAJOR_FIRST_ARPEGGIO',
    );
    expect(
      ArpeggioMaterial(
        'C',
        ArpeggioQuality.minor,
        inversion: ArpeggioInversion.second,
      ).materialId,
      'C_MINOR_SECOND_ARPEGGIO',
    );
  });

  test('all triad qualities and inversions realize their ordered topology', () {
    final cases = [
      (
        ArpeggioQuality.major,
        ArpeggioInversion.root,
        [0, 4, 7, 12],
        ['C', 'E', 'G', 'C'],
      ),
      (
        ArpeggioQuality.major,
        ArpeggioInversion.first,
        [0, 3, 8, 12],
        ['E', 'G', 'C', 'E'],
      ),
      (
        ArpeggioQuality.major,
        ArpeggioInversion.second,
        [0, 5, 9, 12],
        ['G', 'C', 'E', 'G'],
      ),
      (
        ArpeggioQuality.minor,
        ArpeggioInversion.root,
        [0, 3, 7, 12],
        ['C', 'Eb', 'G', 'C'],
      ),
      (
        ArpeggioQuality.minor,
        ArpeggioInversion.first,
        [0, 4, 9, 12],
        ['Eb', 'G', 'C', 'Eb'],
      ),
      (
        ArpeggioQuality.minor,
        ArpeggioInversion.second,
        [0, 5, 8, 12],
        ['G', 'C', 'Eb', 'G'],
      ),
    ];

    for (final (quality, inversion, intervals, spellings) in cases) {
      final exercise = Exercise.linear(
        material: ArpeggioMaterial('C', quality, inversion: inversion),
        hands: HandConfiguration.right,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
      );
      final pitches = [
        for (final moment in realize(exercise).moments)
          moment.notes.single.pitch,
      ];
      final firstMidi = pitches.first.midiNote;

      expect(
        pitches.map((pitch) => pitch.midiNote - firstMidi),
        intervals,
        reason: '$quality $inversion intervals',
      );
      expect(
        pitches.map(
          (pitch) =>
              '${pitch.letter.label}${switch (pitch.alteration) {
                -1 => 'b',
                0 => '',
                1 => '#',
                _ => pitch.alteration,
              }}',
        ),
        spellings,
        reason: '$quality $inversion spelling',
      );
    }
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

  test('only sourced new arpeggio combinations have fingering records', () {
    final cMinor = ArpeggioMaterial('C', ArpeggioQuality.minor);
    final cMajorFirst = ArpeggioMaterial(
      'C',
      ArpeggioQuality.major,
      inversion: ArpeggioInversion.first,
    );

    expect(canonicalFingering(cMinor, Hand.right)?.ascending(2), [
      1,
      2,
      3,
      1,
      2,
      3,
      5,
    ]);
    expect(canonicalFingering(cMinor, Hand.left)?.ascending(2), [
      5,
      4,
      2,
      1,
      4,
      2,
      1,
    ]);
    expect(canonicalFingering(cMajorFirst, Hand.right), isNull);
    expect(canonicalFingering(cMajorFirst, Hand.left), isNull);
  });
}
