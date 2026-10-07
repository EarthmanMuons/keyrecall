import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:kiri_check/stateful_test.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

const LearnerModel learner = LearnerModel();
final DateTime createdAt = DateTime.utc(2026);
final List<TechnicalMaterial> catalog = [
  ...allScales,
  ...allRootPositionArpeggios,
];

/// Every production goal and focus the simulation plays, and soft focuses,
/// so emphasis reaches the scheduler too.
final List<PracticePlan> plans = [
  for (final scope in GoalTrajectoryScope.values) scope.plan,
  const PracticePlan(goalId: 'GENERAL_FLUENCY').focusedOn(
    ActiveFocus(
      material: MaterialFocus(scaleFormIds: {ScaleForm.naturalMinor.id}),
      strength: FocusStrength.emphasis,
      label: 'natural minors',
    ),
  ),
  const PracticePlan(goalId: 'KEY_FLUENCY_24').focusedOn(
    ActiveFocus(
      material: MaterialFocus(arpeggioQualityIds: {ArpeggioQuality.major.id}),
      strength: FocusStrength.emphasis,
      label: 'major arpeggios',
    ),
  ),
];

/// The archetypes a sweep leaves out because only a session supplies what
/// they are for: a pulse, or supported work.
final List<SyntheticPlayer> occasionalPlayers = [
  PlayerArchetypes.unsteadyPulseTransfers,
  PlayerArchetypes.unsteadyPulseRelapses,
  PlayerArchetypes.unsteadyPulseUnresponsive,
  PlayerArchetypes.crossingLimited,
];

/// What one slot asked the scheduler, as it arrived.
class SlotContext {
  final String stateHash;
  final List<Exercise> candidates;
  final AcquisitionFloor? acquisitionFloor;
  final AcquisitionFloor? acquisitionFamilyFloor;
  final AcquisitionProgress? acquisition;
  final AttemptHistory? history;
  final GoalEmphasis emphasis;
  final UncoveredTargets uncoveredTargets;
  SelectionResult? result;

  SlotContext({
    required this.stateHash,
    required this.candidates,
    required this.acquisitionFloor,
    required this.acquisitionFamilyFloor,
    required this.acquisition,
    required this.history,
    required this.emphasis,
    required this.uncoveredTargets,
  });
}

/// Thrown once a slot's context is recorded, so a session opened only to be
/// asked what it would send never decides.
class _Recorded implements Exception {
  const _Recorded();
}

/// The production pipeline, recording what each slot was asked.
class RecordingPipeline extends SchedulerPipeline {
  /// Whether to stop at the recording rather than decide.
  final bool askOnly;

  SlotContext? last;

  RecordingPipeline({this.askOnly = false}) : super(learner: learner);

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
    AttemptHistory? history,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    bool diagnose = true,
  }) {
    final context = last = SlotContext(
      stateHash: learnerStateHash(state),
      candidates: candidates,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
    );
    if (askOnly) throw const _Recorded();
    final slot = super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      diagnose: diagnose,
    );
    context.result = slot.result;
    return slot;
  }
}

/// The shapes each material was played through cleanly in, from memory.
Map<String, Set<RealizationShape>> shapesPlayedCleanly(
  Iterable<AttemptRecord> records,
) {
  final shapes = <String, Set<RealizationShape>>{};
  for (final record in records) {
    if (record.exercise.guidance.isMaterialSupplied) continue;
    if (record.closure.measurement case Measured(:final outcome)
        when outcome.started &&
            outcome.completed &&
            outcome.pitchIntegrity >=
                RequirementCompletionPolicy.standard.minimumPitchIntegrity) {
      shapes
          .putIfAbsent(record.exercise.material.materialId, () => {})
          .add(shapeOf(record.exercise));
    }
  }
  return shapes;
}

/// The ordinary attempts that taught the model about executing what they
/// asked.
Iterable<AttemptRecord> executionEvidence(Iterable<AttemptRecord> records) => [
  for (final record in records)
    if (record.closure.measurement case Measured(
      :final outcome,
      :final weights,
    ) when outcome.started && weights.materialExecution > 0)
      record,
];

/// Each material a hand produced from memory.
Set<(String, Hand)> handsThatRetrieved(Iterable<AttemptRecord> records) => {
  for (final record in records)
    if (record.closure.measurement case Measured(
      :final outcome,
    ) when outcome.retrieval == FactualRetrieval.succeeded)
      for (final hand in record.exercise.conditions.hands.hands)
        (record.exercise.material.materialId, hand),
};

