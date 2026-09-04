# Scheduler decision cost

- **Status:** Census, four equivalence-preserving reductions, and an iOS release
  benchmark. An Android device measurement is outstanding.
- **Written:** September 4, 2026
- **Scope:** What one scheduling decision costs, and how that cost grows with
  the catalog. The stress case is the production-scale corpus, 48 scales and 24
  root-position arpeggios.

The full-catalog census took close to an hour. Worker parallelism is not the
answer to that, because the same decision runs on a phone. A slot that costs 200
ms on a development machine is the number that matters, not the wall clock of an
offline experiment.

## What is measured

`decision_cost` profiles real decisions through the real session, scope
evaluator, learner model, and scheduler. For each sampled slot it records how
much work reached each stage and how long each phase took:

```console
dart run keyrecall_simulation:decision_cost --slots 0,10,40,80
```

Four catalogs, three archetypes, four trajectory positions, one seed. Session
phases are timed by repeating requirement evaluation and candidate assembly on
the inputs the session is about to use, so production carries no timers.

## The shape of a decision

Concrete candidates are what a decision is made of, and the catalog decides how
many there are:

| Catalog                 | Materials | Candidates | Per material |
| ----------------------- | --------: | ---------: | -----------: |
| small fixture           |         2 |         54 |           27 |
| 24 arpeggios            |        24 |        648 |           27 |
| 48 scales               |        48 |      9,216 |          192 |
| 48 scales, 24 arpeggios |        72 |      9,864 |          137 |

The scale realization space is the whole story. A scale material generates
hands, spans, directions, motions, four tempi, and three guidance rungs; an
arpeggio material generates a seventh of that. Adding every arpeggio to the full
scale catalog raises candidate count by 7%, which is why the scale-only and
mixed scopes cost almost the same.

Cost is linear in candidates, at 4 to 16 microseconds each. The constant moves
with how many of them reach ranking, not with the catalog:

| Scope, archetype, slot        | Candidates | Ranked | Ranked share |
| ----------------------------- | ---------: | -----: | -----------: |
| full mixed, true beginner, 40 |     10,446 |      1 |       0.0001 |
| full mixed, developing, 80    |     11,541 |    190 |       0.0193 |
| full mixed, advanced, 80      |     13,059 |  8,245 |       0.8359 |
| 24 arpeggios, advanced, 80    |      1,464 |  1,219 |       1.8812 |

Two structural facts follow from the same table. Evaluated candidates exceed
generated ones by up to 32%, because execution neighbors are added inside
evaluation. And a ranked share above one is not an error: neighbors can rank.

For a weak learner in the mixed scope, 99.99% of a decision's work is spent on
candidates that never reach ranking. That is the eager-expansion cost, and it is
exactly what the acceptance target below is about.

## Where a candidate's time actually went

Timing the stages of one candidate's evaluation put the cost somewhere the stage
counts do not suggest. Over one full-mixed decision:

| Sub-step                   | True beginner | Advanced |
| -------------------------- | ------------: | -------: |
| prediction channels        |         77.1% |    67.0% |
| realization key            |         20.6% |    19.4% |
| rank key                   |          1.8% |    13.3% |
| eligibility, bypass, trace |          0.5% |     0.3% |

Eligibility, admission, and trace construction are free. Nearly nine tenths of a
decision was the guidance-sharing machinery itself: allocating a normalized
exercise per candidate to key the channel caches with, then hashing and
comparing it three times. The comparison walks two opportunity sets.

That reframes the guidance axis. Its cost was never the pedagogy the extra
candidates carry; it was the identity of the thing the caches were keyed on.

## Four reductions that changed no decision

Profiling found four costs that were not about pedagogy at all.

**Exercise hashing was recomputed on every lookup.** The hash combines two set
hashes, and a slot hashes every candidate through set membership and three keyed
caches. Computing it once per exercise cut evaluation by roughly a tenth and
assembly by a quarter.

**Candidate assembly deduplicated by exercise.** Requirements over one material
resolve to equal candidate lists, so the session was hashing ten thousand
exercises to rediscover that two requirements share a material.
`distinctCandidatesOf` keys that on the material instead, which is O(materials)
rather than O(candidates).

**Channel caches were keyed by an exercise standing for a realization.**
Execution, coordination, and topology read the material, the pattern, and the
execution conditions; guidance changes only material availability. Keying the
caches on those three directly removes an allocation per candidate and replaces
three set-comparing lookups with three record lookups. `RealizationKey` is
pinned to partition the generated catalog exactly as the normalized exercise
did.

Together, on the same matrix:

