import 'dart:isolate';
import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'player_archetypes.dart';
import 'synthetic_player.dart';
import 'trajectory.dart';
import 'trajectory_run.dart';

/// Attempts after which the three placements are compared.
const List<int> placementCheckpoints = [30, 60, 120, 200, 500];

/// How far apart the three placements' learner states are after one history.
///
/// Each figure is the largest over the three pairs, so a checkpoint says how
/// much the starting level could still matter, not how much it matters on
/// average.
class PlacementDivergence {
  final int attempts;

  /// The largest gap in a competency mean, over competencies every placement
  /// has observed.
  final double observedCompetency;

  /// The same over competencies no attempt has observed, which keep whatever
  /// placement seeded.
  final double unobservedCompetency;

  /// Mean and largest gap in predicted success over the common candidates.
  final double meanPrediction;
  final double maxPrediction;

  /// Share of candidates whose challenge-band membership differs.
  final double bandDisagreement;

  /// Share of candidates whose eligibility tier differs.
  final double eligibilityDisagreement;

  /// Whether one decision from a fresh sitting chose the same exercise.
  final bool sameSelection;

  Map<String, Object?> toJson() => {
    'attempts': attempts,
    'observed_competency': observedCompetency,
    'unobserved_competency': unobservedCompetency,
    'mean_prediction': meanPrediction,
    'max_prediction': maxPrediction,
    'band_disagreement': bandDisagreement,
    'eligibility_disagreement': eligibilityDisagreement,
    'same_selection': sameSelection,
  };

  factory PlacementDivergence.fromJson(Map<String, Object?> json) =>
      PlacementDivergence(
        attempts: json['attempts']! as int,
        observedCompetency: (json['observed_competency']! as num).toDouble(),
        unobservedCompetency: (json['unobserved_competency']! as num)
            .toDouble(),
        meanPrediction: (json['mean_prediction']! as num).toDouble(),
        maxPrediction: (json['max_prediction']! as num).toDouble(),
        bandDisagreement: (json['band_disagreement']! as num).toDouble(),
        eligibilityDisagreement: (json['eligibility_disagreement']! as num)
            .toDouble(),
        sameSelection: json['same_selection']! as bool,
      );

  const PlacementDivergence({
    required this.attempts,
    required this.observedCompetency,
    required this.unobservedCompetency,
    required this.meanPrediction,
    required this.maxPrediction,
    required this.bandDisagreement,
    required this.eligibilityDisagreement,
    required this.sameSelection,
  });
}

class PlacementConvergenceRun {
  final String playerId;
  final int seed;
  final List<PlacementDivergence> checkpoints;

  PlacementConvergenceRun({
    required this.playerId,
    required this.seed,
    required Iterable<PlacementDivergence> checkpoints,
  }) : checkpoints = List.unmodifiable(checkpoints);

  /// Which history this is, and what a resumed run skips.
  String get identity => '$playerId/$seed';

  Map<String, Object?> toJson() => {
    'player': playerId,
    'seed': seed,
    'checkpoints': [for (final point in checkpoints) point.toJson()],
  };

  factory PlacementConvergenceRun.fromJson(Map<String, Object?> json) =>
      PlacementConvergenceRun(
        playerId: json['player']! as String,
        seed: json['seed']! as int,
        checkpoints: [
          for (final point in json['checkpoints']! as List<Object?>)
            PlacementDivergence.fromJson(point! as Map<String, Object?>),
        ],
      );
}

/// Every realization the production catalog generates, across both families.
List<Exercise> productionCandidates(InstrumentProfile instrument) => [
  ...generateCandidates(instrument, allScales),
  for (final material in allRootPositionArpeggios)
    ...const ArpeggioPracticeMaterialFamily().generate(instrument, material),
];

