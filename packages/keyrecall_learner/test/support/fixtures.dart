import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

/// The reference instant these tests count from.
final DateTime t0 = DateTime.utc(2026);

/// The model under test, at the versioned prototype parameters.
const LearnerModel model = LearnerModel();

/// Shorthand for those parameters.
const LearnerParams params = v1PrototypeLearnerParams;

final TechnicalMaterial cMajor = TechnicalMaterial('C', ScaleForm.major);
final TechnicalMaterial dHarmonicMinor = TechnicalMaterial(
  'D',
  ScaleForm.harmonicMinor,
);
final TechnicalMaterial fSharpHarmonicMinor = TechnicalMaterial(
  'F#',
  ScaleForm.harmonicMinor,
);

/// A two-octave, up-and-down, 80 BPM exercise: the fixed realization these
/// tests vary one thing at a time against.
Exercise exerciseFor(
  TechnicalMaterial material, {
  HandConfiguration hands = HandConfiguration.right,
  GuidanceContext guidance = GuidanceContext.unguided,
  int octaves = 2,
  ScaleDirection direction = ScaleDirection.upDown,
  double tempoBpm = 80,
}) => Exercise.linear(
  material: material,
  hands: hands,
  octaves: octaves,
  direction: direction,
  tempoBpm: tempoBpm,
  guidance: guidance,
);

/// A flawless attempt.
Outcome perfectOutcome({
  FactualRetrieval retrieval = FactualRetrieval.succeeded,
  double? coordination,
}) => Outcome(
  coordination: coordination,
  started: true,
  retrieval: retrieval,
  completed: true,
  materialRetrieval: 1.0,
  pitchIntegrity: 1.0,
  continuity: 1.0,
  temporalStability: 1.0,
  achievedTempoRatio: 1.0,
  topologyAccuracy: 1.0,
);

/// A successful retrieval played at a given execution quality.
Outcome successOfQuality(double quality) => Outcome(
  started: true,
  retrieval: FactualRetrieval.succeeded,
  completed: true,
  materialRetrieval: 1.0,
  pitchIntegrity: quality,
  continuity: quality,
  temporalStability: quality,
  achievedTempoRatio: quality,
  topologyAccuracy: 1.0,
);

/// An attempt that never began, because the material could not be recalled.
Outcome failedToStart() => Outcome(
  started: false,
  retrieval: FactualRetrieval.failed,
  completed: false,
  materialRetrieval: 0.0,
  pitchIntegrity: 0.0,
  continuity: 0.0,
  temporalStability: 0.0,
  achievedTempoRatio: 0.0,
  topologyAccuracy: 0.0,
);

/// A flawless continuously cued attempt, which tests no retrieval at all.
Outcome cuedOutcome() => perfectOutcome(retrieval: FactualRetrieval.notTested);

/// Gives [memory] a retrieval history, and optionally a chosen durability.
///
/// The equivalent of a learner who has practiced this material before, so a
/// test can start from an anchored state instead of simulating its way there.
void anchorMemory(
  MaterialMemoryState memory,
  DateTime at, {
  double? currentHalfLifeDays,
  double? consolidatedHalfLifeDays,
}) {
  memory
    ..memoryAnchorAt = at
    ..factualLastRetrievalAt = at
    ..lastRetrievalAttemptAt = at;
  if (currentHalfLifeDays != null) {
    memory
      ..logCurrentHalfLife = math.log(currentHalfLifeDays)
      ..logConsolidatedHalfLife = math.log(
        consolidatedHalfLifeDays ?? currentHalfLifeDays,
      );
  }
}

/// Runs one complete attempt against [state] and returns the diagnostics.
MemoryUpdateDiagnostics applyAttempt(
  LearnerState state,
  Exercise exercise,
  Outcome outcome, {
  required DateTime at,
  bool applyRetainedDurabilityInference = true,
}) => model.applyOutcome(
  state: state,
  exercise: exercise,
  outcome: outcome,
  weights: evidenceWeightsFor(exercise, outcome),
  prediction: model.predict(state, exercise, at: at),
  at: at,
  applyRetainedDurabilityInference: applyRetainedDurabilityInference,
);
