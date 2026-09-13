import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// A transcript of notes played at the given performance times, null for a
/// note nothing could time. Observation time advances steadily throughout,
/// which is exactly what must not reach a wait.
PerformanceTranscript transcriptOf(List<int?> performanceTimesUs) {
  var transcript = PerformanceTranscript.empty;
  for (final (index, timeUs) in performanceTimesUs.indexed) {
    transcript = transcript.appending(
      pitch: SpelledPitch(letter: NoteLetter.c, octave: 4),
      timestampMs: index * 400,
      performanceTimeUs: timeUs,
    );
  }
  return transcript;
}

void main() {
  test('a fully timed run is one run of consecutive waits', () {
    final runs = timingRunsOf(transcriptOf([100000, 500000, 900000, 1200000]));

    expect(runs, hasLength(1));
    expect(runs.single.waitsUs, [400000, 400000, 300000]);
    expect(runs.single.waitCount, 3);
  });

  // The prohibition the helper exists for. Dropping the untimed note and
  // taking differences would report a 300 ms wait nobody played.
  test('a hole is not stitched shut', () {
    final runs = timingRunsOf(
      transcriptOf([100000, 200000, null, 500000, 600000, 700000]),
    );

    expect(runs.map((run) => run.waitsUs), [
      [100000],
      [100000, 100000],
    ]);
    expect(usableWaitsUsOf(transcriptOf([100000, 200000, null, 500000])), [
      100000,
    ]);
  });

  test('an untimed note costs both of the waits it sat between', () {
    expect(usableWaitsUsOf(transcriptOf([0, 100000, 200000])), hasLength(2));
    expect(usableWaitsUsOf(transcriptOf([0, null, 200000])), isEmpty);
  });

  // One delivery is one moment. A chord is several notes struck at once, and
  // the zeros between them are simultaneity rather than instant playing.
  test('notes sharing a performance time are one onset', () {
    final runs = timingRunsOf(
      transcriptOf([100000, 100000, 100000, 600000, 1100000]),
    );

    expect(runs.single.onsets.map((onset) => onset.notes), [3, 1, 1]);
    expect(runs.single.onsets.first.firstSequence, 0);
    expect(runs.single.waitsUs, [500000, 500000]);
  });

  test('a run of one onset contributes nothing', () {
    expect(timingRunsOf(transcriptOf([100000])), isEmpty);
    expect(timingRunsOf(transcriptOf([100000, 100000, 100000])), isEmpty);
    expect(usableWaitsUsOf(transcriptOf([null, 100000, null])), isEmpty);
  });

  test('a transcript nothing could time yields no waits', () {
    expect(timingRunsOf(transcriptOf([null, null, null])), isEmpty);
    expect(timingRunsOf(PerformanceTranscript.empty), isEmpty);
  });

  // Observation time is the wrong clock, and it is right there on every note.
  test('observation time never becomes a wait', () {
    final waits = usableWaitsUsOf(transcriptOf([100000, null, 300000, 400000]));

    expect(waits, [100000]);
    expect(waits, isNot(contains(400)));
  });

  test('a time that goes backward starts a new run', () {
    final runs = timingRunsOf(transcriptOf([100000, 200000, 50000, 150000]));

    expect(runs.map((run) => run.waitsUs), [
      [100000],
      [100000],
    ]);
  });
}
