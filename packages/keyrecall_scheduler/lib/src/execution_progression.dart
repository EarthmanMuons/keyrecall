import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';

/// Which execution axis a candidate advances, against what the learner has
/// demonstrated on its material.
///
/// The point of naming them is [multiple]. Information gain prefers whatever is
/// least explored, so a candidate that goes wider *and* faster at once is the
/// most attractive thing on offer and the least appropriate: a learner who
/// cannot manage it has told nobody which of the two axes was the problem.
enum ExecutionAdvance {
  /// Not an adjacent step. Either the learner has already been here, or it is
  /// further off than the next rung; admission treats those the same, since
  /// neither is the next thing to ask for.
  none('NONE'),

  /// The next tempo rung, at a span already demonstrated.
  tempo('TEMPO'),

  /// One span wider, at a tempo demonstrated at the narrower one.
  span('SPAN'),

  /// The same work with both hands, where each has demonstrated it alone.
  handsTogether('HANDS_TOGETHER'),

  /// More than one axis moves past what has been demonstrated.
  multiple('MULTIPLE');

  const ExecutionAdvance(this.id);

  /// Stable identifier used in traces.
  final String id;

  /// Whether this is a single adjacent step, which is the only thing
  /// execution progression admits.
  bool get isAdjacentStep =>
      this != ExecutionAdvance.none && this != ExecutionAdvance.multiple;
}

/// What [exercise] advances for this learner, if anything.
///
/// Read against the frontier for its own material and hand configuration,
/// which is where evidence about that combination lives. A hand that has
/// never played the material has no frontier and therefore no adjacent step:
/// meeting material is introduction's business, and this is only about going
/// on from somewhere.
ExecutionAdvance executionAdvanceFor(LearnerState state, Exercise exercise) {
  final conditions = exercise.conditions;
  final materialId = exercise.material.materialId;
  final span = conditions.octaves;
  final tempo = conditions.tempoBpm;

  double demonstratedAt(HandConfiguration hands, int octaves) =>
      state.materialExecution[(materialId, hands)]?.demonstratedTempoAt(
        octaves,
      ) ??
      0;

  if (conditions.hands == HandConfiguration.together) {
    // Entering hands-together work is its own step, and only until the
    // configuration has a frontier of its own. After that it goes on like any
    // other, through its own record.
    if (demonstratedAt(HandConfiguration.together, span) <= 0 &&
        demonstratedAt(HandConfiguration.together, span - 1) <= 0) {
      return tempo == handsTogetherEntryTempo(state, materialId, span)
          ? ExecutionAdvance.handsTogether
          : ExecutionAdvance.none;
    }
  }

  final atSpan = demonstratedAt(conditions.hands, span);
  final atNarrower = demonstratedAt(conditions.hands, span - 1);

  // Both axes past what has been demonstrated: wider than anything managed,
  // and faster than the narrower span was managed at.
  if (atSpan <= 0 && atNarrower > 0 && tempo > atNarrower) {
    return ExecutionAdvance.multiple;
  }

  if (atSpan > 0) {
    return tempo == tempoAfter(atSpan)
        ? ExecutionAdvance.tempo
        : ExecutionAdvance.none;
  }

  // A span nobody has reached, entered at a tempo the narrower one was
  // managed at. One neighbour rather than every slower tempo under the
  // ceiling, so widening does not also become a cloud of tempo choices.
  if (atNarrower > 0 && tempo == atNarrower) return ExecutionAdvance.span;

  return ExecutionAdvance.none;
}

/// Where [exercise] sits against what this learner has demonstrated on its
/// material and hand configuration.
///
/// A different question from [executionAdvanceFor], which asks whether a
/// candidate is *the* next step and is strict about it: exactly one axis, the
/// adjacent rung, nothing else. This asks the looser question ranking needs,
/// which is whether a slot spent here moves the learner on, holds them where
/// they are, or asks for something they are already past.
///
/// Read at the span being played, because the frontier is a lattice and the
/// tempo somebody manages at one octave says nothing about two.
RealizationRank realizationRankFor(LearnerState state, Exercise exercise) {
  if (executionAdvanceFor(state, exercise).isAdjacentStep) {
    return RealizationRank.advancing;
  }

  final conditions = exercise.conditions;
  final demonstrated =
      state.materialExecution[(exercise.material.materialId, conditions.hands)]
          ?.demonstratedTempoAt(conditions.octaves) ??
      0;
  if (demonstrated <= 0) return RealizationRank.unmeasured;

  return conditions.tempoBpm < demonstrated
      ? RealizationRank.surpassed
      : RealizationRank.holding;
}

