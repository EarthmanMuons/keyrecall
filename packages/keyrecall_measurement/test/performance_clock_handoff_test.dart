import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// Which clock the learner-facing timing channels are read from.
///
/// All of them, and only the instrument's own. An attempt on a transport
/// nothing has characterized carries pitch evidence and no timing evidence,
/// which is the outcome `docs/decisions/performance-timing.md` prefers to a
/// confidently wrong one.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  const scale = [60, 62, 64, 65, 67, 69, 71, 72];

  final oneHand = ExerciseRealization([
    for (final (position, midiNote) in scale.indexed)
      RealizationMoment(
        position: position,
        metricOffset: position.toDouble(),
        notes: [RealizedNote(hand: Hand.right, pitch: pitch(midiNote))],
      ),
  ]);

  /// The scale played on the beat. [untimed] names the moments the performance
  /// clock could not place.
  PerformanceTranscript played({Set<int> untimed = const {}}) {
    var transcript = PerformanceTranscript.empty;
    for (final (position, midiNote) in scale.indexed) {
      final atMs = 1000 + position * 500;
      transcript = transcript.appending(
        pitch: pitch(midiNote),
        timestampMs: atMs,
        performanceTimeUs: untimed.contains(position) ? null : atMs * 1000,
      );
    }
    return transcript;
  }

  PerformanceMeasurement measuredWith({Set<int> untimed = const {}}) => measure(
    realization: oneHand,
    transcript: played(untimed: untimed),
  );

  test('a fully timed performance reads every timing channel', () {
    final measurement = measuredWith();

    expect(measurement.medianIntervalMs, 500);
    expect(measurement.temporalStability, 1.0);
    expect(measurement.continuity, 1.0);
    expect(measurement.timing.longestRunWaits, 7);
  });

  // The arrival clock is right there on every note, ordering the stream, and
  // it is not evidence about playing.
  test('a performance nothing could time reads none of them', () {
    final measurement = measuredWith(untimed: scale.indices);

    expect(measurement.materialProduced, 8, reason: 'pitch evidence survives');
    expect(measurement.timing.gaps, isEmpty);
    expect(measurement.medianIntervalMs, isNull);
    expect(measurement.temporalStability, isNull);
    expect(measurement.continuity, isNull);
  });

  group('a hole in the middle', () {
    test('costs the waits around it and is not bridged', () {
      final measurement = measuredWith(untimed: {3});

      expect(measurement.timing.gaps.map((gap) => gap.gapMs), [
        500,
        500,
        500,
        500,
        500,
      ]);
      expect(measurement.timing.gaps.map((gap) => gap.fromPosition), [
        0,
        1,
        4,
        5,
        6,
      ], reason: 'no wait runs from moment 2 to moment 4');
    });

    test('splits the stretch continuity is read from', () {
      final whole = measuredWith();
      final broken = measuredWith(untimed: {3});

      expect(whole.timing.longestRunWaits, 7);
      expect(whole.continuity, isNotNull);

      expect(broken.timing.longestRunWaits, 3);
      expect(
        broken.continuity,
        isNull,
        reason: 'five waits in two stretches are not five in one',
      );
      expect(
        broken.medianIntervalMs,
        500,
        reason: 'a pace asks for waits, not for one stretch of them',
      );
    });
  });

  // Intrusion evidence and timing evidence were separated at the alignment
  // boundary on purpose. A note that realized no moment cannot break the
  // timing of the moments around it, whether or not anything could time it.
  group('a note that realized nothing', () {
    PerformanceMeasurement measuredWithIntrusion({required bool timed}) {
      var transcript = PerformanceTranscript.empty;
      for (final (position, midiNote) in scale.indexed) {
        final atMs = 1000 + position * 500;
        transcript = transcript.appending(
          pitch: pitch(midiNote),
          timestampMs: atMs,
          performanceTimeUs: atMs * 1000,
        );
        if (position == 3) {
          transcript = transcript.appending(
            pitch: pitch(61),
            timestampMs: atMs + 200,
            performanceTimeUs: timed ? (atMs + 200) * 1000 : null,
          );
        }
      }
      return measure(realization: oneHand, transcript: transcript);
    }

    test('does not split the timing run, timed or not', () {
      for (final timed in [true, false]) {
        final measured = measuredWithIntrusion(timed: timed);

        expect(measured.intrusions, 1, reason: 'timed: $timed');
        expect(measured.timing.longestRunWaits, 7, reason: 'timed: $timed');
        expect(measured.timing.gaps.map((gap) => gap.gapMs), everyElement(500));
        expect(measured.continuity, 1.0);
      }
    });
  });

  group('coordination', () {
    final twoHands = ExerciseRealization([
      for (final (position, midiNote) in scale.indexed)
        RealizationMoment(
          position: position,
          metricOffset: position.toDouble(),
          notes: [
            RealizedNote(hand: Hand.left, pitch: pitch(midiNote - 12)),
            RealizedNote(hand: Hand.right, pitch: pitch(midiNote)),
          ],
        ),
    ]);

    PerformanceMeasurement measuredTogether({
      Set<int> untimedRight = const {},
    }) {
      var transcript = PerformanceTranscript.empty;
      for (final (position, midiNote) in scale.indexed) {
        final atMs = 1000 + position * 500;
        transcript = transcript
            .appending(
              pitch: pitch(midiNote - 12),
              timestampMs: atMs,
              performanceTimeUs: atMs * 1000,
            )
            .appending(
              pitch: pitch(midiNote),
              timestampMs: atMs + 30,
              performanceTimeUs: untimedRight.contains(position)
                  ? null
                  : (atMs + 30) * 1000,
            );
      }
      return measure(realization: twoHands, transcript: transcript);
    }

    test('is read on the same clock as the rest', () {
      final measurement = measuredTogether();

      expect(measurement.handAsynchroniesMs, everyElement(30));
      expect(measurement.coordination, isNotNull);
    });

    // The moment stays on the timeline, since one timed hand places it. What
    // is lost is the spread, and it is lost rather than taken from arrival.
    test('a hand the clock could not place leaves the moment timed', () {
      final measurement = measuredTogether(untimedRight: {2, 3});

      expect(measurement.correspondedTwoHandMoments, 6);
      expect(measurement.timing.gaps, hasLength(7));
      expect(measurement.continuity, isNotNull);
    });

    test('and no moment at all leaves coordination absent', () {
      final measurement = measuredTogether(untimedRight: scale.indices);

      expect(measurement.correspondedTwoHandMoments, 0);
      expect(measurement.coordination, isNull);
      expect(measurement.widestAsynchronyAtPosition, isNull);
    });
  });
}

extension on List<int> {
  /// Every position in this list.
  Set<int> get indices => {for (var index = 0; index < length; index++) index};
}
