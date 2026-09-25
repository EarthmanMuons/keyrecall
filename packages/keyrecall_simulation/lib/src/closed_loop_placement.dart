import 'dart:isolate';
import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'goal_trajectory_experiment.dart';
import 'player_archetypes.dart';
import 'synthetic_player.dart';

/// Sittings after which the three placements are compared, twenty slots each.
const List<int> closedLoopCheckpoints = [3, 6, 10, 25];

/// The three placements of one player under one goal, at one checkpoint.
class ClosedLoopCheckpoint {
  final int sittings;

  /// Coverage each placement had reached, beginner first.
  final List<double> covered;

  /// The largest difference between two placements' mix of picks since the
  /// previous checkpoint, as total variation distance, per facet.
  final Map<String, double> mixDistance;

  /// The least overlap between two placements' fully eligible candidates.
  final double eligibleOverlap;

  /// Whether a fresh sitting from each placement's state picks the same
  /// exercise.
  final bool samePick;

  const ClosedLoopCheckpoint({
    required this.sittings,
    required this.covered,
    required this.mixDistance,
    required this.eligibleOverlap,
    required this.samePick,
  });

  Map<String, Object?> toJson() => {
    'sittings': sittings,
    'covered': covered,
    'mix_distance': mixDistance,
    'eligible_overlap': eligibleOverlap,
    'same_pick': samePick,
  };

  factory ClosedLoopCheckpoint.fromJson(Map<String, Object?> json) =>
      ClosedLoopCheckpoint(
        sittings: json['sittings']! as int,
        covered: [
          for (final value in json['covered']! as List<Object?>)
            (value! as num).toDouble(),
        ],
        mixDistance: {
          for (final MapEntry(:key, :value)
              in (json['mix_distance']! as Map<String, Object?>).entries)
            key: (value! as num).toDouble(),
        },
        eligibleOverlap: (json['eligible_overlap']! as num).toDouble(),
        samePick: json['same_pick']! as bool,
      );
}

class ClosedLoopGroup {
  final GoalTrajectoryScope scope;
  final String playerId;
  final int seed;
  final List<ClosedLoopCheckpoint> checkpoints;

  /// The slot each placement first did something, beginner first, per
  /// milestone, or null where it never did.
  final Map<String, List<int?>> milestones;

  ClosedLoopGroup({
    required this.scope,
    required this.playerId,
    required this.seed,
    required Iterable<ClosedLoopCheckpoint> checkpoints,
    required this.milestones,
  }) : checkpoints = List.unmodifiable(checkpoints);

  String get identity => '${scope.name}/$playerId/$seed';

  Map<String, Object?> toJson() => {
    'scope': scope.name,
    'player': playerId,
    'seed': seed,
    'checkpoints': [for (final point in checkpoints) point.toJson()],
    'milestones': milestones,
  };

  factory ClosedLoopGroup.fromJson(Map<String, Object?> json) =>
      ClosedLoopGroup(
        scope: GoalTrajectoryScope.values.byName(json['scope']! as String),
        playerId: json['player']! as String,
        seed: json['seed']! as int,
        checkpoints: [
          for (final point in json['checkpoints']! as List<Object?>)
            ClosedLoopCheckpoint.fromJson(point! as Map<String, Object?>),
        ],
        milestones: {
          for (final MapEntry(:key, :value)
              in (json['milestones']! as Map<String, Object?>).entries)
            key: [for (final slot in value! as List<Object?>) slot as int?],
        },
      );
}

/// Runs [player] from each placement tier under [scope] and compares them.
///
/// The player is the same in all three, so what differs is the starting level
/// and everything the scheduler did because of it: unlike a fixed history,
/// each placement is offered different work and so gathers different
/// evidence.
Future<ClosedLoopGroup> runClosedLoopPlacement({
  required GoalTrajectoryScope scope,
  required SyntheticPlayer player,
  required int seed,
  List<int> checkpoints = closedLoopCheckpoints,
  int slotsPerSitting = 20,
}) async {
  final sittings = checkpoints.reduce(math.max);
  final states = {
    for (final checkpoint in checkpoints) checkpoint: <LearnerState>[],
  };
  final runs = <GoalTrajectoryRun>[];
  for (final tier in PlacementTier.values) {
    runs.add(
      await runGoalTrajectory(
        scope: scope,
        player: player,
        seed: seed,
        sittings: sittings,
        slotsPerSitting: slotsPerSitting,
        placement: tier,
        afterSitting: (sitting, _, session) {
          states[sitting + 1]?.add(session.state.copy());
        },
      ),
    );
  }

  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];
  final plan = scope.plan.resolve(catalog) as ResolvedPlan;
  final resolved =
      (PracticeScopeResolver().resolve(
                goal: plan.goal,
                focus: plan.focus,
                catalog: catalog,
                instrument: InstrumentProfile(),
              )
              as ValidPracticeScope)
          .scope;
  final candidates = distinctCandidatesOf(resolved.requirements);
  const learner = LearnerModel();
  final pipeline = SchedulerPipeline(learner: learner);
  final start = DateTime.utc(2026);

  final compared = <ClosedLoopCheckpoint>[];
  var previous = 0;
  for (final checkpoint in checkpoints) {
    final at = start.add(Duration(days: checkpoint, hours: 23));
    final atCheckpoint = [
      for (final state in states[checkpoint]!) state.copy(),
    ];
    for (final state in atCheckpoint) {
      learner.propagate(state, at);
    }
    compared.add(
      ClosedLoopCheckpoint(
        sittings: checkpoint,
        covered: [
          for (final run in runs) _coveredBy(run, checkpoint * slotsPerSitting),
        ],
        mixDistance: {
          for (final MapEntry(key: facet, value: of) in _facets.entries)
            facet: _largestDistance([
              for (final run in runs)
                [
                  for (final pick in run.selections)
                    if (pick.sitting >= previous && pick.sitting < checkpoint)
                      of(pick),
                ],
            ]),
        },
        eligibleOverlap: _eligibleOverlap(atCheckpoint, candidates, pipeline),
        samePick:
            {
              for (final state in atCheckpoint)
                switch (pipeline
                    .evaluateSlot(
                      state: state.copy(),
                      session: SessionState(),
                      candidates: candidates,
                      at: at,
                    )
                    .result) {
                  CandidateSelected(:final candidate) => candidate.exercise,
                  _ => null,
                },
            }.length ==
            1,
      ),
    );
    previous = checkpoint;
  }

  return ClosedLoopGroup(
    scope: scope,
    playerId: player.id,
    seed: seed,
    checkpoints: compared,
    milestones: {
      'first_unguided': [
        for (final run in runs)
          run.firstSlotWhere((pick) => !pick.guidance.isMaterialSupplied),
      ],
      'first_hands_together': [
        for (final run in runs)
          run.firstSlotWhere(
            (pick) => pick.hands == HandConfiguration.together,
          ),
      ],
      'first_two_octaves': [
        for (final run in runs) run.firstSlotWhere((pick) => pick.octaves >= 2),
      ],
      'half_covered': [for (final run in runs) run.slotCovering(0.5)],
      'fully_covered': [for (final run in runs) run.slotCovering(1)],
    },
  );
}

