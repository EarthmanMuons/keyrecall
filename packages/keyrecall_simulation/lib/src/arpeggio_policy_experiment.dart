import 'dart:isolate';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'player_archetypes.dart';
import 'python_compatible_random.dart';
import 'synthetic_player.dart';

enum ArpeggioPolicyScope {
  scaleOnly,
  smallFixture,
  fullArpeggioCorpus,
  fullMixed,
}

enum ArpeggioPolicyTerminal { slotLimit, caughtUp, blocked, invalid }

class ArpeggioPolicyArm {
  final String id;
  final double rhoFamily;
  final ArpeggioPracticePolicy practicePolicy;
  final IntroductionConfig? introductions;

  const ArpeggioPolicyArm({
    required this.id,
    required this.rhoFamily,
    this.practicePolicy = const ArpeggioPracticePolicy(),
    this.introductions,
  });

  static const baseline = ArpeggioPolicyArm(id: 'baseline', rhoFamily: 0.35);

  /// Counterfactual controls on how much unresolved new material may be open.
  ///
  /// Diagnostic upper bounds rather than proposed policy: the question is
  /// whether controlling introduction breadth removes the observed churn, and
  /// what it costs in depth, family allocation, and scale displacement.
  static const breadthArms = [
    baseline,
    ArpeggioPolicyArm(
      id: 'breadth_catalog_2',
      rhoFamily: 0.35,
      introductions: IntroductionConfig(
        concurrentUnresolved: 2,
        scope: IntroductionScope.catalog,
      ),
    ),
    ArpeggioPolicyArm(
      id: 'breadth_catalog_4',
      rhoFamily: 0.35,
      introductions: IntroductionConfig(
        concurrentUnresolved: 4,
        scope: IntroductionScope.catalog,
      ),
    ),
    ArpeggioPolicyArm(
      id: 'breadth_catalog_8',
      rhoFamily: 0.35,
      introductions: IntroductionConfig(
        concurrentUnresolved: 8,
        scope: IntroductionScope.catalog,
      ),
    ),
    ArpeggioPolicyArm(
      id: 'breadth_family_4',
      rhoFamily: 0.35,
      introductions: IntroductionConfig(
        concurrentUnresolved: 4,
        scope: IntroductionScope.family,
      ),
    ),
  ];

  static const sensitivityArms = [
    baseline,
    ArpeggioPolicyArm(id: 'transfer_0', rhoFamily: 0),
    ArpeggioPolicyArm(id: 'transfer_0_70', rhoFamily: 0.70),
    ArpeggioPolicyArm(
      id: 'floor_separate_hands',
      rhoFamily: 0.35,
      practicePolicy: ArpeggioPracticePolicy(
        acquisitionFloorShape:
            ArpeggioAcquisitionFloorShape.separateHandsAscending,
      ),
    ),
    ArpeggioPolicyArm(
      id: 'floor_up_down',
      rhoFamily: 0.35,
      practicePolicy: ArpeggioPracticePolicy(
        acquisitionFloorShape:
            ArpeggioAcquisitionFloorShape.rightHandAscendingAndDescending,
      ),
    ),
    ArpeggioPolicyArm(
      id: 'tempo_50',
      rhoFamily: 0.35,
      practicePolicy: ArpeggioPracticePolicy(initialTempoBpm: 50),
    ),
    ArpeggioPolicyArm(
      id: 'tempo_70',
      rhoFamily: 0.35,
      practicePolicy: ArpeggioPracticePolicy(initialTempoBpm: 70),
    ),
  ];
}

/// One material's exposure history within a trajectory.
///
/// Slot counts say how much practice a material received; they cannot say
/// whether a scheduler returned to what it introduced. Introduction breadth is
/// a trajectory-grain question, so it needs the first exposure, the first
/// revisit, and the first work that deepened the material beyond it.
class MaterialExposure {
  final String materialId;
  final String familyId;
  final int introducedAtSlot;
  final HandConfiguration introducedHands;
  final int introducedOctaves;
  int selections;
  int? revisitedAtSlot;
  int? otherHandAtSlot;
  int? deeperSpanAtSlot;

  MaterialExposure({
    required this.materialId,
    required this.familyId,
    required this.introducedAtSlot,
    required this.introducedHands,
    required this.introducedOctaves,
    this.selections = 1,
  });

  int? get revisitGap =>
      revisitedAtSlot == null ? null : revisitedAtSlot! - introducedAtSlot;