/// The one tempo hands-together work is entered at for [materialId] at
/// [span], or zero when neither hand has demonstrated that span.
///
/// The slower of what the two hands have each managed alone. Derived from
/// evidence rather than chosen, and conservative by construction: a strong
/// right hand cannot drag a left hand that has never been that fast, because
/// putting them together is exactly when the weaker one starts to matter.
double handsTogetherEntryTempo(
  LearnerState state,
  String materialId,
  int span,
) {
  double readyAt(HandConfiguration hands) =>
      state.materialExecution[(materialId, hands)]?.coordinationReadyTempoAt(
        span,
      ) ??
      0;

  final right = readyAt(HandConfiguration.right);
  final left = readyAt(HandConfiguration.left);
  if (right <= 0 || left <= 0) return 0;

  // A rung below the slower hand. Putting the hands together is a new motor
  // task rather than the two old ones at once, and every source that discusses
  // it says to slow down when they first meet.
  return tempoBefore(right < left ? right : left);
}

/// Whether each hand has separately demonstrated enough of [materialId] at
/// [span] for the other to join it.
///
/// Read from the coordination-readiness record rather than the execution
/// frontier, and it makes no claim about factual retrieval. The frontier says
/// where a hand can be asked to go on from and moves only on an attempt played
/// rather than endured; readiness says the hand produced the right pitches,
/// which is what makes putting the hands together a coordination exercise
/// rather than the simultaneous remediation of two parts. A weak hand rarely
/// clears the frontier's motor bar, and waiting for it to is waiting for the
/// wrong thing.
bool supportsHandsTogether(LearnerState state, String materialId, int span) =>
    handsTogetherEntryTempo(state, materialId, span) > 0;

/// Whether the learner may play [exercise] with both hands at its span.
bool handsTogetherPrerequisiteSatisfied(LearnerState state, Exercise exercise) {
  if (exercise.conditions.hands != HandConfiguration.together) return true;
  final materialId = exercise.material.materialId;
  final span = exercise.conditions.octaves;
  final together =
      state.materialExecution[(materialId, HandConfiguration.together)];
  return (together?.demonstratedTempoAt(span) ?? 0) > 0 ||
      (together?.demonstratedTempoAt(span - 1) ?? 0) > 0 ||
      supportsHandsTogether(state, materialId, span);
}

/// The tempo this learner's [hands] play at on material they already own, or
/// zero when they have shown none.
///
/// Transferable evidence, which is what an unseen scale has to be met on: its
/// own frontier is empty by definition.
///
/// The pace rather than the frontier, since a frontier is capped at what was
/// asked for and would read a learner who plays every sixty-beat exercise at a
/// hundred and twenty as a sixty-beat learner. The median rather than the
/// fastest, so one quick success does not set the pace for every unseen scale.
///
/// [span] is unread: pace is a fact about the hand, and nobody has played this
/// material at any span. It stays in the signature because the caller is
/// choosing a tempo for a particular span.
double transferableTempoFor(
  LearnerState state,
  HandConfiguration hands,
  int span,
) {
  final paced = <double>[
    for (final residual in state.materialExecution.values)
      if (residual.hands == hands)
        if (residual.pacedTempoBpm > 0) residual.pacedTempoBpm,
  ]..sort();
  if (paced.isEmpty) return 0;

  return paced[paced.length ~/ 2];
}

/// The tempo a realization with no frontier at its span should be entered at.
///
/// "Unmeasured" says nothing has been demonstrated *here*, not that nothing is
/// known. Evidence exists, and it is ordered by how local it is:
///
/// 1. this material and hand at the adjacent narrower span, which is the
///    fingering they already play with an octave added;
/// 2. failing that, the pace this hand shows on material it owns, which is
///    what an unseen scale is met at;
/// 3. failing that, [gentleTempoBpm], because nobody has seen them play.
///
/// The first is what makes this different from [transferableTempoFor]: a
/// learner widening B flat major has evidence about B flat major in that hand,
/// and a median over other scales would answer a more distant question.
///
/// The narrower span's tempo unchanged rather than a rung below it, because
/// [executionAdvanceFor] calls the carry at that exact tempo a span step and
/// the intended entry must not disagree with the offered step.
double unmeasuredEntryTempo(
  LearnerState state,
  Exercise exercise, {
  required double gentleTempoBpm,
}) {
  final conditions = exercise.conditions;
  final residual =
      state.materialExecution[(exercise.material.materialId, conditions.hands)];

  final narrower = residual?.demonstratedTempoAt(conditions.octaves - 1) ?? 0;
  if (narrower > 0) return narrower;

  final transferable = transferableTempoFor(
    state,
    conditions.hands,
    conditions.octaves,
  );
  return transferable > 0 ? transferable : gentleTempoBpm;
}