/// Replays one history of [player] into each placement tier and compares
/// them at [checkpoints].
///
/// The history is generated once, by the scheduler, from the player's own
/// placement, and then only its exercises, outcomes, and times are replayed:
/// every placement sees exactly the same evidence, so any gap left is the
/// placement prior and nothing else.
PlacementConvergenceRun runPlacementConvergence({
  required SyntheticPlayer player,
  required int seed,
  List<int> checkpoints = placementCheckpoints,
  int slotsPerSitting = 20,
}) {
  final instrument = InstrumentProfile();
  final candidates = productionCandidates(instrument);
  const learner = LearnerModel();
  final pipeline = SchedulerPipeline(learner: learner);
  final horizon = checkpoints.reduce(math.max);
  final start = DateTime.utc(2026);
  final history = runSittings(
    player: player,
    seed: seed,
    materials: [...allScales, ...allRootPositionArpeggios],
    generated: candidates,
    sittings: [
      for (var day = 0; day * slotsPerSitting < horizon; day++)
        Sitting(
          at: start.add(Duration(days: day)),
          slots: slotsPerSitting,
        ),
    ],
    pipeline: pipeline,
    traceRetention: TraceRetention.selectedOnly,
  );

  final states = {
    for (final tier in PlacementTier.values)
      tier: learner.placementState(tier, at: start),
  };
  final compared = <PlacementDivergence>[];
  var applied = 0;
  for (final slot in history.slots) {
    for (final state in states.values) {
      learner.propagateAndApplyOutcome(
        state: state,
        exercise: slot.chosen,
        outcome: slot.outcome,
        weights: evidenceWeightsFor(slot.chosen, slot.outcome),
        prediction: learner.predict(state, slot.chosen, at: slot.at),
        at: slot.at,
      );
    }
    applied++;
    if (checkpoints.contains(applied)) {
      compared.add(
        _divergenceAt(
          applied,
          states.values.toList(),
          candidates,
          pipeline,
          slot.at,
        ),
      );
    }
  }
  return PlacementConvergenceRun(
    playerId: player.id,
    seed: seed,
    checkpoints: compared,
  );
}

PlacementDivergence _divergenceAt(
  int attempts,
  List<LearnerState> states,
  List<Exercise> candidates,
  SchedulerPipeline pipeline,
  DateTime at,
) {
  final learner = pipeline.learner;
  final challenge = pipeline.config.challenge;
  var observed = 0.0;
  var unobserved = 0.0;
  for (final competency in Competency.values) {
    final means = [
      for (final state in states) state.competency(competency).mean,
    ];
    final gap = means.reduce(math.max) - means.reduce(math.min);
    if (states.every((state) => state.isObserved(competency))) {
      observed = math.max(observed, gap);
    } else {
      unobserved = math.max(unobserved, gap);
    }
  }

  var sum = 0.0;
  var largest = 0.0;
  var bandDiffers = 0;
  var eligibilityDiffers = 0;
  for (final exercise in candidates) {
    final predictions = [
      for (final state in states)
        learner.predict(state, exercise, at: at).overallP,
    ];
    final gap = predictions.reduce(math.max) - predictions.reduce(math.min);
    sum += gap;
    largest = math.max(largest, gap);
    final inBand = {
      for (final p in predictions) p >= challenge.pMin && p <= challenge.pMax,
    };
    if (inBand.length > 1) bandDiffers++;
    final tiers = {
      for (final state in states) pipeline.eligibilityFor(state, exercise).tier,
    };
    if (tiers.length > 1) eligibilityDiffers++;
  }

  final chosen = {
    for (final state in states)
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
  };

  return PlacementDivergence(
    attempts: attempts,
    observedCompetency: observed,
    unobservedCompetency: unobserved,
    meanPrediction: sum / candidates.length,
    maxPrediction: largest,
    bandDisagreement: bandDiffers / candidates.length,
    eligibilityDisagreement: eligibilityDiffers / candidates.length,
    sameSelection: chosen.length == 1,
  );
}

/// Runs every history not in [done], reporting each to [onRun] as it lands.
///
/// Results arrive as they finish rather than at the end, so an interrupted
/// matrix keeps what it completed and a rerun passes those identities back as
/// [done].
Future<List<PlacementConvergenceRun>> runPlacementConvergenceMatrix({
  Iterable<SyntheticPlayer>? players,
  int seeds = 2,
  List<int> checkpoints = placementCheckpoints,
  int parallelism = 1,
  Set<String> done = const {},
  void Function(PlacementConvergenceRun run)? onRun,
  void Function(int completed, int total)? onProgress,
}) async {
  final tasks = [
    for (final player in players ?? PlayerArchetypes.all)
      for (var seed = 0; seed < seeds; seed++)
        if (!done.contains('${player.id}/$seed'))
          () => runPlacementConvergence(
            player: player,
            seed: seed,
            checkpoints: checkpoints,
          ),
  ];
  final runs = List<PlacementConvergenceRun?>.filled(tasks.length, null);
  var next = 0;
  var completed = 0;

  Future<void> work() async {
    while (next < tasks.length) {
      final index = next++;
      final run = await Isolate.run(tasks[index]);
      runs[index] = run;
      onRun?.call(run);
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
  return [for (final run in runs) run!];
}
