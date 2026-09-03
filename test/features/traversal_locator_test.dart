import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/practice/staff_score.dart';
import 'package:keyrecall/features/practice/traversal_locator.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  ExerciseRealization realizationOf({
    HandConfiguration hands = HandConfiguration.right,
    ExerciseDirection direction = ExerciseDirection.up,
  }) => realize(
    Exercise.linear(
      material: material,
      hands: hands,
      octaves: 1,
      direction: direction,
    ),
  );

  PerformanceTranscript playing(List<int> midiNotes) {
    var transcript = PerformanceTranscript.empty;
    for (final (index, midiNote) in midiNotes.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: index * 500,
      );
    }
    return transcript;
  }

  List<int> keysOf(ExerciseRealization realization) => [
    for (final moment in realization.moments)
      for (final note in moment.notes) note.midiNote,
  ];

  test('lights nothing before the traversal has been entered', () {
    final realization = realizationOf();

    expect(
      locatedElementIds(
        realization,
        transcript: PerformanceTranscript.empty,
        pressedNotes: {keysOf(realization).first},
      ),
      isEmpty,
    );
  });

  test('lights the moment that arrived, while its key is held', () {
    final realization = realizationOf();
    final keys = keysOf(realization);
    final transcript = playing(keys.take(3).toList());

    expect(
      locatedElementIds(
        realization,
        transcript: transcript,
        pressedNotes: {keys[2]},
      ),
      {staffElementId(Hand.right, 2)},
    );
    expect(
      locatedElementIds(
        realization,
        transcript: transcript,
        pressedNotes: const {},
      ),
      isEmpty,
      reason: 'a key that came up is not where the learner is',
    );
  });

  test(
    'a note the moment did not ask for lights nothing and moves nothing',
    () {
      final realization = realizationOf();
      final keys = keysOf(realization);
      final wrong = keys[0] + 1;

      expect(
        locatedElementIds(
          realization,
          transcript: playing([keys[0], wrong]),
          pressedNotes: {wrong},
        ),
        isEmpty,
      );
      expect(
        locatedElementIds(
          realization,
          transcript: playing([keys[0], wrong, keys[1]]),
          pressedNotes: {keys[1]},
        ),
        {staffElementId(Hand.right, 1)},
        reason: 'the traversal is still where it was, so the next note lands',
      );
    },
  );

  test('a skipped note costs the locator that note and no more', () {
    final realization = realizationOf();
    final keys = keysOf(realization);

    expect(
      locatedElementIds(
        realization,
        transcript: playing([keys[0], keys[2]]),
        pressedNotes: {keys[2]},
      ),
      {staffElementId(Hand.right, 2)},
    );
    expect(
      locatedElementIds(
        realization,
        transcript: playing([keys[0], keys[2], keys[3]]),
        pressedNotes: {keys[3]},
      ),
      {staffElementId(Hand.right, 3)},
    );
  });

  test('a hand looks no further ahead than the note after next', () {
    final realization = realizationOf();
    final keys = keysOf(realization);

    expect(
      locatedElementIds(
        realization,
        transcript: playing([keys[0], keys[4]]),
        pressedNotes: {keys[4]},
      ),
      isEmpty,
    );
  });

  test('a hand that enters in another octave stays dark for the run', () {
    final realization = realizationOf();
    final keys = keysOf(realization);
    final low = [for (final key in keys) key - 12];

    expect(
      locatedElementIds(
        realization,
        transcript: playing(low.take(3).toList()),
        pressedNotes: {low[2]},
      ),
      isEmpty,
      reason: 'the staff writes the note an octave up, and it is not held',
    );
    expect(
      locatedElementIds(
        realization,
        transcript: playing([...low.take(3), keys[3]]),
        pressedNotes: {keys[3]},
      ),
      isEmpty,
      reason: 'coming back to the written register does not start it mid-run',
    );
  });

  test('the hand in the written register is located, the other is not', () {
    final realization = realizationOf(hands: HandConfiguration.together);
    final left = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.left)!.midiNote,
    ];
    final right = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.right)!.midiNote,
    ];
    final transcript = playing([
      left[0],
      right[0] + 12,
      left[1],
      right[1] + 12,
    ]);

    expect(reachedMoments(realization, transcript), {Hand.left: 1});
    expect(
      locatedElementIds(
        realization,
        transcript: transcript,
        pressedNotes: {left[1], right[1] + 12},
      ),
      {staffElementId(Hand.left, 1)},
    );
  });

  test('a repeated pitch lights the moment reached, not every one of it', () {
    final realization = realizationOf(direction: ExerciseDirection.upDown);
    final keys = keysOf(realization);

    expect(keys.first, keys.last, reason: 'the scale returns to its tonic');
    expect(
      locatedElementIds(
        realization,
        transcript: playing(keys),
        pressedNotes: {keys.last},
      ),
      {staffElementId(Hand.right, realization.moments.length - 1)},
    );
  });

  test('one hand carries on when the other goes wrong', () {
    final realization = realizationOf(hands: HandConfiguration.together);
    final left = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.left)!.midiNote,
    ];
    final right = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.right)!.midiNote,
    ];
    final transcript = playing([
      left[0],
      right[0],
      left[1],
      right[1] + 1,
      left[2],
      right[2],
    ]);

    expect(reachedMoments(realization, transcript), {
      Hand.left: 2,
      Hand.right: 2,
    });
    expect(
      locatedElementIds(
        realization,
        transcript: playing([left[0], right[0], left[1], right[1] + 1]),
        pressedNotes: {left[1], right[1] + 1},
      ),
      {staffElementId(Hand.left, 1)},
      reason: 'the hand that played its note is still lit',
    );
  });

  test('a moment two hands share lights on both staves', () {
    final realization = realize(
      Exercise.linear(
        material: material,
        hands: HandConfiguration.together,
        octaves: 1,
        direction: ExerciseDirection.up,
        handMotion: HandMotion.contrary,
      ),
    );
    final shared = realization.moments.first.notes.single;

    expect(shared.hands, {Hand.left, Hand.right});
    expect(
      locatedElementIds(
        realization,
        transcript: playing([shared.midiNote]),
        pressedNotes: {shared.midiNote},
      ),
      {staffElementId(Hand.left, 0), staffElementId(Hand.right, 0)},
    );
  });
}
