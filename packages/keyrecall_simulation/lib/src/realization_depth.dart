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
  final differs =
      harder.hands != easier.hands ||
      harder.octaves != easier.octaves ||
      harder.direction != easier.direction;
  return hands && span && direction && differs;
}

/// What one interval of picks practiced, read against everything before it.
class RealizationDepthInterval {
  final int fromSession;
  final int picks;

  /// Share of picks at each depth, 0 to 3.
  final List<double> depth;

  /// Share of picks at each octave span played.
  final Map<int, double> spans;

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

  /// Share of picks by how ranking's choice was admitted.
  final Map<String, double> routes;

  /// Share of picks whose choice a shape step may replace, that had one on
  /// offer, and that were replaced.
  final double replaceable;
  final double opportunity;
  final double replaced;

  /// Replacements by the way the step went, and by how it was admitted.
  final Map<String, int> steps;
  final Map<String, int> stepRoutes;

  const RealizationDepthInterval({
    required this.fromSession,
    required this.picks,
    required this.depth,
    required this.spans,
    required this.subsumed,
    required this.materials,
    required this.predicted,
    required this.failed,
    required this.unguided,
    required this.previewed,
    required this.cued,
    required this.establishedRetrieved,
    this.routes = const {},
    this.replaceable = 0,
    this.opportunity = 0,
    this.replaced = 0,
    this.steps = const {},
    this.stepRoutes = const {},
  });

  Map<String, Object?> toJson() => {
    'from_session': fromSession,
    'picks': picks,
    'depth': depth,
    'spans': {
      for (final MapEntry(:key, :value) in spans.entries) '$key': value,
    },
    'subsumed': subsumed,
    'materials': materials,
    'predicted': predicted,
    'failed': failed,
    'unguided': unguided,
    'previewed': previewed,
    'cued': cued,
    'established_retrieved': establishedRetrieved,
    'routes': routes,
    'replaceable': replaceable,
    'opportunity': opportunity,
    'replaced': replaced,
    'steps': steps,
    'step_routes': stepRoutes,
  };
}

/// [selections] in intervals of [every] sessions.
List<RealizationDepthInterval> realizationDepthOf(
  List<GoalTrajectorySelection> selections, {
  required int sessions,
  required int every,
}) {
  final demonstrated = <GoalTrajectorySelection>[];
  final established = <String>{};
  final intervals = <RealizationDepthInterval>[];
  for (var start = 0; start < sessions; start += every) {
    final picks = [
      for (final pick in selections)
        if (pick.session >= start && pick.session < start + every) pick,
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
        fromSession: start,
        picks: picks.length,
        depth: [
          for (var level = 0; level <= 3; level++)
            share((pick) => depthOf(pick) == level),
        ],
        spans: {
          for (final span in {for (final pick in picks) pick.octaves})
            span: share((pick) => pick.octaves == span),
        },
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
        routes: {
          for (final route in {
            for (final pick in picks)
              if (pick.shapeStep case final observed?) observed.route,
          })
            route: share((pick) => pick.shapeStep?.route == route),
        },
        replaceable: share((pick) => pick.shapeStep?.replaceable ?? false),
        opportunity: share((pick) => pick.shapeStep?.opportunity ?? false),
        replaced: share((pick) => pick.shapeStep?.replaced ?? false),
        steps: _counts([
          for (final pick in picks)
            if (pick.shapeStep?.step case final step?) step.name,
        ]),
        stepRoutes: _counts([
          for (final pick in picks) ?pick.shapeStep?.stepRoute,
        ]),
      ),
    );
  }
  return intervals;
}

Map<String, int> _counts(Iterable<String> keys) {
  final counts = <String, int>{};
  for (final key in keys) {
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}
