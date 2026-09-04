# Introduction breadth

- **Status:** Characterization and counterfactual controls. `IntroductionConfig`
  exists in the scheduler and is null in `v1SchedulerConfig`; no policy
  promoted.
- **Written:** September 4, 2026
- **Scope:** How much unresolved new material a trajectory may hold open at
  once. The materials measured here are scales and root-position arpeggios, but
  the mechanism reads a family key it cannot interpret.

Material admission asks whether one unseen material is appropriate now.
Introduction breadth asks whether another one should be opened while earlier
introductions are still unresolved. The distinction only becomes visible in a
catalog wide enough that some defensible first exposure is always available.

The full-catalog census raised it. Every individual decision was sound: the
material was admissible, the rung was the entry rung, the prediction cleared the
introduction floor. The trajectory was not.

```text
existing material is not yet ready for deeper work
        |
another unseen material is introducible
        |
new-material admission takes the slot
        |
breadth grows, and more unseen material remains
```

## What the census measures

`arpeggio_policy` now records, for every trajectory:

- introductions per run and the most any twenty-slot window held;
- open unresolved material at each decision, peak and mean, where unresolved
  means met and never yet retrieved from memory;
- the gap from a material's first selection to its first revisit;
- the share of materials receiving a second attempt, a different hand
  configuration, or a wider span within twenty slots of their introduction.

Follow-through is restricted to materials introduced at least twenty slots
before the horizon, so the measure is not an artifact of the run ending.

## Baseline

Four seeds, eight archetypes, 80 slots, the shipped configuration:

```console
dart run keyrecall_simulation:arpeggio_policy --mode baseline --seeds 4 --slots 80
```

Introductions occupy roughly half of every trajectory, and this is not something
arpeggios introduced. The scale-only control is the clearest case: the advanced
archetype spends 41.5 of 80 slots meeting material for the first time, with 18
of some twenty-slot window given to introductions.

| Scope, archetype               | Introductions | Peak per 20 | Unresolved peak |
| ------------------------------ | ------------: | ----------: | --------------: |
| scale only, advanced           |          41.5 |          18 |               1 |
| scale only, true beginner      |          23.8 |          12 |               7 |
| full mixed, advanced           |          55.0 |          18 |               1 |
| full mixed, developing         |          40.8 |          14 |              12 |
| full mixed, true beginner      |          38.5 |          13 |              12 |
| small fixture, every archetype |           4.0 |           4 |               2 |

Breadth and churn are different questions, and the unresolved column separates
them. Strong archetypes introduce constantly and resolve immediately: their open
unresolved count never exceeds one, because they retrieve what they meet on the
attempt that introduced it. Weak archetypes accumulate: the true beginner holds
twelve met-but-unretrieved materials in the mixed scope and fourteen in the
arpeggio-only scope.

Follow-through within twenty slots of introduction, full mixed scope, pooled
over four seeds:

| Archetype, family       | Introduced | One and done | Revisited | Wider span |
| ----------------------- | ---------: | -----------: | --------: | ---------: |
| true beginner, arpeggio |         49 |            4 |     0.659 |      0.000 |
| developing, arpeggio    |         85 |           25 |     0.554 |      0.000 |
| advanced, scale         |         88 |           47 |     0.149 |      0.011 |
| advanced, arpeggio      |         96 |           58 |     0.081 |      0.000 |

The small fixture reaches 1.000 on every follow-through measure for every
archetype. It could not have exhibited this behavior at all, which is what the
catalog expansion was for.

## Counterfactual controls

`IntroductionConfig` caps the unresolved introductions a scope may hold. It is a
selection-stage filter beside realization-family pacing, and deliberately not an
admission rule: a withheld first exposure stays eligible and ranked, and wins
the slot whenever nothing already met is available.

Two boundaries are part of the mechanism rather than its calibration:

- **The other hand of a material already met is not breadth.** Withholding it
  would make the cap an argument about hands rather than about how many things
  are open at once.
- **Unresolved is factual, not predicted.** It is the same question
  consolidation asks: the learner has been shown this and has never produced it
  from memory.

The arms are diagnostic bounds, not proposed policy:

| Arm                 | Budget                           |
| ------------------- | -------------------------------- |
| `breadth_catalog_2` | 2 unresolved across everything   |
| `breadth_catalog_4` | 4 unresolved across everything   |
| `breadth_catalog_8` | 8 unresolved across everything   |
| `breadth_family_4`  | 4 unresolved per declared family |