  bool reached(int? slot, int within) =>
      slot != null && slot - introducedAtSlot <= within;
}

class ArpeggioPolicyRun {
  final String armId;
  final ArpeggioPolicyScope scope;
  final String playerId;
  final int seed;
  final int schedulerDecisions;
  final int selections;
  final Map<String, int> familySelections;
  final Map<String, int> arpeggioMaterialSelections;
  final Map<String, int> arpeggioFingeringFamilySelections;
  final Map<HandConfiguration, int> arpeggioHandSelections;
  final int floorInvocations;
  final int floorSelections;
  final int longestFloorRun;
  final int? firstArpeggioSlot;
  final int? firstRightHandArpeggioSlot;
  final int? firstLeftHandArpeggioSlot;
  final int? firstHandsTogetherArpeggioSlot;
  final int? firstTwoOctaveArpeggioSlot;
  final int? firstFourOctaveArpeggioSlot;
  final int? firstScaleSlot;
  final int? firstTwoOctaveScaleSlot;
  final int? firstHandsTogetherScaleSlot;
  final int arpeggioCandidatesEvaluated;
  final int admittedArpeggioCandidatesInBand;
  final Map<EligibilityReason, int> progressionStops;
  final List<double> admittedArpeggioPredictions;
  final List<MaterialExposure> exposures;
  final List<int> introductionSlots;
  final List<int> unresolvedByDecision;
  final int withheldSlots;
  final int withheldCandidates;
  final ArpeggioPolicyTerminal terminal;

  ArpeggioPolicyRun({
    required this.armId,
    required this.scope,
    required this.playerId,
    required this.seed,
    required this.schedulerDecisions,
    required this.selections,
    required Map<String, int> familySelections,
    required Map<String, int> arpeggioMaterialSelections,
    required Map<String, int> arpeggioFingeringFamilySelections,
    required Map<HandConfiguration, int> arpeggioHandSelections,
    required this.floorInvocations,
    required this.floorSelections,
    required this.longestFloorRun,
    required this.firstArpeggioSlot,
    required this.firstRightHandArpeggioSlot,
    required this.firstLeftHandArpeggioSlot,
    required this.firstHandsTogetherArpeggioSlot,
    required this.firstTwoOctaveArpeggioSlot,
    required this.firstFourOctaveArpeggioSlot,
    required this.firstScaleSlot,
    required this.firstTwoOctaveScaleSlot,
    required this.firstHandsTogetherScaleSlot,
    required this.arpeggioCandidatesEvaluated,
    required this.admittedArpeggioCandidatesInBand,
    required Map<EligibilityReason, int> progressionStops,
    required Iterable<double> admittedArpeggioPredictions,
    required Iterable<MaterialExposure> exposures,
    required Iterable<int> introductionSlots,
    required Iterable<int> unresolvedByDecision,
    required this.withheldSlots,
    required this.withheldCandidates,
    required this.terminal,
  }) : familySelections = Map.unmodifiable(familySelections),
       arpeggioMaterialSelections = Map.unmodifiable(
         arpeggioMaterialSelections,
       ),
       arpeggioFingeringFamilySelections = Map.unmodifiable(
         arpeggioFingeringFamilySelections,
       ),
       arpeggioHandSelections = Map.unmodifiable(arpeggioHandSelections),
       progressionStops = Map.unmodifiable(progressionStops),
       admittedArpeggioPredictions = List.unmodifiable(
         admittedArpeggioPredictions,
       ),
       exposures = List.unmodifiable(exposures),
       introductionSlots = List.unmodifiable(introductionSlots),
       unresolvedByDecision = List.unmodifiable(unresolvedByDecision);

  double get arpeggioSelectionShare => selections == 0
      ? 0
      : (familySelections[TechnicalMaterial.arpeggioFamilyId] ?? 0) /
            selections;

  double progressionStopShare(EligibilityReason reason) =>
      arpeggioCandidatesEvaluated == 0
      ? 0
      : (progressionStops[reason] ?? 0) / arpeggioCandidatesEvaluated;

  int get maxActiveUnresolved => unresolvedByDecision.fold(
    0,
    (peak, count) => count > peak ? count : peak,
  );

  double get meanActiveUnresolved => unresolvedByDecision.isEmpty
      ? 0
      : unresolvedByDecision.reduce((a, b) => a + b) /
            unresolvedByDecision.length;

