import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'python_compatible_random.dart';

/// Motor-difficulty coefficients the hidden truth uses.
///
/// Deliberately different from the estimator's own coefficients. If the
/// generator and the estimator shared one equation, a simulation would mostly
/// confirm that the model can invert its own arithmetic.
const double _trueTempoBeta = 0.5;
const double _trueOctaveBeta = 0.25;
const double _trueHandBeta = 0.3;
const double _trueDirectionBeta = 0.1;
const double _trueReferenceTempoBpm = 80.0;

/// Standard deviation of the noise on every sampled observation.
const double trueNoiseScale = 0.12;

const double _trueActivationRestorationRate = 0.05;
const double _trueSupportedCurrentDurabilityRate = 0.022556390977443608;
const double _trueSuccessCurrentDurabilityRate = 0.022556390977443608;
const double _trueConsolidationGrowthRate = 0.05;
const double _trueConsolidationGrowthTargetDays = 60.0;
const double _trueMaxMemoryHalfLifeDays = 1000.0;

double _truePracticeFactor(GuidanceContext guidance) =>
    switch (guidance.independence) {
      0 => 0.3,
      1 => 0.7,
      _ => 1.0,
    };

double _trueSuccessFactor(GuidanceContext guidance) =>
    switch (guidance.independence) {
      1 => 0.7,
      2 => 1.0,
      _ => throw StateError(
        'a continuously cued attempt never tests retrieval, so it cannot '
        'report a success',
      ),
    };

double _trueDifficulty(Exercise exercise) {
  final conditions = exercise.conditions;
  return _trueTempoBeta *
          math.log(conditions.tempoBpm / _trueReferenceTempoBpm) +
      _trueOctaveBeta * math.max(0, conditions.octaves - 1) +
      _trueHandBeta *
          (conditions.hands == HandConfiguration.together ? 1.0 : 0.0) +
      _trueDirectionBeta *
          (conditions.direction == ExerciseDirection.upDown ? 1.0 : 0.0);
}

/// The hidden truth about one material's retrievability.
///
/// Decays on its own schedule, independently of whatever the learner model
/// currently estimates. The gap between the two is what a simulation measures.
class TrueMaterialMemory {
  /// True current half-life, in days.
  double currentHalfLifeDays;

  /// True retained half-life, in days.
  double consolidatedHalfLifeDays;

  /// When operative memory was truly last anchored.
  DateTime? memoryAnchorAt;

  /// When retrieval truly last succeeded.
  DateTime? factualLastRetrievalAt;

  /// When retrieval was truly last tested.
  DateTime? lastRetrievalAttemptAt;

  TrueMaterialMemory({
    required this.currentHalfLifeDays,
    required this.consolidatedHalfLifeDays,
    this.memoryAnchorAt,
    this.factualLastRetrievalAt,
    this.lastRetrievalAttemptAt,
  });

  /// True retrievability at [at], falling back to [prior] before any anchor.
  double retrievabilityAt(DateTime at, double prior) {
    final anchor = memoryAnchorAt;
    if (anchor == null) return prior;
    return math
        .pow(2.0, -anchor.daysUntil(at) / currentHalfLifeDays)
        .toDouble();
  }
}

/// A hidden ground-truth learner a simulation samples outcomes from.
///
/// Competencies are fixed for a run: this models a learner whose underlying
/// ability the simulation already knows, so the estimator's convergence toward
/// it can be measured. Memory, unlike competency, does change over a run.
class TrueLearnerProfile {
  /// Which named profile this is.
  final SyntheticProfile profile;

  /// What this learner would report at placement.
  final PlacementTier selfReportTier;

  /// True capability per competency, in the same logit units the model
  /// estimates.
  final Map<Competency, double> trueCompetencies;

  /// True per-material, per-hand execution deviations.
  final Map<ExecutionContext, double> trueMaterialExecution;

  /// True memory state per material, filled in lazily as materials are
  /// practiced.
  final Map<String, TrueMaterialMemory> trueMaterialMemory;

  /// Retrievability of a material with no history yet.
  final double memoryPrior;

  /// Half-life a newly encountered material truly starts with, in days.
  final double defaultCurrentHalfLifeDays;

  TrueLearnerProfile({
    required this.profile,
    required this.selfReportTier,
    required this.trueCompetencies,
    Map<ExecutionContext, double>? trueMaterialExecution,
    Map<String, TrueMaterialMemory>? trueMaterialMemory,
    this.memoryPrior = 0.4,
    this.defaultCurrentHalfLifeDays = 4.0,
  }) : trueMaterialExecution = trueMaterialExecution ?? {},
       trueMaterialMemory = trueMaterialMemory ?? {};

  /// This learner's true memory for [materialId], created at the profile's
  /// defaults if this is the first encounter.
  TrueMaterialMemory memoryFor(String materialId) =>
      trueMaterialMemory.putIfAbsent(
        materialId,
        () => TrueMaterialMemory(
          currentHalfLifeDays: defaultCurrentHalfLifeDays,
          consolidatedHalfLifeDays: defaultCurrentHalfLifeDays,
        ),
      );
}

