import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

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

  /// A performance, with one note per [gapMs] unless [gaps] says otherwise.
  PerformanceTranscript played(
    List<int> midiNotes, {
    int gapMs = 900,
    List<int>? gaps,
  }) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in midiNotes.indexed) {
      at += index == 0 ? 0 : (gaps == null ? gapMs : gaps[index - 1]);
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
      );
    }
    return transcript;
  }

  final policyBrokenRatio = MeasurementPolicy.standard.brokenIntervalRatio;

  AcquisitionObservation observed(List<int> midiNotes, {List<int>? gaps}) =>
      observeAcquisition(
        task: task,
        transcript: played(midiNotes, gaps: gaps),
      );

  group('the contractual outcome', () {
    test('separates a clean pass from one reached through corrections', () {
      final clean = observed(expected);
      expect(clean.completion, AcquisitionCompletion.completedCleanly);
      expect(clean.repairs, 0);

      // The same sequence, with the note above the third played and fixed.
      final repaired = observed([
        ...expected.take(2),
        expected[2] + 1,
        ...expected.skip(2),
      ]);
      expect(
        repaired.completion,
        AcquisitionCompletion.completedWithCorrections,
      );
      expect(repaired.repairs, 1);
      expect(repaired.intrusions, 1);
    });

    test('a traversal of wrong notes is not a traversal', () {
      // Alignment explains each wrong note as a substitution, so every
      // position is accounted for and nothing is missing. None of the material
      // was played, which is what completion is about.
      final wrong = observed([for (final note in expected) note + 1]);

      expect(wrong.completion, AcquisitionCompletion.notCompleted);
      expect(wrong.repairs, 0);
      expect(wrong.intrusions, 0);
      expect(wrong.firstAbsentPosition, isNull);
      expect(wrong.earnsParentProbe, isFalse);
    });

    test('one wrong note the learner moved on from is not completion', () {
      final strayed = observed([
        ...expected.take(3),
        expected[3] + 1,
        ...expected.skip(4),
      ]);

      expect(strayed.completion, AcquisitionCompletion.notCompleted);
    });

    test('says where an unfinished traversal ran out', () {
      final stopped = observed(expected.take(4).toList());

      expect(stopped.started, isTrue);
      expect(stopped.completion, AcquisitionCompletion.notCompleted);
      expect(stopped.firstAbsentPosition, 4);
    });

    test('counts completion through correction as work done', () {
      final repaired = observed([
        ...expected.take(2),
        expected[2] + 1,
        ...expected.skip(2),
      ]);

      // Practice, and not a probe: the sequence came out, and it did not come
      // out first time.
      expect(repaired.completion.isComplete, isTrue);
      expect(repaired.earnsParentProbe, isFalse);
    });
  });

  group('localization', () {
    // Even playing except for one long wait before the fifth degree, which is
    // where the thumb has already crossed.
    List<int> stallingBefore(int position) => [
      for (var i = 1; i < expected.length; i++)
        if (i == position) 4000 else 900,
    ];

    test('names the transition a stall spans', () {
      final observation = observed(expected, gaps: stallingBefore(4));

      expect(observation.stalls, hasLength(1));
      final stall = observation.stalls.single;
      expect(stall.fromPosition, 3);
      expect(stall.toPosition, 4);
      expect(stall.gapMs, 4000);
    });

    test('reads the same stall the same way at any pace', () {
      // Every interval halved: the learner played the whole thing twice as
      // fast and hesitated in the same place for half as long. Nothing about
      // a requested tempo enters, so the reading is unchanged.
      final slow = observed(expected, gaps: stallingBefore(4));
      final quick = observed(
        expected,
        gaps: [for (final gap in stallingBefore(4)) gap ~/ 2],
      );

      expect(quick.stalls.single.fromPosition, slow.stalls.single.fromPosition);
      expect(
        quick.stalls.single.ratio,
        closeTo(slow.stalls.single.ratio, 1e-9),
      );
    });

    test('keeps every gap, not only the worst one', () {
      final observation = observed(expected, gaps: stallingBefore(4));

      expect(observation.gaps, hasLength(expected.length - 1));
      expect(
        [for (final gap in observation.gaps) gap.toPosition],
        [for (var i = 1; i < expected.length; i++) i],
      );
    });

    test('measures against a baseline the same short attempt supplies', () {
      // The known limit of an endogenous baseline. Four intervals, one of them
      // the hesitation, and the quartile the hesitation is compared against is
      // pulled up by the hesitation itself, so the same wait that reads as a
      // stall in a full traversal does not read as one here.
      //
      // Kept as a demonstrated property rather than fixed. An acquisition
      // constant chosen to make this case come out is worse than a threshold
      // shared with ordinary continuity, and device traces are what should
      // settle it.
      final short = observeAcquisition(
        task: task,
        transcript: played(
          expected.take(5).toList(),
          gaps: [900, 900, 900, 4000],
        ),
      );

      expect(short.gaps.last.gapMs, 4000);
      expect(short.gaps.last.ratio, lessThan(policyBrokenRatio));
      expect(short.stalls, isEmpty);
    });

    test('does not call even playing a stall', () {
      expect(observed(expected).stalls, isEmpty);
    });
  });

  group('probe eligibility', () {
    test('short clean traversals cannot certify continuity', () {
      final arpeggio = ArpeggioMaterial('C', ArpeggioQuality.major);
      final shortTask = AcquisitionTask.unmeteredTraversal(
        Exercise.linear(
          material: arpeggio,
          hands: HandConfiguration.right,
          direction: ExerciseDirection.up,
          tempoBpm: 60,
          guidance: GuidanceContext.continuouslyCued,
        ),
      );
      for (final lastOnset in [2700, 61800]) {
        var transcript = PerformanceTranscript.empty;
        final onsets = [0, 900, 1800, lastOnset];
        for (final moment in realizeAcquisition(shortTask).moments) {
          transcript = transcript.appending(
            pitch: spellObservedPitch(
              moment.noteFor(Hand.right)!.midiNote,
              material: arpeggio,
            ),
            timestampMs: onsets[moment.position],
          );
        }
        final observation = observeAcquisition(
          task: shortTask,
          transcript: transcript,
        );
        expect(observation.completion, AcquisitionCompletion.completedCleanly);
        expect(observation.continuity, AcquisitionContinuity.unestablished);
        expect(observation.earnsParentProbe, isFalse);
      }
    });

    test('needs a clean pass the learner did not stop inside', () {
      expect(observed(expected).earnsParentProbe, isTrue);
      expect(
        observed(
          expected,
          gaps: [
            for (var i = 1; i < expected.length; i++)
              if (i == 4) 4000 else 900,
          ],
        ).earnsParentProbe,
        isFalse,
      );
      expect(observed(expected.take(4).toList()).earnsParentProbe, isFalse);
    });
  });

  group('the evidence fence', () {
    test('withholds the readings the relaxed task did not earn', () {
      final observation = observed(expected);

      // Nothing here is an Outcome, and nothing here carries the measurement
      // that would make one. Retrieval was never tested because the cues
      // supplied the material, and no tempo was asked for, so a performed
      // speed is a fact about the attempt rather than a fraction of a request.
      expect(observation, isNot(isA<PerformanceMeasurement>()));
      expect(observation.task.timing.supportsTempoEvidence, isFalse);
      expect(observation.task.parent.guidance.isRetrievalObserved, isFalse);
    });

    test('is not what a probe of the parent would produce', () {
      // The same notes, offered as the parent exercise, are ordinary evidence
      // at the parent's tempo. That is the probe's job and not acquisition's,
      // and the two readings of one performance are deliberately different.
      final measurement = measure(
        realization: realize(parent),
        transcript: played(expected),
      );
      final outcome = outcomeFor(measurement: measurement, exercise: parent);

      expect(outcome.completed, isTrue);
      expect(outcome.retrieval, FactualRetrieval.notTested);
      expect(measurement.achievedTempoRatioFor(parent.conditions), isPositive);
    });
  });
}
