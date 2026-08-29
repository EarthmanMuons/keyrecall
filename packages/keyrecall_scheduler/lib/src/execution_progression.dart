import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

/// Which execution axis a candidate advances, against what the learner has
/// demonstrated on its material.
///
/// The point of naming them is [multiple]. Information gain prefers whatever
/// is least explored, so a candidate that goes wider *and* faster at once is
/// the most attractive thing on offer and the least appropriate: it is two
/// steps taken as one, and a learner who cannot manage it has told nobody
/// which of the two was the problem. One axis at a time is the invariant, and
/// this is what makes it one rather than a comment.
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
  final right =
      state.materialExecution[(materialId, HandConfiguration.right)]
          ?.demonstratedTempoAt(span) ??
      0;
  final left =
      state.materialExecution[(materialId, HandConfiguration.left)]
          ?.demonstratedTempoAt(span) ??
      0;
  if (right <= 0 || left <= 0) return 0;
  return right < left ? right : left;
}

/// The exercises one adjacent execution step from where this learner already
/// is, which the static generator does not contain.
///
/// Candidate generation is deliberately learner-blind: it answers what
/// exercise shapes exist, not which realization of one is meaningful now. But
/// every adjacency relation here can land on a tempo that is a
/// learner-dependent value — sixty-three exists only because somebody managed
/// sixty — so a purely static set has no candidate for the rule to recognize,
/// and the axis could never advance locally however well the rule was written.
///
/// So this is a refinement between generation and eligibility rather than a
/// change to either, and it holds one invariant: **every exercise it adds is a
/// tempo variant of a shape generation already produced.** Same material,
/// hands, span, direction and guidance. It materializes the tempo the three
/// relations ask for and invents nothing else.
///
/// All three, because all three can need one. Widening to a span nobody has
/// reached carries the narrower span's tempo with it, and that tempo may be a
/// rung the generator has no candidate at. Entering hands-together work
/// carries the slower of what the two hands managed, which may be another. It
/// was tempting to add only the first, since that is the one that made the
/// problem visible.
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
