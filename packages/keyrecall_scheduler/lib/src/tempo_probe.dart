import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'config/scheduler_config.dart';

/// Whether [outcome] shows [exercise] was clearly too easy.
///
/// Not a judgment about the performance, which measurement already made. This
/// asks a scheduling question the measurement cannot: was the task itself
/// beneath the learner, so that repeating it at the same difficulty would
/// spend a slot learning nothing.
///
/// Every condition is required, because speed alone is ambiguous. Somebody
/// rushing a scale badly and somebody who finds it trivial both play faster
/// than asked; what separates them is that only one of them stays clean,
/// unbroken, and even while doing it.
///
/// Retrieval had to be tested and to have succeeded. Playing quickly while
/// reading the notes off the screen says something about the fingers and
/// nothing about whether the exercise was easy, and it is the exercise that
/// the next probe would be raising.
bool isUnderchallenged({
  required Exercise exercise,
  required Outcome outcome,
  required ProbeConfig config,
}) =>
    outcome.completed &&
    outcome.retrieval == FactualRetrieval.succeeded &&
    outcome.pitchIntegrity >= config.underchallengePitchIntegrity &&
    outcome.continuity >= config.underchallengeContinuity &&
    outcome.temporalStability >= config.underchallengeTemporalStability &&
    outcome.achievedTempoRatio >= config.underchallengeTempoRatio;

/// The exercise to ask for next when [exercise] was too easy, or null.
///
/// The same task at the fastest offered tempo the learner has already shown
/// they can reach, which is the point: ordinary progression would climb one
/// step at a time toward a speed they were playing at before anyone asked.
///
/// Only the tempo moves. Raising the octave span or the hand configuration at
/// the same time would ask a different question and make the answer
/// unattributable, which is the same reason recovery lowers only guidance.
///
/// Nothing is credited for the fast attempt itself; see
/// [LearnerModel.demonstratedTempoBpm], which caps execution attribution at
/// the tempo that was actually asked for. That cap is what makes this
/// necessary: without it a scheduler could infer the ceiling from an attempt
/// nobody posed, and with it the only way to earn evidence at a tempo is to
/// be asked for that tempo.
Exercise? tempoProbeTarget({
  required Exercise exercise,
  required Outcome outcome,
  required ProbeConfig config,
}) {
  if (!isUnderchallenged(
    exercise: exercise,
    outcome: outcome,
    config: config,
  )) {
    return null;
  }

  // The highest rung of the metronome ladder they were already reaching,
  // rather than the highest tempo the generator happens to offer. Those were
  // sixty, eighty, a hundred and a hundred and twenty, so a learner playing a
  // sixty-beat exercise at a hundred and five was asked for a hundred and saw
  // nothing between: the probe could only land where candidate generation had
  // already put something.
  final requested = exercise.conditions.tempoBpm;
  final achieved = requested * outcome.achievedTempoRatio;
  double? target;
  for (final tempo in metronomeLadder) {
    if (tempo <= requested || tempo > achieved) continue;
    if (target == null || tempo > target) target = tempo;
  }

  return target == null ? null : exercise.atTempo(target);
}