  /// The most introductions any [window] consecutive slots contained.
  int maxIntroductionsIn(int window) {
    var peak = 0;
    for (final start in introductionSlots) {
      final count = introductionSlots
          .where((slot) => slot >= start && slot < start + window)
          .length;
      if (count > peak) peak = count;
    }
    return peak;
  }
}

Future<ArpeggioPolicyRun> runArpeggioPolicyTrajectory({
  required ArpeggioPolicyArm arm,
  required ArpeggioPolicyScope scope,
  required SyntheticPlayer player,
  required int seed,
  int slots = 80,
}) async {
  final at0 = DateTime.utc(2026);
  final learner = LearnerModel(params: _paramsFor(arm));
  final pipeline = _RecordingPipeline(
    learner: learner,
    config: v1SchedulerConfig.withIntroductions(arm.introductions),
  );
  final fixture = _fixtureFor(scope);
  final session = await PracticeSession.open(
    store: InMemoryPracticeStore(createdAt: at0),
    profile: Profile(
      id: '${arm.id}-${scope.name}-${player.id}-$seed',
      displayName: player.id,
      createdAt: at0,
      placement: player.placement,
    ),
    materials: fixture.materials,
    learner: learner,
    pipeline: pipeline,
    goal: fixture.goal,
    scopeResolver: PracticeScopeResolver(
      families: [
        const ScalePracticeMaterialFamily(),
        ArpeggioPracticeMaterialFamily(policy: arm.practicePolicy),
      ],
    ),
    sessionId: 'policy-${arm.id}-${scope.name}-$seed',
    nextId: _countingIds('${arm.id}-${scope.name}-${player.id}-$seed'),
  );
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final accumulator = _PolicyAccumulator(
    armId: arm.id,
    scope: scope,
    playerId: player.id,
    seed: seed,
  );

  for (var slot = 0; slot < slots; slot++) {
    final at = at0.add(Duration(minutes: slot + 1));
    final decision = await session.decideOutcome(at: at);
    switch (decision) {
      case PresentedAttempt(:final exercise):
        final selection = pipeline.lastSelection!;
        accumulator.record(slot, selection, pipeline.lastState!);
        await session.closeWithOutcome(
          playing.play(exercise, random),
          observedWallTime: at,
        );
      case PracticeCaughtUp():
        return accumulator.finish(ArpeggioPolicyTerminal.caughtUp);
      case PracticeBlocked():
        accumulator.record(slot, pipeline.lastSelection!, pipeline.lastState!);
        return accumulator.finish(ArpeggioPolicyTerminal.blocked);
      case PracticeInvalidScope():
        return accumulator.finish(ArpeggioPolicyTerminal.invalid);
    }
  }
  return accumulator.finish(ArpeggioPolicyTerminal.slotLimit);
}

