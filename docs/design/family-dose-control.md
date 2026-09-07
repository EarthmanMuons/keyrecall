# Family dose control

- **Status:** Implemented behind `SchedulerConfig.dose`, and **not in the V1
  policy**. Mechanism pinned by invariant tests; every constant provisional.
- **Written:** September 7, 2026.
- **Scope:** How often a realization family is offered, given what its recent
  attempts produced. Distinct from realization-family pacing, which relieves
  concentration.

Support already adapts to a family that keeps failing: guidance climbs, and
recovery targets the exact exercise one rung more supported. Nothing adapts the
other quantity. A family that has produced nothing for fifty attempts is offered
at the same cadence as one that produces something every time.

## What the harness found

Sixteen sittings of ten attempts across seventy days, four seeds, every
archetype. `share` is a family's share of the run after it first appeared, and
`after` is its share of the ten slots following a run of five attempts that
yielded no managed execution.

| archetype              | family           | share | after | yield | longest run |
| ---------------------- | ---------------- | ----- | ----- | ----- | ----------- |
| `coordination_limited` | `hands:together` | 36%   | 45%   | 0%    | 53          |
| `developing`           | `hands:together` | 42%   | 31%   | 0%    | 60          |
| `true_beginner`        | `hands:left`     | 56%   | 60%   | 0%    | 89          |
| `uneven_hands`         | `hands:left`     | 22%   | 28%   | 4%    | 24          |
| `advanced`             | `hands:together` | 21%   | 0%    | 86%   | 1           |

A learner can be asked the same unanswerable question fifty-three times in a
row, and the family holds **more** of the sitting after a failed run than it
holds overall. The strong archetypes never reach a run of two, so this is not
about the work being hard. It is about the dose not responding to the answer.

## Why pacing cannot answer it

Pacing pressure is `share above the floor x unproductive fraction`, and the
floor is half the window. A family holding a third of a sitting accumulates no
pressure however little it yields, which is why `coordination_limited` was set
aside three times across a run in which nothing it coordinated ever worked.

The two mechanisms are kept apart deliberately. **Pacing asks whether a family
is crowding the sitting. Dose control asks whether it is worth asking this
often.** Folding the second into the first would need pressure to mean two
things at once, and a family can legitimately be subject to one and not the
other.

## The mechanism

Contraction is read from the same recent-selection window pacing uses, and
nothing else:

```text
evidence     at least minAttempts of the family in the window
yield        managed executions over those attempts
contraction  (yieldFloor - yield) / yieldFloor, zero at or above the floor
relief       halved when productive prerequisite work is in the window
cadence      1 + (maximumGap - 1) x contraction, in slots
```

A family over its cadence is held back from the selectable set for that slot. It
keeps its eligibility, its rank and its place; it is asked for less often, and
nothing else about it changes.

**Evidence is required before contracting.** A family with fewer than
`minAttempts` in the window is left alone, so one or two failed introductions
cannot throttle a strand the learner has barely met.

**Prerequisites are declared, not inferred.** `familyPrerequisites` states that
separate-hand work is evidence for hands together, because the coordination
prerequisite is stated in those terms. Nothing establishes parallel motion as
evidence for contrary, so contrary is absent rather than guessed at. Somebody
whose hands are improving separately is a different learner from one whose hands
are not.

**Contraction never removes.** A slot holding only contracted work returns it
untouched. A learner with nothing else useful to do keeps being offered the hard
thing, which is also why the mechanism cannot empty a sitting.

## Pinned invariants

Asserted, because each states a direction rather than a strength:

- managed execution can only lower a contraction;
- productive prerequisite work can only lower a contraction;
- a family under its minimum evidence is not contracted at all;
- the cadence never exceeds `maximumGap`, and is one at no contraction;
- a slot whose every candidate is contracted keeps them;
- a learner whose families all yield practises the identical trajectory to one
  with no dose policy at all.

That last one is the guard against perturbing learners the mechanism has nothing
to say about: `advanced` produces byte-identical runs either way.

## What it does to a trajectory

The same sixteen sittings, with dose control in force:

| archetype              | family           | share    | after    |
| ---------------------- | ---------------- | -------- | -------- |
| `coordination_limited` | `hands:together` | 36 -> 29 | 45 -> 20 |
| `developing`           | `hands:together` | 42 -> 31 | 31 -> 20 |
| `uneven_hands`         | `hands:left`     | 22 -> 21 | 28 -> 16 |
| `true_beginner`        | `hands:left`     | 56 -> 36 | 60 -> 45 |
| `advanced`             | `hands:together` | 21 -> 21 | 0 -> 0   |

The post-failure share now falls below the family's overall share rather than
rising above it, which is the behavior the characterization asked for.

`true_beginner` is the honest exception. Every one of its families yields
nothing, so contraction applies to all of them at once and cannot prefer
anything; its share falls but the post-failure ordering does not invert. A
learner who cannot execute anything is not a dose problem, and the mechanism
correctly declines to invent an alternative.

## What is unsettled

Every constant. `window`, `minAttempts`, `yieldFloor`, `maximumGap` and
`prerequisiteRelief` are provisional, chosen to be legible rather than tuned,
and a sweep either side of them is the work that would justify promoting this
into the V1 policy.

Elapsed time relaxes nothing. The window is counted in attempts, so a family
that failed before a two-month break is still contracted on the way back, and a
break is arguably itself a reason to try again. Adding a time term means
timestamping the window, which is a change to what a resumed sitting rebuilds.

Why a one-slot pacing set-aside does not reduce a family's share over a run is
still unexplained, and dose control does not explain it: `true_beginner` was set
aside fifty-nine times on its left hand under pacing alone with no contraction
at all. Something returns the family immediately afterwards, and finding out
what is a separate investigation.
