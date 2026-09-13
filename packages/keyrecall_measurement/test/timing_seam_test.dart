import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// Whether the two ways of finding onsets agree.
///
/// [TimingEvidence] reads one onset per aligned moment, after correspondence
/// has settled. [timingRunsOf] reads onsets from the transcript, before
/// alignment, by collapsing notes that share a performance time. Both are
/// called an onset, and rewiring the metrics onto performance time is where
/// they would meet, so where they disagree is worth knowing first.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  const rightHand = [60, 62, 64, 65, 67, 69, 71, 72];
  const leftHand = [48, 50, 52, 53, 55, 57, 59, 60];

  ExerciseRealization realizationOf({required bool twoHands}) =>
      ExerciseRealization([
        for (var position = 0; position < rightHand.length; position++)
          RealizationMoment(
            position: position,
            metricOffset: position.toDouble(),
            notes: [
              if (twoHands)
                RealizedNote(hand: Hand.left, pitch: pitch(leftHand[position])),
              RealizedNote(hand: Hand.right, pitch: pitch(rightHand[position])),
            ],
          ),
      ]);

  /// The waits the aligned path reads, in microseconds.
  List<int> alignedWaitsUs(
    ExerciseRealization realization,
    PerformanceTranscript transcript,
  ) => [
    for (final gap in measure(
      realization: realization,
      transcript: transcript,
    ).timing.gaps)
      gap.gapMs * 1000,
  ];

  group('one hand', () {
    final realization = realizationOf(twoHands: false);

    /// The scale played on the beat, timed by the instrument's own clock.
    PerformanceTranscript played({int waitMs = 500}) {
      var transcript = PerformanceTranscript.empty;
      for (final (position, midiNote) in rightHand.indexed) {
        final atMs = 1000 + position * waitMs;
        transcript = transcript.appending(
          pitch: pitch(midiNote),
          timestampMs: atMs,
          performanceTimeUs: atMs * 1000,
        );
      }
      return transcript;
    }

    test('both paths find the same onsets and the same waits', () {
      final transcript = played();

      expect(
        usableWaitsUsOf(transcript),
        alignedWaitsUs(realization, transcript),
      );
      expect(
        timingRunsOf(transcript).single.onsets,
        hasLength(rightHand.length),
      );
    });
  });

  // The divergence. Alignment reads one onset per moment however far apart the
  // hands landed, because that spread is coordination. The transcript helper
  // collapses only notes that share a performance time, so two hands landing
  // 40 ms apart are two onsets to it, and the spread becomes a wait.
  group('two hands', () {
    final realization = realizationOf(twoHands: true);

    PerformanceTranscript played({required int spreadMs}) {
      var transcript = PerformanceTranscript.empty;
      for (var position = 0; position < rightHand.length; position++) {
        final atMs = 1000 + position * 500;
        for (final (midiNote, offsetMs) in [
          (leftHand[position], 0),
          (rightHand[position], spreadMs),
        ]) {
          transcript = transcript.appending(
            pitch: pitch(midiNote),
            timestampMs: atMs + offsetMs,
            performanceTimeUs: (atMs + offsetMs) * 1000,
          );
        }
      }
      return transcript;
    }

    test('the two paths agree when the hands land together', () {
      final transcript = played(spreadMs: 0);

      expect(
        usableWaitsUsOf(transcript),
        alignedWaitsUs(realization, transcript),
      );
    });

    test('and disagree by exactly the hand spread when they do not', () {
      final transcript = played(spreadMs: 40);

      expect(alignedWaitsUs(realization, transcript), everyElement(500000));
      expect(
        usableWaitsUsOf(transcript),
        containsAll([40000, 460000]),
        reason: 'the spread between the hands became a wait of its own',
      );
    });
  });

  // Two performances with the same number of usable waits and different
  // evidence geometry. Flattening is safe for arithmetic over independent
  // waits and loses the structure a continuity claim may need.
  group('run structure survives', () {
    PerformanceTranscript transcriptOf(List<int?> timesUs) {
      var transcript = PerformanceTranscript.empty;
      for (final (index, timeUs) in timesUs.indexed) {
        transcript = transcript.appending(
          pitch: pitch(60),
          timestampMs: index * 500,
          performanceTimeUs: timeUs,
        );
      }
      return transcript;
    }

    test('eight waits in one run and in four are told apart', () {
      final whole = transcriptOf([
        for (var index = 0; index <= 8; index++) index * 500000,
      ]);
      final broken = transcriptOf([
        for (var group = 0; group < 4; group++) ...[
          for (var index = 0; index <= 2; index++)
            (group * 10 + index) * 500000,
          null,
        ],
      ]);

      expect(usableWaitsUsOf(whole), hasLength(8));
      expect(usableWaitsUsOf(broken), hasLength(8));

      expect(timingRunsOf(whole), hasLength(1));
      expect(timingRunsOf(broken), hasLength(4));
      expect(timingRunsOf(broken).map((run) => run.waitCount), everyElement(2));
    });
  });
}
