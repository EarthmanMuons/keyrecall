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
        material: ArpeggioMaterial(
          'C',
          ArpeggioQuality.major,
          inversion: ArpeggioInversion.first,
        ),
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

  test('root position is supported without leaking into inversions', () {
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

  group('root-position fingering corpus', () {
    final expected = <String, (String, String, CanonicalFingeringStatus)>{
      'C_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'Db_MAJOR_ROOT_ARPEGGIO': (
        '2124',
        '2142',
        CanonicalFingeringStatus.established,
      ),
      'D_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5321',
        CanonicalFingeringStatus.established,
      ),
      'Eb_MAJOR_ROOT_ARPEGGIO': (
        '2124',
        '2142',
        CanonicalFingeringStatus.established,
      ),
      'E_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5321',
        CanonicalFingeringStatus.established,
      ),
      'F_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'F#_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5321',
        CanonicalFingeringStatus.canonicalSelected,
      ),
      'G_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'Ab_MAJOR_ROOT_ARPEGGIO': (
        '2124',
        '2142',
        CanonicalFingeringStatus.established,
      ),
      'A_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5321',
        CanonicalFingeringStatus.established,
      ),
      'Bb_MAJOR_ROOT_ARPEGGIO': (
        '2124',
        '3213',
        CanonicalFingeringStatus.canonicalSelected,
      ),
      'B_MAJOR_ROOT_ARPEGGIO': (
        '1235',
        '5321',
        CanonicalFingeringStatus.established,
      ),
      'C_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'C#_MINOR_ROOT_ARPEGGIO': (
        '2124',
        '2142',
        CanonicalFingeringStatus.established,
      ),
      'D_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'Eb_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'E_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'F_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'F#_MINOR_ROOT_ARPEGGIO': (
        '2124',
        '2142',
        CanonicalFingeringStatus.established,
      ),
      'G_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'G#_MINOR_ROOT_ARPEGGIO': (
        '2124',
        '2142',
        CanonicalFingeringStatus.established,
      ),
      'A_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
      'Bb_MINOR_ROOT_ARPEGGIO': (
        '2312',
        '3213',
        CanonicalFingeringStatus.canonicalSelected,
      ),
      'B_MINOR_ROOT_ARPEGGIO': (
        '1235',
        '5421',
        CanonicalFingeringStatus.established,
      ),
    };

    test('covers every canonical major and minor tonic in both hands', () {
      expect(allRootPositionArpeggios, hasLength(24));
      expect(
        allRootPositionArpeggios.map((material) => material.materialId).toSet(),
        expected.keys.toSet(),
      );

      for (final material in allRootPositionArpeggios) {
        final expectedRecord = expected[material.materialId]!;
        final right = canonicalFingering(material, Hand.right)!;
        final left = canonicalFingering(material, Hand.left)!;

        expect(right.ascending(1).join(), expectedRecord.$1);
        expect(left.ascending(1).join(), expectedRecord.$2);
        expect(right.provenance.status, expectedRecord.$3);
        expect(left.provenance.status, expectedRecord.$3);
        for (final record in [right, left]) {
          expect(record.provenance.source, isNotEmpty);
          expect(record.provenance.sourceEdition, isNotEmpty);
          expect(record.provenance.sourceLocation, isNotEmpty);
          expect(record.reversesForDescending, isTrue);
        }
      }
    });

    test('entry, cycle, and terminal realize every supported traversal', () {
      for (final material in allRootPositionArpeggios) {
        for (final hand in Hand.values) {
          final record = canonicalFingering(material, hand)!;
          final hands = hand == Hand.right
              ? HandConfiguration.right
              : HandConfiguration.left;

          for (final octaves in material.progression.octaveSpans) {
            final ascending = record.ascending(octaves);
            expect(
              record.descending(octaves),
              ascending.reversed,
              reason: '${material.materialId} $hand $octaves descending',
            );
            expect(
              ascending,
              everyElement(inInclusiveRange(1, 5)),
              reason: '${material.materialId} $hand $octaves fingers',
            );
            for (var octave = 0; octave < octaves - 1; octave++) {
              final cycleStart =
                  record.entry.length +
                  octave * material.topology.degreesPerOctave;
              expect(
                ascending.sublist(
                  cycleStart,
                  cycleStart + material.topology.degreesPerOctave,
                ),
                record.cycle,
                reason:
                    '${material.materialId} $hand octave ${octave + 1} cycle',
              );
            }

            for (final direction in ExerciseDirection.values) {
              final exercise = Exercise.linear(
                material: material,
                hands: hands,
                octaves: octaves,
                direction: direction,
              );
              final fingers = fingeringFor(exercise, hand)!;
              final moments = realize(exercise).moments;

              expect(
                fingers.length,
                moments.length,
                reason:
                    '${material.materialId} $hand $octaves $direction length',
              );
              expect(
                fingers,
                everyElement(inInclusiveRange(1, 5)),
                reason:
                    '${material.materialId} $hand $octaves $direction fingers',
              );

              final path = handPathsFor(
                exercise.conditions,
                degreesPerOctave: material.topology.degreesPerOctave,
              )[hand]!;
              final crossingIndices = {
                for (var index = 1; index < path.length; index++)
                  if (_isCrossing(path, fingers, hand, index)) index,
              };
              final transitionIndices = {
                for (final site in exercise.opportunitySites)
                  if (site.opportunity == MotorOpportunity.arpeggioTransition &&
                      site.hand == hand)
                    site.momentIndex,
              };
              expect(
                transitionIndices,
                crossingIndices,
                reason:
                    '${material.materialId} $hand $octaves $direction crossings',
              );
            }
          }
        }
      }
    });

    test('unsupported spellings and inversions remain absent', () {
      final unsupported = [
        ArpeggioMaterial('Gb', ArpeggioQuality.major),
        ArpeggioMaterial('Ab', ArpeggioQuality.minor),
        ArpeggioMaterial(
          'C',
          ArpeggioQuality.minor,
          inversion: ArpeggioInversion.first,
        ),
        ArpeggioMaterial(
          'C',
          ArpeggioQuality.major,
          inversion: ArpeggioInversion.second,
        ),
      ];

      for (final material in unsupported) {
        for (final hand in Hand.values) {
          expect(
            canonicalFingering(material, hand),
            isNull,
            reason: '${material.materialId} $hand',
          );
        }
      }
    });
  });
}

bool _isCrossing(List<int> path, List<int> fingers, Hand hand, int index) {
  final degreeMotion = path[index] - path[index - 1];
  final fingerMotion = fingers[index] - fingers[index - 1];
  if (degreeMotion == 0 || fingerMotion == 0) return false;
  return degreeMotion * fingerMotion > 0 == (hand == Hand.left);
}
