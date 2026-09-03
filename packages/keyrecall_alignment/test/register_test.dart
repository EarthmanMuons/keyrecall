import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

/// Which register a scale is played in.
///
/// The realization anchors it so a staff can draw it. That anchor is a drawing
/// decision, not the task: the same fingering, the same intervals, the same
/// shape, wherever on the keyboard it starts.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  bool isPerfect(Alignment alignment) =>
      AlignmentReading(alignment).isComplete &&
      alignment.noteEdits.every((positioned) => positioned.edit is Match);

  group('one hand', () {
    final realization = realize(
      Exercise.linear(
        material: material,
        hands: HandConfiguration.right,
        octaves: 1,
        direction: ExerciseDirection.up,
      ),
    );
    final expected = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.right)!.midiNote,
    ];

    Alignment alignmentOf(List<int> midiNotes) {
      var transcript = PerformanceTranscript.empty;
      for (final (index, midiNote) in midiNotes.indexed) {
        transcript = transcript.appending(
          pitch: pitch(midiNote),
          timestampMs: 1000 + index * 500,
        );
      }
      return align(realization: realization, transcript: transcript);
    }

    test('at the register the staff drew it', () {
      expect(isPerfect(alignmentOf(expected)), isTrue);
    });

    for (final octaves in [-2, -1, 1]) {
      test('$octaves octaves from it is the same scale', () {
        expect(
          isPerfect(alignmentOf([for (final n in expected) n + octaves * 12])),
          isTrue,
        );
      });
    }

    test('one note in the wrong octave is still a register substitution', () {
      // No shift of everything explains this one, which is what separates a
      // learner starting somewhere else from a learner slipping.
      final wrong = [...expected]..[3] -= 12;
      final kinds = [
        for (final positioned in alignmentOf(wrong).noteEdits)
          if (positioned.edit case Substitution(:final kind)) kind,
      ];

      expect(kinds, [SubstitutionKind.register]);
    });
  });

  group('hands together', () {
    RealizationMoment moment(int position, int left, int right) =>
        RealizationMoment(
          position: position,
          metricOffset: position.toDouble(),
          notes: [
            RealizedNote(hand: Hand.left, pitch: pitch(left)),
            RealizedNote(hand: Hand.right, pitch: pitch(right)),
          ],
        );

    // Two moments of C major, an octave apart, as V1 places the hands.
    final realization = ExerciseRealization([
      moment(0, 48, 60),
      moment(1, 50, 62),
      moment(2, 52, 64),
    ]);

    Alignment alignmentOf(List<int> midiNotes) {
      var transcript = PerformanceTranscript.empty;
      for (final (index, midiNote) in midiNotes.indexed) {
        transcript = transcript.appending(
          pitch: pitch(midiNote),
          timestampMs: 1000 + (index ~/ 2) * 500,
        );
      }
      return align(realization: realization, transcript: transcript);
    }

    test('both hands moved together is the same exercise', () {
      expect(
        isPerfect(alignmentOf([60, 72, 62, 74, 64, 76])),
        isTrue,
        reason: 'the octave between the hands is preserved',
      );
    });

    test('hands moved apart is not', () {
      // The distance between the hands is the task; where the pair sits is
      // not. Normalizing each hand on its own would call this correct.
      expect(isPerfect(alignmentOf([36, 72, 38, 74, 40, 76])), isFalse);
    });
  });
}
