# Arpeggio policy, and the residual census

Two experiments on the same corpus of 24 provenance-backed major and minor
root-position arpeggios. The first asks whether the provisional policy forms a
viable practice system. The second asks whether the model leaves repeatable
error that a new competency would explain.

**Both are nulls**, and both are worth keeping for the same reason: the
instrument is now built and calibrated against data whose structure is known, so
it can be pointed at real attempts when those exist.

## Policy characterization

**Question.** Synthetic trajectories cannot calibrate pedagogy. They can reveal
dead ends, concentration, and sensitivity before the catalog becomes expensive
to change.

**Method.** Vary one assumption at a time against a baseline:

| Arm                    | Difference from baseline                        |
| ---------------------- | ----------------------------------------------- |
| `transfer_0`           | `rhoFamily = 0`                                 |
| `transfer_0_70`        | `rhoFamily = 0.70`                              |
| `floor_separate_hands` | both separate hands may enter through the floor |

**Result. No parameter changes follow.**

- The 60 BPM entry remains **structurally executable but pedagogically
  unvalidated**.
- `rhoFamily = 0.35` remains uncalibrated and **low-sensitivity in this
  harness**, which is a statement about the harness as much as the parameter:
  varying it from 0 to 0.70 moved little, so this instrument cannot calibrate
  it.
- The right-hand ascending floor remains unpromoted.

**What the full corpus did reveal.** No tonic or fingering-family concentration.
But broad new-material availability can dominate acquisition-floor use and defer
within-material progression, while deeper scale milestones move substantially in
the mixed scope.

That finding is why introduction allocation was taken up first, in
[`introduction-breadth.md`](introduction-breadth.md): the residual question
below could not be asked cleanly while breadth was confounding it.

## The residual census

**Question.** After the allocation confound was controlled, does the model leave
repeatable error that a material, hand, or fingering-geometry state would
explain?

**Why it could not be asked earlier.** A learner failing to deepen material was
two hypotheses at once: a model missing a competency, or a scheduler that kept
introducing new material and never revisited it. Breadth is now a controlled
variable, so the residual question can be asked on its own.

**Method.** Four archetypes through the arpeggio-only and full mixed catalogs,
reading each attempt back out of the journal as the difference between what the
model expected and what happened.

**Result.** Three effects survive, and **none of them is keyed to material**:

| Axis | Level           | Mean execution residual |
| ---- | --------------- | ----------------------: |
| Hand | right           |                  +0.108 |
| Hand | left            |                  +0.007 |
| Hand | together        |                  -0.084 |
| Rung | continuous cue  |                  +0.137 |
| Rung | notes previewed |                  +0.049 |
| Rung | unguided        |                  +0.002 |

Quality splits nothing: major +0.043 against minor +0.034.

The topology residual is positive everywhere, around +0.17, so the model
**underpredicts topology accuracy across the board** rather than for any
particular material.

Requested tempo shows a monotone trend from -0.146 at 60 BPM to about +0.13 at
the top of the ladder. That one is **confounded by selection rather than
interpretable**: a fast rung is only offered to a learner whose frontier is
already there, so the population at 144 BPM is not the population at 60.

**Verdict: a validated null. No competency proposed.**

### What it establishes, precisely

It does **not** say a fingering-family competency is unwarranted in a real
learner. It says three narrower things:

1. This harness cannot supply evidence for one.
2. The obvious way to look for one **produces a confident false positive if the
   hand is not controlled.**
3. The analysis reports a clean null on data with no such structure, which is
   what makes it trustworthy when pointed at data that might.

The next evidence has to be real attempts. When it exists, the same census runs
unchanged, and the controlled row is the one to read.

### What an attempt has to keep carrying

The controls are the part that would be discovered missing too late. Every field
is already in the journal:

| Census input            | Where it comes from                                  |
| ----------------------- | ---------------------------------------------------- |
| Predicted execution     | `execution_p` on the recorded decision               |
| Predicted topology      | `topology_p` on the recorded decision                |
| Observed motor          | `continuity` and `temporal_stability` on the outcome |
| Observed topology       | `topology_accuracy` on the outcome                   |
| Material identity       | the recorded exercise's material                     |
| Hand configuration      | the recorded exercise's execution conditions         |
| Span, direction, motion | the same                                             |
| Requested tempo         | the same                                             |
| Guidance rung           | the recorded exercise's guidance                     |
| Fingering geometry      | derived from the catalog, not stored                 |

Two things to keep rather than add. The scheduler decision is **optional** on an
attempt record and an attempt without one is skipped: a residual needs the
prediction that was actually made, and recomputing it later would be measuring a
different model. And geometry is derived from the catalog by material and hand,
so a catalog change is a change to the analysis of attempts already recorded.
That is the right dependency and worth knowing about.

**Nothing here argues for new telemetry.** It argues for not dropping any of the
above, since the confound controls are exactly the fields a payload trim would
look able to spare.
