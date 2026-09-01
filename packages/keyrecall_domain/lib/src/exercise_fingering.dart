import 'exercise.dart';
import 'fingering.dart';
import 'hand_path.dart';

/// The finger for each moment of [exercise], for [hand].
List<int>? fingeringFor(Exercise exercise, Hand hand) => fingeringForConditions(
  material: exercise.material,
  conditions: exercise.conditions,
  hand: hand,
);
