import 'dart:isolate';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'player_archetypes.dart';
import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// Attempts after which a run is read, counted within its phase.
const List<int> transferFirstPhaseCheckpoints = [0, 10, 30, 100, 300];
const List<int> transferSecondPhaseCheckpoints = [10, 30, 100, 300];

/// The shapes every probe and evidence stream is built from, at the gentle
/// tempo and unguided.
enum TransferShape {
  rightOneUp(HandConfiguration.right, 1, ExerciseDirection.up),
  leftOneUp(HandConfiguration.left, 1, ExerciseDirection.up),
  rightOneUpDown(HandConfiguration.right, 1, ExerciseDirection.upDown),
  leftOneUpDown(HandConfiguration.left, 1, ExerciseDirection.upDown),
  rightTwoUpDown(HandConfiguration.right, 2, ExerciseDirection.upDown),
  leftTwoUpDown(HandConfiguration.left, 2, ExerciseDirection.upDown),
  togetherOneUp(HandConfiguration.together, 1, ExerciseDirection.up),
  togetherTwoUpDown(HandConfiguration.together, 2, ExerciseDirection.upDown);

  final HandConfiguration hands;
  final int octaves;
  final ExerciseDirection direction;

  const TransferShape(this.hands, this.octaves, this.direction);

  Exercise of(TechnicalMaterial material) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    direction: direction,
    tempoBpm: 60,
  );
}

/// The shapes a reading probes.
const List<TransferShape> transferProbeShapes = [
  TransferShape.rightOneUp,
  TransferShape.leftOneUp,
  TransferShape.rightTwoUpDown,
  TransferShape.togetherOneUp,
];

/// The materials a family's evidence cycles through, the first of them also
/// the one each reading probes.
List<TechnicalMaterial> transferMaterialsOf(String familyId) =>
    familyId == TechnicalMaterial.scaleFamilyId
    ? [
        TechnicalMaterial('C', ScaleForm.major),
        TechnicalMaterial('G', ScaleForm.major),
        TechnicalMaterial('F', ScaleForm.major),
        TechnicalMaterial('A', ScaleForm.naturalMinor),
      ]
    : [
        ArpeggioMaterial('C', ArpeggioQuality.major),
        ArpeggioMaterial('G', ArpeggioQuality.major),
        ArpeggioMaterial('F', ArpeggioQuality.major),
        ArpeggioMaterial('A', ArpeggioQuality.minor),
      ];

String otherFamilyOf(String familyId) =>
    familyId == TechnicalMaterial.scaleFamilyId
    ? TechnicalMaterial.arpeggioFamilyId
    : TechnicalMaterial.scaleFamilyId;

/// What the model expected of one probe, what the player could do, and where
/// the expectation came from.
class TransferProbe {
  final String familyId;
  final TransferShape shape;

  /// The model's execution probability.
  final double predicted;

  /// The share of non-practising attempts this player managed.
  final double managed;

  /// The execution logit, by source: `own:<competency>` for a competency's
  /// own mean times its loading, `family_transfer` and `hand_transfer` for
  /// what the effective means borrow, `residual` for the material's own
  /// execution record, and `difficulty` subtracted.
  final Map<String, double> logit;

  final EligibilityTier tier;

  const TransferProbe({
    required this.familyId,
    required this.shape,
    required this.predicted,
    required this.managed,
    required this.logit,
    required this.tier,
  });

  Map<String, Object?> toJson() => {
    'family': familyId,
    'shape': shape.name,
    'predicted': predicted,
    'managed': managed,
    'logit': logit,
    'tier': tier.name,
  };
}

/// One reading of a run.
class TransferCheckpoint {
  /// `first`, `second`, or `control`.
  final String phase;
  final int attempts;
  final List<TransferProbe> probes;
  final Map<String, double> competencies;

  /// Catalog materials fully eligible in each hand alone at the gentle tempo,
  /// ascending, keyed by family and span, as `SCALE:1`.
  ///
  /// Asked cued, so what it reads is the execution floors transfer can move
  /// rather than the rule that a material's first unguided encounter waits.
  final Map<String, int> eligible;

  const TransferCheckpoint({
    required this.phase,
    required this.attempts,
    required this.probes,
    required this.competencies,
    required this.eligible,
  });

  TransferProbe probe(String familyId, TransferShape shape) =>
      probes.firstWhere(
        (probe) => probe.familyId == familyId && probe.shape == shape,
      );

