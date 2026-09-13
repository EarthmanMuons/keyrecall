import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// What the timing metrics do as the evidence thins out.
///
/// Data rather than policy. The floors each metric should require are not set
/// here; this is what they would be set from. What the table shows:
///
/// - tempo has no floor at all. One wait is a median, and a median is a tempo.
/// - continuity and temporal stability are gated together at five waits by the
///   baseline they share, and say nothing below it.
/// - one pause among regular playing reads as broken at every length.
/// - several pauses stop reading as pauses, and not because the sample is
///   small. The baseline is the upper quartile of the same waits, so once more
///   than about a quarter of them are pauses the pauses become the ordinary
///   playing they are judged against. At fourteen waits, four of them stopped
///   playing still reads as 0.96 unbroken. More waits do not fix this; they
///   only raise the number of pauses it takes.
/// - a single wait much shorter than the rest is invisible to both metrics.
///   Nothing here reads rushing.
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
      'baseline=${(measured.timing.baselineMs?.round() ?? 0).toString().padLeft(5)} '
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

    // Nothing below the baseline floor makes a timing claim at all, so the
    // interesting question starts at five.
    test('no baseline is no claim', () {
      for (var waits = 1; waits < fewestGapsForTimingBaseline; waits++) {
        final measured = measuredWith(regular(waits));
        expect(measured.timing.baselineMs, isNull);
        expect(measured.continuity, isNull);
        expect(measured.temporalStability, isNull);
        expect(measured.medianIntervalMs, isNotNull);
      }
      expect(
        measuredWith(regular(fewestGapsForTimingBaseline)).continuity,
        isNotNull,
      );
    });

    // Tempo is on a different footing from the other two. It needs no baseline,
    // so a single wait produces one.
    test('tempo asks for nothing', () {
      final measured = measuredWith([500]);

      expect(measured.medianIntervalMs, 500);
      expect(
        measured.achievedTempoRatioFor(
          ExecutionConditions(hands: HandConfiguration.right, tempoBpm: 120),
        ),
        1.0,
      );
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

    // Where it turns over, as a proportion rather than a count. The upper
    // quartile sits at 0.75 * (waits - 1), so it lands inside the pauses once
    // there are more than about a quarter of them, whatever the length.
    test('the turn is a fraction of the waits, not a number of them', () {
      expect(measuredWith(withPauses(9, 2)).continuity, 0.0);
      expect(measuredWith(withPauses(9, 3)).continuity, 1.0);

      expect(measuredWith(withPauses(13, 3)).continuity, 0.0);
      expect(measuredWith(withPauses(13, 4)).continuity, 1.0);
    });

    // A quarter of the playing stopped, on the longest material there is, and
    // it reads as very nearly unbroken.
    test('length alone does not rescue it', () {
      final measured = measuredWith(withPauses(14, 4));

      expect(measured.continuity, greaterThan(0.9));
      expect(measured.temporalStability, 0.0);
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
        final measured = measuredWith([...regular(waits - 1), 125]);
        expect(measured.continuity, 1.0);
        expect(measured.temporalStability, 1.0);
      }
    });
  });
}
