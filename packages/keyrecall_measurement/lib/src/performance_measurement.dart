import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';
import 'timing_evidence.dart';

/// How far apart the hands were at one moment, and which moment.
typedef HandAsynchrony = ({int position, int asynchronyMs});

/// What was observed about one performance.
///
/// Facts only: how much of the material appeared, how much of it was the right
/// pitch, how much of it was the right scale degree, and how the playing sat in
/// time. What any of that means for a competency is `outcomeFor`'s job.
///
/// Correspondence is settled before any of this is read, and timing is read
/// afterwards off notes whose correspondence is already fixed, so the same notes
/// at a different speed measure differently through the same channels. See the
/// package README on what that does and does not promise about timing.
@immutable
class PerformanceMeasurement {
  /// The correspondence this reads.
  final Alignment alignment;

  /// How the observations relate to the exercise, one layer up.
  final AlignmentReading reading;

  /// How many notes were asked for, counting each hand's separately.
  final int expectedNotes;

  /// How many moments were asked for.
  final int expectedMoments;

  /// How far apart the hands were at each moment both of them corresponded to
  /// something that arrived, as right minus left, and where.
  ///
  /// The series coordination is read from. A moment where a hand played nothing
  /// is absent rather than zero, as is one the hands meet on, so the length is
  /// what was measurable rather than what was asked for. Positions travel with
  /// the values because where the hands were apart is a separate question from
  /// how far apart they got.
  final List<HandAsynchrony> handAsynchronies;

  /// Expected notes that arrived at all, whatever octave they sounded in.
  final int materialProduced;

  /// Expected notes sounded exactly as written.
  final int soundedCorrectly;

  /// Expected notes whose scale degree was right, octave aside.
  final int degreesCorrect;

  /// Extra notes that were the previous expected note played again.
  final int repeats;

  /// Extra notes that were something else.
  final int intrusions;

  /// How the playing sat in time, and how much of that could be judged.
  final TimingEvidence timing;

  /// Where the hands were furthest apart, as a realization position, or null
  /// when no moment had both.
  final int? widestAsynchronyAtPosition;

  /// What the policy was.
  final MeasurementPolicy policy;

  PerformanceMeasurement({
    required this.alignment,
    required this.reading,
    required this.expectedNotes,
    required this.expectedMoments,
    required List<HandAsynchrony> handAsynchronies,
    required this.materialProduced,
    required this.soundedCorrectly,
    required this.degreesCorrect,
    required this.repeats,
    required this.intrusions,
    required this.timing,
    required this.policy,
    this.widestAsynchronyAtPosition,
  }) : handAsynchronies = List.unmodifiable(handAsynchronies);

  /// Spread of the gaps between the moments that were played, as an
  /// interquartile range over the median, or null when the performance
  /// established no baseline to read them against.
  double? get dispersion => timing.dispersion;

  /// The largest gap between played moments, as a multiple of the slow end of
  /// this performance's own playing, or null without a baseline.
  double? get worstIntervalRatio => timing.worstRatio;

  /// The median gap between played moments in milliseconds, or null when none
  /// arrived.
  int? get medianIntervalMs => timing.medianGapMs?.round();

  /// Where the longest gap between played moments ended, as a realization
  /// position, or null without a baseline.
  int? get longestGapBeforePosition => timing.longestGapBeforePosition;

  /// Whether anything was played at all.
  bool get started =>
      alignment.noteEdits.any((positioned) => positioned.edit is! Deletion);

  /// Whether every expected note eventually arrived.
  ///
  /// Stronger than reaching the final note, which an attempt can do while
  /// having skipped something in the middle.
  bool get completed => reading.isComplete;

  /// Whether the learner produced the intended scale independently and on the
  /// first traversal.
  ///
  /// Register-insensitive, because factual scale memory is about the degrees.
  /// Repeats are exempt unless the policy says otherwise.
  ///
  /// Categorical: the continuous channels carry how well it went, and a
  /// threshold here would make two near-identical performances move the memory
  /// clock in opposite directions.
  bool get retrievedIndependently =>
      degreesCorrect == expectedNotes &&
      intrusions == 0 &&
      (repeats == 0 || !policy.repeatedMatchedPitchBreaksRetrieval);

  /// How much of the material appeared, in `[0, 1]`.
  double get materialAppeared =>
      expectedNotes == 0 ? 0 : materialProduced / expectedNotes;

  /// How right the sounded pitches were, in `[0, 1]`.
  ///
  /// Counts every note the instrument produced, so extra notes cost something
  /// and an octave slip costs something.
  double get pitchIntegrity {
    final sounded = expectedNotes + repeats + intrusions;
    return sounded == 0 ? 0 : soundedCorrectly / sounded;
  }

  /// How right the scale's structure was, in `[0, 1]`.
  ///
  /// Octave-insensitive, and unaffected by extra notes that were the right
  /// degree played again.
  double get topologyAccuracy {
    final degrees = expectedNotes + intrusions;
    return degrees == 0 ? 0 : degreesCorrect / degrees;
  }

