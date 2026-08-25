import 'dart:math' as math;

import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'measurement_policy.dart';

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

  /// How many expected notes there were.
  final int expectedNotes;

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

  /// Spread of the gaps between the notes that correspond to expected ones, as
  /// an interquartile range over the median, or null when too few arrived.
  final double? dispersion;

  /// The largest gap between corresponding notes, as a multiple of the upper
  /// quartile, or null when too few arrived.
  final double? worstIntervalRatio;

  /// The median gap between corresponding notes in milliseconds, or null.
  final int? medianIntervalMs;

  /// What the policy was.
  final MeasurementPolicy policy;

  const PerformanceMeasurement({
    required this.alignment,
    required this.reading,
    required this.expectedNotes,
    required this.materialProduced,
    required this.soundedCorrectly,
    required this.degreesCorrect,
    required this.repeats,
    required this.intrusions,
    required this.policy,
    this.dispersion,
    this.worstIntervalRatio,
    this.medianIntervalMs,
  });

  /// Whether anything was played at all.
  bool get started =>
      alignment.operations.any((operation) => operation is! Deletion);

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

  var produced = 0;
  var sounded = 0;
  var degrees = 0;
  var repeats = 0;
  var intrusions = 0;

  for (final (index, operation) in alignment.operations.indexed) {
    switch (operation) {
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
        if (_isRepeat(observed, alignment.operations, index, realization)) {
          repeats++;
        } else {
          intrusions++;
        }
      case Deletion():
        break;
    }
  }

  final onsets = _correspondingOnsets(alignment, transcript);
  final intervals = [
    for (var i = 1; i < onsets.length; i++) onsets[i] - onsets[i - 1],
  ];

  return PerformanceMeasurement(
    alignment: alignment,
    reading: AlignmentReading(alignment),
    expectedNotes: realization.moments.length,
    materialProduced: produced,
    soundedCorrectly: sounded,
    degreesCorrect: degrees,
    repeats: repeats,
    intrusions: intrusions,
    dispersion: _dispersionOf(intervals),
    worstIntervalRatio: _worstRatioOf(intervals),
    medianIntervalMs: intervals.isEmpty ? null : _median(intervals).round(),
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
  List<EditOperation> operations,
  int index,
  ExerciseRealization realization,
) {
  for (final neighbour in [index - 1, index + 1]) {
    if (neighbour < 0 || neighbour >= operations.length) continue;
    final position = switch (operations[neighbour]) {
      Match(:final realizationPosition) => realizationPosition,
      Substitution(:final realizationPosition) => realizationPosition,
      _ => null,
    };
    if (position == null) continue;
    if (_expectedAt(realization, position).pitchClass == observed.pitchClass) {
      return true;
    }
  }
  return false;
}

SpelledPitch _expectedAt(ExerciseRealization realization, int position) =>
    realization.moments[position].notes.first.pitch;

/// When the notes that correspond to expected ones arrived.
///
/// Both kinds of correspondence count. A substituted note is still the event
/// the learner produced for a note the exercise asked for, and leaving it out
/// would let a wrong pitch manufacture a gap: an octave slip played exactly on
/// the beat would read as a pause. Pitch correctness must not reach the timing
/// scores by any route.
///
/// Insertions correspond to no expected note, and deletions have no onset at
/// all, so neither appears.
List<int> _correspondingOnsets(
  Alignment alignment,
  PerformanceTranscript transcript,
) {
  final bySequence = {
    for (final note in transcript.notes) note.sequence: note.timestampMs,
  };
  return [
    for (final operation in alignment.operations)
      if (operation
          case Match(:final transcriptSequence) ||
              Substitution(:final transcriptSequence))
        bySequence[transcriptSequence]!,
  ];
}

/// Three matched notes is the fewest that can have a spread at all.
const int _fewestIntervals = 2;

/// Spread that one outlier cannot manufacture.
double? _dispersionOf(List<int> intervals) {
  if (intervals.length < _fewestIntervals) return null;
  final median = _median(intervals);
  if (median <= 0) return null;
  final (low, high) = _quartilesOf(intervals);
  return (high - low) / median;
}

/// The longest gap against the slow end of ordinary playing, so a performance
/// that is merely uneven does not read as one that stopped.
double? _worstRatioOf(List<int> intervals) {
  if (intervals.length < _fewestIntervals) return null;
  final (_, high) = _quartilesOf(intervals);
  if (high <= 0) return null;
  return intervals.reduce(math.max) / high;
}

(double, double) _quartilesOf(List<int> values) {
  final ordered = [...values]..sort();
  return (
    ordered[ordered.length ~/ 4].toDouble(),
    ordered[(3 * ordered.length) ~/ 4].toDouble(),
  );
}

double _median(List<int> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle].toDouble()
      : (ordered[middle - 1] + ordered[middle]) / 2;
}
