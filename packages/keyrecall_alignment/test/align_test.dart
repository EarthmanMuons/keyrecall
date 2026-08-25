import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  /// One octave of C major, right hand, ascending: C4 to C5.
  final realization = realize(
    Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ScaleDirection.up,
    ),
  );
  final expected = [
    for (final moment in realization.moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];

  PerformanceTranscript played(List<int> midiNotes) {
    var transcript = PerformanceTranscript.empty;
    for (final (index, midiNote) in midiNotes.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: 1000 + index * 500,
      );
    }
    return transcript;
  }

  Alignment alignmentOf(List<int> midiNotes) =>
      align(realization: realization, transcript: played(midiNotes));

  List<String> shapeOf(Alignment alignment) => [
    for (final operation in alignment.operations)
      switch (operation) {
        Match() => 'match',
        Substitution(:final kind) => 'substitution.${kind.id.toLowerCase()}',
        Insertion() => 'insertion',
        Deletion() => 'deletion',
      },
  ];

  group('a performance with nothing wrong', () {
    test('is all matches, and costs nothing', () {
      final alignment = alignmentOf(expected);
      expect(AlignmentReading(alignment).firstDeparture, isNull);

      expect(shapeOf(alignment), List.filled(expected.length, 'match'));
      expect(alignment.cost, 0);
      expect(AlignmentReading(alignment).isFirstPassClean, isTrue);
      expect(AlignmentReading(alignment).isComplete, isTrue);
    });

    test('nothing played at all is every note missing', () {
      final alignment = alignmentOf(const []);

      expect(shapeOf(alignment), List.filled(expected.length, 'deletion'));
      expect(AlignmentReading(alignment).isComplete, isFalse);
      expect(
        AlignmentReading(alignment).firstDeparture,
        const AtExpectedPosition(0),
      );
    });
  });

  group('one thing wrong', () {
    test(
      'a wrong note in place is a substitution, not a skip and an extra',
      () {
        // E natural replaced by F: the rest of the scale still lines up.
        final alignment = alignmentOf([...expected]..[2] = 65);

        expect(shapeOf(alignment), [
          'match',
          'match',
          'substitution.pitch',
          'match',
          'match',
          'match',
          'match',
          'match',
        ]);
        expect(AlignmentReading(alignment).isComplete, isTrue);
        expect(AlignmentReading(alignment).isFirstPassClean, isFalse);
        expect(
          AlignmentReading(alignment).firstDeparture,
          const AtExpectedPosition(2),
        );
      },
    );

    test('the right note an octave off is a register substitution', () {
      final alignment = alignmentOf([...expected]..[3] = expected[3] - 12);

      expect(
        alignment.operations[3],
        isA<Substitution>().having(
          (s) => s.kind,
          'kind',
          SubstitutionKind.register,
        ),
      );
    });

    test('a skipped note is one deletion and nothing else', () {
      final alignment = alignmentOf([...expected]..removeAt(4));

      expect(shapeOf(alignment), [
        'match',
        'match',
        'match',
        'match',
        'deletion',
        'match',
        'match',
        'match',
      ]);
      expect(AlignmentReading(alignment).deleted, 1);
      expect(AlignmentReading(alignment).matched, expected.length - 1);
    });

    test('an extra note is one insertion, and the rest stays aligned', () {
      final alignment = alignmentOf([...expected]..insert(3, 61));

      expect(shapeOf(alignment), [
        'match',
        'match',
        'match',
        'insertion',
        'match',
        'match',
        'match',
        'match',
        'match',
      ]);
      expect(
        AlignmentReading(alignment).matched,
        expected.length,
        reason: 'a greedy walk would call the rest of the scale substitutions',
      );
      expect(
        AlignmentReading(alignment).firstDeparture,
        const BeforeExpectedPosition(3),
        reason:
            'the extra note fell between two correctly played ones, and '
            'blaming the note after it would blame a note that was right',
      );
    });

    test('a repeated note is an insertion of what was just played', () {
      final alignment = alignmentOf([...expected]..insert(2, expected[1]));

      expect(AlignmentReading(alignment).inserted, 1);
      expect(AlignmentReading(alignment).matched, expected.length);
    });
  });

  group('correcting a mistake mid-scale', () {
    test('reads as an extra note followed by the right one', () {
      // C D F E F G A B C: the F arrives early, then E is played properly.
      final alignment = alignmentOf([
        expected[0],
        expected[1],
        expected[3],
        ...expected.sublist(2),
      ]);

      expect(shapeOf(alignment), [
        'match',
        'match',
        'insertion',
        'match',
        'match',
        'match',
        'match',
        'match',
        'match',
      ]);
      expect(AlignmentReading(alignment).immediateRepairs, 1);
      expect(
        AlignmentReading(alignment).isComplete,
        isTrue,
        reason: 'the scale was finished, which is not the same as clean',
      );
      expect(AlignmentReading(alignment).isFirstPassClean, isFalse);
    });
  });

  group('resynchronizing', () {
    test('after an early omission, the rest still matches', () {
      final alignment = alignmentOf([...expected]..removeAt(1));

      expect(AlignmentReading(alignment).deleted, 1);
      expect(AlignmentReading(alignment).substituted, 0);
      expect(AlignmentReading(alignment).matched, expected.length - 1);
    });

    test('several separated errors stay separate', () {
      final alignment = alignmentOf(
        [...expected]
          ..[1] = 61
          ..[5] = 61,
      );

      expect(AlignmentReading(alignment).substituted, 2);
      expect(AlignmentReading(alignment).matched, expected.length - 2);
    });

    test('stopping early leaves the rest missing, not wrong', () {
      final alignment = alignmentOf(expected.take(4).toList());

      expect(AlignmentReading(alignment).matched, 4);
      expect(AlignmentReading(alignment).deleted, expected.length - 4);
      expect(AlignmentReading(alignment).substituted, 0);
      expect(
        AlignmentReading(alignment).firstDeparture,
        const AtExpectedPosition(4),
      );
    });

    test('playing on past the end is extra notes, not errors', () {
      final alignment = alignmentOf([...expected, 74, 76]);

      expect(AlignmentReading(alignment).matched, expected.length);
      expect(AlignmentReading(alignment).inserted, 2);
      expect(AlignmentReading(alignment).isComplete, isTrue);
      expect(
        AlignmentReading(alignment).firstDeparture,
        const AfterRealization(),
        reason: 'there is no expected note left for the extras to precede',
      );
    });
  });

  group('the policy decides the reading', () {
    test(
      'a cheaper skip-plus-extra turns a wrong note into two operations',
      () {
        const generous = AlignmentPolicy(
          substitutionCost: 5,
          insertionCost: 1,
          deletionCost: 1,
        );
        expect(generous.prefersSubstitution, isFalse);

        final alignment = align(
          realization: realization,
          transcript: played([...expected]..[2] = 65),
          policy: generous,
        );

        expect(alignment.operations.whereType<Substitution>(), isEmpty);
        expect(alignment.operations.whereType<Insertion>().length, 1);
        expect(alignment.operations.whereType<Deletion>().length, 1);
      },
    );

    test('the standard policy keeps a wrong note in place', () {
      expect(AlignmentPolicy.standard.prefersSubstitution, isTrue);
    });
  });

  group('what alignment refuses', () {
    test('hands-together material, until grouping exists', () {
      final together = realize(
        Exercise.linear(
          material: material,
          hands: HandConfiguration.together,
          octaves: 1,
        ),
      );

      expect(
        () => align(realization: together, transcript: played(expected)),
        throwsArgumentError,
      );
    });
  });

  test('the same performance always aligns the same way', () {
    final once = alignmentOf([...expected]..insert(3, 61));
    final again = alignmentOf([...expected]..insert(3, 61));

    expect(once, again);
    expect(once.operations, again.operations);
  });
}
