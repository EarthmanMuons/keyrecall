import 'package:meta/meta.dart';

/// What each explanation of a performance costs.
///
/// The costs are the policy, and they decide readings rather than merely
/// tuning them. The load-bearing relationship is between one substitution and
/// one deletion plus one insertion, because those are two accounts of the same
/// wrong note:
///
/// ```text
/// substitution < deletion + insertion   a wrong note stays in place
/// substitution > deletion + insertion   a wrong note becomes a skip plus an
///                                       extra, and the performance is free to
///                                       drift out of step
/// ```
///
/// V1 takes the first: a learner who plays one wrong note in the middle of a
/// scale has played a wrong note, not skipped one and added another. Integers,
/// so the comparisons are exact and a reader can do the arithmetic in their
/// head.
///
/// A register substitution costs the same as a pitch substitution. The
/// difference between them is a description of what happened, and pricing it
/// would be a claim about how bad an octave error is, which nothing yet
/// supports.
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

  const AlignmentPolicy({
    this.substitutionCost = 2,
    this.insertionCost = 3,
    this.deletionCost = 3,
  });

  /// The V1 policy.
  static const AlignmentPolicy standard = AlignmentPolicy();

  /// Whether a wrong note in place is read as a substitution rather than as a
  /// skip and an extra.
  bool get prefersSubstitution =>
      substitutionCost < insertionCost + deletionCost;

  @override
  String toString() =>
      'AlignmentPolicy(sub $substitutionCost, ins $insertionCost, '
      'del $deletionCost)';
}
