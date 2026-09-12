# Pacing, dose, and decision cost

How work is spread across strands over a trajectory, what happens to a strand
that keeps producing nothing, and where a decision is computed.

Two mechanisms read the same recent window and answer different questions.
Pacing asks **how much of the sitting** a family holds; dose control asks **what
its recent attempts produced**. In longitudinal runs they never change the same
slot.

## Realization-family pacing

**Decision.** A declared realization family over a set-aside threshold has its
candidates removed from the selectable set for that slot, where a comparably
ready alternative from another family exists.

```text
pressure = max(0, share - floor) x (1 - managed fraction)
```

**Why.** Candidate admission asks whether one exercise is defensible. It cannot
ask whether _another_ exercise from the same family is the best use of the next
slot, and that question only becomes visible once several materials, spans, hand
configurations, and motions can all independently produce admissible
progression.

**Evidence.** Measured across archetypes and seeds, with an explicit unpaced
control arm. `SchedulerConfig.pacing` being null leaves allocation unpaced,
which is what the control arm and any later kill switch use.

**Invariants**, pinned at unit grain where the property is local and across
every archetype where it is not:

- pressure alone never makes an inadmissible exercise admissible; the paced set
  is always a subset of the admitted set;
- pacing never empties a selectable set;
- no relief without a cross-family alternative at least as ready, and the
  relieving candidate never shares a family key with the pressured one;
- successful work in a family relieves its pressure, and so does allocation to
  other families;
- overlapping family keys accumulate pressure on the shared strand, so
  alternating between two motions still loads `hands:together`;
- **family names are opaque**: an unrelated key vocabulary paces identically;
- a trajectory where pressure never forms is identical to the unpaced one.

**Consequences.** `window`, `shareFloor`, `minFamilyAttempts`, and `setAsideAt`
are **not** part of the contract. They ship at the values the experiments ran
at, chosen to make a measured allocation failure visible. The qualitative
signature holds across the settings tried, and they carry no device or telemetry
evidence.

**Accepted limitation.** `uneven_hands` ends slightly behind the unpaced
scheduler, four frontier advances over ten runs. Its useful relief is new
material rather than progression, which is exactly the kind the readiness gate
declines. Recorded as accepted rather than fixed: the sample is too small and
too cohort-specific to justify changing generic behavior.

**Extending it.** A new technical strand joins by declaring the family keys it
consumes. No scheduler branch, no clause in admission, recovery, ranking, or
progression, and no entry in any enum the algorithm reads. What the mechanism
cannot do is decide that one strand is pedagogically more valuable than another;
it notices only that one has been consuming the session without yielding while
something comparably prepared is available.

## Family dose control

**Decision.** A family whose recent attempts have produced little is offered
less often, on a cadence that stretches with how unproductive it has been.

```text
evidence     at least minAttempts of the family in the window (six of twelve)
yield        managed executions over those attempts
contraction  (yieldFloor - yield) / yieldFloor, zero at or above the floor
relief       halved when productive prerequisite work is in the window
cadence      1 + (maximumGap - 1) x contraction, in slots
```

**Why.** Support already adapts to a family that keeps failing: guidance climbs,
and recovery targets the exact exercise one rung more supported. Nothing adapted
the other quantity. A family that has produced nothing for fifty attempts was
offered at the same cadence as one that produces something every time.

**Evidence.** Sixteen sittings of ten attempts across seventy days, four seeds,
every archetype. Pacing cannot answer this: it reads share of the window, and a
family can be unproductive without being concentrated.

**The four properties that keep it safe:**

- **Evidence is required before contracting.** A family under `minAttempts` is
  left alone, so one or two failed introductions cannot throttle a strand the
  learner has barely met.
- **Prerequisites are declared, not inferred.** `familyPrerequisites` states
  that separate-hand work is evidence for hands together, because the
  coordination prerequisite is stated in those terms. Nothing establishes
  parallel motion as evidence for contrary, so contrary is **absent rather than
  guessed at**. Somebody whose hands are improving separately is a different
  learner from one whose hands are not.
- **Time relaxes the contraction, and only the contraction.** Evidence counts
  half as much after `evidenceHalfLifeDays`. What ages is confidence that the
  family is still over its cadence, not the record of what it produced: the
  attempts stay unproductive however long ago they were, and a family returning
  from a break comes back at an ordinary cadence rather than a favored one. A
  half-life rather than an expiry, so nothing hinges on a boundary date.
- **Contraction never removes.** A slot holding only contracted work returns it
  untouched. A learner with nothing else useful to do keeps being offered the
  hard thing.

