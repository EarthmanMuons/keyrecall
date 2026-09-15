import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/practice/cue_semantics.dart';
import 'package:keyrecall/features/practice/presentation_policy.dart';

void main() {
  Exercise exerciseUnder(
    GuidanceContext guidance, {
    HandConfiguration hands = HandConfiguration.right,
  }) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: hands,
    octaves: 1,
    direction: ExerciseDirection.up,
    guidance: guidance,
  );

  String? spokenFor(
    GuidanceContext guidance, {
    required bool showsCue,
    HandConfiguration hands = HandConfiguration.right,
  }) {
    final exercise = exerciseUnder(guidance, hands: hands);
    return cueSemantics(
      exercise: exercise,
      presentation: presentationFor(guidance, exercise: exercise),
      showsCue: showsCue,
    );
  }

  group('the cue in words', () {
    test('says the same notes the staff and the keys do', () {
      final spoken = spokenFor(
        GuidanceContext.continuouslyCued,
        showsCue: true,
      )!;

      expect(spoken, startsWith('C major, right hand, up, 1 octave, 8 notes.'));
      for (final note in ['C', 'D', 'E', 'F', 'G', 'A', 'B']) {
        expect(spoken, contains(note));
      }
    });

    test('names a finger only where the motor channel is open', () {
      final exercise = exerciseUnder(GuidanceContext.continuouslyCued);
      final cued = presentationFor(exercise.guidance, exercise: exercise);

      expect(cued.motorCue, MotorCue.fingering);
      expect(
        cueSemantics(exercise: exercise, presentation: cued, showsCue: true),
        contains('finger 1'),
      );
      expect(
        cueSemantics(
          exercise: exercise,
          presentation: PresentationConditions(
            pitchCue: cued.pitchCue,
            cueModality: cued.cueModality,
            motorCue: MotorCue.none,
            performanceFeedback: cued.performanceFeedback,
            tempoSupport: cued.tempoSupport,
          ),
          showsCue: true,
        ),
        isNot(contains('finger')),
      );
    });

    test('separates the two hands', () {
      final spoken = spokenFor(
        GuidanceContext.continuouslyCued,
        showsCue: true,
        hands: HandConfiguration.together,
      )!;

      expect(spoken, contains('Right hand:'));
      expect(spoken, contains('Left hand:'));
    });

    test('is absent wherever the cue is withdrawn', () {
      expect(
        spokenFor(GuidanceContext.notesPreviewedOnly, showsCue: false),
        isNull,
        reason:
            'the words withdraw when the cue does, or the previewed rung '
            'would supply the material throughout for a screen-reader user',
      );
      expect(spokenFor(GuidanceContext.unguided, showsCue: true), isNull);
    });
  });

  group('the echo in words', () {
    final cued = presentationFor(GuidanceContext.continuouslyCued);

    PerformanceTranscript playing(List<String> labels) {
      var transcript = PerformanceTranscript.empty;
      for (final (index, label) in labels.indexed) {
        transcript = transcript.appending(
          pitch: SpelledPitch(letter: NoteLetter.fromLabel(label), octave: 4),
          timestampMs: index * 500,
        );
      }
      return transcript;
    }

    test('reads back arrivals and places none of them', () {
      expect(
        echoSemantics(transcript: playing(['C', 'D', 'F']), presentation: cued),
        'Played so far: C, D, F.',
      );
    });

    test('says nothing about a staff nothing has been played into', () {
      expect(
        echoSemantics(
          transcript: PerformanceTranscript.empty,
          presentation: cued,
        ),
        isNull,
        reason:
            'the reserved slots hold width, and describing one would say '
            'the learner rested',
      );
    });

    test('is absent where the learner is shown nothing of their playing', () {
      expect(
        echoSemantics(
          transcript: playing(['C']),
          presentation: PresentationConditions(
            pitchCue: PitchCue.none,
            motorCue: MotorCue.none,
            performanceFeedback: PerformanceFeedback.none,
            tempoSupport: TempoSupport.countInOnly,
          ),
        ),
        isNull,
      );
    });
  });
}