| Scope, archetype, slot        | Before | After |
| ----------------------------- | -----: | ----: |
| 48 scales, true beginner, 40  |  112.9 |  17.9 |
| 48 scales, advanced, 80       |  184.6 |  82.0 |
| full mixed, true beginner, 40 |  130.8 |  21.5 |
| full mixed, developing, 80    |  146.1 |  37.7 |
| full mixed, advanced, 80      |  199.3 |  82.0 |

Milliseconds per decision. Candidate assembly fell from about 60 ms to 0.1 ms
and is no longer a term. Requirement evaluation was never one, at well under a
millisecond even over 360 requirements: the journal scan it performs is cheap
because the material check fails first.

All four changes are equivalence-preserving by construction, and the whole suite
passes unchanged, including the pinned calibration and trajectory tests.

## Inside the remaining decision

Timing each stage of candidate evaluation again, on the mature advanced decision
this time, separates real prediction from work spent on candidates that share
one:

| Work                                        |  Calls | Share |
| ------------------------------------------- | -----: | ----: |
| channel and information cache misses        |  9,986 |   11% |
| cache lookups on candidates sharing a value | 44,000 |   30% |
| per-candidate admission, rank terms, trace  | 13,059 |   59% |

The answer to "thousands of distinct expensive predictions, or a few hundred
predictions and a great many cheap-but-not-cheap-enough lookups" is the second.
Only about a tenth of the mature advanced decision computes a prediction that
has not already been computed for another candidate.

Two of those per-candidate helpers were asking a question of learner state and
throwing the answer away. `transferableTempoFor` scans, filters, and sorts every
execution residual the learner has, and reads only the hand: at most three
distinct answers, recomputed once per candidate. `handsTogetherEntryTempo`
varies with the material and the span. `ExecutionMemo` holds both for the life
of one decision, on the same boundary the eligibility memo already uses.

Its measured effect is modest, taking the mature advanced decision from about 90
ms to about 82 ms, which is only just outside run-to-run variation. The better
argument for it is that the scan it removes grows with the learner's practice
history, so it was the one term that would get worse with use rather than with
the catalog.

## A note on the numbers

Every timing here is one run of one seed on a development machine, and repeated
runs of the same matrix vary by roughly 5%, occasionally more on the heaviest
cells. Differences of a few percent between arms are not resolvable at this
sample size; the reductions recorded above are all multiples, except the memo,
which is reported as small for that reason.

## What remains, and the acceptance target

Candidate evaluation is now essentially the whole decision: 78 ms of the 82 ms
full-mixed worst case. The two cohorts have diverged, and only one of them is
about waste. A weak learner's full-mixed decision costs about 21 ms while
ranking one candidate in ten thousand. An advanced learner's costs about 82 ms
while genuinely ranking 8,245.

Three properties of the generated set say where the remaining work goes:

- **Guidance triples every realization.** A third of candidates are distinct
  execution realizations; the other two thirds differ only in guidance and share
  every prediction channel through the caches, while still paying eligibility,
  admission, and trace construction of their own.
- **Tempo multiplies by four.** Introductions are admitted at one entry tempo
  and progression only at an adjacent rung, so most tempo variants cannot be
  admitted for any learner in any state.
- **Almost nothing reaches ranking.** Ranked share is under 2% for the two weak
  archetypes across the whole horizon.

The target for any further reduction is algorithmic rather than a millisecond
threshold:

> Holding learner state and the selected exercise constant, doubling catalog
> breadth should double only material-level filtering. Prediction and ranking
> work should grow with the number of currently viable realization frontiers,
> not with the number of generated realizations.

The obvious shape is to derive a learner-relative frontier before constructing
exercises, so that a material contributes the handful of realizations that could
plausibly be selected rather than its whole Cartesian product. That crosses into
what a material family may decide, so it is a design question rather than a
refactor, and it is deliberately not settled here.

One caution the census already supplies. Tempo looks like the cleanest frontier
axis, because entry, adjacency, probes, and recovery all name specific tempi.
But those rules bound admission by exception only. Ordinary band admission asks
prediction, and prediction reads tempo, so a capable learner can hold several
tempi of one realization inside the band at once. A tempo frontier is therefore
provably safe only for a learner whose material admits through the exceptions,
which is the cohort already down at 21 ms. Bounding the advanced case means
bounding candidates that could genuinely be selected, which is a policy question
about how many simultaneous alternatives practice should consider, not an
optimization.

## Where this branch stops

Desktop profiling is done. Accidental hashing and assembly overhead, the
guidance-sharing cache identity, and the frontier scans that grew with practice
history are all removed, and no decision changed:

| Case                          | Before | After |
| ----------------------------- | -----: | ----: |
| production-scale weak learner |    131 |    21 |
| production-scale advanced     |    199 |    82 |

