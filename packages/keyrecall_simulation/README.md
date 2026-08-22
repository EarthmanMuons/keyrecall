# keyrecall_simulation

Synthetic learners and the harness that drives
[KeyRecall](https://github.com/EarthmanMuons/keyrecall) over simulated
practice. Pure Dart, no Flutter dependencies.

A simulation is a mechanism test, not evidence that the parameters are
calibrated for real pianists. Its value is that it knows the hidden truth, and
can therefore expose contradictions, contamination between state layers, and
policy dead ends that no amount of reading the code will surface.

## What is here

- **Hidden learners.** `SyntheticProfile` builds a `TrueLearnerProfile` whose
  true ability the simulation knows. Each profile isolates a way the model could
  go wrong: conflating memory with technique, treating the hands as one system,
  or letting a material-specific problem contaminate a shared competency. The
  truth uses its own coefficients on purpose; if the generator and the estimator
  shared one equation, a run would mostly confirm that the model can invert its
  own arithmetic.
- **The harness.** `PracticeSimulation` runs a hidden learner through repeated
  attempts against the real `LearnerModel`, producing one `AttemptTrace` per
  attempt: the state the decision was made from, the prediction, what happened,
  how it was weighted, and the state it produced.
- **The scheduler in the loop.** Plug a `SchedulerAgent` in as the simulation's
  chooser and the real pipeline decides what to present. No second update loop
  is involved.
- **Reference equivalence.** `PythonCompatibleRandom` reproduces CPython's
  `random.Random` stream exactly, and `attemptTraceToJson` emits the same
  records `analysis/learner-model/simulate.py` does, so a Dart run can be diffed
  against the reference implementation attempt by attempt rather than only in
  distribution.

## Usage

```dart
import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final simulation = PracticeSimulation.of(
    SyntheticProfile.techniqueStrongMemoryWeak,
    seed: 0,
  );
  final traces = simulation.run(60);

  for (final trace in traces.take(3)) {
    print('${trace.exercise.material.materialId}: '
        'predicted ${trace.prediction.overallP.toStringAsFixed(2)}, '
        'retrieval ${trace.outcome.retrieval.name}');
  }
}
```

With the scheduler choosing:

```dart
final simulation = PracticeSimulation.of(SyntheticProfile.advanced, seed: 1);
final agent = SchedulerAgent(
  pipeline: SchedulerPipeline(learner: simulation.learner),
  instrument: const InstrumentProfile(),
  materials: v1ScaleCatalog.take(3).toList(),
);

runSessions(simulation, agent, sessionCount: 4, attemptsPerSession: 20);

for (final record in agent.records) {
  print('${record.at}: ${record.selected?.exercise ?? 'nothing admitted'}');
}
```

## Comparing against the reference

```console
dart run keyrecall_simulation:simulate --profile advanced --attempts 60 --seed 0 --out dart.jsonl
python3 analysis/learner-model/simulate.py --profile advanced --attempts 60 --seed 0 --out py.jsonl
```

The two traces agree to floating-point tolerance on every field. The Dart
records additionally carry `outcome.retrieval_succeeded`, which the Python
trace omits.

Determinism has limits worth knowing. `PythonCompatibleRandom` needs 64-bit
integers, so it runs on native targets rather than the web. Summation order
differs between the two implementations in a few places, so agreement is to
roughly 1e-9 relative rather than bit for bit.

## Documentation

[`docs/learner-model/v1-current-system.md`](../../docs/learner-model/v1-current-system.md)
section 12 summarizes what the synthetic analysis established, and
[`docs/learner-model/05-production-implementation-plan.md`](../../docs/learner-model/05-production-implementation-plan.md)
defines the replay guarantees this harness is meant to grow into.
