import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  Exercise exerciseOf({
    String tonic = 'C',
    ScaleForm form = ScaleForm.major,
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 2,
    ScaleDirection direction = ScaleDirection.upDown,
  }) => Exercise.linear(
    material: TechnicalMaterial(tonic, form),
    hands: hands,
    octaves: octaves,
    direction: direction,
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
      for (final octaves in [1, 2]) {
        for (final tonic in ['C', 'B', 'F']) {
          final left = realize(
            exerciseOf(
              tonic: tonic,
              hands: HandConfiguration.left,
              octaves: octaves,
            ),
          );

          expect(
            left.highestPitch,
            lessThanOrEqualTo(60),
            reason: '$tonic over $octaves octaves climbs above middle C',
          );
        }
      }
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
