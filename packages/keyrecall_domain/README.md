# keyrecall_domain

The practice domain behind
[KeyRecall](https://github.com/EarthmanMuons/keyrecall): what can be played, how
it can be played, and which competencies each combination creates an opportunity
to observe. No Flutter dependencies.

This package answers structural questions only. It holds no beliefs about any
learner, reads no state, and makes no pedagogical judgments; those belong to
`keyrecall_learner` and `keyrecall_scheduler`.

## What is here

- **Materials.** `TechnicalMaterial` pairs a tonic with a `ScaleForm`. Material
  identity deliberately excludes hand, tempo, octaves, direction, and guidance,
  which is why one scale has a single memory state while its right-hand,
  left-hand, and hands-together performances carry separate execution state.
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
- **Catalog and instrument.** `v1ScaleCatalog` is the initial scale set, and
  `InstrumentProfile` gates what the connected instrument can play.

## Usage

```dart
import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final exercise = Exercise.linear(
    material: const TechnicalMaterial('F#', ScaleForm.harmonicMinor),
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

## What is deliberately missing

`MotorRealization`, the canonical fingering and derived event structure, is not
modeled yet: no fingering catalog exists. Until it does, an exercise's
opportunities are supplied by the caller, and `Exercise.linear` applies a
provisional rule that can only read octave span and direction. Replace that with
real derivation when the catalog lands, rather than widening the heuristic.

## Documentation

The domain reasoning lives in [`docs/domain-model/`](../../docs/domain-model/),
and the integrated V1 specification is
[`docs/learner-model/v1-current-system.md`](../../docs/learner-model/v1-current-system.md).
