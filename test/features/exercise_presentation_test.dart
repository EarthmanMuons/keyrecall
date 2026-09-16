import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

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

    test('varies nothing but the pitch cue and what rides on it', () {
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

    test('locates only where a cue staff is on screen while playing', () {
      expect(
        presentationFor(GuidanceContext.continuouslyCued).locatorFeedback,
        LocatorFeedback.positionTracking,
      );
      for (final guidance in [
        GuidanceContext.notesPreviewedOnly,
        GuidanceContext.unguided,
      ]) {
        expect(
          presentationFor(guidance).locatorFeedback,
          LocatorFeedback.none,
          reason:
              'a withdrawn cue takes the locator with it, and an unguided '
              'rung never had one to travel over',
        );
      }
    });

    test('asks for no pulse where no tempo was asked for', () {
      final parent = Exercise.linear(
        material: TechnicalMaterial('C', ScaleForm.major),
        hands: HandConfiguration.right,
        guidance: GuidanceContext.continuouslyCued,
      );
      final task = AcquisitionTask.unmeteredTraversal(parent);

      // Resolved from the task, which is the only form the screen uses: the
      // parent alone cannot say the tempo was removed, and asking it was how
      // a self-paced attempt came to record a count-in it never runs.
      expect(
        presentationForTask(task).tempoSupport,
        TempoSupport.none,
        reason:
            'a supported task removed the tempo, so there is no pulse to '
            'count in to and nothing to record as having counted one',
      );
      expect(
        presentationForTask(task).pitchCue,
        presentationFor(parent.guidance, exercise: parent).pitchCue,
        reason: 'the task removes the tempo and nothing else',
      );
    });

    test('refuses to draw a pitch cue no surface restricts', () {
      expect(drawsWholeSequence(PitchCue.none), isFalse);
      expect(drawsWholeSequence(PitchCue.full), isTrue);
      for (final cue in [PitchCue.startOnly, PitchCue.limitedLookahead]) {
        expect(
          () => drawsWholeSequence(cue),
          throwsUnsupportedError,
          reason: 'drawing it in full would supply what it withheld',
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
      // How many is the one thing the notes on screen cannot say, since they
      // are one traversal whatever the task asks for.
      expect(selfPacedInstruction(1), isNot(contains('twice')));
      expect(selfPacedInstruction(2), contains('twice'));
      expect(selfPacedInstruction(3), contains('three times'));
      expect(selfPacedInstruction(4), contains('4 times'));
    });

    AcquisitionAttemptRecord closed(
      TechnicalMaterial material, {
      bool started = true,
      AcquisitionCompletion completion = AcquisitionCompletion.notCompleted,
      int? firstAbsentPosition,
      int traversals = 1,
      AttemptTermination termination = AttemptTermination.learnerStopped,
    }) => AcquisitionAttemptRecord(
      journalSequence: 0,
      identity: AttemptIdentity(
        profileId: 'abc12345',
        attemptId: 'acq-0',
        sessionId: 'sitting-1',
        indexInSession: 0,
        occurredAt: DateTime.utc(2026, 9, 9),
      ),
      task: AcquisitionTask(
        parent: Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
          direction: ExerciseDirection.up,
          tempoBpm: 60,
          guidance: GuidanceContext.continuouslyCued,
        ),
        timing: TimingDemand.unmetered,
        advancement: TaskAdvancement.learnerDriven,
        portion: traversals == 1
            ? const FullTraversal()
            : TraversalRepetitions(traversals),
      ),
      termination: termination,
      started: started,
      completion: completion,
      repairs: 0,
      repeats: 0,
      intrusions: 0,
      firstAbsentPosition: firstAbsentPosition,
      earnedProbe: false,
      // A capture that may have lost events judges no criterion, which the
      // record itself enforces.
      sequence: termination == AttemptTermination.inputInterrupted
          ? CriterionVerdict.unavailable
          : CriterionVerdict.notMet,
      continuity: CriterionVerdict.unavailable,
      gaps: const [],
    );

    test('says what a supported attempt actually did', () {
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
        'You stopped before completing the scale.',
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
        'You stopped before completing the arpeggio.',
      );
    });

    test('does not put an interrupted capture down to the learner', () {
      // "You stopped" is a claim about what the learner did, and an input
      // fault is not evidence of it. What the app can say is what it recorded.
      expect(
        acquisitionOutcomeLine(
          closed(
            TechnicalMaterial('C', ScaleForm.major),
            firstAbsentPosition: 5,
            termination: AttemptTermination.inputInterrupted,
          ),
        ),
        'The connection was interrupted before the scale was fully recorded.',
      );
      expect(
        acquisitionOutcomeLine(
          closed(
            TechnicalMaterial('C', ScaleForm.major),
            completion: AcquisitionCompletion.completedCleanly,
            termination: AttemptTermination.inputInterrupted,
          ),
        ),
        'The connection was interrupted. The whole scale was recorded.',
      );
      // A timeout is not the learner either, and neither is a record whose
      // format could not say how it ended.
      for (final termination in [
        AttemptTermination.inactivityTimeout,
        AttemptTermination.durationLimit,
      ]) {
        expect(
          acquisitionOutcomeLine(
            closed(
              TechnicalMaterial('C', ScaleForm.major),
              firstAbsentPosition: 5,
              termination: termination,
            ),
          ),
          'The scale was not completed.',
        );
      }
    });

    test('says where the playing got to, not what it produced', () {
      final arpeggio = ArpeggioMaterial('C', ArpeggioQuality.major);

      // Neither how many traversals came out nor which one the playing ended
      // in: the record establishes neither.
      for (final absent in [2, 6]) {
        expect(
          acquisitionOutcomeLine(
            closed(arpeggio, traversals: 2, firstAbsentPosition: absent),
          ),
          'You stopped before completing the arpeggio.',
          reason: 'first absent at $absent',
        );
      }
      expect(
        acquisitionOutcomeLine(
          closed(
            arpeggio,
            traversals: 2,
            completion: AcquisitionCompletion.completedCleanly,
          ),
        ),
        'You played the whole arpeggio twice, at your own pace.',
      );
      expect(
        acquisitionOutcomeLine(
          closed(
            arpeggio,
            traversals: 2,
            firstAbsentPosition: 6,
            termination: AttemptTermination.inputInterrupted,
          ),
        ),
        'The connection was interrupted before the arpeggio was fully '
        'recorded.',
      );
    });

    test('does not read where playing ended out of what is missing', () {
      // The earliest moment nothing arrived for is not where the attempt
      // ended: this omits a note inside the first traversal and then plays on
      // through the final note of the second. Wording that located the ending
      // from that field would put it in the traversal the learner finished.
      final material = ArpeggioMaterial('C', ArpeggioQuality.major);
      final task = AcquisitionScaffold.unmeteredRepetitions(2).taskFor(
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
          direction: ExerciseDirection.up,
          tempoBpm: 60,
          guidance: GuidanceContext.continuouslyCued,
        ),
      );
      final wanted = [
        for (final moment in realizeAcquisition(task).moments)
          moment.noteFor(Hand.right)!.midiNote,
      ];
      final played = [...wanted]..removeAt(2);
      var transcript = PerformanceTranscript.empty;
      for (final (index, midiNote) in played.indexed) {
        transcript = transcript.appending(
          pitch: spellObservedPitch(midiNote, material: material),
          timestampMs: index * 600,
          performanceTimeUs: index * 600 * 1000,
        );
      }
      AcquisitionAttemptRecord closedWith(AttemptTermination termination) =>
          acquisitionRecordOf(
            observation: observeAcquisition(task: task, transcript: transcript),
            identity: AttemptIdentity(
              profileId: 'abc12345',
              attemptId: 'acq-0',
              sessionId: 'sitting-1',
              indexInSession: 0,
              occurredAt: DateTime.utc(2026, 9, 9),
            ),
            journalSequence: 0,
            termination: termination,
          );

      final stopped = closedWith(AttemptTermination.learnerStopped);
      expect(stopped.completion, AcquisitionCompletion.notCompleted);
      expect(
        stopped.firstAbsentPosition,
        lessThan(realize(stopped.parent).moments.length),
        reason: 'the omission is inside the first traversal',
      );
      expect(
        acquisitionOutcomeLine(stopped),
        'You stopped before completing the arpeggio.',
      );
      expect(
        acquisitionOutcomeLine(closedWith(AttemptTermination.inputInterrupted)),
        'The connection was interrupted before the arpeggio was fully '
        'recorded.',
      );
      for (final record in [
        stopped,
        closedWith(AttemptTermination.inputInterrupted),
      ]) {
        expect(
          acquisitionOutcomeLine(record),
          isNot(anyOf(contains('first'), contains('second'))),
          reason: 'no field says which traversal the playing ended in',
        );
      }
    });

    test('never claims a traversal that positions alone cannot establish', () {
      // Built through measurement rather than by supplying the fields, so the
      // test cannot encode the same mistaken assumption the copy did. The
      // first note is something else and the playing stops in the second
      // traversal: positions past the boundary are covered, and no traversal
      // was produced.
      final material = ArpeggioMaterial('C', ArpeggioQuality.major);
      final task = AcquisitionScaffold.unmeteredRepetitions(2).taskFor(
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
          direction: ExerciseDirection.up,
          tempoBpm: 60,
          guidance: GuidanceContext.continuouslyCued,
        ),
      );
      final wanted = [
        for (final moment in realizeAcquisition(task).moments)
          moment.noteFor(Hand.right)!.midiNote,
      ];
      var transcript = PerformanceTranscript.empty;
      for (final (index, midiNote) in [
        wanted.first + 1,
        ...wanted.sublist(1, 5),
      ].indexed) {
        transcript = transcript.appending(
          pitch: spellObservedPitch(midiNote, material: material),
          timestampMs: index * 600,
          performanceTimeUs: index * 600 * 1000,
        );
      }
      final record = acquisitionRecordOf(
        observation: observeAcquisition(task: task, transcript: transcript),
        identity: AttemptIdentity(
          profileId: 'abc12345',
          attemptId: 'acq-0',
          sessionId: 'sitting-1',
          indexInSession: 0,
          occurredAt: DateTime.utc(2026, 9, 9),
        ),
        journalSequence: 0,
      );

      expect(record.completion, AcquisitionCompletion.notCompleted);
      expect(record.firstAbsentPosition, 5);
      expect(
        acquisitionOutcomeLine(record),
        'You stopped before completing the arpeggio.',
      );
      expect(
        acquisitionOutcomeLine(record),
        isNot(contains('1 of 2')),
        reason: 'a covered position is not a produced traversal',
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