/// The named synthetic learners the V1 diagnostics are built around.
///
/// Each one isolates a way the model could go wrong: conflating memory with
/// technique, treating the hands as one system, or letting a material-specific
/// problem contaminate a shared competency.
enum SyntheticProfile {
  /// Weak at everything, and honest about it.
  beginner('beginner'),

  /// Strong at everything, and honest about it.
  advanced('advanced'),

  /// Strong overall, but with a genuinely weak left hand.
  rhStrongLhWeak('rh_strong_lh_weak'),

  /// Strong hands, but memory that fades within a day.
  techniqueStrongMemoryWeak('technique_strong_memory_weak'),

  /// Durable memory, but weak execution across the board.
  memoryStrongTechniqueWeak('memory_strong_technique_weak'),

  /// Strong and experienced, returning after a real two-week gap.
  returning('returning'),

  /// Strong overall, but with a persistent problem on one scale in one hand.
  materialSpecificDifficulty('material_specific_difficulty');

  const SyntheticProfile(this.id);

  /// Stable identifier used in traces.
  final String id;

  /// A fresh hidden learner of this kind, ready to practice from [start].
  ///
  /// Each call builds independent state, so one simulation's practice never
  /// leaks into another's hidden truth.
  TrueLearnerProfile build({required DateTime start}) {
    Map<Competency, double> flat(double value) => {
      for (final competency in Competency.values) competency: value,
    };

    switch (this) {
      case SyntheticProfile.beginner:
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.beginner,
          trueCompetencies: flat(-1.5),
        );
      case SyntheticProfile.advanced:
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.advanced,
          trueCompetencies: flat(1.5),
        );
      case SyntheticProfile.rhStrongLhWeak:
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.someExperience,
          trueCompetencies: flat(1.5)..[Competency.lhScaleExecution] = -1.0,
        );
      case SyntheticProfile.techniqueStrongMemoryWeak:
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.advanced,
          trueCompetencies: flat(1.5),
          memoryPrior: 0.15,
          defaultCurrentHalfLifeDays: 0.5,
        );
      case SyntheticProfile.memoryStrongTechniqueWeak:
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.someExperience,
          trueCompetencies: flat(0.0)
            ..addEntries(
              motorCompetencies.map((competency) => MapEntry(competency, -1.2)),
            ),
          memoryPrior: 0.85,
          defaultCurrentHalfLifeDays: 20.0,
        );
      case SyntheticProfile.returning:
        // An actual gap, not just a self-report label. Fourteen days against a
        // six-day half-life gives roughly 20% per-attempt retrieval odds: low
        // enough to be a real gap, high enough not to make a bounded run flaky.
        final lastPracticed = start.plusDays(-14.0);
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.advanced,
          trueCompetencies: flat(1.5),
          defaultCurrentHalfLifeDays: 6.0,
          trueMaterialMemory: {
            'C_MAJOR': TrueMaterialMemory(
              currentHalfLifeDays: 6.0,
              consolidatedHalfLifeDays: 20.0,
              memoryAnchorAt: lastPracticed,
              factualLastRetrievalAt: lastPracticed,
              lastRetrievalAttemptAt: lastPracticed,
            ),
          },
        );
      case SyntheticProfile.materialSpecificDifficulty:
        return TrueLearnerProfile(
          profile: this,
          selfReportTier: PlacementTier.advanced,
          trueCompetencies: flat(1.5),
          trueMaterialExecution: {
            ('F#_HARMONIC_MINOR', HandConfiguration.right, HandMotion.parallel):
                -1.8,
          },
        );
    }
  }
}

/// Applies the true memory transition after a complete outcome exists.
///
/// Mirrors the estimator's own causal transitions, with the truth's separate
/// coefficients: a success anchors and consolidates, productive supported
/// practice restores without writing retrieval history, and an unproductive
/// attempt changes nothing.
void applyTrueMemoryTransition({
  required TrueMaterialMemory memory,
  required Exercise exercise,
  required Outcome outcome,
  required DateTime at,
}) {
  if (outcome.retrieval.isTested) {
    memory.lastRetrievalAttemptAt = at;
  }

  final quality = outcome.practiceQuality;

  if (outcome.retrieval == FactualRetrieval.succeeded) {
    memory.memoryAnchorAt = at;
    memory.factualLastRetrievalAt = at;
    final successFactor = _trueSuccessFactor(exercise.guidance);
    final gap = math.max(
      0.0,
      _trueConsolidationGrowthTargetDays - memory.consolidatedHalfLifeDays,
    );
    final consolidation = math.min(
      memory.consolidatedHalfLifeDays +
          _trueConsolidationGrowthRate * successFactor * quality * gap,
      _trueMaxMemoryHalfLifeDays,
    );
    memory.currentHalfLifeDays +=
        _trueSuccessCurrentDurabilityRate *
        successFactor *
        quality *
        (consolidation - memory.currentHalfLifeDays);
    memory.consolidatedHalfLifeDays = consolidation;
    return;
  }

  if (quality <= 0.0) return;

  final practiceFactor = _truePracticeFactor(exercise.guidance);
  final anchor = memory.memoryAnchorAt;
  if (anchor != null) {
    final fraction = _trueActivationRestorationRate * practiceFactor * quality;
    memory.memoryAnchorAt = anchor.plusDays(fraction * anchor.daysUntil(at));
  }
  memory.currentHalfLifeDays +=
      _trueSupportedCurrentDurabilityRate *
      practiceFactor *
      quality *
      (memory.consolidatedHalfLifeDays - memory.currentHalfLifeDays);
}

