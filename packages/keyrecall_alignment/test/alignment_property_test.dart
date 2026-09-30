import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

final List<TechnicalMaterial> materials = [
  ...allScales,
  for (final arpeggio in allRootPositionArpeggios)
    for (final inversion in ArpeggioInversion.values)
      ArpeggioMaterial(arpeggio.tonic, arpeggio.quality, inversion: inversion),
];

/// Any exercise, or one played by a single hand, where every moment is one
/// note and an edit has only one place to land.
Arbitrary<Exercise> exercises({bool singleHand = false}) =>
    combine5(
      choiceOf(materials),
      choiceOf(
        singleHand
            ? [HandConfiguration.left, HandConfiguration.right]
            : HandConfiguration.values,
      ),
      choiceOf([1, 2]),
      choiceOf(ExerciseDirection.values),
      choiceOf(HandMotion.values),
    ).map((parts) {
      final (material, hands, octaves, direction, motion) = parts;
      return Exercise.linear(
        material: material,
        hands: hands,
        octaves: octaves,
        direction: direction,
        handMotion: hands == HandConfiguration.together
            ? motion
            : HandMotion.parallel,
      );
    });

/// One key pressed: which, and when.
typedef Press = ({int midiNote, int timestampMs});

/// What was asked for, played exactly: moments 400 ms apart, and the notes of
/// one moment 5 ms apart, the way two hands land together.
List<Press> cleanlyPlayed(ExerciseRealization realization) => [
  for (final moment in realization.moments)
    for (final (index, note) in moment.notes.indexed)
      (
        midiNote: note.midiNote,
        timestampMs: 1000 + moment.position * 400 + 5 * index,
      ),
];

PerformanceTranscript transcriptOf(List<Press> presses, Exercise exercise) {
  var transcript = PerformanceTranscript.empty;
  for (final press in presses) {
    transcript = transcript.appending(
      pitch: spellObservedPitch(press.midiNote, material: exercise.material),
      timestampMs: press.timestampMs,
    );
  }
  return transcript;
}

/// [presses] moved by [octaves], or unmoved where that would leave the
/// keyboard.
List<Press> transposed(List<Press> presses, int octaves) =>
    presses.every(
      (press) =>
          press.midiNote + 12 * octaves >= 0 &&
          press.midiNote + 12 * octaves <= 127,
    )
    ? [
        for (final press in presses)
          (
            midiNote: press.midiNote + 12 * octaves,
            timestampMs: press.timestampMs,
          ),
      ]
    : presses;

/// One way a performance departs from what was asked: a note dropped, one
/// added, or one played an octave away.
typedef Slip = (int, double, int);

/// [presses] with [slips] applied in order. Each slip lands at a fraction of
/// the way through the performance, and an added note arrives with the one
/// before it.
List<Press> slipped(List<Press> presses, List<Slip> slips) {
  final result = [...presses];
  for (final (kind, at, value) in slips) {
    if (result.isEmpty && kind != 1) continue;
    final index = (at * result.length).floor().clamp(0, result.length);
    switch (kind) {
      case 0 when index < result.length:
        result.removeAt(index);
      case 1:
        result.insert(index, (
          midiNote: value,
          timestampMs: index == 0 ? 1000 : result[index - 1].timestampMs,
        ));
      case 2 when index < result.length:
        final press = result[index];
        final moved = press.midiNote + (value.isEven ? 12 : -12);
        if (moved >= 0 && moved <= 127) {
          result[index] = (midiNote: moved, timestampMs: press.timestampMs);
        }
    }
  }
  return result;
}

final Arbitrary<Slip> anySlip = combine3(
  integer(min: 0, max: 2),
  float(min: 0, max: 1),
  integer(min: 21, max: 108),
);

/// The expected note [edit] speaks for, at [position] of [realization].
RealizedNote expectedOf(
  ExerciseRealization realization,
  int position,
  Set<Hand> hands,
) => realization.moments[position].notes.firstWhere(
  (note) => note.hands.length == hands.length && note.hands.containsAll(hands),
);

