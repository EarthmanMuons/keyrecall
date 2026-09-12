import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';
import 'session_state.dart';

/// What the slot may choose between, with a fresh echo held back.
///
/// A probe opened by the attempt just played asks for the same realization one
/// rung faster. Verifying that pace is worth a slot, but doing it in the very
/// next slot is the app repeating itself.
///
/// The defer is unconditional. An empty set asks the slot's fallback for other
/// work; it never makes a fresh probe presentable.
List<CandidateTrace> withoutFreshEcho(
  List<CandidateTrace> selectable,
  SessionState session,
) {
  final probe = session.tempoProbe;
  if (probe == null || !session.tempoProbeIsFresh) return selectable;
  return [
    for (final trace in selectable)
      if (trace.exercise != probe) trace,
  ];
}

/// Whether [outcome] shows [exercise] was clearly too easy.
///
/// A scheduling question rather than a judgment about the performance: was the
/// task itself beneath the learner, so repeating it at the same difficulty
/// would spend a slot learning nothing.
///
/// Every condition is required, because speed alone is ambiguous. Somebody
/// rushing a scale badly and somebody who finds it trivial both play faster
/// than asked, and only one of them stays clean, unbroken, and even.
///
/// Retrieval had to be tested and to have succeeded, since playing quickly
/// while reading the notes off the screen says nothing about whether the
/// exercise was easy.
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
/// they can reach, rather than climbing one rung at a time toward a speed they
/// were playing at before anyone asked.
///
/// Only the tempo moves. Raising the octave span or the hand configuration at
/// the same time would ask a different question and make the answer
/// unattributable, which is the same reason recovery lowers only guidance.
///
/// Nothing is credited for the fast attempt itself; see
/// [LearnerModel.demonstratedTempoBpm], which caps execution attribution at the
/// tempo that was asked for. That cap is what makes this necessary: the only
/// way to earn evidence at a tempo is to be asked for it.
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
  // rather than the highest tempo the generator happens to offer.
  final requested = exercise.conditions.tempoBpm;
  final achieved = requested * outcome.achievedTempoRatio;
  double? target;
  for (final tempo in metronomeLadder) {
    if (tempo <= requested || tempo > achieved) continue;
    if (target == null || tempo > target) target = tempo;
  }

  return target == null ? null : exercise.atTempo(target);
}
