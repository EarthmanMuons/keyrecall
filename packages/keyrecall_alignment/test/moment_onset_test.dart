import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

/// When a moment happened, and on which clock.
///
/// Two rules, and both are about which notes are entitled to answer. Only the
/// notes that took an expected note's place say when the moment was, and among
/// those, the ones the instrument's clock could time say when it was on that
/// clock. Everything else is evidence about something other than timing.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  RealizationMoment twoHands(int position, int left, int right) =>
      RealizationMoment(
        position: position,
        metricOffset: position.toDouble(),
        notes: [
          RealizedNote(hand: Hand.left, pitch: pitch(left)),
          RealizedNote(hand: Hand.right, pitch: pitch(right)),
        ],
      );

  RealizationMoment oneHand(int position, int right) => RealizationMoment(
    position: position,
    metricOffset: position.toDouble(),
    notes: [RealizedNote(hand: Hand.right, pitch: pitch(right))],
  );

  /// A transcript of (note, arrival ms, performance us), the last absent for a
  /// note nothing could time.
  PerformanceTranscript played(List<(int, int, int?)> notes) {
    var transcript = PerformanceTranscript.empty;
    for (final (midiNote, atMs, performanceUs) in notes) {
      transcript = transcript.appending(
        pitch: pitch(midiNote),
        timestampMs: atMs,
        performanceTimeUs: performanceUs,
      );
    }
    return transcript;
  }

  List<MomentCorrespondence> momentsOf(
    ExerciseRealization realization,
    PerformanceTranscript transcript,
  ) => [
    for (final operation in align(
      realization: realization,
      transcript: transcript,
    ).operations)
      if (operation is MomentCorrespondence) operation,
  ];

  group('which notes say when a moment happened', () {
    final realization = ExerciseRealization([oneHand(0, 60), oneHand(1, 62)]);

    test('a moment is where the notes that realized it are centered', () {
      final moments = momentsOf(
        ExerciseRealization([twoHands(0, 48, 60)]),
        played([(48, 1000, 1000000), (60, 1040, 1040000)]),
      );

      expect(moments.single.onsetMs, 1020);
      expect(moments.single.performanceOnsetUs, 1020000);
      expect(moments.single.handAsynchronyMs, 40);
      expect(moments.single.handAsynchronyUs, 40000);
    });

    // The note that realized the moment arrived on time. The intruding note
    // took no expected note's place, so it is intrusion evidence and says
    // nothing about when the moment was.
    test('an intrusion beside a moment does not move it', () {
      final moments = momentsOf(
        realization,
        played([(60, 1000, 1000000), (63, 1500, 1500000), (62, 2000, 2000000)]),
      );

      expect(moments.map((moment) => moment.performanceOnsetUs), [
        1000000,
        2000000,
      ]);
      expect(moments.first.onsetMs, 1000);
    });

    // Which of two identical pitches realized the moment is alignment's
    // choice, and it takes the later one: the earlier reads as an extra note
    // played before the moment rather than the moment itself repeated. The
    // onset follows whichever note it chose, which is the rule working on the
    // reading it was given.
    test('a repeated pitch is realized by the later of the two', () {
      final moments = momentsOf(
        realization,
        played([(60, 1000, 1000000), (60, 1500, 1500000), (62, 2000, 2000000)]),
      );

      expect(moments.map((moment) => moment.performanceOnsetUs), [
        1500000,
        2000000,
      ]);
    });

    // A wrong pitch is still an attempt at that moment. Whether it was right
    // is a different question from when it happened.
    test('a substitution still says when the hand acted', () {
      final moments = momentsOf(
        realization,
        played([(61, 1000, 1000000), (62, 2000, 2000000)]),
      );

      expect(moments.first.noteEdits.single, isA<Substitution>());
      expect(moments.first.performanceOnsetUs, 1000000);
    });
  });

  group('which clock answers', () {
    final realization = ExerciseRealization([twoHands(0, 48, 60)]);

    test('one timed hand is enough to place the moment', () {
      final moments = momentsOf(
        realization,
        played([(48, 1000, 1000000), (60, 1040, null)]),
      );

      expect(
        moments.single.performanceOnsetUs,
        1000000,
        reason: 'the clock did say when part of this moment happened',
      );
      expect(
        moments.single.handAsynchronyUs,
        isNull,
        reason: 'what is lost is the spread, not the moment',
      );
      expect(moments.single.handAsynchronyMs, 40);
    });

    test('a moment nothing could time has no performance onset', () {
      final moments = momentsOf(
        realization,
        played([(48, 1000, null), (60, 1040, null)]),
      );

      expect(moments.single.performanceOnsetUs, isNull);
      expect(moments.single.onsetMs, 1020);
    });

    // An intrusion is not a contributor, so its timing cannot make the moment
    // timed or untimed either way.
    test('an untimed intrusion leaves a timed moment timed', () {
      final moments = momentsOf(
        ExerciseRealization([oneHand(0, 60), oneHand(1, 62)]),
        played([(60, 1000, 1000000), (63, 1500, null), (62, 2000, 2000000)]),
      );

      expect(moments.first.performanceOnsetUs, 1000000);
    });
  });

  // Changing clocks must not change which notes belong to which moment. The
  // two clocks disagree about the numbers and never about the grouping.
  group('the two clocks group identically', () {
    final realization = ExerciseRealization([
      twoHands(0, 48, 60),
      twoHands(1, 50, 62),
      twoHands(2, 52, 64),
    ]);

    test('however far apart the hands landed', () {
      for (final spreadMs in [0, 40, 120]) {
        final transcript = played([
          for (var position = 0; position < 3; position++) ...[
            (
              [48, 50, 52][position],
              1000 + position * 500,
              (1000 + position * 500) * 1000,
            ),
            (
              [60, 62, 64][position],
              1000 + position * 500 + spreadMs,
              (1000 + position * 500 + spreadMs) * 1000,
            ),
          ],
        ]);
        final moments = momentsOf(realization, transcript);

        expect(moments, hasLength(3), reason: 'spread ${spreadMs}ms');
        expect(
          moments.map((moment) => moment.observedSequences.length),
          everyElement(2),
        );
        expect(
          moments.map((moment) => moment.performanceOnsetUs! ~/ 1000),
          moments.map((moment) => moment.onsetMs.round()),
        );

        // The rhythm is the same whatever the hands did, and the spread is
        // reported where it belongs.
        final waits = [
          for (var index = 1; index < moments.length; index++)
            moments[index].performanceOnsetUs! -
                moments[index - 1].performanceOnsetUs!,
        ];
        expect(waits, everyElement(500000));
        expect(
          moments.map((moment) => moment.handAsynchronyUs),
          everyElement(spreadMs * 1000),
        );
      }
    });
  });
}
