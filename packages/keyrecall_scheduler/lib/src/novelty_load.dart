import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';

/// How many execution conditions a candidate would be the learner's first of.
///
/// Execution only. What is being played is a separate scheduler event with its
/// own gate, and introducing material often has to come with one unfamiliar
/// condition; tempo is left out too, since its difficulty is already priced by
/// the challenge band. What this counts is the number of *ways of playing*
/// arriving at once:
///
/// ```text
/// hands    a hand configuration this material has never been played with
/// motion   a motion two hands have never met in, for this material
/// span     a span this hand configuration has never covered, for this material
/// ```
///
/// Parallel is the motion every single-hand record already carries, so two
/// hands meeting in it are new at playing together and not at the motion;
/// contrary is the one a learner has not met until they have met it. Span
/// counts only where the hand configuration is already familiar, because a
/// configuration nobody has used has no span to have covered and counting both
/// would say the same newness twice.
///
/// Material-scoped rather than global, which is the only form the recorded
/// state can answer: a learner who has played contrary motion in C major meets
/// it again in G major as far as this is concerned.
int noveltyLoadOf(LearnerState state, Exercise exercise) {
  final materialId = exercise.material.materialId;
  final conditions = exercise.conditions;

  bool played(bool Function(MaterialExecutionState) matching) =>
      state.materialExecution.entries.any(
        (entry) =>
            entry.value.materialId == materialId && matching(entry.value),
      );

  final handsMet = played((record) => record.hands == conditions.hands);
  final motionMet =
      conditions.handMotion != HandMotion.contrary ||
      played((record) => record.handMotion == HandMotion.contrary);
  final spanMet =
      !handsMet ||
      played(
        (record) =>
            record.hands == conditions.hands &&
            record.demonstratedTempoByOctaves.containsKey(conditions.octaves),
      );

  return (handsMet ? 0 : 1) + (motionMet ? 0 : 1) + (spanMet ? 0 : 1);
}

/// The most independent guidance rung [load] novel conditions may arrive at.
///
/// Each novel condition past the first takes a rung of support back. One new
/// way of playing is an ordinary step and may be asked for from memory; two
/// arriving together keep the notes on screen at least once; three are met
/// with the material in view throughout.
///
/// A ceiling rather than a floor. Nothing here asks for more support than the
/// rest of the pipeline chose, and a candidate whose guidance already sits
/// under the ceiling is untouched.
int allowedIndependence(int load, NoveltyConfig config) {
  final allowed = config.independenceAllowance - load;
  return allowed.clamp(0, GuidanceContext.ladder.length - 1);
}

/// The candidates a slot may choose between, with unsupported novelty stacks
/// set aside.
///
/// Three admissions answer for themselves. Recovery is repairing the attempt
/// that just failed and has already lowered its guidance; a tempo probe moves
/// nothing but the tempo, so it carries the novelty of the attempt that opened
/// it and no more; and an acquisition floor is the most supportive realization
/// its family has. Everything else is governed, including the progression that
/// puts two hands together for the first time.
///
/// Never empties the set, for the reason pacing does not: the alternative to a
/// demanding candidate is presenting nothing, and a first sitting offers
/// first-time conditions only. Set aside where something else is available,
/// offered where nothing is.
List<CandidateTrace> withNoveltySupported(
  List<CandidateTrace> selectable,
  LearnerState state,
  NoveltyConfig? config,
) {
  if (config == null) return selectable;
  final supported = [
    for (final trace in selectable)
      if (!_governed(trace) ||
          trace.exercise.guidance.independence <=
              allowedIndependence(noveltyLoadOf(state, trace.exercise), config))
        trace,
  ];
  return supported.isEmpty ? selectable : supported;
}

bool _governed(CandidateTrace trace) => switch (trace.challengeBypass) {
  ChallengeBypass.recovery ||
  ChallengeBypass.tempoProbe ||
  ChallengeBypass.acquisitionFloor => false,
  _ => true,
};