Milliseconds per decision, JIT, on a development machine. Neither number is the
product metric. That comes from a release build on target hardware, measuring
scheduler computation and user-visible transition latency separately, at median
and p95 over repeated decisions, with the scheduler on and off the UI isolate.
The first such measurement is below.

The criterion is product-grounded rather than a universal number:

> Scheduling must not create a perceptible delay in the exercise transition on
> target hardware, and mature full-catalog decisions must leave enough headroom
> for future catalog expansion.

If a release build clears that, the remaining 82 ms is the price of offering a
mature learner many admissible alternatives, and the scheduler's search space
should not be made artificially smaller to reduce it. If it does not, the next
problem is a policy one: how many simultaneously admissible alternatives a
mature learner's scheduler should consider.

## On device

`SchedulerBenchmarkScreen`, reachable from the practice overflow menu, runs the
same catalogs through the same session in a release build and writes its report
beside the trajectory exports. It sits outside the build-mode check that hides
the developer screen, deliberately: what it measures is release-build scheduling
cost, which a profile build cannot say. It comes out before the app is
published. Release builds, mature full mixed catalog:

| Device        | Decide p50 | Decide p95 | Worker round trip p50 |
| ------------- | ---------: | ---------: | --------------------: |
| iPhone 15 Pro |    81.0 ms |    91.6 ms |               79.9 ms |
| Pixel 9a      |   177.8 ms |   199.1 ms |              186.2 ms |

The weak cases are comfortable on both: 24.5 ms and 45.2 ms at the steady state,
cold decisions cheaper still.

**Compute does not move with placement.** A worker that owns the scope answers
from a state the slot sends it, and its round trip matches the on-isolate
decision to within measurement noise on both devices. Moving scheduling off the
UI isolate therefore costs nothing and the message shape is viable: the learner
state and the sitting cross by copy, and the candidate envelope never moves at
all because the worker resolves it once from the catalog.

**Placement decides whether the interface keeps drawing.** Frames observed while
one mature decision runs:

| Device        | Placement | Worst gap | Frames |
| ------------- | --------- | --------: | -----: |
| iPhone 15 Pro | UI        |   94.4 ms |      1 |
| iPhone 15 Pro | worker    |    9.8 ms |     21 |
| Pixel 9a      | UI        |  219.9 ms |      1 |
| Pixel 9a      | worker    |   40.7 ms |     20 |

On the UI isolate the decision produces exactly one frame, which is the block
itself. On a worker the interface keeps drawing throughout, at roughly a frame
per refresh interval.

The residual worker gap is not zero and is not noise: copying the learner state
happens on the sending isolate, so a slot still holds the interface for as long
as that takes. It is 9.8 ms on the iPhone and 40.7 ms on the Pixel, against 94.4
and 219.9 for the decision itself.

**What this settles.** A fifth of a second of frozen interface on a current
midrange phone is perceptible wherever in a transition it lands, and the
alternative costs nothing in compute. Scheduling belongs off the UI isolate. The
bounded-choice policy question stays closed: nothing here argues that a mature
learner should be offered fewer alternatives, only that computing them should
not be done on the isolate that draws.

## Where the decision is computed

Scheduling runs on a worker isolate. `SchedulerHost` is the seam, and it decides
placement and nothing else: the session binds the resolved scope, the learner,
and the policy constants, so a host cannot decide with anything the session did
not give it. That is not a refinement. The first version let the host default
its own learner, and the worker silently ran the frozen prototype's constants
while the session ran the current ones, which a provider-level equivalence test
caught by presenting different exercises from identical state.

What travels per slot is the epoch, a propagated learner state, the sitting, a
timestamp, and the ids of the requirements due. The ten thousand exercises those
ids resolve to never move, because the worker holds the scope for as long as
that scope is the sitting's. Only the winning candidate comes back.

The main isolate stays authoritative. It owns the state, applies the sitting
effect, and writes the pending decision. The worker owns one scope and a
pipeline, writes nothing, and cannot mutate a sitting it only ever sees a copy
of. Losing one fails the request in flight and nothing else.

Pinned by test: the two placements produce the same exercise and the same
post-decision sitting; a verdict answering a superseded epoch applies nothing
and writes nothing; a lost worker leaves no outstanding attempt and no persisted
decision; provider disposal tears the worker down.

## Preserving the traces

`CandidateTrace` is what every characterization in this repository reads, so
decision equivalence is the acceptance criterion for any reduction: same
selected exercise, same blocked or caught-up outcome, same bypass, same pacing
and introduction dispositions, same traces for candidates that are semantically
evaluated, and an unchanged learner state after the attempt.

A frontier that declines to construct structurally impossible realizations would
change which candidates have traces at all. Whether those need a lighter
structural record is a trace-contract decision to make when something actually
consumes it, not a cost to pay in advance.
