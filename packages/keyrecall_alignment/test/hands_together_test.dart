import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

import 'support/recorded_takes.dart';

/// Aligning material both hands play.
///
/// The corpus is the recorded takes, so the grouping the search has to choose
/// is the one real playing produced rather than one written to be chosen.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  RealizationMoment moment(int position, int left, int right) =>
      RealizationMoment(
        position: position,
        metricOffset: position.toDouble(),
        notes: [
          RealizedNote(hand: Hand.left, pitch: pitch(left)),
          RealizedNote(hand: Hand.right, pitch: pitch(right)),
        ],
      );

  PerformanceTranscript played(List<(int, int)> arrivals) {
    var transcript = PerformanceTranscript.empty;
    for (final (midiNote, timestampMs) in arrivals) {
      transcript = transcript.appending(
        pitch: pitch(midiNote),
        timestampMs: timestampMs,
      );
    }
    return transcript;
  }

  /// Which operation of [alignment] consumed each observation.
  Map<int, int> operationBySequence(Alignment alignment) => {
    for (final (index, operation) in alignment.operations.indexed)
      for (final sequence in operation.observedSequences) sequence: index,
  };

  group('a performance of both hands', () {
    test('comfortable playing is every moment matched in both hands', () {
      final alignment = align(
        realization: realizationOf('comfortable-c-major'),
        transcript: transcriptOf('comfortable-c-major'),
      );
      final reading = AlignmentReading(alignment);

      expect(alignment.operations, everyElement(isA<MomentCorrespondence>()));
      expect(alignment.operations.length, 15);
      expect(reading.matched, 30);
      expect(reading.isFirstPassClean, isTrue);
      expect(reading.isComplete, isTrue);
    });

    test('which hand arrived first is not which hand played', () {
      final alignment = align(
        realization: realizationOf('comfortable-c-major'),
        transcript: transcriptOf('comfortable-c-major'),
      );
      final leadingHand = [
        for (final operation in alignment.operations)
          (operation.noteEdits.first as Match).hand,
      ];

      expect(
        leadingHand.toSet(),
        {Hand.left, Hand.right},
        reason:
            'the hands led in different orders across the take, and every '
            'note still matched',
      );
    });

    test('crossed arrivals take their hand from what they correspond to', () {
      final alignment = align(
        realization: ExerciseRealization([moment(0, 48, 60)]),
        transcript: played([(60, 0), (48, 5)]),
      );

      expect(alignment.operations.single.noteEdits, [
        Match(hand: Hand.right, observedSequence: 0),
        Match(hand: Hand.left, observedSequence: 1),
      ]);
    });

    test('a moment nothing arrived for is missing every note it asked for', () {
      final alignment = align(
        realization: ExerciseRealization([
          moment(0, 48, 60),
          moment(1, 50, 62),
        ]),
        transcript: played([(48, 0), (60, 5)]),
      );

      expect(alignment.operations.last, isA<MomentDeletion>());
      expect(AlignmentReading(alignment).deleted, 2);
      expect(AlignmentReading(alignment).isComplete, isFalse);
    });
  });

  group('when a moment happened', () {
    final realization = ExerciseRealization([
      moment(0, 48, 60),
      moment(1, 50, 62),
    ]);

    MomentCorrespondence firstMomentOf(PerformanceTranscript transcript) =>
        align(realization: realization, transcript: transcript).operations.first
            as MomentCorrespondence;

    test('a moment happens between its hands', () {
      final correspondence = firstMomentOf(
        played([(48, 1000), (60, 1020), (50, 1500), (62, 1540)]),
      );

      expect(correspondence.onsetMs, 1010);
      expect(correspondence.handAsynchronyMs, 20);
    });

    test('which hand arrived first does not move the moment', () {
      final correspondence = firstMomentOf(
        played([(60, 1000), (48, 1020), (50, 1500), (62, 1540)]),
      );

      expect(correspondence.onsetMs, 1010);
      expect(
        correspondence.handAsynchronyMs,
        -20,
        reason:
            'the sign says which hand led and the magnitude says how far '
            'apart they were',
      );
    });

    test('a wrong pitch still says when that hand acted', () {
      final correspondence = firstMomentOf(
        played([(48, 1000), (61, 1020), (50, 1500), (62, 1540)]),
      );

      expect(correspondence.noteEdits.last, isA<Substitution>());
      expect(correspondence.handAsynchronyMs, 20);
    });

    test('a hand that played nothing leaves no asynchrony at all', () {
      final correspondence = firstMomentOf(
        played([(48, 1000), (50, 1500), (62, 1540)]),
      );

      expect(correspondence.noteEdits.last, isA<Deletion>());
      expect(correspondence.onsetMs, 1000);
      expect(
        correspondence.handAsynchronyMs,
        isNull,
        reason: 'absent, not zero: nothing was measured',
      );
    });
  });

  group('the grouping the search chooses', () {
    test('timing that says one moment can still be split', () {
      final transcript = transcriptOf('deliberate-rolled-c-major');
      final alignment = align(
        realization: realizationOf('deliberate-rolled-c-major'),
        transcript: transcript,
      );
      final operations = operationBySequence(alignment);

      final overruled = [
        for (final boundary in groupObservations(
          transcript: transcript,
        ).boundaries)
          if (boundary.lean == BoundaryLean.sameMoment &&
              operations[boundary.beforeSequence] !=
                  operations[boundary.afterSequence])
            boundary,
      ];

      expect(overruled, isNotEmpty);
      expect(
        overruled.map((boundary) => boundary.gapMs),
        contains(0),
        reason:
            'two arrivals in the same millisecond, and correspondence '
            'still explains them as separate moments',
      );
    });

    test('timing that says two moments can still be grouped', () {
      final transcript = transcriptOf('hands-out-of-phase-c-major');
      final alignment = align(
        realization: realizationOf('hands-out-of-phase-c-major'),
        transcript: transcript,
      );
      final operations = operationBySequence(alignment);

      final overruled = [
        for (final boundary in groupObservations(
          transcript: transcript,
        ).boundaries)
          if (boundary.lean == BoundaryLean.separateMoments &&
              operations[boundary.beforeSequence] ==
                  operations[boundary.afterSequence])
            boundary,
      ];

      expect(overruled, isNotEmpty);
      expect(
        overruled.map((boundary) => boundary.gapMs).reduce(math.max),
        greaterThan(300),
        reason:
            'notes a third of a second apart belong to one moment when '
            'that is the cheaper explanation of the whole performance',
      );
    });

    test('every boundary is charged once, and only inside a run', () {
      final realization = ExerciseRealization([
        moment(0, 48, 60),
        moment(1, 50, 62),
      ]);

      // Two boundaries inside runs, one between them. Every note matches, so
      // the cost is the grouping surcharge and nothing else.
      final grouped = align(
        realization: realization,
        transcript: played([(48, 0), (60, 0), (50, 1000), (62, 1000)]),
      );
      expect(grouped.cost, -2 * AlignmentPolicy.standard.maxGroupingPreference);

      // The same correspondence, with all three boundaries wide. Charging the
      // boundary between the moments would make this three surcharges.
      final spread = align(
        realization: realization,
        transcript: played([(48, 0), (60, 500), (50, 1000), (62, 1500)]),
      );
      expect(spread.cost, 2 * AlignmentPolicy.standard.maxGroupingPreference);
      expect(spread.operations, everyElement(isA<MomentCorrespondence>()));
    });
  });

  group('what breaks a tie', () {
    /// A policy that prices a wrong note the same as a missing one plus an
    /// extra, so the two readings of the second arrival cost the same.
    const evenly = AlignmentPolicy(
      substitutionCost: 6,
      maxGroupingPreference: 0,
    );

    test('an extra stands rather than being absorbed into a moment', () {
      final alignment = align(
        realization: ExerciseRealization([moment(0, 48, 60)]),
        transcript: played([(48, 0), (61, 5)]),
        policy: evenly,
      );

      expect(alignment.operations.map((operation) => operation.runtimeType), [
        MomentCorrespondence,
        MomentInsertion,
      ]);
      expect(alignment.operations.first.observedSequences, [0]);
    });

    test('one performance always aligns the same way', () {
      for (final take in recordedTakes.keys) {
        final once = align(
          realization: realizationOf(take),
          transcript: transcriptOf(take),
        );
        final again = align(
          realization: realizationOf(take),
          transcript: transcriptOf(take),
        );

        expect(once.operations, again.operations, reason: take);
      }
    });

    test('equally wrong notes inside a moment resolve the same way', () {
      // Neither arrival is either expected note, so every assignment costs two
      // substitutions and the enumeration order is what decides.
      final alignment = align(
        realization: ExerciseRealization([moment(0, 48, 60)]),
        transcript: played([(51, 0), (63, 5)]),
      );

      expect(alignment.operations.single.noteEdits, [
        isA<Substitution>().having((s) => s.hand, 'hand', Hand.left),
        isA<Substitution>().having((s) => s.hand, 'hand', Hand.right),
      ]);
    });
  });
}
