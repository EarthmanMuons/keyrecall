import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

/// When the screen may decide an attempt is over without being told.
void main() {
  Exercise exerciseOf({
    ScaleDirection direction = ScaleDirection.up,
    int octaves = 1,
  }) => Exercise.linear(
    material: TechnicalMaterial('D', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: octaves,
    direction: direction,
  );

  List<int> expectedOf(Exercise exercise) => [
    for (final moment in realize(exercise).moments)
      moment.notes.single.midiNote,
  ];

  PerformanceTranscript played(Exercise exercise, List<int> notes) {
    var transcript = PerformanceTranscript.empty;
    for (final (index, note) in notes.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(note, material: exercise.material),
        timestampMs: index * 500,
      );
    }
    return transcript;
  }

  test('a whole traversal ends it', () {
    for (final direction in ScaleDirection.values) {
      final exercise = exerciseOf(direction: direction);
      expect(
        hasCoveredTraversal(
          exercise: exercise,
          transcript: played(exercise, expectedOf(exercise)),
        ),
        isTrue,
        reason: direction.id,
      );
    }
  });

  test('no single note ends it, whatever it is', () {
    for (final direction in ScaleDirection.values) {
      for (final octaves in [1, 2]) {
        final exercise = exerciseOf(direction: direction, octaves: octaves);
        final expected = expectedOf(exercise);
        for (
          var note = expected.first - 24;
          note <= expected.last + 24;
          note++
        ) {
          expect(
            hasCoveredTraversal(
              exercise: exercise,
              transcript: played(exercise, [note]),
            ),
            isFalse,
            reason:
                'playing $note once is the cheapest explanation of reaching '
                'the end of ${direction.id} x$octaves, and is not somebody '
                'finishing',
          );
        }
      }
    }
  });

  group('where progress stops being separable from correctness', () {
    // A traversal's worth of notes always accounts for every position, because
    // substituting costs less than dropping one note and adding another. So
    // once that many notes have arrived, no criterion can tell "played it
    // badly" from "played something else" without reading whether the notes
    // were right, which no rung permits. These tests pin that boundary rather
    // than pretend it is elsewhere.

    test('a traversal-length run of one repeated note ends it', () {
      final exercise = exerciseOf();
      final expected = expectedOf(exercise);

      expect(
        hasCoveredTraversal(
          exercise: exercise,
          transcript: played(
            exercise,
            List.filled(expected.length, expected.last),
          ),
        ),
        isTrue,
        reason:
            'every position is accounted for and the learner has stopped '
            'playing; refusing here would be a verdict on the notes',
      );
    });

    test('a traversal-length run of unrelated notes ends it', () {
      final exercise = exerciseOf();
      final expected = expectedOf(exercise);

      expect(
        hasCoveredTraversal(
          exercise: exercise,
          transcript: played(exercise, [
            for (var i = 0; i < expected.length; i++)
              expected.first - 24 + (i % 5),
          ]),
        ),
        isTrue,
      );
    });

    test('nothing shorter ends it, whatever was played', () {
      // The guarantee that does hold, and the one the bug broke. Every
      // transcript shorter than the traversal, over every direction and octave
      // count, including the ones that reach the final position.
      for (final direction in ScaleDirection.values) {
        for (final octaves in [1, 2]) {
          final exercise = exerciseOf(direction: direction, octaves: octaves);
          final expected = expectedOf(exercise);

          for (var length = 0; length < expected.length; length++) {
            for (final notes in [
              // The end of the traversal, which is what the aligner will
              // happily explain as having arrived at the end.
              expected.sublist(expected.length - length),
              expected.sublist(0, length),
              List.filled(length, expected.last),
            ]) {
              expect(
                hasCoveredTraversal(
                  exercise: exercise,
                  transcript: played(exercise, notes),
                ),
                isFalse,
                reason:
                    '$length of ${expected.length} notes ended '
                    '${direction.id} x$octaves',
              );
            }
          }
        }
      }
    });
  });

  test('stopping short does not end it', () {
    final exercise = exerciseOf();
    final expected = expectedOf(exercise);

    expect(
      hasCoveredTraversal(
        exercise: exercise,
        transcript: played(exercise, expected.sublist(0, expected.length - 1)),
      ),
      isFalse,
    );
  });

  test('a wrong note covers its position like a right one', () {
    final exercise = exerciseOf();
    final expected = [...expectedOf(exercise)];
    expected[3] = expected[3] + 1;

    expect(
      hasCoveredTraversal(
        exercise: exercise,
        transcript: played(exercise, expected),
      ),
      isTrue,
      reason: 'coverage is progress, not correctness',
    );
  });

  test('a corrected attempt still ends when it reaches the end', () {
    final exercise = exerciseOf();
    final expected = expectedOf(exercise);
    // One fumbled note, played again correctly, then the rest.
    final withRepair = [expected.first + 1, ...expected];

    expect(
      hasCoveredTraversal(
        exercise: exercise,
        transcript: played(exercise, withRepair),
      ),
      isTrue,
    );
  });
}
