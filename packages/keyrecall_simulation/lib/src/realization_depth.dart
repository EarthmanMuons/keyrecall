import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'goal_trajectory_experiment.dart';

/// How many of hands together, two octaves or more, and up and down a pick
/// asks for, from 0 to 3.
int depthOf(GoalTrajectorySelection pick) =>
    (pick.hands == HandConfiguration.together ? 1 : 0) +
    (pick.octaves >= 2 ? 1 : 0) +
    (pick.direction == ExerciseDirection.upDown ? 1 : 0);

/// Whether [pick] retrieved its material unguided and played it cleanly.
bool demonstrates(GoalTrajectorySelection pick) =>
    pick.clean && !pick.guidance.isMaterialSupplied;

/// Whether playing [harder] also plays everything [easier] asks of the same
/// material, and more.
bool subsumes(GoalTrajectorySelection harder, GoalTrajectorySelection easier) {
  if (harder.materialId != easier.materialId) return false;
  final hands =
      harder.hands == easier.hands ||
      harder.hands == HandConfiguration.together;
  final span = harder.octaves >= easier.octaves;
  final direction =
      harder.direction == easier.direction ||
      harder.direction == ExerciseDirection.upDown;
  return hands && span && direction && depthOf(harder) > depthOf(easier);
}

/// What one interval of picks practiced, read against everything before it.
class RealizationDepthInterval {
  final int fromSitting;
  final int picks;

  /// Share of picks at each depth, 0 to 3.
  final List<double> depth;

  /// Share of picks whose shape a realization the learner had already
  /// demonstrated of the same material subsumes.
  final double subsumed;

  final int materials;
  final double predicted;

  /// Share of picks not played through cleanly.
  final double failed;

  final double unguided;
  final double previewed;
  final double cued;

  /// Of the materials demonstrated before this interval, the share retrieved
  /// unguided in it, in any shape.
  final double establishedRetrieved;

  const RealizationDepthInterval({
    required this.fromSitting,
    required this.picks,
    required this.depth,
    required this.subsumed,
    required this.materials,
    required this.predicted,
    required this.failed,
    required this.unguided,
    required this.previewed,
    required this.cued,
    required this.establishedRetrieved,
  });

  Map<String, Object?> toJson() => {
    'from_sitting': fromSitting,
    'picks': picks,
    'depth': depth,
    'subsumed': subsumed,
    'materials': materials,
    'predicted': predicted,
    'failed': failed,
    'unguided': unguided,
    'previewed': previewed,
    'cued': cued,
    'established_retrieved': establishedRetrieved,
  };
}

/// [selections] in intervals of [every] sittings.
List<RealizationDepthInterval> realizationDepthOf(
  List<GoalTrajectorySelection> selections, {
  required int sittings,
  required int every,
}) {
  final demonstrated = <GoalTrajectorySelection>[];
  final established = <String>{};
  final intervals = <RealizationDepthInterval>[];
  for (var start = 0; start < sittings; start += every) {
    final picks = [
      for (final pick in selections)
        if (pick.sitting >= start && pick.sitting < start + every) pick,
    ];
    double share(bool Function(GoalTrajectorySelection) test) =>
        picks.isEmpty ? 0 : picks.where(test).length / picks.length;
    final before = {...established};
    var subsumed = 0;
    for (final pick in picks) {
      if (demonstrated.any((shown) => subsumes(shown, pick))) subsumed++;
      if (demonstrates(pick)) {
        demonstrated.add(pick);
        established.add(pick.materialId);
      }
    }
    final retrieved = {
      for (final pick in picks)
        if (!pick.guidance.isMaterialSupplied) pick.materialId,
    };
    intervals.add(
      RealizationDepthInterval(
        fromSitting: start,
        picks: picks.length,
        depth: [
          for (var level = 0; level <= 3; level++)
            share((pick) => depthOf(pick) == level),
        ],
        subsumed: picks.isEmpty ? 0 : subsumed / picks.length,
        materials: {for (final pick in picks) pick.materialId}.length,
        predicted: picks.isEmpty
            ? 0
            : picks.map((pick) => pick.predicted).reduce((a, b) => a + b) /
                  picks.length,
        failed: share((pick) => !pick.clean),
        unguided: share((pick) => !pick.guidance.isMaterialSupplied),
        previewed: share(
          (pick) =>
              pick.guidance.isMaterialSupplied &&
              !pick.guidance.concurrentPitchCues,
        ),
        cued: share((pick) => pick.guidance.concurrentPitchCues),
        establishedRetrieved: before.isEmpty
            ? 0
            : before.intersection(retrieved).length / before.length,
      ),
    );
  }
  return intervals;
}
