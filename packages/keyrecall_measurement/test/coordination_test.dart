import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// How together the hands were, read off the moments that had both.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  final exercise = Exercise.linear(
    material: material,
    hands: HandConfiguration.together,
    octaves: 1,
    direction: ScaleDirection.up,
  );

  /// The first four moments of that exercise.
  final realization = ExerciseRealization(
    realize(exercise).moments.take(4).toList(),
  );

  /// The scale played on the beat, with the hands [spreads] apart at each
  /// moment. A positive spread puts the right hand second.
  PerformanceMeasurement measuredWith(
    List<int> spreads, {
    Set<Hand> silent = const {},
    int atMoment = -1,
  }) {
    var transcript = PerformanceTranscript.empty;
    var at = 1000;
    for (final (index, moment) in realization.moments.indexed) {
      final spread = spreads[index];
      final arrivals = <(Hand, int, int)>[
        (
          Hand.left,
          moment.noteFor(Hand.left)!.midiNote,
          spread < 0 ? at - spread : at,
        ),
        (
          Hand.right,
          moment.noteFor(Hand.right)!.midiNote,
          spread < 0 ? at : at + spread,
        ),
      ]..sort((left, right) => left.$3.compareTo(right.$3));
      for (final (hand, midiNote, timestampMs) in arrivals) {
        if (index == atMoment && silent.contains(hand)) continue;
        transcript = transcript.appending(
          pitch: pitch(midiNote),
          timestampMs: timestampMs,
        );
      }
      at += 500;
    }
    return measure(realization: realization, transcript: transcript);
  }

  group('what coordination is read from', () {
    test('a single-hand performance measures none of it', () {
      final rightHand = realize(
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
          direction: ScaleDirection.up,
        ),
      );
      var transcript = PerformanceTranscript.empty;
      for (final (index, moment) in rightHand.moments.indexed) {
        transcript = transcript.appending(
          pitch: moment.notes.single.pitch,
          timestampMs: 1000 + index * 500,
        );
      }

      final measurement = measure(
        realization: rightHand,
        transcript: transcript,
      );

      expect(measurement.handAsynchroniesMs, isEmpty);
      expect(measurement.coordination, isNull);
      expect(measurement.medianAbsoluteHandAsynchronyMs, isNull);
      expect(measurement.signedMedianHandAsynchronyMs, isNull);
    });

    test('a hand that played nothing contributes no moment', () {
      final measurement = measuredWith(
        const [0, 0, 0, 0],
        silent: {Hand.right},
        atMoment: 2,
      );

      expect(measurement.correspondedTwoHandMoments, 3);
      expect(measurement.coordination, isNotNull);
    });

    test('a wrong pitch still contributes one', () {
      var transcript = PerformanceTranscript.empty;
      var at = 1000;
      for (final (index, moment) in realization.moments.indexed) {
        final right = moment.noteFor(Hand.right)!.midiNote;
        transcript = transcript
            .appending(pitch: moment.noteFor(Hand.left)!.pitch, timestampMs: at)
            .appending(
              pitch: pitch(index == 1 ? right + 1 : right),
              timestampMs: at + 20,
            );
        at += 500;
      }

      final measurement = measure(
        realization: realization,
        transcript: transcript,
      );

      expect(measurement.correspondedTwoHandMoments, 4);
      expect(measurement.soundedCorrectly, 7);
    });

    test('nothing to read leaves it absent rather than bad', () {
      final measurement = measure(
        realization: realization,
        transcript: PerformanceTranscript.empty,
      );

      expect(measurement.coordination, isNull);
      expect(measurement.continuity, 0.0);
    });
  });

  group('what the score reacts to', () {
    test('hands together score better than hands apart', () {
      expect(
        measuredWith(const [10, 10, 10, 10]).coordination,
        greaterThan(measuredWith(const [100, 100, 100, 100]).coordination!),
      );
    });

    test('a worse usual spread lowers it', () {
      final occasional = measuredWith(const [0, 0, 0, 100]);
      final habitual = measuredWith(const [100, 100, 100, 100]);

      expect(
        occasional.p90AbsoluteHandAsynchronyMs,
        habitual.p90AbsoluteHandAsynchronyMs,
      );
      expect(habitual.coordination, lessThan(occasional.coordination!));
    });

    test('a worse worst moment lowers it', () {
      final even = measuredWith(const [0, 0, 0, 0]);
      final ragged = measuredWith(const [0, 0, 0, 120]);

      expect(
        ragged.medianAbsoluteHandAsynchronyMs,
        even.medianAbsoluteHandAsynchronyMs,
      );
      expect(ragged.coordination, lessThan(even.coordination!));
    });

    test('which hand led does not', () {
      final rightLate = measuredWith(const [40, 40, 40, 40]);
      final leftLate = measuredWith(const [-40, -40, -40, -40]);

      expect(rightLate.signedMedianHandAsynchronyMs, 40);
      expect(leftLate.signedMedianHandAsynchronyMs, -40);
      expect(leftLate.coordination, rightLate.coordination);
    });
  });

  group('where the hands came apart', () {
    test('names the moment they were furthest apart', () {
      expect(
        measuredWith(const [10, 10, 90, 10]).widestAsynchronyAtPosition,
        2,
      );
    });

    test('does not care which hand led', () {
      expect(
        measuredWith(const [10, 10, -90, 10]).widestAsynchronyAtPosition,
        2,
      );
    });

    test('skips moments a hand played nothing at', () {
      final measurement = measuredWith(
        const [90, 10, 10, 10],
        silent: {Hand.left},
        atMoment: 0,
      );

      expect(measurement.correspondedTwoHandMoments, 3);
      expect(
        measurement.widestAsynchronyAtPosition,
        isNot(0),
        reason: 'a moment with one hand has no spread to be the widest',
      );
    });
  });

  test('a note both hands meet on is not coordination evidence', () {
    // What contrary motion starts on. One key gives one onset, so the hands
    // cannot be observed apart there however they played, and a zero would be
    // the representation rather than the performance.
    final withUnison = ExerciseRealization([
      RealizationMoment(
        position: 0,
        metricOffset: 0,
        notes: [
          RealizedNote.shared(hands: {Hand.left, Hand.right}, pitch: pitch(60)),
        ],
      ),
      ...realize(exercise).moments.skip(1).take(2),
    ]);

    // The unison struck once, then each later moment with the hands 40ms apart.
    var transcript = PerformanceTranscript.empty.appending(
      pitch: withUnison.moments.first.notes.single.pitch,
      timestampMs: 1000,
    );
    var at = 2000;
    for (final moment in withUnison.moments.skip(1)) {
      transcript = transcript
          .appending(pitch: moment.noteFor(Hand.left)!.pitch, timestampMs: at)
          .appending(
            pitch: moment.noteFor(Hand.right)!.pitch,
            timestampMs: at + 40,
          );
      at += 1000;
    }

    final measurement = measure(
      realization: withUnison,
      transcript: transcript,
    );

    expect(
      measurement.correspondedTwoHandMoments,
      2,
      reason: 'the unison is not a moment coordination was read from',
    );
    expect(measurement.medianAbsoluteHandAsynchronyMs, 40);
  });

  test('the outcome carries the score and not which hand led', () {
    Outcome outcomeOf(List<int> spreads) =>
        outcomeFor(measurement: measuredWith(spreads), exercise: exercise);

    final rightLate = outcomeOf(const [40, 40, 40, 40]);
    final leftLate = outcomeOf(const [-40, -40, -40, -40]);

    expect(rightLate.coordination, isNotNull);
    expect(
      rightLate,
      leftLate,
      reason: 'the lead is description, and nothing the learner model reads',
    );
  });
}
