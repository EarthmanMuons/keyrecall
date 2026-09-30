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

/// Sees each slot a goal trajectory decides: the pipeline deciding it, the
/// state it was decided from, what it decided, and the goal's target
/// materials.
typedef GoalSlotObserver =
    void Function(
      SchedulerPipeline pipeline,
      LearnerState state,
      SelectionResult result,
      Set<String> targetMaterialIds,
    );

/// How one session ended.
enum SessionEnd { slotLimit, caughtUp, blocked, invalid }

/// One presented attempt, as much of it as the census reads.
class GoalTrajectorySelection {
  final int slot;
  final int session;
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

  /// What the shape frontier could do with this decision, and did.
  final ShapeStepObservation? shapeStep;

  const GoalTrajectorySelection({
    required this.slot,
    required this.session,
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
    this.shapeStep,
  });
}

class GoalTrajectoryRun {
  final GoalTrajectoryScope scope;
  final String playerId;
  final int seed;
  final int targetCount;
  final int finalCovered;
  final List<GoalTrajectorySelection> selections;
  final List<SessionEnd> sessions;

  GoalTrajectoryRun({
    required this.scope,
    required this.playerId,
    required this.seed,
    required this.targetCount,
    required this.finalCovered,
    required Iterable<GoalTrajectorySelection> selections,
    required Iterable<SessionEnd> sessions,
  }) : selections = List.unmodifiable(selections),
       sessions = List.unmodifiable(sessions);

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

/// Runs [player] under [scope] over daily sessions.
///
/// [placement] replaces the player's own, for runs that ask what the starting
/// level alone changes. [afterSession] sees the learner state as each session
/// closes, before the next one opens.
Future<GoalTrajectoryRun> runGoalTrajectory({
  required GoalTrajectoryScope scope,
  required SyntheticPlayer player,
  required int seed,
  int sessions = 10,
  int slotsPerSession = 20,
  PlacementTier? placement,
  ProgressPreference? progress,
  void Function(int sessionIndex, int slots, PracticeSession session)?
  afterSession,
  GoalSlotObserver? observeSlot,
}) async {
  final at0 = DateTime.utc(2026);
  const learner = LearnerModel();
  final pipeline = _ShapeStepRecorder(
    learner: learner,
    config: progress == null
        ? v1SchedulerConfig
        : v1SchedulerConfig.withProgress(progress),
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
  if (observeSlot != null) {
    pipeline.onSlot = (state, result) =>
        observeSlot(pipeline, state, result, targetMaterialIds);
  }
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
  final ends = <SessionEnd>[];
  var ids = 0;
  var slot = 0;
  late PracticeSession session;

  for (var sessionIndex = 0; sessionIndex < sessions; sessionIndex++) {
    final start = at0.add(Duration(days: sessionIndex + 1));
    playing.restUntil(start);
    session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: catalog,
      learner: learner,
      pipeline: pipeline,
      goal: resolution.goal,
      focus: resolution.focus,
      sessionId: '$name-$sessionIndex',
      nextId: () => '$name-${ids++}',
    );
    var end = SessionEnd.slotLimit;
    for (var index = 0; index < slotsPerSession; index++) {
      final at = start.add(Duration(minutes: index));
      pipeline.last = null;
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
            session: sessionIndex,
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
            shapeStep: pipeline.last,
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
          end = SessionEnd.caughtUp;
        case PracticeBlocked():
          end = SessionEnd.blocked;
        default:
          end = SessionEnd.invalid;
      }
      break;
    }
    ends.add(end);
    afterSession?.call(sessionIndex, slot, session);
  }

  final evaluated = const PracticeScopeEvaluator().evaluate(
    scope: resolved,
    state: session.state,
    journal: session.journal,
    learner: learner,
    at: at0.add(Duration(days: sessions + 1)),
  );
  return GoalTrajectoryRun(
    scope: scope,
    playerId: player.id,
    seed: seed,
    targetCount: evaluated.coverage.targetCount,
    finalCovered: evaluated.coverage.coveredTargets,
    selections: selections,
    sessions: ends,
  );
}

Future<List<GoalTrajectoryRun>> runGoalTrajectoryMatrix({
  Iterable<GoalTrajectoryScope> scopes = GoalTrajectoryScope.values,
  Iterable<SyntheticPlayer>? players,
  int seeds = 4,
  int sessions = 10,
  int slotsPerSession = 20,
  int parallelism = 1,
  ProgressPreference? progress,
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
            sessions: sessions,
            slotsPerSession: slotsPerSession,
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

/// How one decision stood toward the shape frontier.
class ShapeStepObservation {
  /// How ranking's choice was admitted: a bypass id, or `band`.
  final String route;

  /// Whether that choice was progression a shape step may replace.
  final bool replaceable;

  /// Whether a shape step of its material was on offer in its place.
  final bool opportunity;

  /// Which way the step presented instead went, if one was.
  final ShapeStep? step;

  /// How the step presented instead was admitted, if one was.
  final String? stepRoute;

  const ShapeStepObservation({
    required this.route,
    required this.replaceable,
    required this.opportunity,
    this.step,
    this.stepRoute,
  });

  bool get replaced => step != null;
}

class _ShapeStepRecorder extends SchedulerPipeline {
  ShapeStepObservation? last;
  void Function(LearnerState state, SelectionResult result)? onSlot;

  _ShapeStepRecorder({required super.learner, required super.config});

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
    onSlot?.call(state, slot.result);
    return slot;
  }

  @override
  CandidateTrace? advancedWithin(
    List<CandidateTrace> selectable,
    CandidateTrace? chosen, {
    Map<String, Set<RealizationShape>> demonstratedShapes = const {},
  }) {
    final presented = super.advancedWithin(
      selectable,
      chosen,
      demonstratedShapes: demonstratedShapes,
    );
    if (chosen == null || presented == null) return presented;
    String routeOf(CandidateTrace trace) => trace.challengeBypass?.id ?? 'band';
    Set<RealizationShape> shapesOf(CandidateTrace trace) =>
        demonstratedShapes[trace.exercise.material.materialId] ?? const {};
    final replaceable =
        SchedulerPipeline.isProgression(chosen) &&
        !chosen.rankKey!.coordinationTransition &&
        !chosen.rankKey!.targetShaped &&
        !advancesShapeFrontier(chosen.exercise, shapesOf(chosen));
    final replaced = presented != chosen;
    last = ShapeStepObservation(
      route: routeOf(chosen),
      replaceable: replaceable,
      opportunity:
          replaceable &&
          selectable.any(
            (trace) =>
                trace.isRanked &&
                trace.exercise.material == chosen.exercise.material &&
                trace.exercise.guidance == chosen.exercise.guidance &&
                trace.rankKey!.tier == chosen.rankKey!.tier &&
                SchedulerPipeline.isProgression(trace) &&
                advancesShapeFrontier(trace.exercise, shapesOf(trace)),
          ),
      step: replaced
          ? shapeStepOf(presented.exercise, shapesOf(presented))
          : null,
      stepRoute: replaced ? routeOf(presented) : null,
    );
    return presented;
  }
}