```console
dart run keyrecall_simulation:arpeggio_policy \
  --mode breadth --seeds 4 --slots 80 --jobs 8
```

Five arms over the two full scopes, four seeds, eight archetypes: 320
trajectories in 1470 seconds on eight workers.

## What controlling breadth does

**It acts only where churn exists.** For the intermediate, advanced,
tempo-noncompliant, uneven-hands, and coordination-limited archetypes, every arm
reproduces the baseline allocation, milestones, and prediction quantiles
exactly, including at the tightest budget. Those learners rarely hold two
unresolved materials. Where the cap does fire for them, in a handful of slots
for three of the five, it removes candidates that were not going to win, which
is the same inert-substitution pattern realization-family pacing found. The
three cohorts it changes are the true beginner, developing, and
fast-but-placed-low profiles.

**It removes the churn it was aimed at.** Developing, full mixed scope:

| Arm                 | Introductions | Unresolved peak | Materials | Arpeggio share |
| ------------------- | ------------: | --------------: | --------: | -------------: |
| baseline            |          40.8 |              12 |        24 |          80.3% |
| `breadth_catalog_8` |          38.0 |               8 |        22 |          76.9% |
| `breadth_family_4`  |          32.0 |               7 |        22 |          65.6% |
| `breadth_catalog_4` |          25.3 |               6 |        18 |          59.4% |
| `breadth_catalog_2` |          12.3 |               2 |         9 |          40.0% |

One-and-done introductions fall with it, from 25 of 85 arpeggio introductions at
baseline to 1 of 16 at the tightest budget, and the true beginner's
arpeggio-only trajectory reaches a 1.000 revisit rate at every budget below
eight.

**No arm produced a terminal failure.** Every trajectory ran the full horizon.
Nothing blocked, caught up, or became invalid, and the acquisition floor stayed
uninvoked throughout, which is what the never-empty-the-set rule predicts.

**It does not buy depth.** This is the result that matters most. Wider-span work
within twenty slots of introduction stays at 0.000 in every arm, for every
archetype, in both full scopes. The true beginner still reaches neither
two-octave nor hands-together arpeggio work under any budget. Where depth does
move it moves modestly and inconsistently: the fast-but-placed-low profile
reaches hands-together arpeggios at slot 24.0 rather than 34.3 and two octaves
at 42.5 rather than 51.0 under the tightest budget, while the developing profile
gains an earlier hands-together milestone in three seeds of four and loses its
only two-octave milestone.

The reading is that breadth and depth are separately governed. Withholding
introductions changes which material the slot goes to; it does not change
whether progression on that material is admissible, which is decided by
prerequisites and evidence the cap does not touch.

## Interpretation boundary

A one-and-done introduction is not by itself a defect. For the advanced
archetype most of them are materials retrieved on the attempt that introduced
them, and not returning to those within twenty slots is ordinary spacing rather
than abandonment. The measure that distinguishes the cohorts is unresolved
material held open, and it is the only one the cap reads.

The census also cannot say that a narrower trajectory taught more. It reports
allocation, follow-through, and milestones for a synthetic player. Whether
meeting nine materials well beats meeting twenty-four thinly is a question about
learners, and the answer is not in this harness.

## Known limitations

The cap counts unresolved material through the families this slot's candidates
name, so material outside the current scope does not hold a budget against
material inside it. That is deliberate for scoped practice and wrong if a
learner returns to a narrowed goal carrying unresolved work from a wider one.

Paired scale displacement under a cap is unmeasured. The scale-only control is
what turns a milestone shift into an externality measure, and the arms above did
not run it. The runner now pairs it per arm, but the 480-trajectory census that
would fill the gap was abandoned: at roughly four seconds per slot-limited
trajectory it approached an hour, which is the cost this work stopped for.

## Where that leaves the roadmap

The census cost is the immediate blocker. Decision cost grows with the catalog,
and the full mixed scope is the production-scale case rather than an offline
one: the same pipeline runs on a phone. Scheduler decision cost comes before the
remaining allocation questions.

Breadth is otherwise a controlled variable rather than a confound, and the
remaining questions separate cleanly:

- introduction allocation has a mechanism and a measured signature, and needs a
  real trajectory rather than another synthetic arm to calibrate;
- entry fit is unaffected by it, and the true beginner's inability to reach
  wider work at 60 BPM survives every budget;
- the learner-model extension analysis can now ask whether shared arpeggio
  execution plus material-hand residuals leave repeatable error structure,
  conditional on an exposure trajectory that is not dominated by novelty.
