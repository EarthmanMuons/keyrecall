import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'synthetic_player.dart';
import 'trajectory.dart';
import 'trajectory_run.dart';

/// What one candidate is, along every dimension ranking might not see.
///
/// Each entry names a dimension and the value this candidate has on it, so two
/// tied candidates can be compared field by field.
Map<String, String> tieDimensionsOf(CandidateTrace trace) {
  final exercise = trace.exercise;
  final conditions = exercise.conditions;
  return {
    'material': exercise.material.materialId,
    'family': exercise.material.familyId,
    'hands': conditions.hands.id,
    'direction': conditions.direction.id,
    'hand motion': conditions.handMotion.id,
    'octaves': '${conditions.octaves}',
    'guidance': '${exercise.guidance.independence}',
    'tempo': conditions.tempoBpm.toStringAsFixed(1),
    'bypass': trace.challengeBypass?.id ?? 'none',
    'execution advance': trace.executionAdvance.name,
    'floor reason': trace.challengeFloorReason.name,
    'eligibility': trace.eligibility.code.id,
    'prediction': trace.prediction.overallP.toStringAsFixed(6),
  };
}

/// A slot whose ranking was decided by candidate order.
///
/// [winner] is what ranking picks in the order candidates were generated, and
/// [reversed] what it picks with that order reversed. They are tied on every
/// rank term, so the only thing choosing between them is which came first.
class RankTie {
  final String playerId;
  final int seed;
  final int slot;

  /// How many selectable candidates shared the top rank.
  final int tied;

  final CandidateTrace winner;
  final CandidateTrace reversed;

  /// Whether the slot presented the ranked pick, rather than a stage that
  /// overrides ranking choosing something else.
  final bool presented;

  const RankTie({
    required this.playerId,
    required this.seed,
    required this.slot,
    required this.tied,
    required this.winner,
    required this.reversed,
    required this.presented,
  });

  /// The dimensions the two sides differ on, each with the winning value and
  /// the losing one.
  Map<String, (String, String)> get differences {
    final won = tieDimensionsOf(winner);
    final lost = tieDimensionsOf(reversed);
    return {
      for (final MapEntry(:key, :value) in won.entries)
        if (lost[key] != value) key: (value, lost[key]!),
    };
  }
}

/// What a census of one trajectory saw.
class RankTieCensus {
  final int slots;
  final int slotsWithSelection;
  final List<RankTie> ties;

  /// The trajectory the census read, which is the production one.
  final Trajectory trajectory;

  const RankTieCensus({
    required this.slots,
    required this.slotsWithSelection,
    required this.ties,
    required this.trajectory,
  });
}

/// Runs [player] and records every slot whose ranking candidate order decided.
///
/// Observational only. The trajectory is the production one; the census reads
/// each slot's selectable candidates and asks what ranking would pick in each
/// order, without changing what was chosen.
RankTieCensus censusRankTies({
  required SyntheticPlayer player,
  required int seed,
  required List<TechnicalMaterial> materials,
  int slots = 40,
  SchedulerConfig config = v1SchedulerConfig,
}) {
  final recorder = _TieRecorder(
    learner: const LearnerModel(),
    config: config,
    playerId: player.id,
    seed: seed,
  );
  final trajectory = runTrajectory(
    player: player,
    seed: seed,
    materials: materials,
    slots: slots,
    pipeline: recorder,
  );
  return RankTieCensus(
    slots: recorder.slots,
    slotsWithSelection: recorder.selections,
    ties: recorder.ties,
    trajectory: trajectory,
  );
}

class _TieRecorder extends SchedulerPipeline {
  final String playerId;
  final int seed;
  final List<RankTie> ties = [];
  int slots = 0;
  int selections = 0;

  _TieRecorder({
    required super.learner,
    required super.config,
    required this.playerId,
    required this.seed,
  });

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Set<(String, Hand)>? retrievedMaterialHands,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    Map<String, Set<RealizationShape>> demonstratedShapes = const {},
    bool diagnose = true,
  }) {
    final slot = super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      attemptedExercises: attemptedExercises,
      retrievedMaterialHands: retrievedMaterialHands,
      executionEvidenceRevisions: executionEvidenceRevisions,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      demonstratedShapes: demonstratedShapes,
      diagnose: diagnose,
    );
    final index = slots++;
    final result = slot.result;
    if (result case CandidateSelected(:final candidate)) {
      selections++;
      final selectable = result.selectable;
      final winner = selectBest(selectable);
      final reversed = selectBest(selectable.reversed.toList());
      if (winner != null && reversed != null && !identical(winner, reversed)) {
        ties.add(
          RankTie(
            playerId: playerId,
            seed: seed,
            slot: index,
            tied: [
              for (final trace in selectable)
                if (config.rankTolerances.compare(
                      trace.rankKey!,
                      winner.rankKey!,
                    ) ==
                    0)
                  trace,
            ].length,
            winner: winner,
            reversed: reversed,
            presented: identical(candidate, winner),
          ),
        );
      }
    }
    return slot;
  }
}
