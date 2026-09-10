import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';

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

    test('names each condition the way a learner would say it', () {
      expect(handsName(HandConfiguration.right), 'Right hand');
      expect(handsName(HandConfiguration.together), 'Hands together');
      expect(octavesName(1), '1 octave');
      expect(octavesName(2), '2 octaves');
      expect(
        traversalName(
          ExecutionConditions(
            hands: HandConfiguration.right,
            direction: ExerciseDirection.up,
          ),
        ),
        'Up',
      );
      expect(
        traversalName(ExecutionConditions(hands: HandConfiguration.right)),
        'Up and down',
      );
      expect(
        traversalName(
          ExecutionConditions(
            hands: HandConfiguration.together,
            handMotion: HandMotion.contrary,
            direction: ExerciseDirection.up,
          ),
        ),
        'Contrary motion, apart',
      );
      expect(
        traversalName(
          ExecutionConditions(
            hands: HandConfiguration.together,
            handMotion: HandMotion.contrary,
          ),
        ),
        'Contrary motion, apart and back',
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

    test('puts each hand in its own register and spans both together', () {
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
      expect(
        left.memberNotes.reduce((a, b) => a > b ? a : b),
        60,
        reason: 'the left hand is placed by where it finishes',
      );
      expect(left.memberNotes.reduce((a, b) => a < b ? a : b), 36);
      expect(together.memberNotes.reduce((a, b) => a < b ? a : b), 36);
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
          guidance.isMaterialSupplied ? CueModality.keyboardAndStaff : isNull,
        );
      }
    });

    test('leaves the tempo axis where the rung cannot reach it', () {
      for (final guidance in GuidanceContext.ladder) {
        expect(
          presentationFor(guidance).tempoSupport,
          TempoSupport.countInOnly,
          reason:
              'tempo support is an independent axis, so a rung change must '
              'not move it in either direction',
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

  group('the way out of an attempt', () {
    test('is about playing where the notes were studied first', () {
      // The previewed rung showed them, so what is in question is producing
      // them again rather than knowing them at all.
      expect(
        declineLabel(GuidanceContext.notesPreviewedOnly, metBefore: true),
        "I can't play this from memory",
      );
      expect(
        declineLabel(GuidanceContext.notesPreviewedOnly, metBefore: false),
        "I can't play this from memory",
      );
    });

    test('is about forgetting only where there is something to forget', () {
      expect(
        declineLabel(GuidanceContext.unguided, metBefore: true),
        "I don't remember",
      );
      expect(
        declineLabel(GuidanceContext.unguided, metBefore: false),
        "I don't know this yet",
        reason: 'nothing shown for the first time can have been forgotten',
      );
    });
  });

  group('what a material is called in a sentence', () {
    test('root arpeggios have short titles while inversions stay distinct', () {
      expect(
        materialName(ArpeggioMaterial('C', ArpeggioQuality.major)),
        'C major arpeggio',
      );
      expect(
        materialName(
          ArpeggioMaterial(
            'C',
            ArpeggioQuality.major,
            inversion: ArpeggioInversion.first,
          ),
        ),
        'C major first-inversion arpeggio',
      );
    });
    test('says how many times through a self-paced task asks for', () {
      // Playing the pattern twice and playing twice as much of it are
      // different things to be asked for, so a repeated task has to say which
      // and a single one must not.
      expect(selfPacedInstruction(1), isNot(contains('again')));
      expect(selfPacedInstruction(2), contains('twice'));
      expect(selfPacedInstruction(2), contains('starting again each time'));
      expect(selfPacedInstruction(3), contains('three times'));
      expect(selfPacedInstruction(4), contains('4 times'));
    });

    test('says what a supported attempt actually did', () {
      AcquisitionAttemptRecord closed(
        TechnicalMaterial material, {
        bool started = true,
        AcquisitionCompletion completion = AcquisitionCompletion.notCompleted,
        int? firstAbsentPosition,
      }) => AcquisitionAttemptRecord(
        journalSequence: 0,
        identity: AttemptIdentity(
          profileId: 'abc12345',
          attemptId: 'acq-0',
          sessionId: 'sitting-1',
          indexInSession: 0,
          occurredAt: DateTime.utc(2026, 9, 9),
        ),
        task: AcquisitionTask.unmeteredTraversal(
          Exercise.linear(
            material: material,
            hands: HandConfiguration.right,
            octaves: 1,
            direction: ExerciseDirection.up,
            tempoBpm: 60,
            guidance: GuidanceContext.continuouslyCued,
          ),
        ),
        started: started,
        completion: completion,
        repairs: 0,
        repeats: 0,
        intrusions: 0,
        firstAbsentPosition: firstAbsentPosition,
        earnedProbe: false,
        gaps: const [],
      );

      final scale = TechnicalMaterial('C', ScaleForm.major);
      final arpeggio = ArpeggioMaterial('C', ArpeggioQuality.major);

      expect(
        acquisitionOutcomeLine(
          closed(scale, completion: AcquisitionCompletion.completedCleanly),
        ),
        'You played the whole scale, at your own pace.',
      );
      expect(
        acquisitionOutcomeLine(closed(scale, firstAbsentPosition: 5)),
        'You stopped before the end of the scale.',
      );
      // Every position was played and some of them were something else, which
      // is a different thing to have done than running out.
      expect(
        acquisitionOutcomeLine(closed(scale)),
        'Some of the notes were not the ones in the scale.',
      );
      expect(
        acquisitionOutcomeLine(closed(scale, started: false)),
        'Nothing came through that time.',
      );
      // The family's own word, so an arpeggio is never called a scale.
      expect(
        acquisitionOutcomeLine(closed(arpeggio, firstAbsentPosition: 3)),
        'You stopped before the end of the arpeggio.',
      );
    });

    test('each family uses its own word', () {
      expect(materialNoun(TechnicalMaterial('C', ScaleForm.major)), 'scale');
      expect(
        materialNoun(ArpeggioMaterial('C', ArpeggioQuality.major)),
        'arpeggio',
      );
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