  Map<String, Object?> toJson() => {
    'phase': phase,
    'attempts': attempts,
    'probes': [for (final probe in probes) probe.toJson()],
    'competencies': competencies,
    'eligible': eligible,
  };
}

/// One player from one placement given one family's evidence, then the
/// other's, beside a control given only the other's at the same instants.
class TransferRun {
  final String playerId;
  final PlacementTier tier;
  final String firstFamilyId;
  final List<TransferCheckpoint> checkpoints;

  TransferRun({
    required this.playerId,
    required this.tier,
    required this.firstFamilyId,
    required Iterable<TransferCheckpoint> checkpoints,
  }) : checkpoints = List.unmodifiable(checkpoints);

  Map<String, Object?> toJson() => {
    'player': playerId,
    'tier': tier.name,
    'first': firstFamilyId,
    'checkpoints': [for (final point in checkpoints) point.toJson()],
  };
}

/// Runs [player] from [tier] through [firstFamilyId]'s evidence and then the
/// other family's, and a control through only the other family's.
///
/// The player's abilities are per family, so practising one never improves
/// the other: whatever the model moves across families, the evidence did not
/// justify. The second family's evidence draws from its own stream, so the
/// run and its control see identical second-phase attempts.
TransferRun runTransfer({
  required SyntheticPlayer player,
  required PlacementTier tier,
  required String firstFamilyId,
  int firstPhaseAttempts = 300,
  int secondPhaseAttempts = 300,
  int truthSamples = 30,
  LearnerModel learner = const LearnerModel(),
}) {
  final pipeline = SchedulerPipeline(learner: learner);
  final withoutFamily = LearnerModel(
    params: learner.params.copyWith(
      modelVersion: '${learner.params.modelVersion}-no-family-transfer',
      competencyTransfer: CompetencyTransferParams(
        rhoHand: learner.params.competencyTransfer.rhoHand,
        rhoFamily: 0,
        shrinkageTau: learner.params.competencyTransfer.shrinkageTau,
      ),
    ),
  );
  final withoutTransfer = LearnerModel(
    params: learner.params.copyWith(
      modelVersion: '${learner.params.modelVersion}-no-transfer',
      competencyTransfer: CompetencyTransferParams(
        rhoHand: 0,
        rhoFamily: 0,
        shrinkageTau: learner.params.competencyTransfer.shrinkageTau,
      ),
    ),
  );
  final start = DateTime.utc(2026);
  final secondFamilyId = otherFamilyOf(firstFamilyId);
  DateTime slotAt(int index) =>
      start.add(Duration(days: index ~/ 20, minutes: index % 20));

  TransferCheckpoint read(
    String phase,
    int attempts,
    LearnerState state,
    PlayerState playing,
  ) {
    TransferProbe probeOf(String familyId, TransferShape shape) {
      final exercise = shape.of(transferMaterialsOf(familyId).first);
      final loadings = motorLoadings(exercise.structuralQ);
      final logit = <String, double>{};
      var family = 0.0;
      var hand = 0.0;
      for (final MapEntry(key: competency, value: q) in loadings.entries) {
        final full = learner.effectiveCompetencyMean(state, competency);
        final noFamily = withoutFamily.effectiveCompetencyMean(
          state,
          competency,
        );
        final none = withoutTransfer.effectiveCompetencyMean(state, competency);
        logit['own:${competency.id}'] = q * none;
        family += q * (full - noFamily);
        hand += q * (noFamily - none);
      }
      logit['family_transfer'] = family;
      logit['hand_transfer'] = hand;
      logit['residual'] =
          state.materialExecution[executionContextOf(exercise)]?.residualMean ??
          0;
      logit['difficulty'] = -learner.motorDifficulty(exercise);

      var managed = 0;
      for (var sample = 0; sample < truthSamples; sample++) {
        final outcome = playing.play(
          exercise,
          PythonCompatibleRandom(1000 * shape.index + sample),
          practising: false,
        );
        if (learner.executionWasManaged(outcome)) managed++;
      }
      return TransferProbe(
        familyId: familyId,
        shape: shape,
        predicted: learner.executionProbability(state, exercise),
        managed: managed / truthSamples,
        logit: logit,
        tier: pipeline.eligibilityFor(state, exercise).tier,
      );
    }

    int eligibleIn(List<TechnicalMaterial> materials, int octaves) => materials
        .where(
          (material) => [HandConfiguration.right, HandConfiguration.left].every(
            (hands) =>
                pipeline
                    .eligibilityFor(
                      state,
                      Exercise.linear(
                        material: material,
                        hands: hands,
                        octaves: octaves,
                        direction: ExerciseDirection.up,
                        tempoBpm: 60,
                        guidance: GuidanceContext.continuouslyCued,
                      ),
                    )
                    .tier ==
                EligibilityTier.fullyEligible,
          ),
        )
        .length;

    return TransferCheckpoint(
      phase: phase,
      attempts: attempts,
      probes: [
        for (final familyId in [firstFamilyId, secondFamilyId])
          for (final shape in transferProbeShapes) probeOf(familyId, shape),
      ],
      competencies: {
        for (final competency in [
          ...motorCompetencies,
          ...coordinationCompetencies,
        ])
          competency.id: state.competency(competency).mean,
      },
      eligible: {
        for (final octaves in [1, 2]) ...{
          '${TechnicalMaterial.scaleFamilyId}:$octaves': eligibleIn(
            allScales,
            octaves,
          ),
          '${TechnicalMaterial.arpeggioFamilyId}:$octaves': eligibleIn(
            allRootPositionArpeggios,
            octaves,
          ),
        },
      },
    );
  }

  void practise(
    LearnerState state,
    PlayerState playing,
    String familyId,
    int from,
    int count,
    List<int> readAt,
    String phase,
    List<TransferCheckpoint> into,
  ) {
    final materials = transferMaterialsOf(familyId);
    final random = PythonCompatibleRandom(
      familyId == TechnicalMaterial.scaleFamilyId ? 11 : 13,
    );
    for (var index = 0; index < count; index++) {
      final at = slotAt(from + index);
      final exercise = TransferShape.values[index % TransferShape.values.length]
          .of(
            materials[(index ~/ TransferShape.values.length) %
                materials.length],
          );
      playing.restUntil(at);
      final outcome = playing.play(exercise, random);
      learner.propagateAndApplyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: learner.predict(state, exercise, at: at),
        at: at,
      );
      if (readAt.contains(index + 1)) {
        into.add(read(phase, index + 1, state, playing));
      }
    }
  }

  final checkpoints = <TransferCheckpoint>[];
  final state = learner.placementState(tier, at: start);
  final playing = player.begin();
  if (transferFirstPhaseCheckpoints.contains(0)) {
    checkpoints.add(read('first', 0, state, playing));
  }
  practise(
    state,
    playing,
    firstFamilyId,
    0,
    firstPhaseAttempts,
    transferFirstPhaseCheckpoints,
    'first',
    checkpoints,
  );
  practise(
    state,
    playing,
    secondFamilyId,
    firstPhaseAttempts,
    secondPhaseAttempts,
    transferSecondPhaseCheckpoints,
    'second',
    checkpoints,
  );

  final control = learner.placementState(tier, at: start);
  final controlPlaying = player.begin();
  practise(
    control,
    controlPlaying,
    secondFamilyId,
    firstPhaseAttempts,
    secondPhaseAttempts,
    transferSecondPhaseCheckpoints,
    'control',
    checkpoints,
  );

  return TransferRun(
    playerId: player.id,
    tier: tier,
    firstFamilyId: firstFamilyId,
    checkpoints: checkpoints,
  );
}

