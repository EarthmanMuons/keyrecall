import 'dart:math' as math;

import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';

/// The wait between two moments that arrived, and which two.
///
/// Named by both ends because a moment nothing arrived for leaves no onset, so
/// consecutive gaps are not always consecutive positions. A gap spanning a
/// skipped moment covers a stretch of the exercise rather than one transition.
///
/// [ratio] is the wait against this performance's own pace, or null when the
/// performance supplied too little unbroken playing for an interruption to
/// mean anything. An observed gap with no ratio is a transition that happened
/// and was not judged.
typedef MomentGap = ({
  int fromPosition,
  int toPosition,
  int gapMs,
  double? ratio,
});

/// The fewest waits a pace can be read from.
///
/// One wait is an interval, not a pace. Two supply no center either one
/// cannot dominate. Three are the first that let a median set one of them
/// aside.
const int fewestWaitsForPace = 3;

/// The fewest waits a spread can be read from.
///
/// Below this a single wait carries too much of the deviation for the result
/// to describe the playing rather than that wait.
const int fewestWaitsForSpread = 5;

/// The fewest waits in one unbroken stretch a continuity claim needs.
///
/// Continuity is a claim about playing that did not stop, so it asks for a
/// stretch that did not stop rather than for waits gathered from wherever they
/// survived. Eight waits in one run and in four runs of two are the same
/// arithmetic and not the same evidence, and only the first can support this.
const int fewestContiguousWaitsForContinuity = 5;

/// How the playing sat in time, and how much of that could be judged.
///
/// Three separate questions, and the type exists so that measurement,
/// acquisition, and the transition census cannot answer them differently:
///
/// - which waits happened, which [gaps] always reports;
/// - how fast the playing went, which [paceMs] answers;
/// - which waits were interruptions of that pace and how far the rest spread
///   around it, which [worstRatio] and [dispersion] answer.
///
/// Two references, because the questions are different. The pace is the median
/// wait, which is what the playing usually did. Interruption is judged against
/// the slow end of ordinary playing, taken as the upper quartile of the waits
/// with the longest one left out.
///
/// Leaving it out is what keeps the longest wait from setting the bar it is
/// measured against. Without that, a quarter of the waits stopping made the
/// stops the ordinary playing, and a performance that broke four times in
/// fourteen read as 0.96 unbroken. Judging against the median instead would
/// fix that case and break another: playing that alternates 400 and 1600 ms
/// has a median of 400, so every slow wait would read as an interruption and
/// the unevenness would vanish from the spread.
///
/// Facts only. What a dispersion or a ratio is worth is a policy's judgment,
/// and it stays outside this type.
@immutable
class TimingEvidence {
  /// Every wait between consecutive moments that arrived, as played.
  final List<MomentGap> gaps;

  /// How fast the playing went, in milliseconds per wait, or null below
  /// [fewestWaitsForPace].
  ///
  /// The median wait. Relative to the learner's own playing rather than to a
  /// requested tempo, so it reads the same whether they play fast or slowly.
  final double? paceMs;

  /// The slow end of ordinary playing, in milliseconds, or null when
  /// continuity was not judged.
  ///
  /// The upper quartile of the waits with the longest one left out, so that no
  /// wait helps set the bar it is judged against. What a ratio here is a
  /// multiple of, and what separates a stop from playing that is merely slow.
  final double? referenceMs;

  /// Spread of the waits that were not interruptions, or null below
  /// [fewestWaitsForSpread].
  ///
  /// Their mean absolute deviation from their median, over that median. It
  /// answers to every wait rather than to the quartiles, so a single rushed
  /// wait among steady ones moves it, which an interquartile range does not.
  /// Interruptions are left out because a stop is not unsteady playing, and
  /// continuity is where it is already accounted for.
  final double? dispersion;

  /// The longest wait as a multiple of [paceMs], or null when no stretch of
  /// unbroken playing was long enough to judge one.
  final double? worstRatio;

  /// The waits in the longest stretch with nothing missing from it.
  ///
  /// Provenance for [worstRatio]: what continuity was read from, and why it is
  /// absent when it is.
  final int longestRunWaits;

  /// Where the longest wait ended, as a realization position, or null when
  /// continuity was not judged.
  ///
  /// The moment [worstRatio] is about. A wait is a gap rather than a note, so
  /// the moment that ended it is where playing resumed.
  final int? longestGapBeforePosition;

  TimingEvidence._({
    required List<MomentGap> gaps,
    required this.paceMs,
    required this.referenceMs,
    required this.dispersion,
    required this.worstRatio,
    required this.longestRunWaits,
    required this.longestGapBeforePosition,
  }) : gaps = List.unmodifiable(gaps);