**Pinned invariants**, asserted because each states a direction rather than a
strength: managed execution can only lower a contraction; productive
prerequisite work can only lower it; a family under minimum evidence is not
contracted; the cadence never exceeds `maximumGap` and is one at no contraction;
a slot whose every candidate is contracted keeps them; time away can only lower
a contraction and can never manufacture yield; and **a learner whose families
all yield practices the identical trajectory to one with no dose policy at
all**. `advanced` produces byte-identical runs either way, which is the guard
against perturbing learners the mechanism has nothing to say about.

**Consequences.** Constants are calibrated from synthetic characterization
rather than device evidence, and stay provisional.

## Where a decision is computed

**Decision.** Scheduling runs on a worker isolate. `SchedulerHost` is the seam.

**Why.** Placement does not change compute, and does change whether the
interface keeps drawing.

**Evidence.** Release builds, mature full mixed catalog:

| Device        | Decide p50 | Decide p95 | Worker round trip p50 |
| ------------- | ---------: | ---------: | --------------------: |
| iPhone 15 Pro |    81.0 ms |    91.6 ms |               79.9 ms |
| Pixel 9a      |   177.8 ms |   199.1 ms |              186.2 ms |

The worker round trip matches the on-isolate decision to within measurement
noise on both devices, so moving scheduling off the UI isolate costs nothing.
Frames observed while one mature decision runs:

| Device        | Placement | Worst gap | Frames |
| ------------- | --------- | --------: | -----: |
| iPhone 15 Pro | UI        |   94.4 ms |      1 |
| iPhone 15 Pro | worker    |    9.8 ms |     21 |
| Pixel 9a      | UI        |  219.9 ms |      1 |
| Pixel 9a      | worker    |   40.7 ms |     20 |

On the UI isolate the decision produces exactly one frame, which is the block
itself. A fifth of a second of frozen interface on a current midrange phone is
perceptible wherever in a transition it lands, and the alternative costs
nothing.

**Consequences.** The residual worker gap is not zero and is not noise: copying
the learner state happens on the sending isolate. An Android device measurement
beyond the Pixel 9a is outstanding.

This settles nothing about policy. Nothing here argues that a mature learner
should be offered fewer alternatives, only that computing them should not happen
on the isolate that draws.

### The cost target is algorithmic, not a millisecond threshold

Four equivalence-preserving reductions took the production-scale weak case from
131 ms to 21 ms and the advanced case from 199 ms to 82 ms on a development
machine, changing no decision. Candidate evaluation is now essentially the whole
decision.

The two cohorts have diverged and only one is about waste. A weak learner ranks
one candidate in ten thousand; an advanced learner genuinely ranks 8,245.

Three properties of the generated set say where any further work goes: guidance
triples every realization while sharing every prediction channel; tempo
multiplies by four though most tempo variants cannot be admitted for any learner
in any state; and ranked share is under 2% for the weak archetypes across the
whole horizon.

> Holding learner state and the selected exercise constant, doubling catalog
> breadth should double only material-level filtering. Prediction and ranking
> work should grow with the number of currently viable realization frontiers,
> not with the number of generated realizations.

The obvious shape is to derive a learner-relative frontier before constructing
exercises. That crosses into what a material family may decide, so it is a
design question rather than a refactor, and it is deliberately not settled.

**One caution the census supplies.** Tempo looks like the cleanest frontier
axis, because entry, adjacency, probes, and recovery all name specific tempi.
But those rules bound admission by _exception_ only. Ordinary band admission
asks prediction, and prediction reads tempo, so a capable learner can hold
several tempi of one realization inside the band at once. A tempo frontier is
provably safe only for a learner whose material admits through the exceptions,
which is the cohort already down at 21 ms.

## The introduction cap stays off

> **Status:** proposed. `IntroductionConfig` exists and is null in the shipped
> configuration.

**Decision.** Characterized and built, but not promoted.

**Why.** Material admission asks whether one unseen material is appropriate now.
Introduction breadth asks whether another should be opened while earlier
introductions are still unresolved, and the distinction only becomes visible in
a catalog wide enough that some defensible first exposure is always available.

**Evidence.** The full-catalog census raised it: every individual decision was
sound, and the trajectory was not. The counterfactual controls are in
[`../research/experiments/introduction-breadth.md`](../research/experiments/introduction-breadth.md).

**Consequences.** It filters the available set beside pacing, never empties it,
and leaves admission untouched. Shipping it null means the mechanism is
available without a policy claim it has not earned.
