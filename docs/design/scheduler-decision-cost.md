# Scheduler decision cost

- **Status:** Census and two equivalence-preserving reductions. The dominant
  term is identified and unaddressed.
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

## Three reductions that changed no decision

Profiling found three costs that were not about pedagogy at all.

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
| 48 scales, true beginner, 40  |  112.9 |  16.4 |
| 48 scales, advanced, 80       |  184.6 |  81.5 |
| full mixed, true beginner, 40 |  130.8 |  20.9 |
| full mixed, developing, 80    |  146.1 |  43.0 |
| full mixed, advanced, 80      |  199.3 |  89.9 |

Milliseconds per decision. Candidate assembly fell from about 60 ms to 0.1 ms
and is no longer a term. Requirement evaluation was never one, at well under a
millisecond even over 360 requirements: the journal scan it performs is cheap
because the material check fails first.

All three changes are equivalence-preserving by construction, and the whole
suite passes unchanged, including the pinned calibration and trajectory tests.

## What remains, and the acceptance target

Candidate evaluation is now essentially the whole decision: 125 ms of the 129 ms
full-mixed worst case. Three properties of the generated set say where that
goes:

- **Guidance triples every realization.** A third of candidates are distinct
  execution realizations; the other two thirds differ only in guidance and share
  every prediction channel through the caches, while still paying eligibility,
  admission, and trace construction of their own.
- **Tempo multiplies by four.** Introductions are admitted at one entry tempo
  and progression only at an adjacent rung, so most tempo variants cannot be
  admitted for any learner in any state.
- **Almost nothing reaches ranking.** Ranked share is under 2% for the two weak
  archetypes across the whole horizon.

The target for the next tranche is therefore algorithmic rather than a
millisecond threshold:

> Holding learner state and the selected exercise constant, doubling catalog
> breadth should double only material-level filtering. Prediction and ranking
> work should grow with the number of currently viable realization frontiers,
> not with the number of generated realizations.

The obvious shape is to derive a learner-relative frontier before constructing
exercises, so that a material contributes the handful of realizations that could
plausibly be selected rather than its whole Cartesian product. That crosses into
what a material family may decide, so it is a design question rather than a
refactor, and it is deliberately not settled here.

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
