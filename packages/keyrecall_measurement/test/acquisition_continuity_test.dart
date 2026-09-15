import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// What the continuity reading does across constructed playing.
///
/// Invariants rather than a parameter sweep: these expose cliffs in the rule as
/// it stands, and do not choose a threshold from synthetic gaps.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  final parent = Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );
  final task = AcquisitionTask.unmeteredTraversal(parent);
  final expected = [
    for (final moment in realizeAcquisition(task).moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];

  PerformanceTranscript played(List<int> midiNotes, List<int> gaps) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in midiNotes.indexed) {
      at += index == 0 ? 0 : gaps[index - 1];
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
        performanceTimeUs: at * 1000,
      );
    }
    return transcript;
  }

  AcquisitionObservation observe(List<int> notes, List<int> gaps) =>
      observeAcquisition(task: task, transcript: played(notes, gaps));

  /// The same playing, on a transport whose clock nothing has characterized.
  AcquisitionObservation observeUntimed(List<int> notes, List<int> gaps) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in notes.indexed) {
      at += index == 0 ? 0 : gaps[index - 1];
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
      );
    }
    return observeAcquisition(task: task, transcript: transcript);
  }

  /// Even playing at [gapMs] a note.
  List<int> even(int gapMs, {int notes = 8}) => [
    for (var i = 1; i < notes; i++) gapMs,
  ];

  group('clean playing at any speed', () {
    test('reads the same however slow it is', () {
      // Nothing was asked about tempo, so an unmetered attempt has no speed to
      // be wrong. A rule that read differently at 40 and at 4000 milliseconds
      // a note would be reading a tempo it was never given.
      for (final gapMs in [120, 300, 600, 1200, 2400, 4800]) {
        final result = observe(expected, even(gapMs));

        expect(
          result.completion,
          AcquisitionCompletion.completedCleanly,
          reason: '$gapMs ms',
        );
        expect(result.continuity, CriterionVerdict.met, reason: '$gapMs ms');
        expect(result.earnsParentProbe, isTrue, reason: '$gapMs ms');
      }
    });

    test('survives ordinary unevenness', () {
      // Human playing is not a metronome. Gaps within a factor of two of each
      // other are not an interruption, and a rule that called them one would
      // never let anybody earn anything.
      final uneven = observe(expected, const [
        600,
        800,
        500,
        900,
        700,
        650,
        750,
      ]);

      expect(uneven.continuity, CriterionVerdict.met);
      expect(uneven.earnsParentProbe, isTrue);
    });
  });

  group('one localized stall', () {
    test('is found wherever in the traversal it happens', () {
      for (var position = 1; position < expected.length; position++) {
        final gaps = [
          for (var i = 1; i < expected.length; i++)
            if (i == position) 9000 else 600,
        ];
        final result = observe(expected, gaps);

        expect(
          result.continuity,
          CriterionVerdict.notMet,
          reason: 'stall before $position',
        );
        expect(result.stalls.single.toPosition, position);
        expect(
          result.earnsParentProbe,
          isFalse,
          reason: 'stall before $position',
        );
      }
    });

    test('is read the same at any pace', () {
      // The same shape twice as fast. Ratios are relative to the performance's
      // own playing, so nothing about the reading may move.
      final slow = observe(expected, const [
        600,
        600,
        9000,
        600,
        600,
        600,
        600,
      ]);
      final quick = observe(expected, const [
        300,
        300,
        4500,
        300,
        300,
        300,
        300,
      ]);

      expect(quick.continuity, slow.continuity);
      expect(quick.stalls.single.toPosition, slow.stalls.single.toPosition);
      expect(
        quick.stalls.single.ratio,
        closeTo(slow.stalls.single.ratio!, 1e-9),
      );
    });

    test('several smaller hesitations are not one interruption', () {
      // Where the rule sits, stated as a case rather than as a number. Three
      // gaps at twice the ordinary one is uneven playing, not a stop.
      final hesitant = observe(expected, const [
        600,
        1200,
        600,
        1200,
        600,
        1200,
        600,
      ]);

      expect(hesitant.continuity, CriterionVerdict.met);
      expect(hesitant.stalls, isEmpty);
    });
  });

  group('what the notes were', () {
    test('a correction is completion, and never a clean one', () {
      final repaired = observe([
        ...expected.take(3),
        expected[3] + 1,
        ...expected.skip(3),
      ], even(600, notes: expected.length + 1));

      expect(
        repaired.completion,
        AcquisitionCompletion.completedWithCorrections,
      );
      expect(repaired.repairs, 1);
      expect(repaired.earnsParentProbe, isFalse);
    });

    test('an unrepaired substitution is not completion', () {
      final strayed = observe([
        ...expected.take(3),
        expected[3] + 1,
        ...expected.skip(4),
      ], even(600));

      expect(strayed.completion, AcquisitionCompletion.notCompleted);
      expect(strayed.earnsParentProbe, isFalse);
    });

    test('a repeated note is not a wrong one', () {
      final repeated = observe([
        ...expected.take(3),
        expected[2],
        ...expected.skip(3),
      ], even(600, notes: expected.length + 1));

      expect(repeated.repeats, 1);
      expect(repeated.intrusions, 0);
      expect(
        repeated.completion,
        AcquisitionCompletion.completedWithCorrections,
      );
    });
  });

  // The task was performed and part of it was observed. What is missing is the
  // evidence one verdict needs, which is not the same as the verdict going
  // badly: the sequence was demonstrated and continuity could not be
  // established, so the probe is not earned rather than failed.
  group('an attempt nothing could time', () {
    test('demonstrates the sequence and establishes no continuity', () {
      final result = observeUntimed(expected, even(600));

      expect(result.completion, AcquisitionCompletion.completedCleanly);
      expect(result.stalls, isEmpty);
      expect(result.continuity, CriterionVerdict.unavailable);
      expect(result.earnsParentProbe, isFalse);
    });

    test('is not read as an interruption however long the waits were', () {
      final result = observeUntimed(expected, const [
        600,
        600,
        10000,
        600,
        600,
        600,
        600,
      ]);

      expect(
        result.continuity,
        CriterionVerdict.unavailable,
        reason: 'nothing here measured that wait, so nothing calls it a stall',
      );
      expect(result.stalls, isEmpty);
    });
  });

  // Continuity is a claim about every transition inside a traversal, so the
  // evidence it needs is every one of those transitions, not enough waits to
  // compute a pace from.
  group('an attempt that could time only part of itself', () {
    /// The same clean playing with the performance clock missing at [absent].
    AcquisitionObservation observeMissing(Set<int> absent) {
      var transcript = PerformanceTranscript.empty;
      var at = 0;
      for (final (index, midiNote) in expected.indexed) {
        at += index == 0 ? 0 : 600;
        transcript = transcript.appending(
          pitch: spellObservedPitch(midiNote, material: material),
          timestampMs: at,
          performanceTimeUs: absent.contains(index) ? null : at * 1000,
        );
      }
      return observeAcquisition(task: task, transcript: transcript);
    }

    for (final (where, absent) in [
      ('at the beginning', {0}),
      ('inside', {4}),
      ('at the end', {7}),
    ]) {
      test('establishes no continuity with a note untimed $where', () {
        final result = observeMissing(absent);

        expect(result.completion, AcquisitionCompletion.completedCleanly);
        expect(result.stalls, isEmpty);
        expect(result.isFullyTimed, isFalse);
        expect(result.continuity, CriterionVerdict.unavailable);
        expect(result.earnsParentProbe, isFalse);
      });
    }

    test('still calls an observed stall an interruption', () {
      // A wait that was timed and was long is a stop, and the transitions
      // nobody timed do not take that back.
      var transcript = PerformanceTranscript.empty;
      var at = 0;
      for (final (index, midiNote) in expected.indexed) {
        at += index == 0 ? 0 : (index == 5 ? 9000 : 600);
        transcript = transcript.appending(
          pitch: spellObservedPitch(midiNote, material: material),
          timestampMs: at,
          performanceTimeUs: index == 0 ? null : at * 1000,
        );
      }
      final result = observeAcquisition(task: task, transcript: transcript);

      expect(result.isFullyTimed, isFalse);
      expect(result.stalls, isNotEmpty);
      expect(result.continuity, CriterionVerdict.notMet);
    });
  });

  group('repeated traversals', () {
    final parent = Exercise.linear(
      material: ArpeggioMaterial('C', ArpeggioQuality.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
      guidance: GuidanceContext.continuouslyCued,
    );
    final task = AcquisitionScaffold.unmeteredRepetitions(2).taskFor(parent);
    final notes = [
      for (final moment in realizeAcquisition(task).moments)
        moment.notes.single.midiNote,
    ];

    for (var position = 1; position < 4; position++) {
      test(
        'recurring hesitation at transition $position is seen, not pooled away',
        () {
          final result = observeAcquisition(
            task: task,
            transcript: _played(notes, [
              for (var i = 1; i < notes.length; i++)
                if (i == 4) 5000 else if (i % 4 == position) 10000 else 600,
            ], parent),
          );
          expect(result.completion, AcquisitionCompletion.completedCleanly);
          expect(result.stalls, hasLength(2));
          expect(result.continuity, CriterionVerdict.notMet);
          expect(result.earnsParentProbe, isFalse);
        },
      );
    }

    test('each traversal may use its own steady pace', () {
      final result = observeAcquisition(
        task: task,
        transcript: _played(notes, [
          600,
          600,
          600,
          10000,
          3000,
          3000,
          3000,
        ], parent),
      );
      expect(result.continuity, CriterionVerdict.met);
      expect(result.earnsParentProbe, isTrue);
    });

    test('the criterion covers every transition but the resets', () {
      // Four moments twice over: three transitions inside each traversal, and
      // the turnaround between them belongs to neither.
      expect(acquisitionContinuityTransitions(task), [
        (0, 1),
        (1, 2),
        (2, 3),
        (4, 5),
        (5, 6),
        (6, 7),
      ]);
    });

    for (final omittedStarts in [1, 2]) {
      test('a reset crossing $omittedStarts missing notes is not a stall', () {
        final played = [...notes.take(4), ...notes.skip(4 + omittedStarts)];
        final result = observeAcquisition(
          task: task,
          transcript: _played(played, [
            for (var i = 1; i < played.length; i++) i == 4 ? 10000 : 600,
          ], parent),
        );
        expect(result.completion, AcquisitionCompletion.notCompleted);
        expect(result.gaps.length, 6 - omittedStarts);
        expect(
          result.gaps.any((gap) => gap.fromPosition < 4 && gap.toPosition >= 4),
          isFalse,
        );
        expect(result.gaps.every((gap) => gap.gapMs == 600), isTrue);
        expect(result.stalls, isEmpty);
        expect(result.earnsParentProbe, isFalse);
      });
    }
  });

  group('too little to say', () {
    test('a short traversal establishes no continuity', () {
      // Under five intervals the interpolated upper quartile contains the
      // maximum, so absence of a detected stall proves nothing.
      final short = observe(expected.take(4).toList(), even(600, notes: 4));

      expect(short.continuity, CriterionVerdict.unavailable);
      expect(short.stalls, isEmpty);
      expect(short.earnsParentProbe, isFalse);
    });

    test('repeating a short traversal supplies what it lacked', () {
      // The count is arithmetic, not a dose: each traversal of a four-moment
      // pattern gives three intervals, the reset between two gives none, and
      // the criterion wants five.
      final short = Exercise.linear(
        material: ArpeggioMaterial('C', ArpeggioQuality.major),
        hands: HandConfiguration.right,
        octaves: 1,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );
      final once = AcquisitionTask.unmeteredTraversal(short);
      expect(traversalsForContinuity(realizeAcquisition(once)), 2);

      final twice = AcquisitionScaffold.unmeteredRepetitions(
        traversalsForContinuity(realize(short)),
      ).taskFor(short);
      final notes = [
        for (final moment in realizeAcquisition(twice).moments)
          moment.noteFor(Hand.right)!.midiNote,
      ];
      final result = observeAcquisition(
        task: twice,
        // A long wait where the hand goes back, which the task asked for.
        transcript: _played(notes, [600, 600, 600, 5000, 600, 600, 600], short),
      );

      expect(result.completion, AcquisitionCompletion.completedCleanly);
      expect(result.gaps, hasLength(6));
      expect(result.stalls, isEmpty);
      expect(result.continuity, CriterionVerdict.met);
      expect(result.earnsParentProbe, isTrue);
    });

    test('a stall inside a traversal is still a stall', () {
      // The reset is excused because the task drew that boundary. Nothing else
      // is, and the excused interval does not join the baseline the rest are
      // read against.
      final short = Exercise.linear(
        material: ArpeggioMaterial('C', ArpeggioQuality.major),
        hands: HandConfiguration.right,
        octaves: 1,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );
      final twice = AcquisitionScaffold.unmeteredRepetitions(2).taskFor(short);
      final notes = [
        for (final moment in realizeAcquisition(twice).moments)
          moment.noteFor(Hand.right)!.midiNote,
      ];
      final result = observeAcquisition(
        task: twice,
        transcript: _played(notes, [
          600,
          5000,
          600,
          5000,
          600,
          600,
          600,
        ], short),
      );

      expect(result.stalls, isNotEmpty);
      expect(result.continuity, CriterionVerdict.notMet);
      expect(result.earnsParentProbe, isFalse);
    });

    test('nothing played says nothing at all', () {
      final silent = observeAcquisition(
        task: task,
        transcript: PerformanceTranscript.empty,
      );

      expect(silent.started, isFalse);
      expect(silent.completion, AcquisitionCompletion.notCompleted);
      expect(silent.continuity, CriterionVerdict.unavailable);
      expect(silent.gaps, isEmpty);
    });
  });
}

PerformanceTranscript _played(
  List<int> midiNotes,
  List<int> gaps,
  Exercise exercise,
) {
  var transcript = PerformanceTranscript.empty;
  var at = 0;
  for (final (index, midiNote) in midiNotes.indexed) {
    at += index == 0 ? 0 : gaps[index - 1];
    transcript = transcript.appending(
      pitch: spellObservedPitch(midiNote, material: exercise.material),
      timestampMs: at,
      performanceTimeUs: at * 1000,
    );
  }
  return transcript;
}