  /// How unbroken the playing was, in `[0, 1]`, or null when nothing measured
  /// it.
  ///
  /// Reacts to one interruption rather than to overall spread: a steady
  /// performance with a single long pause scores badly here and may still be
  /// stable.
  ///
  /// Null and zero are different claims: zero says the playing stopped, null
  /// that the performance supplied too few waits to judge one against the
  /// others. Scoring a two-note performance would measure its single wait
  /// against itself.
  double? get continuity => switch (worstIntervalRatio) {
    final ratio? => policy.unbrokennessOf(ratio),
    null => null,
  };

  /// How steady the playing was, in `[0, 1]`, or null when nothing measured it.
  ///
  /// Reacts to spread across the traversal rather than to one gap: a
  /// performance that alternates fast and slow scores badly here without ever
  /// stopping.
  ///
  /// Absent on the same grounds as [continuity], and separately, so a future
  /// spread estimator that needs different evidence can say so here.
  double? get temporalStability => switch (dispersion) {
    final spread? => policy.steadinessOf(spread),
    null => null,
  };

  /// The measured spreads alone, in the order they were played.
  List<int> get handAsynchroniesMs => [
    for (final moment in handAsynchronies) moment.asynchronyMs,
  ];

  /// The moments the hands were further apart than the policy calls together.
  ///
  /// What a claim about where coordination went rests on. A series can have a
  /// widest moment without having a loose one.
  List<HandAsynchrony> get looseMoments => [
    for (final moment in handAsynchronies)
      if (moment.asynchronyMs.abs() > policy.synchronizedAsynchronyMs) moment,
  ];

  /// Moments both hands corresponded at, which is what coordination was read
  /// from.
  ///
  /// Provenance rather than a score: coordination read off one moment and off
  /// thirty are not the same evidence.
  int get correspondedTwoHandMoments => handAsynchroniesMs.length;

  /// How far apart the hands usually were, in milliseconds, or null when no
  /// moment had both.
  double? get medianAbsoluteHandAsynchronyMs => handAsynchroniesMs.isEmpty
      ? null
      : _median([for (final gap in handAsynchroniesMs) gap.abs().toDouble()]);

  /// How far apart the hands got, in milliseconds, or null when no moment had
  /// both.
  ///
  /// The ninetieth percentile by nearest rank, so a short series reports its
  /// worst moment rather than interpolating one that did not happen.
  double? get p90AbsoluteHandAsynchronyMs => handAsynchroniesMs.isEmpty
      ? null
      : _nearestRank([
          for (final gap in handAsynchroniesMs) gap.abs().toDouble(),
        ], 0.9);

  /// Which hand usually led, as a signed median in milliseconds, or null when
  /// no moment had both.
  ///
  /// Descriptive, not evidence. Across the recorded takes the left hand led 8
  /// of 12 moments in one and 2 of 12 in another, so which hand starts a moment
  /// is a fact about a performance rather than a fault in it.
  double? get signedMedianHandAsynchronyMs => handAsynchroniesMs.isEmpty
      ? null
      : _median([for (final gap in handAsynchroniesMs) gap.toDouble()]);

  /// How together the hands were, in `[0, 1]`, or null when nothing measured
  /// it.
  ///
  /// Null and zero are different claims: zero says the hands were as far apart
  /// as playing gets, null that no moment had both.
  double? get coordination {
    final median = medianAbsoluteHandAsynchronyMs;
    final tail = p90AbsoluteHandAsynchronyMs;
    if (median == null || tail == null) return null;
    return policy.coordinationOf(medianMs: median, p90Ms: tail);
  }

  /// Achieved tempo as a fraction of what was asked for.
  ///
  /// Phase-free by construction: it compares the requested beat to the median
  /// gap between the learner's own notes, so starting late costs nothing and
  /// only the speed shows up. Recorded, not consumed. See
  /// `docs/roadmap.md`.
  double achievedTempoRatioFor(ExecutionConditions conditions) {
    final median = medianIntervalMs;
    if (median == null || median <= 0) return 0;
    final requested = 60000 / conditions.tempoBpm;
    return requested / median;
  }

  @override
  String toString() =>
      'PerformanceMeasurement($materialProduced/$expectedNotes produced, '
      '$intrusions intrusions, $repeats repeats)';
}

