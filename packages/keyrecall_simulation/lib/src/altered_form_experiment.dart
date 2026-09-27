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

/// The goal and focus shapes the altered-form gate has to serve.
enum AlteredFormScope {
  /// The production catalog under the general goal.
  general,

  /// A syllabus-sized goal with every minor form of a few tonics.
  broad,

  /// The general goal, exclusively focused on one altered form.
  narrowAltered,

  /// A goal whose ordinary material sits entirely in the foundation band.
  foundationOnly,
}

enum AlteredFormTerminal { slotLimit, caughtUp, blocked, invalid }

/// One scheduler configuration the census runs every scope under.
class AlteredFormArm {
  final String id;
  final SchedulerConfig config;

  AlteredFormArm({required this.id, required this.config});

  static final shipped = AlteredFormArm(
    id: 'shipped',
    config: v1SchedulerConfig,
  );

  /// Core retrieval breadth for harmonic and melodic minor, around the
  /// shipped six and eight.
  static List<AlteredFormArm> get breadth => [
    for (final (harmonic, melodic) in [(4, 6), (6, 8), (8, 10)])
      AlteredFormArm(
        id: 'breadth_${harmonic}_$melodic',
        config: v1SchedulerConfig.withEligibility(
          v1SchedulerConfig.eligibility.withAlteredFormPolicy(
            harmonicMinorCoreRetrievals: harmonic,
            melodicMinorCoreRetrievals: melodic,
          ),
        ),
      ),
  ];

  /// The same-tonic prerequisite and the scope-aware breadth cap, crossed.
  static List<AlteredFormArm> get factorial => [
    for (final (sameTonic, scopeAware) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ])
      AlteredFormArm(
        id:
            '${sameTonic ? 'tonic' : 'no_tonic'}_'
            '${scopeAware ? 'capped' : 'uncapped'}',
        config: v1SchedulerConfig.withEligibility(
          v1SchedulerConfig.eligibility.withAlteredFormPolicy(
            sameTonicAlteredFormPrerequisite: sameTonic,
            scopeAwareAlteredFormBreadth: scopeAware,
          ),
        ),
      ),
  ];
}

/// What the learner held when an altered form was first introduced.
class AlteredFormIntroduction {
  final int slot;
  final ScaleForm form;
  final String materialId;
  final HandConfiguration hands;
  final int majorsRetrieved;
  final int naturalMinorsRetrieved;
  final int bandsRetrieved;
  final bool naturalMinorRetrieved;
  final bool waiverOpen;

  /// Successful retrievals of the same tonic's natural minor, in any hand.
  final int sameTonicRetrievals;

  /// Distinct natural minors retrieved, counted per hand.
  final int naturalMinorHandsRetrieved;

  const AlteredFormIntroduction({
    required this.slot,
    required this.form,
    required this.materialId,
    required this.hands,
    required this.majorsRetrieved,
    required this.naturalMinorsRetrieved,
    required this.bandsRetrieved,
    required this.naturalMinorRetrieved,
    required this.waiverOpen,
    required this.sameTonicRetrievals,
    required this.naturalMinorHandsRetrieved,
  });
}

/// One of the first attempts at an altered form in one hand configuration.
class AlteredFormAttempt {
  final ScaleForm form;

  /// Which attempt at this material and hands it was, from 1.
  final int ordinal;
  final bool managed;
  final GuidanceContext guidance;
  final bool recovery;

  const AlteredFormAttempt({
    required this.form,
    required this.ordinal,
    required this.managed,
    required this.guidance,
    required this.recovery,
  });
}

/// What one presented attempt was, as much as the window after the first
/// introduction reads.
class AlteredFormPick {
  final int slot;
  final ScaleForm? form;
  final String materialId;
  final bool unguided;

  const AlteredFormPick({
    required this.slot,
    required this.form,
    required this.materialId,
    required this.unguided,
  });
}

class AlteredFormRun {
  final String armId;
  final AlteredFormScope scope;
  final String playerId;
  final int seed;
  final int selections;
  final int supportSelections;

  /// Selections of material offered only because a due requirement could not
  /// be introduced without it.
  final int liveSupportSelections;

  /// Those after the first altered form was introduced, when nothing should
  /// still be waiting on them.
  final int liveSupportSelectionsAfterOpening;

  /// Slots at which anything was offered as live support.
  final int liveSupportSlots;
  final int supportedSlots;
  final List<AlteredFormIntroduction> introductions;
  final AlteredFormTerminal terminal;
  final int? terminalSlot;

  /// The first three attempts at each altered material and hands.
  final List<AlteredFormAttempt> firstAttempts;

  /// Every presented attempt, in order.
  final List<AlteredFormPick> picks;

