import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  Exercise exerciseOf({
    String tonic = 'C',
    ScaleForm form = ScaleForm.major,
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 2,
    ScaleDirection direction = ScaleDirection.upDown,
    HandMotion handMotion = HandMotion.parallel,
  }) => Exercise.linear(
    material: TechnicalMaterial(tonic, form),
    hands: hands,
    octaves: octaves,
    direction: direction,
    handMotion: handMotion,
  );

  List<int> pitchesOf(ExerciseRealization realization, Hand hand) => [
    for (final moment in realization.moments)
      if (moment.noteFor(hand) case final note?) note.midiNote,
  ];

  group('what the exercise asks for', () {
    test('ascends an octave and lands on the upper tonic', () {
      final realization = realize(
        exerciseOf(octaves: 1, direction: ScaleDirection.up),
      );

      expect(pitchesOf(realization, Hand.right), [
        60,
        62,
        64,
        65,
        67,
        69,
        71,
        72,
      ]);
    });

    test('turns around on the apex rather than playing it twice', () {
      final realization = realize(
        exerciseOf(octaves: 1, direction: ScaleDirection.upDown),
      );
      final pitches = pitchesOf(realization, Hand.right);

      expect(pitches.length, 15);
      expect(pitches.first, 60);
      expect(pitches[7], 72);
      expect(pitches.last, 60);
      expect(pitches.sublist(7, 9), [
        72,
        71,
      ], reason: 'the apex is one moment, not two');
    });

    test('spans as many octaves as the conditions ask for', () {
      expect(
        realize(
          exerciseOf(octaves: 2, direction: ScaleDirection.up),
        ).moments.length,
        15,
      );
      expect(
        realize(exerciseOf(octaves: 2)).moments.length,
        29,
        reason: 'two octaves up and back, with a single apex',
      );
    });

    test('takes its accidentals from the form', () {
      final harmonic = realize(
        exerciseOf(
          tonic: 'D',
          form: ScaleForm.harmonicMinor,
          octaves: 1,
          direction: ScaleDirection.up,
        ),
      );

      // D E F G A Bb C#, so a raised seventh and no natural C.
      expect(pitchesOf(harmonic, Hand.right), [62, 64, 65, 67, 69, 70, 73, 74]);
    });

    test('descends in the same form as it ascends', () {
      final melodic = realize(
        exerciseOf(tonic: 'E', form: ScaleForm.melodicMinor, octaves: 1),
      );
      final pitches = pitchesOf(melodic, Hand.right);

      expect(
        pitches.reversed.toList(),
        pitches,
        reason: 'V1 melodic minor is the fixed ascending form both ways',
      );
    });
  });

  group('hands', () {
    test('one hand plays and the other is absent', () {
      final left = realize(exerciseOf(hands: HandConfiguration.left));

      expect(left.hands, {Hand.left});
      expect(left.moments.first.noteFor(Hand.right), isNull);
      expect(left.highestPitch, 60);
      expect(
        left.lowestPitch,
        36,
        reason:
            'the left hand is anchored by where it ends, so two octaves '
            'reach down rather than up',
      );
    });

    test('the left hand stays in its register however many octaves', () {
      // The property is about where a tonic sits, so what it needs is every
      // pitch class. The production catalog is what gets scheduled and covers
      // all twelve, which is asserted here rather than assumed; the frozen
      // prototype corpus covers seven and is the wrong fixture for this.
      expect({
        for (final material in allScales) pitchClassOf(material.tonic),
      }, hasLength(12));

      for (final octaves in [1, 2]) {
        for (final material in allScales) {
          for (final hands in [
            HandConfiguration.left,
            HandConfiguration.right,
          ]) {
            final realization = realize(
              Exercise.linear(
                material: material,
                hands: hands,
                octaves: octaves,
              ),
            );
            final home = hands == HandConfiguration.left
                ? realization.highestPitch
                : realization.lowestPitch;

            expect(
              (home - 60).abs(),
              lessThanOrEqualTo(6),
              reason:
                  '${material.materialId} on ${hands.id} over $octaves '
                  'octaves sits more than half an octave from middle C',
            );
          }
        }
      }
    });

    test('neither hand is dropped an octave to avoid crossing middle C', () {
      // Two octaves of D in the left hand ended two semitones below middle C
      // by starting from D1, when starting from D2 and finishing two above is
      // the same scale in the register a pianist would use.
      final left = realize(
        exerciseOf(tonic: 'D', hands: HandConfiguration.left, octaves: 2),
      );

      expect(left.lowestPitch, 38);
      expect(left.highestPitch, 62);
    });

    test('both hands sound in the same moment, an octave apart', () {
      final together = realize(
        exerciseOf(hands: HandConfiguration.together, octaves: 1),
      );
      final first = together.moments.first;

      expect(together.hands, {Hand.left, Hand.right});
      expect(first.notes.length, 2);
      expect(
        first.noteFor(Hand.right)!.midiNote -
            first.noteFor(Hand.left)!.midiNote,
        12,
      );
      expect(together.lowestPitch, 48);
      expect(together.highestPitch, 72);
    });
  });

  group('hands moving contrary to each other', () {
    ExerciseRealization contrary({
      int octaves = 1,
      ScaleDirection direction = ScaleDirection.upDown,
    }) => realize(
      exerciseOf(
        hands: HandConfiguration.together,
        octaves: octaves,
        direction: direction,
        handMotion: HandMotion.contrary,
      ),
    );

    test('the hands begin on one key, in unison', () {
      final first = contrary().moments.first;

      expect(first.notes.single.hands, {Hand.left, Hand.right});
      expect(first.notes.single.midiNote, 60);
    });

    test('the lines run in opposite directions', () {
      final realization = contrary(direction: ScaleDirection.up);

      expect(pitchesOf(realization, Hand.right), [
        60,
        62,
        64,
        65,
        67,
        69,
        71,
        72,
      ]);
      expect(pitchesOf(realization, Hand.left), [
        60,
        59,
        57,
        55,
        53,
        52,
        50,
        48,
      ]);
    });

    test('each line turns around at its own outside end', () {
      final realization = contrary();

      expect(realization.moments.length, 15);
      expect(realization.moments.last.notes.single.hands, {
        Hand.left,
        Hand.right,
      });
      expect(realization.lowestPitch, 48);
      expect(realization.highestPitch, 72);
    });

    test('the span is per hand, so the keyboard reach doubles', () {
      final oneOctave = contrary();
      final twoOctaves = contrary(octaves: 2);

      expect(oneOctave.highestPitch - oneOctave.lowestPitch, 24);
      expect(twoOctaves.highestPitch - twoOctaves.lowestPitch, 48);
    });

    test('the descending line is spelled on its own degrees', () {
      final realization = contrary(direction: ScaleDirection.up);
      final left = [
        for (final moment in realization.moments)
          '${moment.noteFor(Hand.left)!.pitch.label}'
              '${moment.noteFor(Hand.left)!.pitch.octave}',
      ];

      expect(left, ['C4', 'B3', 'A3', 'G3', 'F3', 'E3', 'D3', 'C3']);
    });

    test('a unison is one note the exercise asks for', () {
      // Fifteen moments, two of them unisons, so twenty-eight keys rather
      // than thirty: the instrument reports one note-on for a shared key.
      expect(contrary().noteCount, 28);
    });
  });

  group('moments', () {
    test('are numbered in order and carry their own metric position', () {
      final moments = realize(exerciseOf(octaves: 1)).moments;

      expect(
        [for (final moment in moments) moment.position],
        [for (var i = 0; i < moments.length; i++) i],
      );
      expect(
        [for (final moment in moments) moment.metricOffset],
        [for (var i = 0; i < moments.length; i++) i.toDouble()],
        reason:
            'V1 puts one moment on each beat; the two are still separate '
            'quantities',
      );
    });

    test('say nothing about when a note was or should be played in time', () {
      // Realization is what the task asks for. Anything about a performance,
      // including tolerance and alignment, belongs to a layer that does not
      // exist yet.
      final moment = realize(exerciseOf()).moments.first;

      expect(moment.notes.single.midiNote, 60);
      expect(moment.metricOffset, 0.0);
    });
  });

  group('identity', () {
    test('the same exercise realizes the same way', () {
      expect(realize(exerciseOf()), realize(exerciseOf()));
      expect(realize(exerciseOf()), isNot(realize(exerciseOf(tonic: 'G'))));
    });

    test('guidance does not change what is asked for', () {
      final unguided = exerciseOf();
      expect(
        realize(unguided.withGuidance(GuidanceContext.continuouslyCued)),
        realize(unguided),
      );
    });
  });

  group('spelling', () {
    test('spells each degree on its own letter', () {
      final realization = realize(
        exerciseOf(
          tonic: 'F#',
          form: ScaleForm.harmonicMinor,
          octaves: 1,
          direction: ScaleDirection.up,
        ),
      );

      expect(
        [
          for (final moment in realization.moments)
            moment.notes.single.pitch.label,
        ],
        ['F#', 'G#', 'A', 'B', 'C#', 'D', 'E#', 'F#'],
        reason: 'the seventh degree is a raised E, not an F natural',
      );
    });

    test('reaches a double accidental when the degree needs one', () {
      final realization = realize(
        exerciseOf(
          tonic: 'G#',
          form: ScaleForm.harmonicMinor,
          octaves: 1,
          direction: ScaleDirection.up,
        ),
      );
      final seventh = realization.moments[6].notes.single;

      expect(seventh.pitch.label, 'F##');
      expect(seventh.pitch.prettyLabel, 'F𝄪');
      expect(
        seventh.midiNote % 12,
        7,
        reason: 'it is written as a raised seventh and sounds like a G',
      );
    });

    test('the written pitch and the key played always agree', () {
      for (final material in v1ScaleCatalog) {
        final realization = realize(
          Exercise.linear(
            material: material,
            hands: HandConfiguration.together,
          ),
        );
        for (final moment in realization.moments) {
          for (final note in moment.notes) {
            expect(note.midiNote, note.pitch.midiNote);
          }
        }
      }
    });
  });

  group('invariants', () {
    test('a hand plays at most one note per moment', () {
      expect(
        () => RealizationMoment(
          position: 0,
          metricOffset: 0,
          notes: [
            RealizedNote(
              hand: Hand.right,
              pitch: SpelledPitch(letter: NoteLetter.c, octave: 4),
            ),
            RealizedNote(
              hand: Hand.right,
              pitch: SpelledPitch(letter: NoteLetter.e, octave: 4),
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('an exercise that asks for nothing is not a realization', () {
      expect(() => ExerciseRealization([]), throwsArgumentError);
    });
  });

  test('pitch classes read canonical tonics', () {
    expect(pitchClassOf('C'), 0);
    expect(pitchClassOf('F#'), 6);
    expect(pitchClassOf('Bb'), 10);
    expect(() => pitchClassOf('H'), throwsArgumentError);
  });
}