/// Measures [transcript] against what [realization] asked for.
///
/// Throws [ArgumentError] for material alignment cannot handle; see [align].
PerformanceMeasurement measure({
  required ExerciseRealization realization,
  required PerformanceTranscript transcript,
  MeasurementPolicy policy = MeasurementPolicy.standard,
  AlignmentPolicy alignmentPolicy = AlignmentPolicy.standard,
}) {
  final alignment = align(
    realization: realization,
    transcript: transcript,
    policy: alignmentPolicy,
  );

  final edits = alignment.noteEdits;
  final repeated = _repeatsIn(alignment, realization);
  var produced = 0;
  var sounded = 0;
  var degrees = 0;
  var repeats = 0;
  var intrusions = 0;

  for (final (index, positioned) in edits.indexed) {
    switch (positioned.edit) {
      case Match():
        produced++;
        sounded++;
        degrees++;
      case Substitution(:final kind):
        if (kind == SubstitutionKind.register) {
          produced++;
          degrees++;
        }
      case Insertion():
        if (repeated[index]) {
          repeats++;
        } else {
          intrusions++;
        }
      case Deletion():
        break;
    }
  }

  return PerformanceMeasurement(
    alignment: alignment,
    reading: AlignmentReading(alignment),
    expectedNotes: realization.noteCount,
    expectedMoments: realization.moments.length,
    handAsynchronies: [
      for (final operation in alignment.operations)
        if (operation case MomentCorrespondence(
          :final realizationPosition,
          handAsynchronyMs: final asynchrony?,
        ))
          (position: realizationPosition, asynchronyMs: asynchrony),
    ],
    materialProduced: produced,
    soundedCorrectly: sounded,
    degreesCorrect: degrees,
    repeats: repeats,
    intrusions: intrusions,
    timing: TimingEvidence.of(alignment),
    widestAsynchronyAtPosition: _widestAsynchronyPositionOf(alignment),
    policy: policy,
  );
}

/// Which extra notes are the material around them, played again.
///
/// Indexed the way [Alignment.noteEdits] is; false everywhere an edit is not
/// an extra note. Structural rather than attributed: a repetition of the note
/// the performance is on, before it moves past that note. What caused it is not
/// observable here.
///
/// Each contiguous run of extras is read once, against the moments on either
/// side of it rather than the note edits next to it. A moment is one event
/// however many hands realize it, so which of its arrivals the traceback left
/// adjacent says nothing about what was played again. Which side of the moment
/// the extras land on is an artifact of the traceback too, so both count.
///
/// Every note in a run is read on its own, which leaves a foreign note foreign
/// however many repetitions surround it.
List<bool> _repeatsIn(Alignment alignment, ExerciseRealization realization) {
  final edits = alignment.noteEdits;
  final owner = [
    for (final (index, operation) in alignment.operations.indexed)
      for (var n = 0; n < operation.noteEdits.length; n++) index,
  ];
  final repeated = List<bool>.filled(edits.length, false);

  var start = 0;
  while (start < edits.length) {
    if (edits[start].edit is! Insertion) {
      start++;
      continue;
    }
    var end = start;
    while (end + 1 < edits.length && edits[end + 1].edit is Insertion) {
      end++;
    }

    final anchors = <int>{
      if (start > 0)
        ..._repeatableClassesOf(
          alignment.operations[owner[start - 1]],
          realization,
        ),
      if (end + 1 < edits.length)
        ..._repeatableClassesOf(
          alignment.operations[owner[end + 1]],
          realization,
        ),
    };
    for (var index = start; index <= end; index++) {
      final observed = (edits[index].edit as Insertion).observed;
      repeated[index] = anchors.contains(observed.pitchClass);
    }

    start = end + 1;
  }

  return repeated;
}

/// The pitch classes an extra note beside [operation] could be repeating.
///
/// What the moment asked for, in every hand something arrived for. A note that
/// never arrived is not one the performance could be playing again, and a
/// moment nothing was expected at asks for nothing.
Set<int> _repeatableClassesOf(
  MomentOperation operation,
  ExerciseRealization realization,
) {
  if (operation.realizationPosition case final position?) {
    final moment = realization.moments[position];
    return {
      for (final edit in operation.noteEdits)
        if (edit case Match(:final hands) || Substitution(:final hands))
          // Any of them finds the same note: a note two hands meet on is one
          // note.
          moment.noteFor(hands.first)!.pitch.pitchClass,
    };
  }
  return const {};
}

/// How many notes the realization asks for, over all its moments.
int expectedNotesIn(ExerciseRealization realization) =>
    realization.moments.fold(0, (total, moment) => total + moment.notes.length);

/// Where the hands got furthest apart, or null when no moment had both.
int? _widestAsynchronyPositionOf(Alignment alignment) {
  int? widestPosition;
  var widest = -1;
  for (final operation in alignment.operations) {
    if (operation case MomentCorrespondence(
      :final realizationPosition,
      handAsynchronyMs: final asynchrony?,
    )) {
      if (asynchrony.abs() > widest) {
        widest = asynchrony.abs();
        widestPosition = realizationPosition;
      }
    }
  }
  return widestPosition;
}

/// The value at [fraction] of the way through [values] by nearest rank.
double _nearestRank(List<double> values, double fraction) {
  final ordered = [...values]..sort();
  final rank = (fraction * ordered.length).ceil() - 1;
  return ordered[rank.clamp(0, ordered.length - 1)];
}

double _median(List<double> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}