/// Samples what [profile] would actually do on [exercise] at [at].
///
/// Retrieval, motor quality, and topology quality are separate pathways, so a
/// learner can be strong in one and weak in another. Independent retrieval is
/// never attenuated by cueing, because it asks whether the material would be
/// retrievable without support; what cueing changes is whether that question
/// was asked at all, and whether the attempt could start.
///
/// Advances [profile]'s hidden memory unless [applyMemoryTransition] is false.
Outcome sampleOutcome({
  required TrueLearnerProfile profile,
  required Exercise exercise,
  required DateTime at,
  required PythonCompatibleRandom rng,
  bool applyMemoryTransition = true,
}) {
  final materialId = exercise.material.materialId;
  final trueMemory = profile.memoryFor(materialId);
  final trueRetrievability = trueMemory.retrievabilityAt(
    at,
    profile.memoryPrior,
  );
  final retrievalDemand = exercise.guidance.retrievalDemand;

  final retrievalSucceeded = rng.nextDouble() < trueRetrievability;

  // Continuous cueing supplies the material outright, so the attempt never
  // tests independent retrieval: report no observation rather than a
  // low-confidence one that repetition could accumulate into evidence.
  final retrieval = exercise.guidance.isRetrievalObserved
      ? (retrievalSucceeded
            ? FactualRetrieval.succeeded
            : FactualRetrieval.failed)
      : FactualRetrieval.notTested;

  // Starting is broader than retrieving: cueing can supply enough support to
  // begin even when independent retrieval would have failed.
  final started =
      retrievalSucceeded || rng.nextDouble() < 1.0 - retrievalDemand;

  final effectiveRetrievability =
      1.0 - retrievalDemand * (1.0 - trueRetrievability);
  final materialRetrieval = rng
      .nextGaussian(effectiveRetrievability, trueNoiseScale)
      .clamp(0.0, 1.0);

  final q = exercise.structuralQ;
  final motorRelevant = Competency.values
      .where((competency) => q.contains(competency) && competency.isMotor)
      .toList();
  final topologyRelevant = Competency.values
      .where((competency) => q.contains(competency) && competency.isTopology)
      .toList();

  var motorAbility =
      motorRelevant.fold<double>(
        0.0,
        (sum, competency) => sum + profile.trueCompetencies[competency]!,
      ) /
      math.max(1, motorRelevant.length);
  motorAbility +=
      profile.trueMaterialExecution[executionContextOf(exercise)] ?? 0.0;
  final motorQuality = _sigmoid(
    motorAbility -
        _trueDifficulty(exercise) +
        rng.nextGaussian(0.0, trueNoiseScale),
  );

  final topologyAbility =
      topologyRelevant.fold<double>(
        0.0,
        (sum, competency) => sum + profile.trueCompetencies[competency]!,
      ) /
      math.max(1, topologyRelevant.length);
  final topologyQuality = _sigmoid(
    topologyAbility + rng.nextGaussian(0.0, trueNoiseScale),
  );

  late final Outcome outcome;
  if (!started) {
    outcome = Outcome(
      started: false,
      retrieval: retrieval,
      completed: false,
      materialRetrieval: materialRetrieval,
      pitchIntegrity: 0.0,
      continuity: 0.0,
      temporalStability: 0.0,
      achievedTempoRatio: 0.0,
      topologyAccuracy: 0.0,
    );
  } else {
    double noisy(double center) =>
        rng.nextGaussian(center, trueNoiseScale).clamp(0.0, 1.0);

    // Draw order matters: these consume the same random stream the reference
    // implementation does, and reordering them would silently produce a
    // different simulated learner.
    final pitchIntegrity = noisy(0.6 * materialRetrieval + 0.4 * motorQuality);
    final continuity = noisy(motorQuality);
    final temporalStability = noisy(motorQuality);
    final completed =
        motorQuality > 0.3 && rng.nextDouble() < motorQuality + 0.2;

    outcome = Outcome(
      started: true,
      retrieval: retrieval,
      completed: completed,
      materialRetrieval: materialRetrieval,
      pitchIntegrity: pitchIntegrity,
      continuity: continuity,
      temporalStability: temporalStability,
      achievedTempoRatio: noisy(motorQuality),
      topologyAccuracy: noisy(topologyQuality),
    );
  }

  if (applyMemoryTransition) {
    applyTrueMemoryTransition(
      memory: trueMemory,
      exercise: exercise,
      outcome: outcome,
      at: at,
    );
  }
  return outcome;
}

double _sigmoid(double logit) => 1.0 / (1.0 + math.exp(-logit));
