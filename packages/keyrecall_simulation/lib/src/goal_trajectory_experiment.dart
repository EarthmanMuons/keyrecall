import 'dart:isolate';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'player_archetypes.dart';
import 'python_compatible_random.dart';
import 'synthetic_performance.dart';
import 'synthetic_player.dart';

/// A production goal, with or without a narrow focus inside it.
enum GoalTrajectoryScope {
  general('GENERAL_FLUENCY'),
  foundations('FOUNDATIONS'),
  keyFluency('KEY_FLUENCY_24'),
  generalFocusedOnDHarmonic('GENERAL_FLUENCY'),
  foundationsFocusedOnBFlat('FOUNDATIONS'),
  keyFluencyFocusedOnD('KEY_FLUENCY_24');

  const GoalTrajectoryScope(this.goalId);

  final String goalId;

  /// The plan a learner choosing this would hold.
  PracticePlan get plan => switch (this) {
    general || foundations || keyFluency => PracticePlan(goalId: goalId),
    generalFocusedOnDHarmonic => _focused(
      MaterialFocus(scaleFormIds: {ScaleForm.harmonicMinor.id}, tonics: {'D'}),
    ),
    foundationsFocusedOnBFlat => _focused(
      MaterialFocus(scaleFormIds: {ScaleForm.major.id}, tonics: {'Bb'}),
    ),
    keyFluencyFocusedOnD => _focused(
      MaterialFocus(
        scaleFormIds: {ScaleForm.major.id},
        arpeggioQualityIds: {ArpeggioQuality.major.id},
        tonics: {'D'},
      ),
    ),
  };

  PracticePlan _focused(MaterialFocus material) =>
      PracticePlan(goalId: goalId).focusedOn(
        ActiveFocus(
          material: material,
          strength: FocusStrength.exclusive,
          label: name,
        ),
      );

  /// Whether this scope names an end it can be finished at.
  bool get hasFinishLine => this != general;
}

/// How one sitting ended.
enum SittingEnd { slotLimit, caughtUp, blocked, invalid }

/// One presented attempt, as much of it as the census reads.
class GoalTrajectorySelection {
  final int slot;
  final int sitting;
  final String materialId;
  final String familyId;
  final ScaleForm? form;
  final HandConfiguration hands;
  final int octaves;
  final ExerciseDirection direction;
  final GuidanceContext guidance;
  final bool isTarget;
  final bool isTargetShaped;
  final bool isLiveSupport;
  final int coveredBefore;

  /// Whether the attempt was played through with the pitch accuracy coverage
  /// asks for, whatever it was retrieved from.
  final bool clean;

  /// The overall success the scheduler predicted when it chose this.
  final double predicted;

  const GoalTrajectorySelection({
    required this.slot,
    required this.sitting,
    required this.materialId,
    required this.familyId,
    required this.form,
    required this.hands,
    required this.octaves,
    required this.direction,
    required this.guidance,
    required this.isTarget,
    required this.isTargetShaped,
    required this.isLiveSupport,
    required this.coveredBefore,
    required this.clean,
    required this.predicted,
  });
}

class GoalTrajectoryRun {
  final GoalTrajectoryScope scope;
  final String playerId;
  final int seed;
  final int targetCount;
  final int finalCovered;
  final List<GoalTrajectorySelection> selections;
  final List<SittingEnd> sittings;

  GoalTrajectoryRun({
    required this.scope,
    required this.playerId,
    required this.seed,
    required this.targetCount,
    required this.finalCovered,
    required Iterable<GoalTrajectorySelection> selections,
    required Iterable<SittingEnd> sittings,
  }) : selections = List.unmodifiable(selections),
       sittings = List.unmodifiable(sittings);

  bool get isComplete => targetCount > 0 && finalCovered == targetCount;

  /// The first slot at which [fraction] of the targets were covered, or null.
  ///
  /// Read off the coverage each decision reported before its attempt, so the
  /// slot is the one after the attempt that reached it.
  int? slotCovering(double fraction) {
    final wanted = (fraction * targetCount).ceil();
    if (wanted == 0) return null;
    for (final selection in selections) {
      if (selection.coveredBefore >= wanted) return selection.slot;
    }
    return finalCovered >= wanted ? selections.length : null;
  }

  int? firstSlotWhere(bool Function(GoalTrajectorySelection) test) {
    for (final selection in selections) {
      if (test(selection)) return selection.slot;
    }
    return null;
  }

  int count(bool Function(GoalTrajectorySelection) test) =>
      selections.where(test).length;
}

