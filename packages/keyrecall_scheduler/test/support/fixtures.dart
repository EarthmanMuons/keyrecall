import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// The reference instant these tests count from.
final DateTime t0 = DateTime.utc(2026);

const LearnerModel learner = LearnerModel();
const SchedulerPipeline pipeline = SchedulerPipeline(learner: learner);
const SchedulerConfig config = v1PrototypeSchedulerConfig;
const LearnerParams learnerParams = v1PrototypeLearnerParams;
const InstrumentProfile instrument = InstrumentProfile();

/// The materials these tests schedule over.
const List<TechnicalMaterial> materials = v1ScaleCatalog;

/// A learner state placed at [tier].
LearnerState stateAt(PlacementTier tier) =>
    learner.placementState(tier, at: t0);

/// A two-octave, up-and-down, 80 BPM exercise: the shape candidate generation
/// produces, built directly for tests that need one specific candidate.
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

/// Gives every material a memory entry at its priors.
///
/// Mathematically a no-op for prediction, since a missing entry falls back to
/// the same prior. It only removes candidates from the new-material exception,
/// so ordinary band behavior can be observed.
void seedAllMaterials(LearnerState state) {
  for (final material in materials) {
    state.materialMemoryFor(material.materialId, learnerParams);
  }
}

/// Every candidate over the full catalog.
List<Exercise> allCandidates() => generateCandidates(instrument, materials);

/// The traces from one evaluation, keyed by candidate.
Map<Exercise, CandidateTrace> tracesByExercise(List<CandidateTrace> traces) => {
  for (final trace in traces) trace.exercise: trace,
};