  /// Altered-form targets covered at the end, and how many there were.
  final int alteredCovered;
  final int alteredTargets;

  AlteredFormRun({
    required this.armId,
    required this.scope,
    required this.playerId,
    required this.seed,
    required this.selections,
    required this.supportSelections,
    required this.liveSupportSelections,
    required this.liveSupportSelectionsAfterOpening,
    required this.liveSupportSlots,
    required this.supportedSlots,
    required Iterable<AlteredFormIntroduction> introductions,
    required this.terminal,
    required this.terminalSlot,
    Iterable<AlteredFormAttempt> firstAttempts = const [],
    Iterable<AlteredFormPick> picks = const [],
    this.alteredCovered = 0,
    this.alteredTargets = 0,
  }) : introductions = List.unmodifiable(introductions),
       firstAttempts = List.unmodifiable(firstAttempts),
       picks = List.unmodifiable(picks);

  /// The [window] picks after the first altered form was introduced, or none
  /// when none was.
  List<AlteredFormPick> afterOpening(int window) {
    final opened = introductions.isEmpty ? null : introductions.first.slot;
    if (opened == null) return const [];
    return picks.where((pick) => pick.slot > opened).take(window).toList();
  }

  /// Of the core materials retrieved unguided before the first introduction,
  /// the share retrieved unguided again in the [window] picks after it.
  double? coreRetainedAfterOpening(int window) {
    final opened = introductions.isEmpty ? null : introductions.first.slot;
    if (opened == null) return null;
    bool core(AlteredFormPick pick) =>
        pick.form != null && coreForms.contains(pick.form);
    final established = {
      for (final pick in picks)
        if (pick.slot < opened && core(pick) && pick.unguided) pick.materialId,
    };
    if (established.isEmpty) return null;
    final again = {
      for (final pick in afterOpening(window))
        if (core(pick) && pick.unguided) pick.materialId,
    };
    return established.intersection(again).length / established.length;
  }

  /// The first introduction of [form], or null when it never happened.
  AlteredFormIntroduction? first(ScaleForm form) {
    for (final introduction in introductions) {
      if (introduction.form == form) return introduction;
    }
    return null;
  }
}

/// The catalog, goal, focus, and completion targets of one [scope].
({
  List<TechnicalMaterial> materials,
  PracticeGoal goal,
  PracticeFocus focus,
  Set<String> targetMaterialIds,
})
alteredFormFixture(AlteredFormScope scope) {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];
  switch (scope) {
    case AlteredFormScope.general:
      return (
        materials: catalog,
        goal: PracticeGoal.generalFluency,
        focus: PracticeFocus.unrestricted,
        targetMaterialIds: {
          for (final material in catalog) material.materialId,
        },
      );
    case AlteredFormScope.broad:
      final targets = {
        for (final tonic in ['C', 'G', 'F', 'D', 'A', 'Bb'])
          ScaleMaterial(tonic, ScaleForm.major).materialId,
        for (final tonic in ['A', 'E', 'D', 'G', 'B'])
          for (final form in [
            ScaleForm.naturalMinor,
            ScaleForm.harmonicMinor,
            ScaleForm.melodicMinor,
          ])
            ScaleMaterial(tonic, form).materialId,
      };
      return (
        materials: catalog,
        goal: PracticeGoal(id: 'BROAD', targetMaterialIds: targets),
        focus: PracticeFocus.unrestricted,
        targetMaterialIds: targets,
      );
    case AlteredFormScope.narrowAltered:
      final target = ScaleMaterial('D', ScaleForm.harmonicMinor).materialId;
      return (
        materials: catalog,
        goal: PracticeGoal.generalFluency,
        focus: PracticeFocus(
          exclusiveRequirementIds: {
            catalogRequirementId(PracticeGoal.generalFluency.id, target),
          },
        ),
        targetMaterialIds: {target},
      );
    case AlteredFormScope.foundationOnly:
      final targets = {
        ScaleMaterial('C', ScaleForm.major).materialId,
        ScaleMaterial('G', ScaleForm.major).materialId,
        ScaleMaterial('A', ScaleForm.naturalMinor).materialId,
        ScaleMaterial('D', ScaleForm.naturalMinor).materialId,
        ScaleMaterial('A', ScaleForm.harmonicMinor).materialId,
      };
      return (
        materials: catalog,
        goal: PracticeGoal(id: 'FOUNDATION_ONLY', targetMaterialIds: targets),
        focus: PracticeFocus.unrestricted,
        targetMaterialIds: targets,
      );
  }
}