final Map<String, Object Function(GoalTrajectorySelection)> _facets = {
  'guidance': (pick) => pick.guidance,
  'hands': (pick) => pick.hands,
  'octaves': (pick) => pick.octaves,
  'direction': (pick) => pick.direction,
  'family': (pick) => pick.familyId,
};

/// Coverage reached by the time [slots] picks had been made.
double _coveredBy(GoalTrajectoryRun run, int slots) {
  if (run.targetCount == 0) return 0;
  var covered = 0;
  for (final pick in run.selections) {
    if (pick.slot >= slots) break;
    covered = pick.coveredBefore;
  }
  if (run.selections.length <= slots) covered = run.finalCovered;
  return covered / run.targetCount;
}

/// The largest total variation distance between two of [samples].
double _largestDistance(List<List<Object>> samples) {
  Map<Object, double> shares(List<Object> picks) {
    final counts = <Object, double>{};
    for (final pick in picks) {
      counts[pick] = (counts[pick] ?? 0) + 1;
    }
    return {
      for (final entry in counts.entries) entry.key: entry.value / picks.length,
    };
  }

  var largest = 0.0;
  for (var a = 0; a < samples.length; a++) {
    for (var b = a + 1; b < samples.length; b++) {
      if (samples[a].isEmpty || samples[b].isEmpty) continue;
      final left = shares(samples[a]);
      final right = shares(samples[b]);
      var distance = 0.0;
      for (final key in {...left.keys, ...right.keys}) {
        distance += ((left[key] ?? 0) - (right[key] ?? 0)).abs();
      }
      largest = math.max(largest, distance / 2);
    }
  }
  return largest;
}

double _eligibleOverlap(
  List<LearnerState> states,
  List<Exercise> candidates,
  SchedulerPipeline pipeline,
) {
  final sets = [
    for (final state in states)
      {
        for (final exercise in candidates)
          if (pipeline.eligibilityFor(state, exercise).tier ==
              EligibilityTier.fullyEligible)
            exercise,
      },
  ];
  var overlap = 1.0;
  for (var a = 0; a < sets.length; a++) {
    for (var b = a + 1; b < sets.length; b++) {
      final union = sets[a].union(sets[b]).length;
      if (union == 0) continue;
      overlap = math.min(overlap, sets[a].intersection(sets[b]).length / union);
    }
  }
  return overlap;
}

/// Runs every group not in [done], reporting each to [onGroup] as it lands.
Future<List<ClosedLoopGroup>> runClosedLoopPlacementMatrix({
  Iterable<GoalTrajectoryScope> scopes = const [
    GoalTrajectoryScope.general,
    GoalTrajectoryScope.foundations,
  ],
  Iterable<SyntheticPlayer>? players,
  int seeds = 2,
  List<int> checkpoints = closedLoopCheckpoints,
  int parallelism = 1,
  Set<String> done = const {},
  void Function(ClosedLoopGroup group)? onGroup,
  void Function(int completed, int total)? onProgress,
}) async {
  final tasks = [
    for (final scope in scopes)
      for (final player in players ?? PlayerArchetypes.all)
        for (var seed = 0; seed < seeds; seed++)
          if (!done.contains('${scope.name}/${player.id}/$seed'))
            () => runClosedLoopPlacement(
              scope: scope,
              player: player,
              seed: seed,
              checkpoints: checkpoints,
            ),
  ];
  final groups = <ClosedLoopGroup>[];
  var next = 0;
  var completed = 0;

  Future<void> work() async {
    while (next < tasks.length) {
      final task = tasks[next++];
      final group = await Isolate.run(task);
      groups.add(group);
      onGroup?.call(group);
      onProgress?.call(++completed, tasks.length);
    }
  }

  await Future.wait([
    for (
      var worker = 0;
      worker < parallelism && worker < tasks.length;
      worker++
    )
      work(),
  ]);
  return groups;
}
