import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'exercise_presentation.dart';
import 'goal_progress.dart';

/// The heading over a review's coverage statement.
String coverageHeading(CoverageProgress progress) =>
    '${progress.focused ? 'Focus' : 'Goal'} '
    '${progress.completes ? 'complete' : 'progress'}';

/// What a review says about the targets an attempt covered.
String coverageStatement(CoverageProgress progress) {
  final first = progress.newlyCovered.first;
  final name = coveredTargetName(first, progress.targets);
  final total = progress.targets.length;
  if (progress.completes) {
    final memory = progress.targets.every(_fromMemory) ? ' from memory' : '';
    final last = progress.newlyCovered.length == 1
        ? ' The last was $name.'
        : '';
    return 'All $total demonstrated$memory.$last';
  }
  final memory = _fromMemory(first) ? ', from memory' : '';
  final more = switch (progress.newlyCovered.length - 1) {
    0 => '',
    final others => ', and $others more',
  };
  return '$name$memory$more. ${progress.covered} of $total demonstrated.';
}

bool _fromMemory(GoalTarget target) =>
    target.requirement.retrieval == CoverageRetrieval.unguided;

/// A target named as much as it takes to tell it from the others its material
/// has in [targets].
String coveredTargetName(GoalTarget target, List<GoalTarget> targets) {
  final material = materialName(target.material);
  final siblings = [
    for (final other in targets)
      if (other.material == target.material) other.requirement.constraints,
  ];
  if (siblings.length == 1) return material;
  final hands = [for (final constraints in siblings) constraints.hands];
  final handsTellApart =
      !hands.contains(null) && hands.toSet().length == hands.length;
  final constraints = target.requirement.constraints;
  final shape = handsTellApart
      ? handsName(constraints.hands!)
      : targetShapeName(constraints);
  return '$material, ${shape[0].toLowerCase()}${shape.substring(1)}';
}

/// The whole shape a target asks for, as a learner would say it.
///
/// What the explicit list names each target by, so two targets of one
/// material read differently whenever they are different.
String targetShapeName(ExerciseConstraints constraints) => [
  if (constraints.hands case final hands?) handsName(hands),
  if (constraints.octaves case final octaves?) octavesName(octaves),
  if (constraints.handMotion == HandMotion.contrary) 'contrary motion',
  switch (constraints.direction) {
    ExerciseDirection.up => 'up',
    ExerciseDirection.upDown => 'up and down',
    null => null,
  },
  if (constraints.minimumTempoBpm case final tempo?) 'at ${tempo.round()} bpm',
].nonNulls.join(', ');
