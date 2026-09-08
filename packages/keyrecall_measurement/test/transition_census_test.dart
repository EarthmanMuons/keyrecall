import 'package:keyrecall_domain/keyrecall_domain.dart';
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

  PerformanceTranscript played(List<int> midiNotes, List<int> gaps) {
    var transcript = PerformanceTranscript.empty;
    var at = 0;
    for (final (index, midiNote) in midiNotes.indexed) {
      at += index == 0 ? 0 : gaps[index - 1];
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: at,
      );
    }
    return transcript;
  }

  /// A whole traversal that waits before [position], or plays evenly for null.
  AcquisitionObservation traversalStalling(int? position) => observeAcquisition(
    task: task,
    transcript: played(expected, [
      for (var i = 1; i < expected.length; i++)
        if (i == position) 4000 else 900,
    ]),
  );

  /// A traversal abandoned after [count] notes, waiting before the last one.
  AcquisitionObservation stoppedAfter(int count) => observeAcquisition(
    task: task,
    transcript: played(expected.take(count).toList(), [
      for (var i = 1; i < count; i++)
        if (i == count - 1) 4000 else 900,
    ]),
  );

  group('recording', () {
    test('counts every transition played and the ones that stalled', () {
      var census = TransitionCensus.of(task);
      census = census.recording(traversalStalling(4));

      expect(census.attempts, 1);
      expect(census.played[(fromPosition: 3, toPosition: 4)], 1);
      expect(census.stalled[(fromPosition: 3, toPosition: 4)], 1);
      expect(census.stalled[(fromPosition: 4, toPosition: 5)], isNull);
    });

    test(
      'separates a transition that keeps failing from one that once did',
      () {
        var census = TransitionCensus.of(task);
        for (var attempt = 0; attempt < 3; attempt++) {
          census = census.recording(traversalStalling(4));
        }
        census = census.recording(traversalStalling(6));

        expect(census.attempts, 4);
        expect(census.stalledAtLeast(2), [(fromPosition: 3, toPosition: 4)]);
        expect(census.stallRateOf((fromPosition: 3, toPosition: 4)), 0.75);
        expect(census.stallRateOf((fromPosition: 5, toPosition: 6)), 0.25);
      },
    );

    test('does not count a transition the learner never reached', () {
      var census = TransitionCensus.of(task);
      census = census.recording(stoppedAfter(4));

      // Three intervals arrived, so three transitions were played. Everything
      // past where the attempt stopped has no reading at all, which is not the
      // same as having been played through.
      expect(census.played[(fromPosition: 2, toPosition: 3)], 1);
      expect(census.played[(fromPosition: 4, toPosition: 5)], isNull);
      expect(census.stallRateOf((fromPosition: 4, toPosition: 5)), isNull);
    });

    test('keeps the denominators apart', () {
      // One attempt that stalls late and stops there, then two that never get
      // that far. The late transition stalled once in one chance; counting
      // against attempts would call it a third as troublesome as it was.
      var census = TransitionCensus.of(task);
      census = census.recording(stoppedAfter(7));
      census = census.recording(stoppedAfter(4));
      census = census.recording(stoppedAfter(4));

      expect(census.attempts, 3);
      expect(census.stallRateOf((fromPosition: 5, toPosition: 6)), 1.0);
    });

    test('refuses an observation of a different task', () {
      final other = AcquisitionTask.unmeteredTraversal(
        parent.withGuidance(GuidanceContext.notesPreviewedOnly),
      );

      expect(
        () => TransitionCensus.of(other).recording(traversalStalling(4)),
        throwsArgumentError,
      );
    });
  });

  group('the threshold', () {
    test('belongs to the caller', () {
      var census = TransitionCensus.of(task);
      census = census.recording(traversalStalling(4));
      census = census.recording(traversalStalling(4));

      expect(census.stalledAtLeast(2), hasLength(1));
      expect(census.stalledAtLeast(3), isEmpty);
    });
  });
}