  /// Reads the timing of [alignment], whose correspondence is already settled.
  ///
  /// [restartPositions] names positions the task lets the learner begin again
  /// at. The wait before one of those is the reset the task asked for, so it is
  /// neither reported nor allowed into the pace the others are read against,
  /// and it ends the unbroken stretch continuity is read from.
  factory TimingEvidence.of(
    Alignment alignment, {
    Set<int> restartPositions = const {},
    MeasurementPolicy policy = MeasurementPolicy.standard,
  }) {
    final onsets = _momentOnsets(alignment);
    final spans = [
      for (var i = 1; i < onsets.length; i++)
        if (!restartPositions.any(
          (start) =>
              onsets[i - 1].position < start && start <= onsets[i].position,
        ))
          (
            from: onsets[i - 1].position,
            to: onsets[i].position,
            intervalMs: onsets[i].onsetMs - onsets[i - 1].onsetMs,
          ),
    ];
    final waits = [for (final span in spans) span.intervalMs];
    final pace = _paceOf(waits);
    final reference = _referenceOf(waits);
    final longestRun = _longestRunOf(spans);
    final judged =
        reference != null && longestRun >= fewestContiguousWaitsForContinuity;

    return TimingEvidence._(
      gaps: [
        for (final span in spans)
          (
            fromPosition: span.from,
            toPosition: span.to,
            gapMs: span.intervalMs.round(),
            ratio: judged ? span.intervalMs / reference : null,
          ),
      ],
      paceMs: pace,
      referenceMs: judged ? reference : null,
      dispersion: _dispersionOf(waits, reference, policy),
      worstRatio: judged ? waits.reduce(math.max) / reference : null,
      longestRunWaits: longestRun,
      longestGapBeforePosition: judged
          ? spans.reduce((a, b) => b.intervalMs > a.intervalMs ? b : a).to
          : null,
    );
  }

  /// The gaps whose waits were judged against the pace.
  ///
  /// What a stall rate can be read from, and empty whenever the performance
  /// supplied no stretch long enough to judge one.
  List<MomentGap> get assessableGaps => [
    for (final gap in gaps)
      if (gap.ratio != null) gap,
  ];

  /// Whether the playing supplied a pace.
  bool get hasPace => paceMs != null;

  /// Whether it supplied enough unbroken playing to say whether it stopped.
  bool get isContinuityAssessable => worstRatio != null;

  @override
  String toString() =>
      'TimingEvidence(${gaps.length} gaps, '
      '${hasPace ? 'pace ${paceMs!.round()}ms' : 'no pace'}, '
      'longest run $longestRunWaits)';
}

/// How fast the playing went, or null when too few waits arrived to say.
///
/// Zero when the playing was instantaneous, which nothing can be read against,
/// so that reads as no pace either.
double? _paceOf(List<double> waits) {
  if (waits.length < fewestWaitsForPace) return null;
  final pace = _median(waits);
  return pace <= 0 ? null : pace;
}

/// The slow end of ordinary playing, or null when there is none to read.
///
/// The upper quartile of every wait but the longest, so the wait being judged
/// is never part of what judges it.
double? _referenceOf(List<double> waits) {
  if (waits.length < 2) return null;
  final rest = [...waits]..sort();
  rest.removeLast();
  final reference = _quantileOf(rest, 0.75);
  return reference <= 0 ? null : reference;
}

/// How far the ordinary waits sat from each other, or null when too few
/// arrived or there is nothing to call a wait ordinary against.
///
/// Interruptions are set aside first: a stop is not unsteady playing, and
/// leaving it in would let one pause read as a performance that never settled.
double? _dispersionOf(
  List<double> waits,
  double? reference,
  MeasurementPolicy policy,
) {
  if (reference == null || waits.length < fewestWaitsForSpread) return null;
  final ordinary = [
    for (final wait in waits)
      if (wait < policy.interruptionRatio * reference) wait,
  ];
  if (ordinary.isEmpty) return null;
  final middle = _median(ordinary);
  if (middle <= 0) return null;
  var deviation = 0.0;
  for (final wait in ordinary) {
    deviation += (wait - middle).abs();
  }
  return deviation / ordinary.length / middle;
}

/// The most waits in a row that are one stretch of playing.
///
/// Every wait here qualifies, because the two things that remove one do not
/// break the playing. A moment nothing arrived for widens the wait around it
/// rather than splitting it, and the reset before a repeat is a boundary the
/// task asked for rather than evidence that went missing: the learner played
/// on either side of it and only the turnaround is not theirs to be judged on.
///
/// A hole in the timing itself is the break this exists to notice, and the
/// clock that can produce one does not reach here yet.
int _longestRunOf(List<({int from, int to, double intervalMs})> spans) =>
    spans.length;

/// When the moments that were played happened.
///
/// One onset per moment, so the gap between the hands of one moment is not a
/// wait and cannot read as an unsteady tempo.
///
/// Both kinds of correspondence count, so pitch correctness cannot reach the
/// timing scores: leaving substitutions out would let an octave slip played
/// exactly on the beat read as a pause.
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

/// The value [fraction] of the way through [ordered], linearly interpolated.
///
/// Interpolated rather than picking an index, which is not the same statistic
/// at every length: that index lands on the 23rd percentile over fourteen
/// waits and the 17th over seven, so exercise length would change what the
/// reference means.
double _quantileOf(List<double> ordered, double fraction) {
  if (ordered.length == 1) return ordered.first;
  final position = fraction * (ordered.length - 1);
  final below = position.floor();
  final above = position.ceil();
  if (below == above) return ordered[below];
  return ordered[below] +
      (ordered[above] - ordered[below]) * (position - below);
}

double _median(List<double> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}
