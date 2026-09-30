import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'goal_trajectory_experiment.dart';
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

/// The dimensions of an exercise itself, as opposed to how it was admitted.
const Set<String> exerciseDimensions = {
  'material',
  'family',
  'hands',
  'direction',
  'hand motion',
  'octaves',
  'guidance',
  'tempo',
};

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

  /// Whether the learner had practised each side's material before the slot.
  final bool winnerPractised;
  final bool reversedPractised;

  /// What each side's material was to the goal in force: `target`,
  /// `in scope`, or `no goal` for a run without one.
  final String winnerRole;
  final String reversedRole;

  /// Where each side's material stands in the goal's introduction order, or
  /// null outside a goal's targets.
  final int? winnerIntroduction;
  final int? reversedIntroduction;

  const RankTie({
    required this.playerId,
    required this.seed,
    required this.slot,
    required this.tied,
    required this.winner,
    required this.reversed,
    required this.presented,
    required this.winnerPractised,
    required this.reversedPractised,
    this.winnerRole = 'no goal',
    this.reversedRole = 'no goal',
    this.winnerIntroduction,
    this.reversedIntroduction,
  });

  /// Whether the two sides are different materials, which makes the tie a
  /// question of what to practise rather than how.
  bool get isMaterialTie =>
      winner.exercise.material.materialId !=
      reversed.exercise.material.materialId;

  /// Which kind of material question the tie left to order.
  String get materialKind => switch ((winnerPractised, reversedPractised)) {
    (false, false) => 'two new materials',
    (true, true) => 'two practised materials',
    (false, true) => 'new over practised',
    (true, false) => 'practised over new',
  };

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

  /// The trajectory the census read, which is the production one, when it ran
  /// without a goal.
  final Trajectory? trajectory;

  const RankTieCensus({
    required this.slots,
    required this.slotsWithSelection,
    required this.ties,
    this.trajectory,
  });
}

/// The tie [pipeline] left to candidate order in [result], or null when
/// ranking picks the same candidate in either order.
///
/// [roleOf] names what each side's material is to the goal in force.
RankTie? rankTieOf(
  SchedulerPipeline pipeline,
  LearnerState state,
  SelectionResult result, {
  required String playerId,
  required int seed,
  required int slot,
  String Function(Exercise exercise)? roleOf,
  int? Function(Exercise exercise)? introductionOf,
}) {
  if (result is! CandidateSelected) return null;
  final selectable = result.selectable;
  final winner = pipeline.selectBest(selectable);
  final reversed = pipeline.selectBest(selectable.reversed.toList());
  if (winner == null || reversed == null || identical(winner, reversed)) {
    return null;
  }
  return RankTie(
    playerId: playerId,
    seed: seed,
    slot: slot,
    tied: [
      for (final trace in selectable)
        if (pipeline.config.rankTolerances.compare(
              trace.rankKey!,
              winner.rankKey!,
            ) ==
            0)
          trace,
    ].length,
    winner: winner,
    reversed: reversed,
    presented: identical(result.candidate, winner),
    winnerPractised: _practised(state, winner),
    reversedPractised: _practised(state, reversed),
    winnerRole: roleOf?.call(winner.exercise) ?? 'no goal',
    reversedRole: roleOf?.call(reversed.exercise) ?? 'no goal',
    winnerIntroduction: introductionOf?.call(winner.exercise),
    reversedIntroduction: introductionOf?.call(reversed.exercise),
  );
}

/// Runs [player] under [scope]'s goal through the production practice
/// session, and records every slot whose ranking candidate order decided.
///
/// Observational only, like [censusRankTies], but through the path the app
/// takes: the goal's requirements, emphasis, and uncovered targets reach the
/// pipeline exactly as they do in practice.
Future<RankTieCensus> censusGoalRankTies({
  required GoalTrajectoryScope scope,
  required SyntheticPlayer player,
  required int seed,
  int sessions = 10,
  int slotsPerSession = 20,
}) async {
  final ties = <RankTie>[];
  var slots = 0;
  var selections = 0;
  await runGoalTrajectory(
    scope: scope,
    player: player,
    seed: seed,
    sessions: sessions,
    slotsPerSession: slotsPerSession,
    observeSlot: (pipeline, state, result, targetMaterialIds) {
      final introduction = {
        for (final (position, materialId) in targetMaterialIds.indexed)
          materialId: position,
      };
      final index = slots++;
      if (result is CandidateSelected) selections++;
      final tie = rankTieOf(
        pipeline,
        state,
        result,
        playerId: player.id,
        seed: seed,
        slot: index,
        roleOf: (exercise) =>
            targetMaterialIds.contains(exercise.material.materialId)
            ? 'target'
            : 'in scope',
        introductionOf: (exercise) =>
            introduction[exercise.material.materialId],
      );
      if (tie != null) ties.add(tie);
    },
  );
  return RankTieCensus(
    slots: slots,
    slotsWithSelection: selections,
    ties: ties,
  );
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
    if (slot.result is CandidateSelected) selections++;
    if (rankTieOf(
          this,
          state,
          slot.result,
          playerId: playerId,
          seed: seed,
          slot: index,
        )
        case final tie?) {
      ties.add(tie);
    }
    return slot;
  }
}

/// Whether [state] holds evidence of the learner playing [trace]'s material,
/// in any hands or from memory.
bool _practised(LearnerState state, CandidateTrace trace) {
  final materialId = trace.exercise.material.materialId;
  return state.materialMemory[materialId]?.lastObservedAt != null ||
      state.materialExecution.entries.any(
        (entry) =>
            entry.key.$1 == materialId && entry.value.lastEvidenceAt != null,
      );
}