String shapeOf(NoteEdit edit) => switch (edit) {
  Match() => 'match',
  Substitution(:final kind) => 'substitution ${kind.id.toLowerCase()}',
  Insertion() => 'insertion',
  Deletion() => 'deletion',
};

/// The contract [align] states, checked of one alignment.
void checkContract(
  Alignment alignment,
  ExerciseRealization realization,
  PerformanceTranscript transcript,
) {
  final edits = alignment.noteEdits;

  // Every played note appears exactly once, in the order it arrived.
  expect(
    [for (final positioned in edits) ?positioned.edit.observedSequence],
    [for (var i = 0; i < transcript.length; i++) i],
    reason: 'every played note once, in arrival order',
  );

  // Every expected note appears exactly once, moment by moment in order. An
  // extra note grouped into a moment belongs to it but speaks for none.
  final expected = [
    for (final (:realizationPosition, :edit) in edits)
      if ((realizationPosition, edit) case (
        final position?,
        Match(:final hands) ||
            Substitution(:final hands) ||
            Deletion(:final hands),
      ))
        (position, hands),
  ];
  expect(
    [
      for (final (position, hands) in expected)
        '$position ${hands.map((h) => h.id).toSet()}',
    ]..sort(),
    [
      for (final moment in realization.moments)
        for (final note in moment.notes)
          '${moment.position} ${note.hands.map((h) => h.id).toSet()}',
    ]..sort(),
    reason: 'every expected note once',
  );
  final positions = [
    for (final operation in alignment.operations)
      ?operation.realizationPosition,
  ];
  expect(positions, [...positions]..sort(), reason: 'moments in order');

  // What an edit says was played is what was played, and every match reads
  // the realization at one octave shift.
  final shifts = <int>{};
  for (final (:realizationPosition, :edit) in edits) {
    final played = switch (edit.observedSequence) {
      final sequence? => transcript.notes[sequence],
      null => null,
    };
    switch (edit) {
      case Match(:final hands):
        final note = expectedOf(realization, realizationPosition!, hands);
        final difference = played!.midiNote - note.midiNote;
        expect(difference % 12, 0, reason: 'a match is the note asked for');
        shifts.add(difference);
      case Substitution(:final observed):
        expect(observed, played!.pitch);
      case Insertion(:final observed):
        expect(observed, played!.pitch);
      case Deletion():
        break;
    }
  }
  expect(shifts.length, lessThanOrEqualTo(1), reason: 'one register for all');
}