/// Runs [player] under [scope] over daily sittings.
///
/// [placement] replaces the player's own, for runs that ask what the starting
/// level alone changes. [afterSitting] sees the learner state as each sitting
/// closes, before the next one opens.
Future<GoalTrajectoryRun> runGoalTrajectory({
  required GoalTrajectoryScope scope,
  required SyntheticPlayer player,
  required int seed,
  int sittings = 10,
  int slotsPerSitting = 20,
  PlacementTier? placement,
  ProgressPreference progress = ProgressPreference.materialOnly,
  void Function(int sitting, int slots, PracticeSession session)? afterSitting,
}) async {
  final at0 = DateTime.utc(2026);
  const learner = LearnerModel();
  final pipeline = SchedulerPipeline(
    learner: learner,
    config: v1SchedulerConfig.withProgress(progress),
  );
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];
  final plan = scope.plan;
  final resolution = plan.resolve(catalog) as ResolvedPlan;
  final resolved =
      (PracticeScopeResolver().resolve(
                goal: resolution.goal,
                focus: resolution.focus,
                catalog: catalog,
                instrument: InstrumentProfile(),
              )
              as ValidPracticeScope)
          .scope;
  final targets = [
    for (final requirement in resolved.requirements)
      if (requirement.isTarget) requirement,
  ];
  final targetMaterialIds = {
    for (final requirement in targets) requirement.material.materialId,
  };
  bool targetShaped(Exercise exercise) => targets.any(
    (requirement) =>
        requirement.material == exercise.material &&
        requirement.requirement.constraints.matchesStructure(exercise),
  );

  final name = '${scope.name}-${player.id}-$seed-${placement?.name ?? 'own'}';
  final store = InMemoryPracticeStore(createdAt: at0);
  final profile = Profile(
    id: name,
    displayName: player.id,
    createdAt: at0,
    placement: placement ?? player.placement,
  );
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final selections = <GoalTrajectorySelection>[];
  final ends = <SittingEnd>[];
  var ids = 0;
  var slot = 0;
  late PracticeSession session;

  for (var sitting = 0; sitting < sittings; sitting++) {
    final start = at0.add(Duration(days: sitting + 1));
    playing.restUntil(start);
    session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: catalog,
      learner: learner,
      pipeline: pipeline,
      goal: resolution.goal,
      focus: resolution.focus,
      sessionId: '$name-$sitting',
      nextId: () => '$name-${ids++}',
    );
    var end = SittingEnd.slotLimit;
    for (var index = 0; index < slotsPerSitting; index++) {
      final at = start.add(Duration(minutes: index));
      final outcome = await session.decideOutcome(at: at);
      if (outcome case PresentedAttempt(
        :final exercise,
        :final decision,
        :final coverage,
        :final liveSupportMaterialIds,
        :final prediction,
      )) {
        final conditions = exercise.conditions;
        final played = playing.play(exercise, random);
        selections.add(
          GoalTrajectorySelection(
            slot: slot++,
            sitting: sitting,
            materialId: exercise.material.materialId,
            familyId: exercise.material.familyId,
            form: exercise.material.scaleForm,
            hands: conditions.hands,
            octaves: conditions.octaves,
            direction: conditions.direction,
            guidance: exercise.guidance,
            isTarget: targetMaterialIds.contains(exercise.material.materialId),
            isTargetShaped: targetShaped(exercise),
            isLiveSupport: liveSupportMaterialIds.contains(
              exercise.material.materialId,
            ),
            coveredBefore: coverage?.coveredTargets ?? 0,
            clean:
                played.completed &&
                played.pitchIntegrity >=
                    RequirementCompletionPolicy.standard.minimumPitchIntegrity,
            predicted: prediction.overallP,
          ),
        );
        await session.acknowledgePresentation(decision.attemptId);
        await session.closeWithOutcome(played, observedWallTime: at);
        continue;
      }
      switch (outcome) {
        case PresentedAcquisition(:final task):
          await session.closeAcquisition(
            performAcquisition(state: playing, task: task, rng: random),
            at: at,
          );
          continue;
        case PracticeCaughtUp():
          end = SittingEnd.caughtUp;
        case PracticeBlocked():
          end = SittingEnd.blocked;
        default:
          end = SittingEnd.invalid;
      }
      break;
    }
    ends.add(end);
    afterSitting?.call(sitting, slot, session);
  }

  final evaluated = const PracticeScopeEvaluator().evaluate(
    scope: resolved,
    state: session.state,
    journal: session.journal,
    learner: learner,
    at: at0.add(Duration(days: sittings + 1)),
  );
  return GoalTrajectoryRun(
    scope: scope,
    playerId: player.id,
    seed: seed,
    targetCount: evaluated.coverage.targetCount,
    finalCovered: evaluated.coverage.coveredTargets,
    selections: selections,
    sittings: ends,
  );
}

Future<List<GoalTrajectoryRun>> runGoalTrajectoryMatrix({
  Iterable<GoalTrajectoryScope> scopes = GoalTrajectoryScope.values,
  Iterable<SyntheticPlayer>? players,
  int seeds = 4,
  int sittings = 10,
  int slotsPerSitting = 20,
  int parallelism = 1,
  ProgressPreference progress = ProgressPreference.materialOnly,
  void Function(int completed, int total)? onProgress,
}) async {
  if (parallelism < 1) {
    throw ArgumentError.value(parallelism, 'parallelism', 'must be positive');
  }
  final tasks = [
    for (final scope in scopes)
      for (final player in players ?? PlayerArchetypes.all)
        for (var seed = 0; seed < seeds; seed++)
          () => runGoalTrajectory(
            scope: scope,
            player: player,
            seed: seed,
            sittings: sittings,
            slotsPerSitting: slotsPerSitting,
            progress: progress,
          ),
  ];
  final runs = List<GoalTrajectoryRun?>.filled(tasks.length, null);
  var next = 0;
  var completed = 0;

  Future<void> work() async {
    while (next < tasks.length) {
      final index = next++;
      runs[index] = await Isolate.run(tasks[index]);
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
