import 'dart:math' as math;

import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:meta/meta.dart';

/// The wait between two moments that arrived, and which two.
///
/// Named by both ends because a moment nothing arrived for leaves no onset, so
/// consecutive gaps are not always consecutive positions. A gap spanning a
/// skipped moment covers a stretch of the exercise rather than one transition.
///
/// [ratio] is the wait against the slow end of this performance's own playing,
/// or null when the performance supplied too few waits to have a slow end. An
/// observed gap with no ratio is a transition that happened and was not judged.
typedef MomentGap = ({
  int fromPosition,
  int toPosition,
  int gapMs,
  double? ratio,
});

/// The fewest gaps a baseline can be read from.
///
/// The quartiles are interpolated, and at five gaps the upper one first lands
/// below the longest gap and the lower one above the shortest. With fewer, the
/// baseline includes the gap being judged against it, so the longest wait is
/// measured partly against itself and the absence of a break means nothing.
/// Material short of it supplies more waits rather than being read against a
/// lower bar.
const int fewestGapsForTimingBaseline = 5;

/// How the playing sat in time, and how much of that could be judged.
///
/// Three separate questions, and the type exists so that measurement,
/// acquisition, and the transition census cannot answer them differently:
///
/// - which waits happened, which [gaps] always reports;
/// - whether this performance established a slow end of its own ordinary
///   playing, which [baselineMs] answers;
/// - what the waits mean against that baseline, which every ratio here is
///   absent without.
///
/// Facts only. What a dispersion or a ratio is worth is a policy's judgment,
/// and it stays outside this type.
@immutable
class TimingEvidence {
  /// Every wait between consecutive moments that arrived, as played.
  final List<MomentGap> gaps;

  /// The slow end of this performance's own playing, in milliseconds, or null
  /// when too few gaps arrived to establish one.
  ///
  /// The upper quartile of the gaps. Relative to the learner's own playing
  /// rather than to a requested tempo, so it reads the same whether they play
  /// fast or slowly.
  final double? baselineMs;

  /// How long a wait usually was, in milliseconds, or null when none arrived.
  ///
  /// Needs no baseline, since nothing is being judged against the rest.
  final double? medianGapMs;

  /// Spread of the waits, as an interquartile range over the median, or null
  /// without a baseline.
  final double? dispersion;

  /// The longest wait as a multiple of [baselineMs], or null without one.
  final double? worstRatio;

  /// Where the longest wait ended, as a realization position, or null without a
  /// baseline.
  ///
  /// The moment [worstRatio] is about. A wait is a gap rather than a note, so
  /// the moment that ended it is where playing resumed.
  final int? longestGapBeforePosition;

  TimingEvidence._({
    required List<MomentGap> gaps,
    required this.baselineMs,
    required this.medianGapMs,
    required this.dispersion,
    required this.worstRatio,
    required this.longestGapBeforePosition,
  }) : gaps = List.unmodifiable(gaps);

  /// Reads the timing of [alignment], whose correspondence is already settled.
  ///
  /// [restartPositions] names positions the task lets the learner begin again
  /// at. The wait before one of those is the reset the task asked for, so it is
  /// neither reported nor allowed into the baseline the others are read
  /// against.
  factory TimingEvidence.of(
    Alignment alignment, {
    Set<int> restartPositions = const {},
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
    final median = waits.isEmpty ? null : _median(waits);
    final baseline = _baselineOf(waits);

    return TimingEvidence._(
      gaps: [
        for (final span in spans)
          (
            fromPosition: span.from,
            toPosition: span.to,
            gapMs: span.intervalMs.round(),
            ratio: baseline == null ? null : span.intervalMs / baseline,
          ),
      ],
      baselineMs: baseline,
      medianGapMs: median,
      dispersion: baseline == null || median == null || median <= 0
          ? null
          : (baseline - _quantileOf([...waits]..sort(), 0.25)) / median,
      worstRatio: baseline == null ? null : waits.reduce(math.max) / baseline,
      longestGapBeforePosition: baseline == null
          ? null
          : spans.reduce((a, b) => b.intervalMs > a.intervalMs ? b : a).to,
    );
  }

  /// The gaps whose waits were judged against a baseline.
  ///
  /// What a stall rate can be read from, and fewer than [gaps] whenever the
  /// performance was too short to establish one.
  List<MomentGap> get assessableGaps => [
    for (final gap in gaps)
      if (gap.ratio != null) gap,
  ];

  /// Whether the waits were judged at all.
  bool get isAssessable => baselineMs != null;

  @override
  String toString() =>
      'TimingEvidence(${gaps.length} gaps, '
      '${isAssessable ? 'baseline ${baselineMs!.round()}ms' : 'no baseline'})';
}

/// The slow end of ordinary playing among [waits], or null when too few.
///
/// Zero when the playing was instantaneous, which nothing can be read against,
/// so that reads as no baseline either.
double? _baselineOf(List<double> waits) {
  if (waits.length < fewestGapsForTimingBaseline) return null;
  final high = _quantileOf([...waits]..sort(), 0.75);
  return high <= 0 ? null : high;
}

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
/// Interpolated rather than picking `ordered[n ~/ 4]`, which is not the same
/// statistic at every length: that index lands on the 23rd percentile over
/// fourteen waits and the 17th over seven, so exercise length would change what
/// dispersion means.
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