/// How well [exercise] matches the realization this learner should be entering
/// at, as a negative rung distance, where zero is the intended one.
///
/// Only meaningful for a realization with no frontier at its span. Everything
/// else is ordered by its relationship to the frontier, which [RealizationRank]
/// already says, and this returns zero so it cannot reorder them.
///
/// Negative so that larger is better, which is the direction every other rank
/// term runs in.
double realizationFitFor(
  LearnerState state,
  Exercise exercise, {
  required double gentleTempoBpm,
}) {
  if (realizationRankFor(state, exercise) != RealizationRank.unmeasured) {
    return 0;
  }
  final target = unmeasuredEntryTempo(
    state,
    exercise,
    gentleTempoBpm: gentleTempoBpm,
  );
  return -(tempoRungOf(exercise.conditions.tempoBpm) - tempoRungOf(target))
      .abs()
      .toDouble();
}

/// Whether [exercise] is this learner's first chance to play its material with
/// both hands, having just earned it.
///
/// Derived rather than stored, which is what bounds it: it holds only while
/// both hands satisfy coordination readiness for the material and the two have
/// never been put together on it, so the first hands-together attempt ends it
/// whatever that attempt was like. Nothing accumulates and nothing expires on a
/// timer.
///
/// The attempt rather than the success. What the scheduler owes is bringing
/// newly available coordination work into practice promptly; how it went is
/// then evidence like any other.
///
/// Once per material rather than once per span, and direction is unread. The
/// event is the learner moving from never having coordinated this scale to
/// having coordinated it. A wider span afterwards is ordinary execution
/// progression on a skill that exists, which [ExecutionAdvance.span] offers,
/// and up against up-down is not a second first encounter. Costing one slot per
/// scale rather than one per realization is what justifies overriding retention
/// at all.
bool isCoordinationTransition(LearnerState state, Exercise exercise) =>
    exercise.conditions.hands == HandConfiguration.together &&
    !state.hasPlayed(
      exercise.material.materialId,
      HandConfiguration.together,
    ) &&
    supportsHandsTogether(
      state,
      exercise.material.materialId,
      exercise.conditions.octaves,
    );

/// The exercises one adjacent execution step from where this learner already
/// is, which the static generator does not contain.
///
/// Candidate generation is deliberately learner-blind: it answers what exercise
/// shapes exist, not which realization of one is meaningful now. But every
/// adjacency relation here can land on a learner-dependent tempo, so a purely
/// static set has no candidate for the rule to recognize.
///
/// A refinement between generation and eligibility rather than a change to
/// either, holding one invariant: **every exercise it adds is a tempo variant
/// of a shape generation already produced.** Same material, hands, span,
/// direction and guidance.
List<Exercise> withExecutionNeighbours(
  LearnerState state,
  List<Exercise> candidates,
) {
  double demonstratedAt(String materialId, HandConfiguration hands, int span) =>
      state.materialExecution[(materialId, hands)]?.demonstratedTempoAt(span) ??
      0;

  final variants = <Exercise>{};
  for (final candidate in candidates) {
    final conditions = candidate.conditions;
    final materialId = candidate.material.materialId;
    final span = conditions.octaves;
    final atSpan = demonstratedAt(materialId, conditions.hands, span);
    final atNarrower = demonstratedAt(materialId, conditions.hands, span - 1);

    final wanted = <double>{
      // Meeting something new at a tempo this hand has shown elsewhere. Its
      // own frontier is empty, so without this the introduction has only the
      // tempi the generator lists and picks between them on nothing.
      if (atSpan <= 0 && atNarrower <= 0)
        transferableTempoFor(state, conditions.hands, span),
      // Staying where this span has been managed. The rung a learner is on is
      // not always one the generator has, and it has to remain offerable:
      // holding there is ordinary work, and a recovery context targets an
      // exact exercise, so letting the current rung disappear the moment the
      // frontier reaches it leaves recovery with nothing to admit at all.
      if (atSpan > 0) atSpan,
      // Going faster where this span has been managed.
      if (atSpan > 0) tempoAfter(atSpan),
      // Going wider, carrying the tempo the narrower span was managed at.
      if (atSpan <= 0 && atNarrower > 0) atNarrower,
      // Going together, at the slower of what each hand managed alone.
      if (conditions.hands == HandConfiguration.together &&
          atSpan <= 0 &&
          atNarrower <= 0)
        handsTogetherEntryTempo(state, materialId, span),
    };

    for (final tempoBpm in wanted) {
      if (tempoBpm > 0 && tempoBpm != conditions.tempoBpm) {
        variants.add(candidate.atTempo(tempoBpm));
      }
    }
  }
  return [...candidates, ...variants];
}