void expectSameProgress(
  AcquisitionProgress? actual,
  AcquisitionProgress expected,
  String reason,
) {
  final parents = expected.byParent.keys.toSet();
  expect(actual?.byParent.keys.toSet(), parents, reason: reason);
  for (final parent in parents) {
    expect(actual!.probeOwed(parent), expected.probeOwed(parent));
    expect(actual.earnsParentProbe(parent), expected.earnsParentProbe(parent));
    expect(
      actual.lastCriterionFailureAt(parent),
      expected.lastCriterionFailureAt(parent),
    );
  }
}

List<Exercise>? floorOf(AcquisitionFloor? floor) =>
    floor == null ? null : [for (final entry in floor.entries) entry.exercise];

/// What the live session sent against what a session opened fresh from
/// storage at the same moment would send: everything history determines.
void expectSameHistoryInputs(SlotContext live, SlotContext fresh) {
  expect(live.stateHash, fresh.stateHash, reason: 'learner state');
  expect(live.candidates, fresh.candidates, reason: 'candidates');
  expect(
    floorOf(live.acquisitionFamilyFloor),
    floorOf(fresh.acquisitionFamilyFloor),
    reason: 'family floor',
  );
  expect(
    floorOf(live.acquisitionFloor),
    floorOf(fresh.acquisitionFloor),
    reason: 'acquisition floor',
  );
  expectSameProgress(live.acquisition, fresh.acquisition!, 'acquisition');
  expect(live.emphasis.weightByMaterialId, fresh.emphasis.weightByMaterialId);
  expect(
    [for (final c in live.candidates) live.uncoveredTargets.admits(c)],
    [for (final c in live.candidates) fresh.uncoveredTargets.admits(c)],
    reason: 'uncovered targets',
  );
}

/// What history alone says the slot should have been sent, derived from what
/// storage holds rather than from the session.
Future<void> expectDerivedFromStorage(
  SlotContext live,
  PracticeStore store,
  Profile profile,
  DateTime at,
) async {
  final journal = await store.loadJournal(profile.id);
  final records = journal.records;
  final state = replayJournal(
    journal,
    model: learner,
    initial: learner.placementState(profile.placement, at: createdAt),
  ).state.copy();
  learner.propagate(state, at);
  expect(live.stateHash, learnerStateHash(state), reason: 'state at $at');
  expect(live.history!.demonstratedShapes, shapesPlayedCleanly(records));
  expect(live.history!.retrievedMaterialHands, handsThatRetrieved(records));
  expect(live.history!.startedExercises, {
    for (final record in records)
      if (record.closure.measurement case Measured(
        :final outcome,
      ) when outcome.started)
        record.exercise,
  });
  final evidence = executionEvidence(records);
  expect(live.history!.executionEvidenceExercises, {
    for (final record in evidence) record.exercise,
  });
  final revisions = <ExecutionContext, int>{};
  for (final record in evidence) {
    final context = executionContextOf(record.exercise);
    revisions[context] = (revisions[context] ?? 0) + 1;
  }
  expect(live.history!.executionEvidenceRevisions, revisions);
  expectSameProgress(
    live.acquisition,
    (await store.loadAcquisitionJournal(profile.id)).replay(),
    'acquisition from the durable log',
  );
}

/// The stage that chose [result]'s candidate held to its own contract.
SelectionStage expectStageHeld(SlotContext live, CandidateSelected result) {
  final pipeline = SchedulerPipeline(learner: learner);
  final winner = result.candidate;
  final best = pipeline.selectBest(result.selectable)!;
  bool advances(CandidateTrace trace) => advancesShapeFrontier(
    trace.exercise,
    live.history!.demonstratedShapes[trace.exercise.material.materialId] ??
        const {},
  );
  switch (result.stage) {
    case SelectionStage.ranking:
      expect(identical(winner, best), isTrue, reason: 'ranking chose $winner');
    case SelectionStage.acquisitionProbe:
      expect(winner.challengeBypass, ChallengeBypass.acquisitionProbe);
    case SelectionStage.introductionBreadth:
      expect(winner.challengeBypass, ChallengeBypass.newMaterial);
      expect(best.challengeBypass, ChallengeBypass.newMaterial);
      expect(
        winner.exercise.material.familyId,
        isNot(best.exercise.material.familyId),
      );
    case SelectionStage.pulseCycle:
      expect(
        winner.challengeBypass,
        anyOf(ChallengeBypass.pulseSupport, ChallengeBypass.pulseWithdrawal),
      );
    case SelectionStage.guidanceProbe:
      expect(winner.challengeBypass, ChallengeBypass.guidanceProbe);
    case SelectionStage.frontierStep:
      expect(SchedulerPipeline.isProgression(best), isTrue);
      expect(advances(best), isFalse);
      expect(SchedulerPipeline.isProgression(winner), isTrue);
      expect(advances(winner), isTrue);
      expect(winner.exercise.material, best.exercise.material);
      expect(winner.exercise.guidance, best.exercise.guidance);
    case SelectionStage.floorCheck:
      expect(floorOf(live.acquisitionFamilyFloor), contains(winner.exercise));
      expect(
        live.history!.executionEvidenceExercises,
        isNot(contains(winner.exercise)),
      );
  }
  return result.stage;
}

