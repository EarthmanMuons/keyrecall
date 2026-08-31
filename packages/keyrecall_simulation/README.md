# keyrecall_simulation

Synthetic learners and the harness that drives
[KeyRecall](https://github.com/EarthmanMuons/keyrecall) over simulated practice.
Pure Dart, no Flutter dependencies.

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

## What the reference numbers are now

They are **evidence, not an obligation**. The Python prototype under `analysis/`
was the reference implementation the Dart model was written against and then
checked against attempt by attempt. That reproduction is what the pinned digests
and recorded reference runs preserve, and it is finished: the Dart
implementation is canonical and carries no forward-parity requirement. See
`analysis/README.md`.

So a mismatch means **this implementation changed**. That may be a defect or it
may be intended, and the pins are updated when it is intended, the way any
regression pin is. What they no longer mean is "Dart and Python disagree, and
one of them is wrong".

The digest runs choose exercises with `randomExercise` rather than through the
scheduler, which is why they still hold: they exercise the model, and Dart-only
scheduler policy such as material admission never enters them.

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

To inspect detector cases by archetype:

```console
dart run keyrecall_simulation:cases \
  --detector entry_tempo_band_step_down \
  --archetype uneven_hands \
  --order worst \
  --limit 5
```

The report includes a detector-specific timeline and the decisive census.
Use `--summary-only` to compare selected cases without printing their timelines.

## Comparing against the reference

Three gates, each answering a different question.

**Did the two implementations make the same decisions?** `discreteTraceDigest`
hashes the categorical fields of a run: exercise identity, realization, guidance
rung, `started`, `completed`, and the factual retrieval outcome. No
floating-point value appears, so it is exact across implementations.

The hashed record is declared in `discreteDigestFields` and tagged with
`discreteDigestSchema`, which is hashed as the first line. The digest is
therefore a statement about a named record shape, not about whatever the
simulation happens to record, so adding a diagnostic field later cannot look
like a behavioral change. Changing the field set means bumping the schema on
both sides. The Python side computes the same digest:

```console
python3 tool/reference_digest.py --all
```

A mismatch means the runs diverged, not that arithmetic drifted.

**Do the numbers still agree?** Run both simulators and diff:

```console
dart run keyrecall_simulation:simulate --profile advanced --attempts 80 --seed 4 --out dart.jsonl
python3 analysis/learner-model/simulate.py --profile advanced --attempts 80 --seed 4 --out py.jsonl
```

Measured worst-case divergence is about 1e-11 relative. Most of it is the
activation anchor: supported practice moves it partway toward the present, and
this implementation stores a real `DateTime` rounded to the microsecond while
the prototype carries an unbounded float day count. Sub-millisecond against a
multi-day half-life, and it then propagates into retrievability and the sampled
observations. `reference_equivalence_test.dart` pins final-state scalars from a
reference run at a 1e-9 tolerance.

Two field-level differences in that diff are expected. The Dart records carry
`outcome.retrieval_succeeded`, which the Python trace omits. And where the
prototype samples "notes previewed" together with "cues visible", Dart reports
`notes_previewed: false`, because visible cues supply the material either way
and the domain model has no fourth guidance value for that combination.

**Did anything here change at all?** `fullTraceDigest` hashes everything a run
computed, at full precision. That one is a regression sentinel for this
implementation rather than a cross-language check.

`PythonCompatibleRandom` needs 64-bit integers, so all of this runs on native
targets rather than the web.

## Documentation

[`docs/learner-model/v1-current-system.md`](../../docs/learner-model/v1-current-system.md)
section 12 summarizes what the synthetic analysis established, and
[`docs/learner-model/05-production-implementation-plan.md`](../../docs/learner-model/05-production-implementation-plan.md)
defines the replay guarantees this harness is meant to grow into.
