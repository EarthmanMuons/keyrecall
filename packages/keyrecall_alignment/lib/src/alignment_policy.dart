import 'package:meta/meta.dart';

/// What each explanation of a performance costs.
///
/// The costs decide readings rather than merely tuning them. The load-bearing
/// relationship is between one substitution and one deletion plus one
/// insertion, two accounts of the same wrong note:
///
/// ```text
/// substitution < deletion + insertion   a wrong note stays in place
/// substitution > deletion + insertion   a wrong note becomes a skip plus an
///                                       extra, and the performance is free to
///                                       drift out of step
/// ```
///
/// V1 takes the first: a learner who plays one wrong note in the middle of a
/// scale has played a wrong note, not skipped one and added another. The costs
/// are integers so the comparisons are exact. A register substitution costs the
/// same as a pitch substitution, since pricing the difference would claim how
/// bad an octave error is.
///
/// Costs alone do not always pick one reading. When explanations tie, the
/// traceback takes the one placing the performance as early in the traversal as
/// the cost allows. That is part of the policy: it decides what an ambiguous
/// performance means, and so reaches every measurement derived from it.
@immutable
class AlignmentPolicy {
  /// What a note played where it was expected costs. Zero, by definition.
  static const int matchCost = 0;

  /// What playing something else in the right place costs.
  final int substitutionCost;

  /// What a note nobody asked for costs.
  final int insertionCost;

  /// What an expected note that never arrived costs.
  final int deletionCost;

  /// The most that timing may prefer one grouping of the observations over
  /// another.
  ///
  /// A boundary may tip a reading that correspondence is indifferent to, but
  /// never outbid a correspondence decision, so both readings of every boundary
  /// stay affordable. See `docs/system/observation.md`.
  final int maxGroupingPreference;

  const AlignmentPolicy({
    this.substitutionCost = 2,
    this.insertionCost = 3,
    this.deletionCost = 3,
    this.maxGroupingPreference = 2,
  }) : assert(
         substitutionCost >= 0 && insertionCost >= 0 && deletionCost >= 0,
         'no explanation may cost less than a match',
       ),
       assert(
         maxGroupingPreference >= 0 &&
             maxGroupingPreference <= substitutionCost,
         'grouping proposes, so it may not outbid a correspondence decision',
       );

  /// The V1 policy.
  static const AlignmentPolicy standard = AlignmentPolicy();

  /// Whether a wrong note in place is read as a substitution rather than as a
  /// skip and an extra.
  bool get prefersSubstitution =>
      substitutionCost < insertionCost + deletionCost;

  @override
  String toString() =>
      'AlignmentPolicy(sub $substitutionCost, ins $insertionCost, '
      'del $deletionCost, grouping $maxGroupingPreference)';
}
