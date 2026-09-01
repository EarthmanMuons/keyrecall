# keyrecall_scheduler

The V1 scheduler behind [KeyRecall](https://github.com/EarthmanMuons/keyrecall):
given what the system currently believes about a pianist, which valid scale
exercise should they play next. Pure Dart, no Flutter dependencies.

The scheduler is a staged policy, not a scoring function. Each stage answers one
question and may read only what its information boundary permits, and every
candidate comes back with a `CandidateTrace` explaining what happened to it.

## The four stages

1. **Candidate generation** (`generateCandidates`) reads the catalog and the
   `InstrumentProfile`, and nothing else. It takes no learner or session
   parameter at all, and that absence is the boundary enforcement.
2. **Eligibility and safety.** The `REQUIRES` gate reads competencies and is
   soft: a provisionally eligible candidate stays reachable but can never
   outrank a fully eligible one. The safety gate reads session state only and is
   hard.
3. **Challenge admission** keeps ordinary candidates inside a probability band,
   with four named exceptions: new material, guidance probe, bootstrap probe,
   and recovery. Recovery is reactive and exclusive: after a retrieval failure,
   only the same motor task with one more step of guidance survives.
4. **Priority ranking** orders survivors lexicographically by eligibility tier,
   retention, information, diversity, and goals. There is no hidden weighted
   sum. A repetition guard then keeps one material from winning forever, without
   ever removing the only admitted option, and realization-family pacing sets
   aside a strand of work that has been consuming the session without yielding
   when another comparably ready strand is admitted.

## Usage

```dart
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

void main() {
  const model = LearnerModel();
  const pipeline = SchedulerPipeline(learner: model);

  final now = DateTime.now().toUtc();
  final state = model.placementState(PlacementTier.beginner, at: now);
  final session = SessionState();

  final candidates = generateCandidates(
    const InstrumentProfile(),
    v1ScaleCatalog,
  );
  final decision = pipeline.decide(
    state: state,
    session: session,
    candidates: candidates,
    at: now,
  );

  final choice = decision.selected;
  if (choice == null) {
    print('nothing admitted');
    return;
  }
  print('present ${choice.exercise}');
  print('because ${choice.eligibility.reason}, ${choice.terms}');
}
```

A decision opportunity that admits nothing is a real outcome, not an error. Keep
attempt slots and selections distinct in session caps, replay, diagnostics, and
telemetry.

## Recording the result

After the attempt is played, tell the session what happened:

```dart
pipeline.recordOutcome(session, choice.exercise, outcome);
```

Only a tested failure opens a recovery context. An attempt that never tested
retrieval is categorically not a failure to recover from, which is why
`retrievalFailed` is not simply "did not succeed".

## Configuration

`v1SchedulerConfig` is the live registry, at version `v1-3`. It began as a
mirror of `analysis/scheduler/config.toml` at `v1-prototype-0` and has since
moved past it, so a test now checks that the inherited values still match the
archive while the version deliberately does not. The stage structure and
information boundaries are frozen for initial production; the thresholds, probe
intervals, and window sizes are placeholders awaiting calibration against real
practice data. `pacing` is null in a configuration that leaves allocation
unpaced.

## Documentation

[`docs/learner-model/04-v1-scheduler.md`](../../docs/learner-model/04-v1-scheduler.md)
is the boundary contract and the experiment record behind each mechanism;
[`docs/learner-model/v1-current-system.md`](../../docs/learner-model/v1-current-system.md)
puts the scheduler in context with the learner model.
