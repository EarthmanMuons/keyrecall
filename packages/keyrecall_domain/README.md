# keyrecall_domain

The practice domain behind
[KeyRecall](https://github.com/EarthmanMuons/keyrecall): what can be played, how
it can be played, and which competencies each combination creates an opportunity
to observe. No Flutter dependencies.

This package answers structural questions only. It holds no beliefs about any
learner, reads no state, and makes no pedagogical judgments; those belong to
`keyrecall_learner` and `keyrecall_scheduler`.

## What is here

- **Materials.** `TechnicalMaterial` is the shared identity contract for
  family-owned `ScaleMaterial` and `ArpeggioMaterial` topologies. Identity
  excludes hand, tempo, octaves, direction, and guidance, so realizations do not
  fragment exact-material memory.
- **Exercises.** An `Exercise` bundles a material, an `ExercisePattern`,
  `ExecutionConditions`, a `GuidanceContext`, and the `MotorOpportunity` sites
  its event structure exposes.
- **Guidance.** `GuidanceContext` is a three-rung support ladder. It sets how
  much independent production an attempt demands, and whether independent
  retrieval is tested at all.
- **The Q-matrix.** `Exercise.structuralQ` maps an exercise onto the
  `Competency` values it creates an opportunity to observe. Guidance does not
  change it: a cued harmonic-minor exercise still contains harmonic-minor
  topology.
- **Realization.** `realize` turns an exercise into the ordered notes it asks
  for, spelled by scale degree, so a staff and a keyboard diagram read one
  answer. `PerformanceTranscript` is the other side: what was played, in arrival
  order, with no relation to what was expected.
- **Fingering.** Family-neutral `CanonicalFingering` records carry material and
  hand identity, `entry / cycle / terminal`, explicit descent symmetry, and
  compact provenance. They cover all 48 scales in both hands and the sourced C,
  G, and D major arpeggio fixture without guessing unsupported materials.
- **Presentation conditions.** `PresentationConditions` records what an attempt
  was given on four independent channels: pitch cue, motor cue, performance
  feedback, and tempo support.
- **Catalog, bands, and instrument.** `allScales` is the learner-facing V1
  catalog; `proofArpeggios` is a deliberately tiny architecture fixture;
  `admissionBandOf` says how early each is conventionally introduced;
  `CurriculumRequirement` identifies a stable target or support capability;
  `PracticeGoal` names a custom scope or versioned curriculum; and
  `InstrumentProfile` gates what the connected instrument can play.
  `v1ScaleCatalog` is a fixture the frozen Python prototype matches, not a
  product list.

## Usage

```dart
import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final exercise = Exercise.linear(
    material: ScaleMaterial('F#', ScaleForm.harmonicMinor),
    hands: HandConfiguration.right,
    octaves: 2,
    tempoBpm: 100,
    guidance: GuidanceContext.notesPreviewedOnly,
  );

  print(exercise.material.materialId); // F#_HARMONIC_MINOR
  print(exercise.structuralQ); // topology, RH execution, crossing, ...
  print(exercise.guidance.retrievalDemand); // 0.6
  print(exercise.guidance.isRetrievalObserved); // true
}
```

## Motor structure

`Exercise.linear` derives motor opportunities from the same hand paths and
canonical fingerings that realize the exercise. Recorded exercises retain the
opportunities stored with them so replay does not reinterpret history.

Nothing here knows how a performance relates to what was asked for. That is
`keyrecall_alignment`, and it is deliberately one directional: the domain says
what an exercise is, and never what an attempt at one was worth.

## Documentation

The domain reasoning lives in [`docs/domain-model/`](../../docs/domain-model/),
and the integrated V1 specification is
[`docs/learner-model/v1-current-system.md`](../../docs/learner-model/v1-current-system.md).
