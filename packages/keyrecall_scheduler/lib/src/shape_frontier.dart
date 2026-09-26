import 'package:keyrecall_domain/keyrecall_domain.dart';

/// What a realization asks of its material structurally: which hands, how
/// wide, and which way, apart from tempo, motion, and guidance.
typedef RealizationShape = ({
  HandConfiguration hands,
  int octaves,
  ExerciseDirection direction,
});

RealizationShape shapeOf(Exercise exercise) => (
  hands: exercise.conditions.hands,
  octaves: exercise.conditions.octaves,
  direction: exercise.conditions.direction,
);

/// Which way a shape steps past another on its material.
enum ShapeStep { span, direction, hands }

/// The step [exercise] takes past the [demonstrated] shapes of its material,
/// or null where its shape is demonstrated or no single step reaches it.
///
/// The steps are the material's own: the next span its progression declares,
/// ascending to up and down, and each hand alone to both together, where
/// both hands have to have shown the shape if the material asks for separate
/// hands first.
ShapeStep? shapeStepOf(Exercise exercise, Set<RealizationShape> demonstrated) {
  final shape = shapeOf(exercise);
  if (demonstrated.contains(shape)) return null;
  final (:hands, :octaves, :direction) = shape;

  final previousSpan = exercise.material.progression.previousSpan(octaves);
  if (previousSpan != null &&
      demonstrated.contains((
        hands: hands,
        octaves: previousSpan,
        direction: direction,
      ))) {
    return ShapeStep.span;
  }
  if (direction == ExerciseDirection.upDown &&
      demonstrated.contains((
        hands: hands,
        octaves: octaves,
        direction: ExerciseDirection.up,
      ))) {
    return ShapeStep.direction;
  }
  if (hands == HandConfiguration.together) {
    bool shown(HandConfiguration alone) => demonstrated.contains((
      hands: alone,
      octaves: octaves,
      direction: direction,
    ));
    final ready =
        exercise.material.progression.requiresSeparateHandsBeforeTogether
        ? shown(HandConfiguration.right) && shown(HandConfiguration.left)
        : shown(HandConfiguration.right) || shown(HandConfiguration.left);
    if (ready) return ShapeStep.hands;
  }
  return null;
}

/// Whether [exercise] is a shape not yet demonstrated that is one declared
/// step past one that has been, among [demonstrated] shapes of its material.
bool advancesShapeFrontier(
  Exercise exercise,
  Set<RealizationShape> demonstrated,
) => shapeStepOf(exercise, demonstrated) != null;
