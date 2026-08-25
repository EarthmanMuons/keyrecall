import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/practice/exercise_presentation.dart';
import 'package:keyrecall/features/practice/presentation_policy.dart';

void main() {
  group('naming', () {
    test('reads a material the way a musician would say it', () {
      expect(
        materialName(TechnicalMaterial('F#', ScaleForm.harmonicMinor)),
        'F♯ harmonic minor',
      );
      expect(materialName(TechnicalMaterial('C', ScaleForm.major)), 'C major');
      expect(
        materialName(TechnicalMaterial('Bb', ScaleForm.naturalMinor)),
        'B♭ natural minor',
      );
    });

    test('states the conditions as one line', () {
      expect(
        conditionsLine(
          ExecutionConditions(
            hands: HandConfiguration.right,
            octaves: 2,
            direction: ScaleDirection.upDown,
            tempoBpm: 80,
          ),
        ),
        'Right hand · 2 octaves · up and down · 80 bpm',
      );
      expect(
        conditionsLine(
          ExecutionConditions(
            hands: HandConfiguration.together,
            octaves: 1,
            direction: ScaleDirection.up,
            tempoBpm: 66,
          ),
        ),
        'Hands together · 1 octave · up · 66 bpm',
      );
    });
  });

  group('pitch surface', () {
    Exercise exerciseOf(
      String tonic,
      ScaleForm form, {
      HandConfiguration hands = HandConfiguration.right,
      int octaves = 2,
    }) => Exercise.linear(
      material: TechnicalMaterial(tonic, form),
      hands: hands,
      octaves: octaves,
    );

    test('marks the member notes of the requested range', () {
      final surface = KeyboardDiagram.forExercise(
        exerciseOf('C', ScaleForm.major, octaves: 1),
      );

      expect(surface.memberNotes, {
        60,
        62,
        64,
        65,
        67,
        69,
        71,
        72,
      }, reason: 'one octave of C major from middle C, both tonics included');
      expect(surface.tonicPitchClass, 0);
    });

    test('takes the accidentals from the form, not just the key', () {
      final surface = KeyboardDiagram.forExercise(
        exerciseOf('D', ScaleForm.harmonicMinor, octaves: 1),
      );

      // D harmonic minor: D E F G A Bb C#, so the leading tone is C# and
      // there is no natural C in the range.
      expect(surface.memberNotes.contains(73), isTrue);
      expect(surface.memberNotes.contains(72), isFalse);
      expect(surface.tonicPitchClass, 2);
    });

    test('drops the left hand an octave and spans both when together', () {
      final right = KeyboardDiagram.forExercise(
        exerciseOf('C', ScaleForm.major, hands: HandConfiguration.right),
      );
      final left = KeyboardDiagram.forExercise(
        exerciseOf('C', ScaleForm.major, hands: HandConfiguration.left),
      );
      final together = KeyboardDiagram.forExercise(
        exerciseOf('C', ScaleForm.major, hands: HandConfiguration.together),
      );

      expect(right.memberNotes.reduce((a, b) => a < b ? a : b), 60);
      expect(left.memberNotes.reduce((a, b) => a < b ? a : b), 48);
      expect(together.memberNotes.reduce((a, b) => a < b ? a : b), 48);
      expect(
        together.memberNotes.reduce((a, b) => a > b ? a : b),
        84,
        reason: 'two octaves from where the right hand starts',
      );
    });

    test('draws a window wide enough to hold the range', () {
      final surface = KeyboardDiagram.forExercise(
        exerciseOf('C', ScaleForm.major, hands: HandConfiguration.together),
      );
      final lastWhite = _whiteMidiAfter(
        surface.firstWhiteMidi,
        surface.whiteKeyCount - 1,
      );

      expect(surface.firstWhiteMidi, lessThan(48));
      expect(lastWhite, greaterThan(84));
    });
  });

  group('policy', () {
    test('supplies a cue exactly when the rung supplies material', () {
      for (final guidance in GuidanceContext.ladder) {
        final presentation = presentationFor(guidance);
        expect(presentation.suitsGuidance(guidance), isTrue);
        expect(
          presentation.pitchCue,
          guidance.isMaterialSupplied ? PitchCue.full : PitchCue.none,
        );
        expect(
          presentation.cueModality,
          guidance.isMaterialSupplied ? CueModality.keyboard : isNull,
        );
      }
    });

    test('varies nothing but the pitch cue across the rungs', () {
      for (final guidance in GuidanceContext.ladder) {
        final presentation = presentationFor(guidance);
        expect(presentation.tempoSupport, TempoSupport.countInOnly);
        expect(presentation.motorCue, MotorCue.none);
        expect(
          presentation.performanceFeedback,
          PerformanceFeedback.neutralEcho,
          reason:
              'a rung change must move one variable, so the echo and the '
              'count-in are the same at every rung',
        );
      }
    });

    test('keeps the cue up only while the material is supplied throughout', () {
      expect(
        showsPitchCueDuringAttempt(GuidanceContext.continuouslyCued),
        isTrue,
      );
      expect(
        showsPitchCueDuringAttempt(GuidanceContext.notesPreviewedOnly),
        isFalse,
        reason: 'previewed means withdrawn at start, not recallable on demand',
      );
      expect(showsPitchCueDuringAttempt(GuidanceContext.unguided), isFalse);
    });
  });
}

/// The MIDI note [steps] white keys above [firstWhiteMidi].
int _whiteMidiAfter(int firstWhiteMidi, int steps) {
  const whites = {0, 2, 4, 5, 7, 9, 11};
  var midi = firstWhiteMidi;
  var seen = 0;
  while (seen < steps) {
    midi++;
    if (whites.contains(midi % 12)) seen++;
  }
  return midi;
}
