import 'dart:math' as math;

import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';

/// How far apart the hands were at one moment, and which moment.
typedef HandAsynchrony = ({int position, int asynchronyMs});

/// What was observed about one performance.
///
/// Facts first: how much of the material appeared, how much of it was the
/// right pitch, how much of it was the right scale degree, and how the playing
/// sat in time. What any of that means for a competency is [toOutcome]'s job,
/// and what it means for the learner is the model's.
///
/// Alignment settles which played note corresponds to which expected one using
/// pitch alone. Timing is read afterwards, off notes whose correspondence is
/// already settled, so a performance played at a different speed aligns
/// identically and measures differently.
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
  /// The series coordination is read from. Moments where a hand played nothing
  /// are absent rather than zero, and so is a moment the two hands meet on one
  /// key, which the instrument reports as one onset. The length is therefore
  /// what was measurable rather than what was asked for.
  ///
  /// Positions travel with the values because where the hands were apart is a
  /// different question from how far apart they got, and a summary that keeps
  /// only the widest cannot answer it.
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

  /// Spread of the gaps between the moments that were played, as an
  /// interquartile range over the median, or null when too few arrived.
  final double? dispersion;

  /// The largest gap between played moments, as a multiple of the upper
  /// quartile, or null when too few arrived.
  final double? worstIntervalRatio;

  /// The median gap between played moments in milliseconds, or null.
  final int? medianIntervalMs;

  /// Where the longest gap between played moments ended, as a realization
  /// position, or null when too few arrived.
  ///
  /// The moment [worstIntervalRatio] is about. A break is a gap rather than a
  /// note, and the moment that ended it is the one a learner can be pointed
  /// at: it is where playing resumed.
  final int? longestGapBeforePosition;

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
    required this.policy,
    this.dispersion,
    this.worstIntervalRatio,
    this.medianIntervalMs,
    this.longestGapBeforePosition,
    this.widestAsynchronyAtPosition,
  }) : handAsynchronies = List.unmodifiable(handAsynchronies);

  /// Whether anything was played at all.
  bool get started =>
      alignment.noteEdits.any((positioned) => positioned.edit is! Deletion);

  /// Whether every expected note eventually arrived.
  ///
  /// Stronger than reaching the final note, which an attempt can do while
  /// having skipped something in the middle. Alignment is what makes the
  /// stronger reading available.
  bool get completed => reading.isComplete;

  /// Whether the learner produced the intended scale independently and on the
  /// first traversal.
  ///
  /// Register-insensitive: landing an octave away is a wrong sounded pitch and
  /// a right scale degree, and factual scale memory is about the degrees.
  /// Repeats are exempt unless the policy says otherwise, since replaying the
  /// note just played is producing the right material twice rather than
  /// producing the wrong material.
  ///
  /// Categorical on purpose. The continuous channels carry how well it went;
  /// putting a threshold here would make two nearly identical performances
  /// move the memory clock in opposite directions.
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

  /// How unbroken the playing was, in `[0, 1]`.
  ///
  /// Reacts to one interruption rather than to overall spread: a steady
  /// performance with a single long pause scores badly here and may still be
  /// stable.
  double get continuity => worstIntervalRatio == null
      ? 0
      : policy.unbrokennessOf(worstIntervalRatio!);

  /// How steady the playing was, in `[0, 1]`.
  ///
  /// Reacts to spread across the traversal rather than to one gap: a
  /// performance that alternates fast and slow scores badly here without ever
  /// stopping.
  double get temporalStability =>
      dispersion == null ? 0 : policy.steadinessOf(dispersion!);

  /// The measured spreads alone, in the order they were played.
  List<int> get handAsynchroniesMs => [
    for (final moment in handAsynchronies) moment.asynchronyMs,
  ];

  /// The moments the hands were further apart than the policy calls together.
  ///
  /// What a claim about where coordination went is allowed to rest on. A
  /// series can have a widest moment without having a loose one.
  List<HandAsynchrony> get looseMoments => [
    for (final moment in handAsynchronies)
      if (moment.asynchronyMs.abs() > policy.synchronizedAsynchronyMs) moment,
  ];

  /// Moments both hands corresponded at, which is what coordination was read
  /// from.
  ///
  /// Provenance rather than a score: a coordination reading off one moment and
  /// off thirty are not the same evidence.
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
  /// Descriptive, and deliberately not evidence. Across the recorded takes the
  /// left hand led 8 of 12 in one and 2 of 12 in another, so which hand starts
  /// a moment is a fact about a performance rather than a fault in it.
  double? get signedMedianHandAsynchronyMs => handAsynchroniesMs.isEmpty
      ? null
      : _median([for (final gap in handAsynchroniesMs) gap.toDouble()]);

  /// How together the hands were, in `[0, 1]`, or null when nothing measured
  /// it.
  ///
  /// Null and zero are different claims. Zero says the hands were as far apart
  /// as playing gets; null says no moment had both hands, which is every
  /// single-hand performance.
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
  /// only the speed shows up. Recorded, not consumed; when it is, it should
  /// set the difficulty the execution evidence is attributed at rather than
  /// damp the motor score. See `docs/design/future-planning.md`.
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
      case Insertion(:final observed):
        if (_isRepeat(observed, edits, index, realization)) {
          repeats++;
        } else {
          intrusions++;
        }
      case Deletion():
        break;
    }
  }

  final onsets = _momentOnsets(alignment);
  final intervals = [
    for (var i = 1; i < onsets.length; i++)
      onsets[i].onsetMs - onsets[i - 1].onsetMs,
  ];
  final longestGap = _longestGapIndexOf(intervals);

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
    dispersion: _dispersionOf(intervals),
    worstIntervalRatio: _worstRatioOf(intervals),
    medianIntervalMs: intervals.isEmpty ? null : _median(intervals).round(),
    longestGapBeforePosition: longestGap == null
        ? null
        : onsets[longestGap + 1].position,
    widestAsynchronyAtPosition: _widestAsynchronyPositionOf(alignment),
    policy: policy,
  );
}

