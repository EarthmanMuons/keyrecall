import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// One moment of playing, on the instrument's own clock.
///
/// A chord reaches the transcript as several notes that were all struck at
/// once, because one delivery is one moment however many notes it normalizes
/// to. They are one onset here, so the zero between them cannot read as an
/// instant rhythmic wait.
///
/// Sameness is an equal performance time, which reads simultaneity at the
/// resolution of the clock that was authorized. The coarsest one characterized
/// so far resolves to a millisecond, so two genuinely separate strikes could
/// in principle share an onset. That is a property of the clock rather than of
/// this rule, and it is the reason the rule is stated in terms of what the
/// clock said rather than of what the player did.
///
/// It is not the same collapse alignment makes. Alignment reads one onset per
/// moment however far apart the hands landed, because that spread is
/// coordination. This reads two.
typedef TimedOnset = ({int performanceTimeUs, int firstSequence, int notes});

/// A stretch of playing whose timing can be trusted end to end.
///
/// The unit a timing metric may read waits from. Every wait inside a run is
/// the difference between two performance times that belong to one continuous
/// timeline, so nothing here was reconstructed across a hole.
@immutable
class TimingRun {
  /// The moments in this run, in the order they were played.
  final List<TimedOnset> onsets;

  TimingRun(List<TimedOnset> onsets) : onsets = List.unmodifiable(onsets);

  /// The waits between consecutive moments, in microseconds.
  ///
  /// One fewer than there are moments, which is why a run of one contributes
  /// nothing: timing is read from waits, and a single onset has none.
  List<int> get waitsUs => [
    for (var index = 1; index < onsets.length; index++)
      onsets[index].performanceTimeUs - onsets[index - 1].performanceTimeUs,
  ];

  /// How many waits this run contributes.
  int get waitCount => onsets.isEmpty ? 0 : onsets.length - 1;

  @override
  String toString() => 'TimingRun(${onsets.length} onsets, $waitCount waits)';
}

/// The stretches of [transcript] whose timing can be trusted, as a single
/// stream of notes.
///
/// A characterization helper, not the production definition of a timing run:
/// production reads runs over aligned musical moments, where alignment has
/// already said which notes realized one. This sees notes, so it treats every
/// untimed note as a boundary and every equal-timed pair as one onset, which is
/// the right reading of a transcript and a stricter one than the metrics use.
/// See `docs/decisions/evidence-and-measurement.md`.
///
/// A note with no performance time ends the run it falls in and belongs to no
/// run, so the two waits it would have been part of are both lost and neither
/// is replaced by the wait across it. That last part is the whole point:
/// dropping the untimed notes first and then taking differences would stitch a
/// hole shut and report a wait nobody played.
///
/// An observation boundary does not appear here because it cannot: a reset or
/// an integrity fault closes the capture, so the notes on either side of one
/// are never in the same transcript.
List<TimingRun> timingRunsOf(PerformanceTranscript transcript) {
  final runs = <TimingRun>[];
  var onsets = <TimedOnset>[];

  void endRun() {
    if (onsets.length > 1) runs.add(TimingRun(onsets));
    onsets = [];
  }

  for (final note in transcript.notes) {
    final timeUs = note.performanceTimeUs;
    if (timeUs == null) {
      endRun();
      continue;
    }
    final last = onsets.isEmpty ? null : onsets.last;
    if (last == null) {
      onsets.add((
        performanceTimeUs: timeUs,
        firstSequence: note.sequence,
        notes: 1,
      ));
      continue;
    }
    if (timeUs == last.performanceTimeUs) {
      onsets.last = (
        performanceTimeUs: last.performanceTimeUs,
        firstSequence: last.firstSequence,
        notes: last.notes + 1,
      );
      continue;
    }
    // A timeline only runs forward. A time that went backward cannot be the
    // same one the moment before it was read from, so this is a new run rather
    // than a negative wait.
    if (timeUs < last.performanceTimeUs) {
      endRun();
    }
    onsets.add((
      performanceTimeUs: timeUs,
      firstSequence: note.sequence,
      notes: 1,
    ));
  }
  endRun();

  return List.unmodifiable(runs);
}

/// Every wait in [transcript] that a timing metric may read.
///
/// Flattened across runs, which is safe only because no wait spans two of
/// them. The count is the denominator an assessability floor belongs in: six
/// timed notes in one run are five waits, and in two runs fewer.
List<int> usableWaitsUsOf(PerformanceTranscript transcript) => [
  for (final run in timingRunsOf(transcript)) ...run.waitsUs,
];
