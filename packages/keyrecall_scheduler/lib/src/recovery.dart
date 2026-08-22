import 'package:keyrecall_domain/keyrecall_domain.dart';

/// The one candidate a recovery context admits: same material, hands,
/// octaves, direction, and tempo as what just failed, one step more guidance.
///
/// Deliberately narrow. Recovery is not "some candidate with a retention or
/// information edge", it is the same motor task, slightly more supported.
/// Letting tempo, direction, octave span, or hand configuration collapse at
/// the same time would trade away the motor challenge to fix a memory
/// problem.
///
/// Returns null when the failed exercise was already at maximum support, which
/// no real recovery target reaches: a continuously cued attempt never observes
/// retrieval, so it is never a failure to recover from.
Exercise? recoveryTarget(Exercise failedExercise) {
  final moreSupport = failedExercise.guidance.oneStepMoreSupportive;
  return moreSupport == null ? null : failedExercise.withGuidance(moreSupport);
}