/// The archetypes the census reads: both single-family players and a
/// balanced one to compare them with.
List<SyntheticPlayer> get transferPlayers => [
  for (final id in [
    'arpeggio_strong_scale_weak',
    'scale_strong_arpeggio_weak',
    'intermediate',
  ])
    PlayerArchetypes.all.firstWhere((player) => player.id == id),
];

/// Every player, placement, and first family, in parallel.
Future<List<TransferRun>> runTransferMatrix({
  Iterable<SyntheticPlayer>? players,
  int parallelism = 4,
}) async {
  final tasks = [
    for (final player in players ?? transferPlayers)
      for (final tier in PlacementTier.values)
        for (final familyId in [
          TechnicalMaterial.scaleFamilyId,
          TechnicalMaterial.arpeggioFamilyId,
        ])
          () =>
              runTransfer(player: player, tier: tier, firstFamilyId: familyId),
  ];
  final runs = List<TransferRun?>.filled(tasks.length, null);
  var next = 0;
  Future<void> work() async {
    while (next < tasks.length) {
      final index = next++;
      runs[index] = await Isolate.run(tasks[index]);
    }
  }

  await Future.wait([
    for (var worker = 0; worker < parallelism; worker++) work(),
  ]);
  return [for (final run in runs) run!];
}