/// A learner practicing one plan, a session at a time.
class Learner {
  final Reached<String> reached;

  late InMemoryPracticeStore store;
  late ResolvedPlan plan;
  late List<ResolvedRequirement> targets;

  /// The floor of everything a general session offers, which is all of it.
  late AcquisitionFloor? generalFloor;
  late Profile profile;
  late PlayerState playing;
  late PythonCompatibleRandom random;
  late int sessions;
  late int ids;
  late DateTime start;

  Learner(this.reached) {
    begin(0, PlayerArchetypes.developing, null, 0);
  }

  /// Starts over with a new learner practicing [plans] at [planIndex].
  void begin(
    int planIndex,
    SyntheticPlayer player,
    PlacementTier? placement,
    int seed,
  ) {
    store = InMemoryPracticeStore(createdAt: createdAt);
    plan = plans[planIndex].resolve(catalog) as ResolvedPlan;
    final resolver = PracticeScopeResolver();
    final scope =
        (resolver.resolve(
                  goal: plan.goal,
                  focus: plan.focus,
                  catalog: catalog,
                  instrument: InstrumentProfile(),
                )
                as ValidPracticeScope)
            .scope;
    targets = [
      for (final requirement in scope.requirements)
        if (requirement.isTarget &&
            requirement.requirement.constraints.namesShape)
          requirement,
    ];
    generalFloor = scope.isNarrow
        ? null
        : resolver.acquisitionFloorFor(scope.requirements);
    profile = Profile(
      id: 'learner',
      displayName: player.id,
      createdAt: createdAt,
      placement: placement ?? player.placement,
    );
    playing = player.begin();
    random = PythonCompatibleRandom(seed);
    sessions = 0;
    ids = 0;
    start = createdAt;
  }

  Future<PracticeSession> _open(RecordingPipeline pipeline, String id) =>
      PracticeSession.open(
        store: store,
        profile: profile,
        materials: catalog,
        learner: learner,
        pipeline: pipeline,
        goal: plan.goal,
        focus: plan.focus,
        sessionId: id,
        nextId: () => 'attempt-${ids++}',
      );

  /// Uncovered targets are the plan's targets that name a shape: none of
  /// anything else, and every one of them before anything has been played.
  Future<void> _expectTargetsUncovered(SlotContext live) async {
    final admitted = live.candidates.where(live.uncoveredTargets.admits);
    for (final exercise in admitted) {
      expect(
        targets.any(
          (target) =>
              target.material == exercise.material &&
              target.requirement.constraints.matches(exercise) &&
              target.requirement.retrieval.admits(exercise.guidance),
        ),
        isTrue,
        reason: '$exercise is admitted as a target no requirement asks for',
      );
    }
    if ((await store.loadJournal(profile.id)).isEmpty) {
      for (final target in targets) {
        final shaped = live.candidates.where(
          (exercise) =>
              exercise.material == target.material &&
              target.requirement.constraints.matches(exercise) &&
              target.requirement.retrieval.admits(exercise.guidance),
        );
        if (shaped.isEmpty) continue;
        expect(
          shaped.any(live.uncoveredTargets.admits),
          isTrue,
          reason: '${target.requirement.id} is uncovered before any practice',
        );
      }
    }
  }

  Future<void> practise(int pauseHours, int slots) async {
    start = start.add(Duration(hours: pauseHours));
    playing.restUntil(start);
    final recorder = RecordingPipeline();
    final session = await _open(recorder, 'session-${sessions++}');
    for (var slot = 0; slot < slots; slot++) {
      await _slot(session, recorder, start.add(Duration(minutes: 2 * slot)));
    }
  }