Future<AlteredFormRun> runAlteredFormTrajectory({
  required AlteredFormArm arm,
  required AlteredFormScope scope,
  required SyntheticPlayer player,
  required int seed,
  int slots = 120,
}) async {
  final at0 = DateTime.utc(2026);
  const learner = LearnerModel();
  final pipeline = _StateRecordingPipeline(
    learner: learner,
    config: arm.config,
  );
  final fixture = alteredFormFixture(scope);
  final name = '${arm.id}-${scope.name}-${player.id}-$seed';
  final session = await PracticeSession.open(
    store: InMemoryPracticeStore(createdAt: at0),
    profile: Profile(
      id: name,
      displayName: player.id,
      createdAt: at0,
      placement: player.placement,
    ),
    materials: fixture.materials,
    learner: learner,
    pipeline: pipeline,
    goal: fixture.goal,
    focus: fixture.focus,
    sessionId: 'altered-$name',
    nextId: _countingIds(name),
  );
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final introductions = <AlteredFormIntroduction>[];
  final met = <(String, HandConfiguration)>{};
  final attemptsOf = <(String, HandConfiguration), int>{};
  final firstAttempts = <AlteredFormAttempt>[];
  final picks = <AlteredFormPick>[];
  var selections = 0;
  var supportSelections = 0;
  var liveSupportSelections = 0;
  var liveSupportSelectionsAfterOpening = 0;
  var liveSupportSlots = 0;
  var supportedSlots = 0;

  final resolved =
      (PracticeScopeResolver().resolve(
                goal: fixture.goal,
                focus: fixture.focus,
                catalog: fixture.materials,
                instrument: InstrumentProfile(),
              )
              as ValidPracticeScope)
          .scope;

  AlteredFormRun finish(AlteredFormTerminal terminal, int? slot) {
    final evaluated = const PracticeScopeEvaluator().evaluate(
      scope: resolved,
      state: session.state,
      journal: session.journal,
      learner: learner,
      at: at0.add(Duration(minutes: slots + 1)),
    );
    final altered = [
      for (final requirement in evaluated.requirements)
        if (requirement.resolved.isTarget &&
            !coreForms.contains(requirement.resolved.material.scaleForm))
          requirement,
    ];
    return AlteredFormRun(
      armId: arm.id,
      scope: scope,
      playerId: player.id,
      seed: seed,
      selections: selections,
      supportSelections: supportSelections,
      liveSupportSelections: liveSupportSelections,
      liveSupportSelectionsAfterOpening: liveSupportSelectionsAfterOpening,
      liveSupportSlots: liveSupportSlots,
      supportedSlots: supportedSlots,
      introductions: introductions,
      terminal: terminal,
      terminalSlot: slot,
      firstAttempts: firstAttempts,
      picks: picks,
      alteredCovered: altered.where((state) => state.isCovered).length,
      alteredTargets: altered.length,
    );
  }

  for (var slot = 0; slot < slots; slot++) {
    final at = at0.add(Duration(minutes: slot + 1));
    final outcome = await session.decideOutcome(at: at);
    switch (outcome) {
      case PresentedAttempt(
        :final exercise,
        :final decision,
        :final liveSupportMaterialIds,
      ):
        selections++;
        final material = exercise.material;
        if (!fixture.targetMaterialIds.contains(material.materialId)) {
          supportSelections++;
        }
        if (liveSupportMaterialIds.isNotEmpty) liveSupportSlots++;
        if (liveSupportMaterialIds.contains(material.materialId)) {
          liveSupportSelections++;
          if (introductions.isNotEmpty) liveSupportSelectionsAfterOpening++;
        }
        final form = material.scaleForm;
        final hands = exercise.conditions.hands;
        final altered = form != null && !coreForms.contains(form);
        if (altered && met.add((material.materialId, hands))) {
          introductions.add(
            _introductionAt(
              slot,
              material as ScaleMaterial,
              hands,
              pipeline.lastState!,
              arm.config,
              session.journal.records,
            ),
          );
        }
        picks.add(
          AlteredFormPick(
            slot: slot,
            form: form,
            materialId: material.materialId,
            unguided: !exercise.guidance.isMaterialSupplied,
          ),
        );
        final played = playing.play(exercise, random);
        if (altered) {
          final ordinal = attemptsOf.update(
            (material.materialId, hands),
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          if (ordinal <= 3) {
            firstAttempts.add(
              AlteredFormAttempt(
                form: form,
                ordinal: ordinal,
                managed: learner.executionWasManaged(played),
                guidance: exercise.guidance,
                recovery:
                    decision.decision.challengeBypass ==
                    ChallengeBypass.recovery,
              ),
            );
          }
        }
        await session.acknowledgePresentation(decision.attemptId);
        await session.closeWithOutcome(played, observedWallTime: at);
      case PresentedAcquisition(:final task):
        supportedSlots++;
        await session.closeAcquisition(
          performAcquisition(state: playing, task: task, rng: random),
          at: at,
        );
      case PracticeCaughtUp():
        return finish(AlteredFormTerminal.caughtUp, slot);
      case PracticeBlocked():
        return finish(AlteredFormTerminal.blocked, slot);
      case PracticeInvalidScope():
      case PracticeSuperseded():
        return finish(AlteredFormTerminal.invalid, slot);
    }
  }
  return finish(AlteredFormTerminal.slotLimit, null);
}

AlteredFormIntroduction _introductionAt(
  int slot,
  ScaleMaterial material,
  HandConfiguration hands,
  LearnerState state,
  SchedulerConfig config,
  Iterable<AttemptRecord> records,
) {
  final sameTonic = ScaleMaterial(material.tonic, ScaleForm.naturalMinor);
  final naturalMinorIds = {
    for (final scale in allScales)
      if (scale.form == ScaleForm.naturalMinor) scale.materialId,
  };
  var sameTonicRetrievals = 0;
  for (final record in records) {
    if (record.exercise.material != sameTonic) continue;
    if (record.closure.measurement case Measured(
      :final outcome,
    ) when outcome.retrieval == FactualRetrieval.succeeded) {
      sameTonicRetrievals++;
    }
  }
  bool retrieved(ScaleMaterial scale) =>
      state.materialMemory[scale.materialId]?.hasFactualRetrieval == true;
  final core = [
    for (final scale in allScales)
      if (coreForms.contains(scale.form) && retrieved(scale)) scale,
  ];
  final coordination = state.competency(Competency.handsTogetherCoordination);
  return AlteredFormIntroduction(
    slot: slot,
    form: material.form,
    materialId: material.materialId,
    hands: hands,
    majorsRetrieved: core
        .where((scale) => scale.form == ScaleForm.major)
        .length,
    naturalMinorsRetrieved: core
        .where((scale) => scale.form == ScaleForm.naturalMinor)
        .length,
    bandsRetrieved: {for (final scale in core) admissionBandOf(scale)}.length,
    naturalMinorRetrieved: retrieved(
      ScaleMaterial(material.tonic, ScaleForm.naturalMinor),
    ),
    waiverOpen:
        state.isObserved(Competency.handsTogetherCoordination) &&
        coordination.mean >= config.eligibility.fluentHandsTogetherFloor,
    sameTonicRetrievals: sameTonicRetrievals,
    naturalMinorHandsRetrieved: {
      for (final (materialId, hand) in retrievedMaterialHands(records))
        if (naturalMinorIds.contains(materialId)) (materialId, hand),
    }.length,
  );
}

Future<List<AlteredFormRun>> runAlteredFormMatrix({
  required Iterable<AlteredFormArm> arms,
  Iterable<AlteredFormScope> scopes = AlteredFormScope.values,
  Iterable<SyntheticPlayer>? players,
  int seeds = 4,
  int slots = 120,
  int parallelism = 1,
  void Function(int completed, int total)? onProgress,
}) async {
  if (parallelism < 1) {
    throw ArgumentError.value(parallelism, 'parallelism', 'must be positive');
  }
  final tasks = [
    for (final arm in arms)
      for (final scope in scopes)
        for (final player in players ?? PlayerArchetypes.all)
          for (var seed = 0; seed < seeds; seed++)
            _AlteredFormTask(
              arm: arm,
              scope: scope,
              player: player,
              seed: seed,
              slots: slots,
            ),
  ];
  final runs = List<AlteredFormRun?>.filled(tasks.length, null);
  var next = 0;
  var completed = 0;

  Future<void> work() async {
    while (next < tasks.length) {
      final index = next++;
      runs[index] = await Isolate.run(tasks[index].run);
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

class _AlteredFormTask {
  final AlteredFormArm arm;
  final AlteredFormScope scope;
  final SyntheticPlayer player;
  final int seed;
  final int slots;

  const _AlteredFormTask({
    required this.arm,
    required this.scope,
    required this.player,
    required this.seed,
    required this.slots,
  });

  Future<AlteredFormRun> run() => runAlteredFormTrajectory(
    arm: arm,
    scope: scope,
    player: player,
    seed: seed,
    slots: slots,
  );
}

/// A pipeline that keeps the learner state its last slot decided from.
class _StateRecordingPipeline extends SchedulerPipeline {
  LearnerState? lastState;

  _StateRecordingPipeline({required super.learner, required super.config});

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
    Set<Exercise> uncoveredTargets = const {},
    Map<String, Set<RealizationShape>> demonstratedShapes = const {},
  }) {
    lastState = state;
    return super.evaluateSlot(
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
    );
  }
}

IdGenerator _countingIds(String prefix) {
  var next = 0;
  return () => '$prefix-${next++}';
}
