import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'trajectory.dart';

/// What a run of slots on one material turned out to be.
///
/// Run length says nothing on its own: six slots on one scale can be a learner
/// taken through it hand by hand and then together, or the same introduction
/// offered over and over. So a cluster is named by what changed inside it.
enum ClusterKind {
  /// Motor quality rose across the run. Repetition doing its job.
  improving('IMPROVING'),

  /// Guidance came down and stayed down: a learner settling on the support
  /// they need.
  findingSupport('FINDING_SUPPORT'),

  /// Guidance moved in both directions. Introduce, fail, recover, introduce
  /// again, which is not a learner settling on anything.
  ///
  /// Distinguished from [findingSupport] by direction changes rather than by
  /// the ends, which read identically: a run that oscillates finishes below
  /// where it started too.
  oscillatingSupport('OSCILLATING_SUPPORT'),

  /// At the most supportive rung the ladder has, and going nowhere.
  stuckAtFloor('STUCK_AT_FLOOR'),

  /// One hand, then the other, then both. Concentrated practice on a scale
  /// that has just become coordination work.
  coordinationPhase('COORDINATION_PHASE'),

  /// None of the above.
  other('OTHER');

  const ClusterKind(this.id);

  /// Stable identifier used in reports.
  final String id;
}

/// Every run of [minimumLength] or more consecutive slots on one material.
List<List<TrajectorySlot>> clustersIn(
  Trajectory trajectory, {
  int minimumLength = 6,
}) {
  final found = <List<TrajectorySlot>>[];
  var start = 0;
  for (var i = 1; i <= trajectory.slots.length; i++) {
    final ended =
        i == trajectory.slots.length ||
        trajectory.slots[i].chosen.material.materialId !=
            trajectory.slots[start].chosen.material.materialId;
    if (!ended) continue;
    if (i - start >= minimumLength) {
      found.add(trajectory.slots.sublist(start, i));
    }
    start = i;
  }
  return found;
}

/// Which kind of cluster [cluster] is, read from what changed inside it.
ClusterKind describeCluster(List<TrajectorySlot> cluster) {
  final motor = [for (final slot in cluster) slot.outcome.motorScore];
  final independence = [
    for (final slot in cluster) slot.chosen.guidance.independence,
  ];
  final hands = {for (final slot in cluster) slot.chosen.conditions.hands};

  if (hands.contains(HandConfiguration.together) && hands.length > 1) {
    return ClusterKind.coordinationPhase;
  }

  var descents = 0;
  var climbs = 0;
  for (var i = 1; i < independence.length; i++) {
    if (independence[i] < independence[i - 1]) descents++;
    if (independence[i] > independence[i - 1]) climbs++;
  }
  if (descents > 0 && climbs > 0) return ClusterKind.oscillatingSupport;
  if (descents > 0) return ClusterKind.findingSupport;

  double mean(Iterable<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  final movement =
      mean(motor.skip(motor.length ~/ 2)) - mean(motor.take(motor.length ~/ 2));
  if (movement > 0.1) return ClusterKind.improving;
  if (independence.every((rung) => rung == 0) && mean(motor) < 0.4) {
    return ClusterKind.stuckAtFloor;
  }
  return ClusterKind.other;
}

/// The cluster kinds [trajectory] contains.
List<ClusterKind> clusterKindsIn(Trajectory trajectory) => [
  for (final cluster in clustersIn(trajectory)) describeCluster(cluster),
];
