import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'acquisition_floor.dart';

/// Hand configurations candidate generation offers.
const List<HandConfiguration> generatedHands = HandConfiguration.values;

/// Octave spans candidate generation offers.
const List<int> generatedOctaves = [1, 2];

/// Directions candidate generation offers.
const List<ExerciseDirection> generatedDirections = ExerciseDirection.values;

/// Hand motions candidate generation offers for a given hand configuration.
///
/// A single hand has no motion relative to another, so only two hands carry
/// the choice. Every scale and form the catalog holds realizes and fingers
/// under both, so nothing narrows this further by material.
List<HandMotion> generatedHandMotions(HandConfiguration hands) =>
    hands == HandConfiguration.together
    ? HandMotion.values
    : const [HandMotion.parallel];

/// Tempi candidate generation offers, in beats per minute.
const List<double> generatedTempi = [60, 80, 100, 120];

/// Every valid exercise over [materials] that [instrument] can play.
///
/// Stage 1 of the pipeline: pure combinatorics over domain and instrument
/// validity. It takes no learner or session state, and the absence of those
/// parameters is the boundary enforcement. Pedagogy is a later stage's job;
/// this one only decides whether an exercise exists at all.
///
/// All three guidance levels are generated so later stages have something to
/// admit or reject, rather than baking a guidance choice in here.
List<Exercise> generateCandidates(
  InstrumentProfile instrument,
  List<TechnicalMaterial> materials,
) => [
  for (final material in materials)
    for (final hands in generatedHands)
      for (final octaves in generatedOctaves)
        if (instrument.supportsOctaveSpan(octaves))
          for (final direction in generatedDirections)
            for (final handMotion in generatedHandMotions(hands))
              for (final tempoBpm in generatedTempi)
                for (final guidance in GuidanceContext.ladder)
                  Exercise.linear(
                    material: material,
                    hands: hands,
                    octaves: octaves,
                    direction: direction,
                    handMotion: handMotion,
                    tempoBpm: tempoBpm,
                    guidance: guidance,
                  ),
];

/// The scale family's safe starting realizations within [candidates].
AcquisitionFloor scaleAcquisitionFloor(Iterable<Exercise> candidates) =>
    scaleAcquisitionFloorFor([
      for (final materialId in {
        for (final exercise in candidates) exercise.material.materialId,
      })
        AcquisitionFloorRequest(
          requirementId: materialId,
          candidates: candidates.where(
            (exercise) => exercise.material.materialId == materialId,
          ),
        ),
    ]);

/// Safe scale-family entries for the supplied actionable requirements.
AcquisitionFloor scaleAcquisitionFloorFor(
  Iterable<AcquisitionFloorRequest> requests,
) => AcquisitionFloor([
  for (final request in requests)
    for (final exercise in request.candidates)
      if (exercise.conditions.hands != HandConfiguration.together &&
          exercise.conditions.octaves == 1 &&
          exercise.conditions.direction == ExerciseDirection.up &&
          exercise.conditions.tempoBpm == generatedTempi.first &&
          exercise.guidance == GuidanceContext.continuouslyCued)
        AcquisitionFloorEntry(
          requirementId: request.requirementId,
          exercise: exercise,
        ),
]);
