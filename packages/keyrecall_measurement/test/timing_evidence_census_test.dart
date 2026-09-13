import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// What the timing metrics do as the evidence thins out.
///
/// Data rather than policy. The floors each metric should require are not set
/// here; this is what they would be set from. What the table shows:
///
/// - the three floors are separate: a pace needs three waits, a spread five,
///   and continuity five in one stretch.
/// - one pause among regular playing reads as broken at every length, and
///   costs no steadiness, because a stop is not unsteady playing.
/// - pauses stay interruptions until they are most of the waits, at which
///   point they are the pace rather than interruptions of it.
/// - a single wait much shorter than the rest reads as unsteady without
///   reading as broken, and its effect fades as the performance lengthens.
void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  SpelledPitch pitch(int midiNote) =>
      spellObservedPitch(midiNote, material: material);

  const scale = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84];

  /// One hand, [notes] long, so a performance of it supplies exactly one wait
  /// fewer than it has notes.
  ExerciseRealization realizationOf(int notes) => ExerciseRealization([
    for (var position = 0; position < notes; position++)
      RealizationMoment(
        position: position,
        metricOffset: position.toDouble(),
        notes: [RealizedNote(hand: Hand.right, pitch: pitch(scale[position]))],
      ),
  ]);

  /// The whole thing played, with [waits] between its notes.
  PerformanceMeasurement measuredWith(List<int> waits) {
    final realization = realizationOf(waits.length + 1);
    var transcript = PerformanceTranscript.empty;
    var at = 1000;
    for (final (index, moment) in realization.moments.indexed) {
      if (index > 0) at += waits[index - 1];
      transcript = transcript.appending(
        pitch: moment.notes.single.pitch,
        timestampMs: at,
      );
    }
    return measure(realization: realization, transcript: transcript);
  }

  String cell(double? value) =>
      value == null ? '    -' : value.toStringAsFixed(2).padLeft(5);

  void report(String label, List<int> waits) {
    final measured = measuredWith(waits);
    print(
      '${label.padRight(26)} waits=${waits.length.toString().padLeft(2)} '
      'pace=${(measured.timing.paceMs?.round() ?? 0).toString().padLeft(5)} '
      'worstRatio=${cell(measured.worstIntervalRatio)} '
      'continuity=${cell(measured.continuity)} '
      'stability=${cell(measured.temporalStability)} '
      'median=${(measured.medianIntervalMs ?? 0).toString().padLeft(4)}',
    );
  }

  List<int> regular(int count) => [for (var i = 0; i < count; i++) 500];

  /// Regular playing with [pauses] of them four times as long, at the end.
  List<int> withPauses(int count, int pauses) => [
    ...regular(count - pauses),
    for (var i = 0; i < pauses; i++) 2000,
  ];

  group('how much evidence there is', () {
    test('regular playing, one wait at a time', () {
      for (var waits = 1; waits <= 12; waits++) {
        report('regular', regular(waits));
      }
    });

    // Each metric asks for what it needs and no more, so a performance can
    // support a pace and nothing else.
    test('the three floors are separate', () {
      for (var waits = 1; waits < fewestWaitsForPace; waits++) {
        final measured = measuredWith(regular(waits));
        expect(measured.medianIntervalMs, isNull, reason: '$waits waits');
        expect(measured.dispersion, isNull);
        expect(measured.continuity, isNull);
      }

      for (
        var waits = fewestWaitsForPace;
        waits < fewestWaitsForSpread;
        waits++
      ) {
        final measured = measuredWith(regular(waits));
        expect(measured.medianIntervalMs, 500, reason: '$waits waits');
        expect(measured.dispersion, isNull);
        expect(measured.continuity, isNull);
      }

      final enough = measuredWith(regular(fewestWaitsForSpread));
      expect(enough.medianIntervalMs, 500);
      expect(enough.temporalStability, isNotNull);
      expect(enough.continuity, isNotNull);
    });

    // Continuity asks for its waits in one stretch. Nothing here can produce a
    // broken one yet, so what is pinned is that the stretch is what it counts.
    test('continuity counts a stretch, not a total', () {
      final measured = measuredWith(
        regular(fewestContiguousWaitsForContinuity),
      );

      expect(
        measured.timing.longestRunWaits,
        fewestContiguousWaitsForContinuity,
      );
      expect(measured.continuity, isNotNull);
    });
  });

  group('one interruption in otherwise regular playing', () {
    test('is read at every length', () {
      for (var waits = 5; waits <= 12; waits++) {
        report('one pause', withPauses(waits, 1));
        final measured = measuredWith(withPauses(waits, 1));
        expect(measured.worstIntervalRatio, 4.0);
        expect(measured.continuity, 0.0);
        expect(
          measured.temporalStability,
          1.0,
          reason: 'one long wait is not spread',
        );
      }
    });
  });

  // The self-contamination the audit named. The baseline is the upper quartile
  // of the same waits being judged against it, so once enough of them are
  // pauses the pauses become the ordinary playing they are measured against.
  group('several interruptions', () {
    test(
      'stop reading as interruptions once enough of the waits are pauses',
      () {
        for (var waits = 5; waits <= 14; waits++) {
          for (var pauses = 1; pauses <= 4; pauses++) {
            if (pauses >= waits) continue;
            report('$pauses pauses', withPauses(waits, pauses));
          }
        }
      },
    );

    // What the reference being set without the judged wait buys. Under an
    // upper quartile of every wait, three pauses in nine and four in thirteen
    // read as perfectly unbroken, because the pauses had become the playing.
    test('a minority of pauses stays a minority', () {
      expect(measuredWith(withPauses(9, 2)).continuity, 0.0);
      expect(measuredWith(withPauses(9, 3)).continuity, lessThan(0.5));

      expect(measuredWith(withPauses(13, 3)).continuity, 0.0);
      expect(measuredWith(withPauses(13, 4)).continuity, lessThan(0.5));
    });

    // A quarter of the playing stopped, which used to read as 0.96 unbroken.
    test('a quarter of the waits stopping reads as broken', () {
      final measured = measuredWith(withPauses(14, 4));

      expect(measured.continuity, 0.0);
    });

    // Where they stop being interruptions: when they are most of the waits,
    // they are the playing.
    test('a majority of long waits is the pace', () {
      final measured = measuredWith(withPauses(14, 9));

      expect(measured.continuity, 1.0);
      expect(measured.medianIntervalMs, 2000);
    });
  });

  group('unevenness that never stops', () {
    test('alternating waits', () {
      for (var waits = 5; waits <= 12; waits++) {
        report('alternating', [
          for (var i = 0; i < waits; i++) i.isEven ? 700 : 300,
        ]);
      }
    });

    test('one wait shorter than the rest', () {
      for (var waits = 5; waits <= 12; waits++) {
        report('one rushed', [...regular(waits - 1), 125]);
        expect(measuredWith([...regular(waits - 1), 125]).continuity, 1.0);
      }

      // Rushing reads as unsteady rather than as a break, which an
      // interquartile range never noticed at all. How much depends on how much
      // of the performance it is: a mean deviation divides by the waits, so
      // one rushed wait in twelve is a twelfth of the deviation it is in five.
      expect(
        measuredWith([...regular(4), 125]).temporalStability,
        lessThan(0.8),
      );
      expect(measuredWith([...regular(11), 125]).temporalStability, 1.0);
    });
  });
}