  Future<void> _slot(
    PracticeSession session,
    RecordingPipeline recorder,
    DateTime at,
  ) async {
    final asker = RecordingPipeline(askOnly: true);
    try {
      await (await _open(asker, 'asking')).decideOutcome(at: at);
    } on _Recorded {
      // Asked, and not decided.
    }

    recorder.last = null;
    final decision = await session.decideOutcome(at: at);
    final live = recorder.last;
    expect(live == null, asker.last == null, reason: 'both asked or neither');
    if (live != null) {
      expectSameHistoryInputs(live, asker.last!);
      await expectDerivedFromStorage(live, store, profile, at);
      await _expectTargetsUncovered(live);
      if (generalFloor case final floor?) {
        expect(
          floorOf(live.acquisitionFamilyFloor)?.toSet(),
          floorOf(floor)!.toSet(),
          reason: 'a general session asks about the floor of its whole scope',
        );
      }
      if (!live.emphasis.isEmpty) reached.add('emphasis');
      if (live.history!.demonstratedShapes.isNotEmpty) reached.add('shapes');
      if (live.acquisition?.byParent.isNotEmpty ?? false) {
        reached.add('acquisition history');
      }
    }

    switch (decision) {
      case PresentedAttempt(:final exercise, :final decision):
        final result = live!.result! as CandidateSelected;
        expect(exercise, result.candidate.exercise);
        reached.add(expectStageHeld(live, result).name);
        if (live.uncoveredTargets.admits(exercise)) {
          reached.add('arrived at a target');
        }
        await session.acknowledgePresentation(decision.attemptId);
        await session.closeWithOutcome(
          playing.play(exercise, random),
          observedWallTime: at,
        );
      case PresentedAcquisition(:final task):
        expect((live!.result! as AcquisitionOffered).task.parent, task.parent);
        reached.add('acquisition');
        await session.closeAcquisition(
          performAcquisition(state: playing, task: task, rng: random),
          at: at,
        );
      default:
        reached.add('nothing presented');
    }
  }
}

/// Runs [body], with any [Error] reported as a failure the runner can shrink.
///
/// The runner tears down before it reports a falsified sequence, so a failure
/// marks [Learner.reached] falsified on its way out.
Future<void> _command(Learner learner, Future<void> Function() body) async {
  try {
    try {
      await body();
    } on TestFailure {
      rethrow;
    } catch (error, stackTrace) {
      fail('$error\n$stackTrace');
    }
  } on TestFailure {
    learner.reached.falsified(null);
    rethrow;
  }
}

class PracticeBehavior extends Behavior<Learner, Learner> {
  final Reached<String> reached;

  PracticeBehavior(this.reached);

  @override
  Learner initialState() => Learner(reached);

  @override
  Learner createSystem(Learner state) => state;

  @override
  void destroySystem(Learner system) {}

  @override
  void tearDownAll() => reached.check();

  @override
  List<Command<Learner, Learner>> generateCommands(Learner state) => [
    Action(
      'begin a learner',
      combine4(
        integer(min: 0, max: plans.length - 1),
        weighted([
          (1, choiceOf(PlayerArchetypes.all)),
          (1, choiceOf(occasionalPlayers)),
        ]),
        optional(choiceOf(PlacementTier.values)),
        integer(min: 0, max: 1 << 20),
      ),
      nextState: (_, _) {},
      run: (learner, choice) => _command(
        learner,
        () async => learner.begin(choice.$1, choice.$2, choice.$3, choice.$4),
      ),
    ),
    Action(
      'practise a session',
      combine2(
        weighted<int>([
          (3, integer(min: 1, max: 48)),
          (1, integer(min: 48, max: 60 * 24)),
        ]),
        integer(min: 1, max: 12),
      ),
      nextState: (_, _) {},
      run: (learner, session) =>
          _command(learner, () => learner.practise(session.$1, session.$2)),
    ),
  ];
}

void main() {
  property('a session asks the scheduler what its history implies', () {
    runBehavior(
      PracticeBehavior(
        Reached({
          // A pulse cycle takes a long session from an unsteady player, and a
          // frontier step progression on material whose shape frontier fell
          // behind, which this budget rarely generates. The slot property in
          // keyrecall_scheduler reaches the second directly; a wider budget
          // reaches both here.
          for (final stage in SelectionStage.values)
            if (stage != SelectionStage.pulseCycle &&
                stage != SelectionStage.frontierStep)
              stage.name,
          'acquisition',
          'acquisition history',
          'emphasis',
          'shapes',
          'arrived at a target',
        }),
      ),
      seed: propertySeed,
      maxCycles: propertyBudget(10),
      maxSteps: 10,
    );
  });
}