/// Whether an extra note is the material on either side of it, played again.
///
/// Structural rather than attributed: a repetition of the note the performance
/// is currently on, before it moves past that note. Which side of the matching
/// note the extra one lands on is an artifact of the traceback, not something
/// the learner did, so both count.
bool _isRepeat(
  SpelledPitch observed,
  List<PositionedNoteEdit> edits,
  int index,
  ExerciseRealization realization,
) {
  for (final neighbor in [index - 1, index + 1]) {
    if (neighbor < 0 || neighbor >= edits.length) continue;
    final (:realizationPosition, :edit) = edits[neighbor];
    final hands = switch (edit) {
      Match(:final hands) => hands,
      Substitution(:final hands) => hands,
      _ => null,
    };
    if (hands == null) continue;
    // Any of them finds the same note: a note two hands meet on is one note.
    final expected = realization.moments[realizationPosition!].noteFor(
      hands.first,
    )!;
    if (expected.pitch.pitchClass == observed.pitchClass) return true;
  }
  return false;
}

/// How many notes the realization asks for, over all its moments.
int expectedNotesIn(ExerciseRealization realization) =>
    realization.moments.fold(0, (total, moment) => total + moment.notes.length);

/// When the moments that were played happened.
///
/// One onset per moment, so the gap between the hands of one moment is not an
/// interval and cannot read as an unsteady tempo.
///
/// Both kinds of correspondence count. A substituted note is still the event
/// the learner produced for a note the exercise asked for, and leaving it out
/// would let a wrong pitch manufacture a gap: an octave slip played exactly on
/// the beat would read as a pause. Pitch correctness must not reach the timing
/// scores by any route.
///
/// A moment nothing arrived for has no onset, and a moment whose observations
/// were all extra corresponds to no expected note, so neither appears.
List<({int position, double onsetMs})> _momentOnsets(Alignment alignment) => [
  for (final operation in alignment.operations)
    if (operation case MomentCorrespondence(
      :final realizationPosition,
      :final onsetMs,
      :final noteEdits,
    ))
      if (noteEdits.any((edit) => edit is Match || edit is Substitution))
        (position: realizationPosition, onsetMs: onsetMs),
];

/// Which interval was the longest, or null when there are too few to compare.
///
/// Gated the same way [_worstRatioOf] is, because it is that ratio's location
/// and the two must not disagree about whether there was a worst gap at all.
int? _longestGapIndexOf(List<double> intervals) {
  if (intervals.length < _fewestIntervals) return null;
  var longest = 0;
  for (var i = 1; i < intervals.length; i++) {
    if (intervals[i] > intervals[longest]) longest = i;
  }
  return longest;
}

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

/// Three matched notes is the fewest that can have a spread at all.
const int _fewestIntervals = 2;

/// Spread that one outlier cannot manufacture.
double? _dispersionOf(List<double> intervals) {
  if (intervals.length < _fewestIntervals) return null;
  final median = _median(intervals);
  if (median <= 0) return null;
  final (low, high) = _quartilesOf(intervals);
  return (high - low) / median;
}

/// The longest gap against the slow end of ordinary playing, so a performance
/// that is merely uneven does not read as one that stopped.
double? _worstRatioOf(List<double> intervals) {
  if (intervals.length < _fewestIntervals) return null;
  final (_, high) = _quartilesOf(intervals);
  if (high <= 0) return null;
  return intervals.reduce(math.max) / high;
}

/// The lower and upper quartiles, interpolated between the values either side.
///
/// Interpolated rather than picking `ordered[n ~/ 4]`, which is not the same
/// statistic at every length: on the fourteen intervals of a one-octave
/// traversal that index lands on the 23rd percentile, and on the seven of an
/// ascending one it lands on the 17th, so exercise length changed what
/// dispersion meant before any playing was considered. Calibration takes
/// measured that inflation at 1.3x on seven intervals and 1.1x on fourteen.
(double, double) _quartilesOf(List<double> values) {
  final ordered = [...values]..sort();
  return (_quantileOf(ordered, 0.25), _quantileOf(ordered, 0.75));
}

/// The value [fraction] of the way through [ordered], linearly interpolated.
double _quantileOf(List<double> ordered, double fraction) {
  if (ordered.length == 1) return ordered.first;
  final position = fraction * (ordered.length - 1);
  final below = position.floor();
  final above = position.ceil();
  if (below == above) return ordered[below];
  return ordered[below] +
      (ordered[above] - ordered[below]) * (position - below);
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
