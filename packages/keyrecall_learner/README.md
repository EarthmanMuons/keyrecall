# keyrecall_learner

The V1 learner model behind
[KeyRecall](https://github.com/EarthmanMuons/keyrecall): what the system
believes about a pianist, what it expects from the next attempt, and how it
revises those beliefs afterward. Pure Dart, no Flutter dependencies.

The model is a deterministic library. It reads no clock of its own, performs no
I/O, and mutates only the state it is handed, so a recorded attempt can be
replayed and must produce the same result.

## The three layers of belief

`LearnerState` keeps three answers apart, because they fail independently:

- **`CompetencyState`** per transferable `Competency`: what technique and
  knowledge carries across the repertoire. Practice of any relevant material
  updates it, which is how transfer emerges. Nonuse erodes confidence without
  implying decline.
- **`MaterialMemoryState`** per exact material: whether this scale is
  independently retrievable, tracked as current durability, retained
  consolidation, an activation anchor, and factual retrieval clocks.
- **`MaterialExecutionState`** per material and hand: a shrinkage-based residual
  for problems that are specific to one scale in one hand, rather than a reason
  to lower the shared estimate.

## Four predictions, not one

`LearnerModel.predict` answers four narrower questions than "will they succeed":
independent retrieval, supported material availability, conditional motor
execution, and topology knowledge. `Prediction.overallP` multiplies the two
hurdles, and that product is what challenge admission consumes.

Splitting the channels is the interpretability boundary the model rests on: a
failure to recall is a memory observation, a failure after starting is an
execution observation, and a clean cued performance is useful execution evidence
but no retrieval evidence at all.

## Evidence is attributed, not averaged

`FactualRetrieval` is three-valued. `notTested` is not a weak failure: it
carries exactly zero memory evidence and moves neither factual clock, which is
what stops repeated fully cued practice from accumulating into false evidence of
forgetting. `evidenceWeightsFor` produces separate competency, execution, and
memory weights, and `LearnerModel.applyOutcome` updates only the channels the
attempt genuinely observed.

`Outcome.coordination` is the same idea one layer down. Every competency belongs
to exactly one prediction channel, motor, topology, or coordination, and
`HANDS_TOGETHER_COORDINATION` is the only member of the third. It learns from
how together the hands actually were, and an attempt that measured none carries
no weight for it, so it keeps its prior rather than inheriting a motor score
that never observed it.

## Usage

```dart
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

void main() {
  const model = LearnerModel();
  final now = DateTime.now().toUtc();
  final state = model.placementState(PlacementTier.someExperience, at: now);

  final exercise = Exercise.linear(
    material: const TechnicalMaterial('G', ScaleForm.major),
    hands: HandConfiguration.right,
    guidance: GuidanceContext.notesPreviewedOnly,
  );

  model.propagate(state, now);
  final prediction = model.predict(state, exercise, at: now);

  const outcome = Outcome(
    started: true,
    retrieval: FactualRetrieval.succeeded,
    completed: true,
    materialRetrieval: 0.95,
    pitchIntegrity: 0.9,
    continuity: 0.85,
    temporalStability: 0.8,
    achievedTempoRatio: 1.0,
    topologyAccuracy: 0.9,
  );

  model.applyOutcome(
    state: state,
    exercise: exercise,
    outcome: outcome,
    weights: evidenceWeightsFor(exercise, outcome),
    prediction: prediction,
    at: now,
  );
}
```

## Parameters

`v1PrototypeLearnerParams` mirrors `analysis/learner-model/params.toml` at
registry version `v1-prototype-2`, and a test reconciles the two. Every value
there is a heuristic V1 choice, not a research-established coefficient. The
architecture is frozen for initial production; the numbers are versioned
starting points. Persist `LearnerParams.modelVersion` with every attempt so
replay does not reinterpret old evidence under new constants.

## Documentation

[`docs/learner-model/v1-current-system.md`](../../docs/learner-model/v1-current-system.md)
is the integrated specification;
[`docs/learner-model/03-v1-math.md`](../../docs/learner-model/03-v1-math.md) has
the detailed derivations, and [`docs/GLOSSARY.md`](../../docs/GLOSSARY.md)
defines every term and symbol.