void main() {
  property('any performance is explained completely and in order', () {
    forAll(
      combine3(
        exercises(),
        choiceOf([0, 0, 0, -1, 1, -2, 2]),
        list(anySlip, maxLength: 6),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<(Exercise, int, List<Slip>)>((parts) {
        final (exercise, octaves, slips) = parts;
        final realization = realize(exercise);
        final transcript = transcriptOf(
          slipped(transposed(cleanlyPlayed(realization), octaves), slips),
          exercise,
        );
        final alignment = align(
          realization: realization,
          transcript: transcript,
        );

        checkContract(alignment, realization, transcript);
        expect(
          align(realization: realization, transcript: transcript),
          alignment,
          reason: 'one performance always aligns the same way',
        );
      }),
    );
  });

  property('what was asked for, in any register, is every note matched', () {
    forAll(
      combine2(exercises(), choiceOf([0, -1, 1, -2, 2])),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<(Exercise, int)>((parts) {
        final (exercise, octaves) = parts;
        final realization = realize(exercise);
        final alignment = align(
          realization: realization,
          transcript: transcriptOf(
            transposed(cleanlyPlayed(realization), octaves),
            exercise,
          ),
        );

        expect(alignment.noteEdits.map((p) => shapeOf(p.edit)).toSet(), {
          'match',
        });
        // Timing can only lower the cost of notes that arrived together, and
        // the register they were played in cannot move it.
        expect(alignment.cost, lessThanOrEqualTo(0));
        expect(
          alignment.cost,
          align(
            realization: realization,
            transcript: transcriptOf(cleanlyPlayed(realization), exercise),
          ).cost,
        );
      }),
    );
  });

  property('one note an octave away is a register slip, not a match', () {
    forAll(
      combine3(exercises(singleHand: true), float(min: 0, max: 1), boolean()),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<(Exercise, double, bool)>((parts) {
        final (exercise, at, up) = parts;
        final realization = realize(exercise);
        final clean = cleanlyPlayed(realization);
        final index = (at * clean.length).floor().clamp(0, clean.length - 1);
        final moved = clean[index].midiNote + (up ? 12 : -12);
        if (moved < 0 || moved > 127) return;
        final presses = [...clean]
          ..[index] = (midiNote: moved, timestampMs: clean[index].timestampMs);
        final alignment = align(
          realization: realization,
          transcript: transcriptOf(presses, exercise),
        );

        final departures = [
          for (final positioned in alignment.noteEdits)
            if (positioned.edit is! Match) positioned.edit,
        ];
        expect(departures, hasLength(1));
        expect(shapeOf(departures.single), 'substitution register');
        expect(departures.single.observedSequence, index);
        expect(alignment.cost, AlignmentPolicy.standard.substitutionCost);
      }),
    );
  });

  property('one note missing is a deletion of that note, and nothing else', () {
    forAll(
      combine2(exercises(singleHand: true), float(min: 0, max: 1)),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<(Exercise, double)>((parts) {
        final (exercise, at) = parts;
        final realization = realize(exercise);
        final clean = cleanlyPlayed(realization);
        final index = (at * clean.length).floor().clamp(0, clean.length - 1);
        final alignment = align(
          realization: realization,
          transcript: transcriptOf([...clean]..removeAt(index), exercise),
        );

        final departures = [
          for (final positioned in alignment.noteEdits)
            if (positioned.edit is! Match) positioned,
        ];
        expect(departures, hasLength(1));
        final (:realizationPosition, :edit) = departures.single;
        expect(edit, isA<Deletion>());
        expect(
          (edit as Deletion).expected.midiNote,
          clean[index].midiNote,
          reason: 'the note that was not played is the one missing',
        );
        expect(
          clean[realizationPosition!].midiNote,
          clean[index].midiNote,
          reason: 'it is missing where it was asked for, or at a repeat of it',
        );
        expect(alignment.cost, AlignmentPolicy.standard.deletionCost);
      }),
    );
  });

  property('an unrelated extra note is an insertion, and nothing else', () {
    forAll(
      combine3(
        exercises(singleHand: true),
        float(min: 0, max: 1),
        integer(min: 0, max: 11),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<(Exercise, double, int)>((parts) {
        final (exercise, at, pick) = parts;
        final realization = realize(exercise);
        final asked = {
          for (final moment in realization.moments)
            for (final note in moment.notes) note.midiNote % 12,
        };
        final foreign = [
          for (var pitchClass = 0; pitchClass < 12; pitchClass++)
            if (!asked.contains(pitchClass)) pitchClass,
        ];
        if (foreign.isEmpty) return;
        final clean = cleanlyPlayed(realization);
        final index = (at * (clean.length + 1)).floor().clamp(0, clean.length);
        final near = clean[index.clamp(0, clean.length - 1)].midiNote;
        final extra = near - near % 12 + foreign[pick % foreign.length];
        final presses = [...clean]
          ..insert(index, (
            midiNote: extra,
            timestampMs: index == 0 ? 1000 : clean[index - 1].timestampMs,
          ));
        final alignment = align(
          realization: realization,
          transcript: transcriptOf(presses, exercise),
        );

        final departures = [
          for (final positioned in alignment.noteEdits)
            if (positioned.edit is! Match) positioned.edit,
        ];
        expect(departures, hasLength(1));
        expect(departures.single, isA<Insertion>());
        expect(departures.single.observedSequence, index);
        expect(alignment.cost, AlignmentPolicy.standard.insertionCost);
      }),
    );
  });
}