Future<List<ArpeggioPolicyRun>> runArpeggioPolicyMatrix({
  Iterable<ArpeggioPolicyArm> arms = const [ArpeggioPolicyArm.baseline],
  Iterable<ArpeggioPolicyScope> scopes = ArpeggioPolicyScope.values,
  Iterable<SyntheticPlayer>? players,
  int seeds = 4,
  int slots = 80,
  int parallelism = 1,
  void Function(int completed, int total)? onProgress,
}) async {
  if (parallelism < 1) {
    throw ArgumentError.value(parallelism, 'parallelism', 'must be positive');
  }
  final tasks = <_ArpeggioPolicyTask>[];
  for (final arm in arms) {
    for (final scope in scopes) {
      // The scale-only control pairs with the mixed scope, so an arm runs it
      // only where the arm can change what a scale-only trajectory does.
      if (scope == ArpeggioPolicyScope.scaleOnly &&
          arm.id != ArpeggioPolicyArm.baseline.id &&
          arm.introductions == null) {
        continue;
      }
      for (final player in players ?? PlayerArchetypes.all) {
        for (var seed = 0; seed < seeds; seed++) {
          tasks.add(
            _ArpeggioPolicyTask(
              arm: arm,
              scope: scope,
              player: player,
              seed: seed,
              slots: slots,
            ),
          );
        }
      }
    }
  }
  final runs = List<ArpeggioPolicyRun?>.filled(tasks.length, null);
  var next = 0;
  var completed = 0;

  Future<void> work() async {
    while (next < tasks.length) {
      final index = next++;
      final task = tasks[index];
      runs[index] = await Isolate.run(task.run);
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

class _ArpeggioPolicyTask {
  final ArpeggioPolicyArm arm;
  final ArpeggioPolicyScope scope;
  final SyntheticPlayer player;
  final int seed;
  final int slots;

  const _ArpeggioPolicyTask({
    required this.arm,
    required this.scope,
    required this.player,
    required this.seed,
    required this.slots,
  });

  Future<ArpeggioPolicyRun> run() => runArpeggioPolicyTrajectory(
    arm: arm,
    scope: scope,
    player: player,
    seed: seed,
    slots: slots,
  );
}

class _RecordingPipeline extends SchedulerPipeline {
  SelectionResult? lastSelection;
  LearnerState? lastState;

  _RecordingPipeline({required super.learner, required super.config});

  @override
  SelectionResult decide({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    lastState = state;
    lastSelection = super.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      practiceEntryPolicy: practiceEntryPolicy,
    );
    return lastSelection!;
  }
}

class _PolicyAccumulator {
  final String armId;
  final ArpeggioPolicyScope scope;
  final String playerId;
  final int seed;
  final Map<String, int> familySelections = {};
  final Map<String, int> arpeggioMaterialSelections = {};
  final Map<String, int> arpeggioFingeringFamilySelections = {};
  final Map<HandConfiguration, int> arpeggioHandSelections = {};
  final Map<EligibilityReason, int> progressionStops = {};
  final List<double> admittedArpeggioPredictions = [];
  final Map<String, MaterialExposure> exposures = {};
  final List<int> introductionSlots = [];
  final List<int> unresolvedByDecision = [];
  int withheldSlots = 0;
  int withheldCandidates = 0;
  int schedulerDecisions = 0;
  int selections = 0;
  int floorInvocations = 0;
  int floorSelections = 0;
  int longestFloorRun = 0;
  int _currentFloorRun = 0;
  int arpeggioCandidatesEvaluated = 0;
  int admittedArpeggioCandidatesInBand = 0;
  int? firstArpeggioSlot;
  int? firstRightHandArpeggioSlot;
  int? firstLeftHandArpeggioSlot;
  int? firstHandsTogetherArpeggioSlot;
  int? firstTwoOctaveArpeggioSlot;
  int? firstFourOctaveArpeggioSlot;
  int? firstScaleSlot;
  int? firstTwoOctaveScaleSlot;
  int? firstHandsTogetherScaleSlot;

  _PolicyAccumulator({
    required this.armId,
    required this.scope,
    required this.playerId,
    required this.seed,
  });

  void record(int slot, SelectionResult selection, LearnerState state) {
    schedulerDecisions++;
    if (selection.introductions.withheld > 0) {
      withheldSlots++;
      withheldCandidates += selection.introductions.withheld;
    }
    unresolvedByDecision.add(
      exposures.keys
          .where((id) => state.materialMemory[id]?.hasFactualRetrieval != true)
          .length,
    );
    final floorInvoked = selection.traces.any(
      (trace) =>
          trace.exercise.material.familyId ==
              TechnicalMaterial.arpeggioFamilyId &&
          trace.challengeBypass == ChallengeBypass.acquisitionFloor,
    );
    if (floorInvoked) floorInvocations++;

    for (final trace in selection.traces) {
      if (trace.exercise.material.familyId !=
          TechnicalMaterial.arpeggioFamilyId) {
        continue;
      }
      arpeggioCandidatesEvaluated++;
      final reason = trace.eligibility.code;
      if (_progressionReasons.contains(reason)) {
        progressionStops[reason] = (progressionStops[reason] ?? 0) + 1;
      }
      if (trace.isRanked) {
        admittedArpeggioPredictions.add(trace.prediction.overallP);
        if (trace.isWithinChallengeBand) admittedArpeggioCandidatesInBand++;
      }
    }

    if (selection case SelectionBlocked()) return;
    final chosen = (selection as CandidateSelected).candidate;
    final exercise = chosen.exercise;
    final familyId = exercise.material.familyId;
    selections++;
    familySelections[familyId] = (familySelections[familyId] ?? 0) + 1;
    _recordExposure(slot, chosen);
    if (familyId == TechnicalMaterial.arpeggioFamilyId &&
        chosen.challengeBypass == ChallengeBypass.acquisitionFloor) {
      floorSelections++;
      _currentFloorRun++;
      if (_currentFloorRun > longestFloorRun) {
        longestFloorRun = _currentFloorRun;
      }
    } else {
      _currentFloorRun = 0;
    }

    if (familyId == TechnicalMaterial.arpeggioFamilyId) {
      final materialId = exercise.material.materialId;
      arpeggioMaterialSelections[materialId] =
          (arpeggioMaterialSelections[materialId] ?? 0) + 1;
      final conditions = exercise.conditions;
      arpeggioHandSelections[conditions.hands] =
          (arpeggioHandSelections[conditions.hands] ?? 0) + 1;
      for (final hand in Hand.values) {
        if (!_usesHand(conditions.hands, hand)) continue;
        final family = _fingeringFamily(exercise.material, hand);
        arpeggioFingeringFamilySelections[family] =
            (arpeggioFingeringFamilySelections[family] ?? 0) + 1;
      }
      firstArpeggioSlot ??= slot;
      if (conditions.hands.usesRightHand) firstRightHandArpeggioSlot ??= slot;
      if (conditions.hands.usesLeftHand) firstLeftHandArpeggioSlot ??= slot;
      if (conditions.hands == HandConfiguration.together) {
        firstHandsTogetherArpeggioSlot ??= slot;
      }
      if (conditions.octaves == 2) firstTwoOctaveArpeggioSlot ??= slot;
      if (conditions.octaves == 4) firstFourOctaveArpeggioSlot ??= slot;
    } else if (familyId == TechnicalMaterial.scaleFamilyId) {
      firstScaleSlot ??= slot;
      if (exercise.conditions.octaves == 2) firstTwoOctaveScaleSlot ??= slot;
      if (exercise.conditions.hands == HandConfiguration.together) {
        firstHandsTogetherScaleSlot ??= slot;
      }
    }
  }

  void _recordExposure(int slot, CandidateTrace chosen) {
    final exercise = chosen.exercise;
    final conditions = exercise.conditions;
    final exposure = exposures[exercise.material.materialId];
    if (exposure == null) {
      exposures[exercise.material.materialId] = MaterialExposure(
        materialId: exercise.material.materialId,
        familyId: exercise.material.familyId,
        introducedAtSlot: slot,
        introducedHands: conditions.hands,
        introducedOctaves: conditions.octaves,
      );
    } else {
      exposure.selections++;
      exposure.revisitedAtSlot ??= slot;
      if (conditions.hands != exposure.introducedHands) {
        exposure.otherHandAtSlot ??= slot;
      }
      if (conditions.octaves > exposure.introducedOctaves) {
        exposure.deeperSpanAtSlot ??= slot;
      }
    }
    if (chosen.challengeBypass == ChallengeBypass.newMaterial) {
      introductionSlots.add(slot);
    }
  }

  ArpeggioPolicyRun finish(ArpeggioPolicyTerminal terminal) =>
      ArpeggioPolicyRun(
        armId: armId,
        scope: scope,
        playerId: playerId,
        seed: seed,
        schedulerDecisions: schedulerDecisions,
        selections: selections,
        familySelections: familySelections,
        arpeggioMaterialSelections: arpeggioMaterialSelections,
        arpeggioFingeringFamilySelections: arpeggioFingeringFamilySelections,
        arpeggioHandSelections: arpeggioHandSelections,
        floorInvocations: floorInvocations,
        floorSelections: floorSelections,
        longestFloorRun: longestFloorRun,
        firstArpeggioSlot: firstArpeggioSlot,
        firstRightHandArpeggioSlot: firstRightHandArpeggioSlot,
        firstLeftHandArpeggioSlot: firstLeftHandArpeggioSlot,
        firstHandsTogetherArpeggioSlot: firstHandsTogetherArpeggioSlot,
        firstTwoOctaveArpeggioSlot: firstTwoOctaveArpeggioSlot,
        firstFourOctaveArpeggioSlot: firstFourOctaveArpeggioSlot,
        firstScaleSlot: firstScaleSlot,
        firstTwoOctaveScaleSlot: firstTwoOctaveScaleSlot,
        firstHandsTogetherScaleSlot: firstHandsTogetherScaleSlot,
        arpeggioCandidatesEvaluated: arpeggioCandidatesEvaluated,
        admittedArpeggioCandidatesInBand: admittedArpeggioCandidatesInBand,
        progressionStops: progressionStops,
        admittedArpeggioPredictions: admittedArpeggioPredictions,
        exposures: exposures.values,
        introductionSlots: introductionSlots,
        unresolvedByDecision: unresolvedByDecision,
        withheldSlots: withheldSlots,
        withheldCandidates: withheldCandidates,
        terminal: terminal,
      );
}

const _progressionReasons = {
  EligibilityReason.materialProgressionPrerequisite,
  EligibilityReason.handsTogetherPrerequisite,
  EligibilityReason.octaveSpanPrerequisite,
};

LearnerParams _paramsFor(ArpeggioPolicyArm arm) {
  final transfer = v1LearnerParams.competencyTransfer;
  return v1LearnerParams.copyWith(
    modelVersion: '${v1LearnerParams.modelVersion}-policy-${arm.id}',
    competencyTransfer: CompetencyTransferParams(
      rhoHand: transfer.rhoHand,
      rhoFamily: arm.rhoFamily,
      shrinkageTau: transfer.shrinkageTau,
    ),
  );
}

({List<TechnicalMaterial> materials, PracticeGoal goal}) _fixtureFor(
  ArpeggioPolicyScope scope,
) {
  final cMajorArpeggio = allRootPositionArpeggios.firstWhere(
    (material) =>
        material.tonic == 'C' && material.quality == ArpeggioQuality.major,
  );
  final cMinorArpeggio = allRootPositionArpeggios.firstWhere(
    (material) =>
        material.tonic == 'C' && material.quality == ArpeggioQuality.minor,
  );
  final scales = allScales;
  final arpeggios = switch (scope) {
    ArpeggioPolicyScope.scaleOnly => <ArpeggioMaterial>[],
    ArpeggioPolicyScope.smallFixture => [cMajorArpeggio, cMinorArpeggio],
    ArpeggioPolicyScope.fullArpeggioCorpus ||
    ArpeggioPolicyScope.fullMixed => allRootPositionArpeggios,
  };
  final materials = <TechnicalMaterial>[
    if (scope == ArpeggioPolicyScope.scaleOnly ||
        scope == ArpeggioPolicyScope.fullMixed)
      ...scales,
    ...arpeggios,
  ];
  final requirements = <CurriculumRequirement>[
    if (scope == ArpeggioPolicyScope.scaleOnly ||
        scope == ArpeggioPolicyScope.fullMixed)
      ..._scaleRequirements(scales),
    for (final material in arpeggios) ..._arpeggioRequirements(material),
  ];
  final curriculum = Curriculum(
    id: 'ARPEGGIO_POLICY_${scope.name.toUpperCase()}',
    version: '1',
    requirements: requirements,
  );
  return (
    materials: materials,
    goal: PracticeGoal(id: curriculum.id, curriculum: curriculum),
  );
}

Iterable<CurriculumRequirement> _scaleRequirements(
  List<ScaleMaterial> materials,
) sync* {
  for (final material in materials) {
    yield _requirement(material, HandConfiguration.right, 1);
    yield _requirement(material, HandConfiguration.left, 1);
    yield _requirement(material, HandConfiguration.right, 2);
    yield _requirement(material, HandConfiguration.left, 2);
    yield _requirement(material, HandConfiguration.together, 2);
  }
}

Iterable<CurriculumRequirement> _arpeggioRequirements(
  ArpeggioMaterial material,
) sync* {
  for (final span in material.progression.octaveSpans) {
    yield _requirement(material, HandConfiguration.right, span);
    yield _requirement(material, HandConfiguration.left, span);
    if (span > 1) {
      yield _requirement(material, HandConfiguration.together, span);
    }
  }
}

CurriculumRequirement _requirement(
  TechnicalMaterial material,
  HandConfiguration hands,
  int octaves,
) => CurriculumRequirement(
  id: '${material.materialId}:${hands.id}:$octaves',
  familyId: material.familyId,
  materialId: material.materialId,
  constraints: ExerciseConstraints(
    hands: hands,
    octaves: octaves,
    direction: ExerciseDirection.up,
  ),
);

IdGenerator _countingIds(String prefix) {
  var next = 0;
  return () => '$prefix-${next++}';
}

bool _usesHand(HandConfiguration hands, Hand hand) => switch (hand) {
  Hand.left => hands.usesLeftHand,
  Hand.right => hands.usesRightHand,
};

String _fingeringFamily(TechnicalMaterial material, Hand hand) {
  final fingers = canonicalFingering(material, hand)!.ascending(1).join();
  return '${hand == Hand.right ? 'RH' : 'LH'} $fingers';
}
