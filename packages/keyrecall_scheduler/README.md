# keyrecall_scheduler

The V1 scheduler behind [KeyRecall](https://github.com/EarthmanMuons/keyrecall):
given what the system currently believes about a pianist, which valid technical
exercise should they play next. Pure Dart, no Flutter dependencies.

The scheduler is a staged policy, not a scoring function. Each stage answers one
question and may read only what its information boundary permits, and every
candidate comes back with a `CandidateTrace` explaining what happened to it.

## The stages

1. **Candidate generation** (`generateCandidates`) reads the catalog and the
   `InstrumentProfile`, and nothing else. It takes no learner or session
   parameter at all, and that absence is the boundary enforcement.
2. **Eligibility and safety.** The `REQUIRES` gate reads competencies and is
   soft: a provisionally eligible candidate stays reachable but can never
   outrank a fully eligible one. The safety gate reads session state only and is
   hard.
3. **Challenge admission** keeps ordinary candidates inside a probability band,
   and admits outside it only through a named exception: an explicit override,
   recovery, a tempo, observation, guidance, or bootstrap probe, consolidation,
   new material, or execution progression. Each is recorded as the bypass it
   was. Recovery is reactive and exclusive: after a retrieval failure, only the
   same motor task with one more step of guidance survives.
4. **Priority ranking** orders survivors lexicographically by eligibility tier,
   coordination transition, retention, information, diversity, goals,
   realization rank, and realization fit. There is no hidden weighted sum.

Selection then narrows what ranking produced, without ever emptying it: a
repetition guard keeps one material from winning forever, an optional
introduction cap withholds first exposures while a scope already holds its
budget of unretrieved material, and realization-family pacing sets aside a
strand that has been consuming the session without yielding when another
comparably ready strand is admitted.

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

  final candidate = switch (decision) {
    CandidateSelected(:final candidate) => candidate,
    SelectionBlocked(:final reason) => throw StateError(
      'practice blocked: ${reason.name}',
    ),
  };
  print('present ${candidate.exercise}');
  print('because ${candidate.eligibility.reason}, ${candidate.rankKey}');
}
```

A decision opportunity returns either `CandidateSelected` or `SelectionBlocked`;
absence is never silent. A caller that knows it is scheduling unresolved
requirements may supply family-declared `AcquisitionFloorEntry` values. The
pipeline consults them only after ordinary admission exhausts and admits an
in-scope entry under the `acquisition_floor` bypass. No floor or a floor
rejected by later stages remains blocked.

## Recording the result

After the attempt is played, tell the session what happened:

```dart
pipeline.recordOutcome(session, candidate.exercise, outcome);
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
