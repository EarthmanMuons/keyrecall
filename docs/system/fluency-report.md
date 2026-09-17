# The fluency report

- **Status:** proposed. Only the fluency history projection is built.

A menu destination, beside Goal, that answers three questions a learner asks
about their practice, and keeps them apart:

```text
What have I demonstrated?          evidence facts
What probably needs attention now? current inferences
How am I developing?               historical projection
```

It is not a score. No composite number appears anywhere in the report, because
the primitives below already mean something and a synthetic number would look
more precise than the model is.

## Three layers

**Evidence facts** are read from the attempt journal and stated with crisp
values: demonstrated independence, demonstrated tempo, goal coverage, and
practice days. They do not move when a coefficient changes.

**Current inferences** come from learner state and are stated with softened
language or ranges: due for review, durability, competency ranges, and trouble
spots.

**Historical projection** is a series derived from evidence facts. It never
charts an inference.

The visual convention follows the layers and holds across the app: facts have
crisp values, estimates have ranges and words. A learner should be able to tell
how seriously to take something without understanding the model.

## Layout

One scrolling report, most trustworthy first:

```text
summary header    18 of 24 goal scales played from memory
                  3 due for review · 6 practice days this month
key map           facts, with one inference marker
skills            inferences
over time         projection
detail sheet      on tap, for one material
```

## Truth conditions

Each display is defined here rather than in a widget, so changing one is a
change to this contract.

### Demonstrated independence

The most independent guidance rung at which factual retrieval of a material has
ever succeeded: from memory (`unguided`) or notes previewed. Continuous cues
never observe retrieval, so a material completed only under them is cued, and
one never completed is not yet demonstrated.

It is derived from the journal and never from
`MaterialMemoryState.establishedIndependence`, which records the latest rung and
is cleared by a failure. That field serves the guidance ladder. A single failed
retrieval must not erase a demonstration from the map.

The date of the most recent success at the demonstrated rung is kept for the
detail sheet.

### Demonstrated tempo

The fastest pace of an attempt that qualifies under `TempoQualification`: the
requested tempo times the measured tempo ratio, capped at the requested tempo,
so neither a request the learner fell short of nor an unscheduled overshoot
counts. Kept per material, hands, motion, octave span, **and guidance rung**.

Qualification is the report's own versioned rule, read from observed fields
only. Version 1 uses the same motor-score bar as
`LearnerModel.executionWasManaged`, but it does not follow that threshold: the
learner model is uncalibrated, and tuning it must not rewrite what a learner's
history says they demonstrated. Changing the report's rule is a deliberate
change to its identity.

`MaterialExecutionState.demonstratedTempoByOctaves` cannot serve. It records the
request rather than the pace, and it is not keyed by guidance, so a cued attempt
and an unguided one at the same tempo share a slot. A tempo played while reading
cues is a different demonstration.

An attempt without authorized timing has no motor score and contributes no
tempo. The report says once, in words, when an instrument's timing is missing,
rather than showing slowness.

### Typical tempo

The median of a week's qualifying tempos for one hand configuration at one
octave, read from **one guidance rung**, never combined from daily summaries and
never pooled across rungs. It exists for the trend chart, where a maximum is too
noisy to read as development.

Which rung, and whether the chart should read qualified attempts at all, is
open. Characterization found the guidance rule matters only in the first weeks,
while the motor bar leaves a beginner's weaker hand empty for weeks; see
[`../research/experiments/fluency-tempo.md`](../research/experiments/fluency-tempo.md).

### Due for review

A material with a factual retrieval whose current retrievability has fallen
below a threshold. Categorical, never a percentage.

### Durability

The current half-life, rounded hard into words: "holds about 3 days", "about 2
weeks", "about 2 months".

### Skill ranges

Each competency is drawn as a range on unnumbered emerging, developing, and
secure zones. The zones are defined by predicted success on a **reference
exercise per competency**, not by shared raw thresholds on competency means:
hands-together coordination, crossings, and one hand's execution need different
reference tasks to mean the same thing. The common meaning is probability of
successful performance.

The reference exercises and thresholds are versioned policy. A range covering
most of the axis reads "still learning about this" and is drawn so that it does
not resemble weakness.

### Trouble spots

A material-execution residual confidently below the shared prediction and
supported by several attempts. At most two are shown. The wording states the
comparison and not a cause: "F major, left hand: harder than your other scales
with similar demands." When nothing qualifies, nothing is shown.

### Goal coverage and practice days

Coverage is `ScopeCoverage` for the active goal. A practice day is a local
calendar day with at least one committed attempt.

## Key map

A circle of fifths with one ring per scale form, major outermost. The wheel is a
**material selector**: each cell is one material, and every realization
dimension (hands, span, tempo, guidance) belongs in the detail sheet.

Fill encodes a demonstrated fact, and a separate secondary mark encodes due for
review. Hatching is avoided at phone cell sizes; an outer-edge notch or a thin
contrasting border is the candidate. A lens switches what the fill means without
moving any cell:

```text
Recall demonstrated   from memory, notes previewed, cued, not yet demonstrated
Tempo                 demonstrated tempo, unguided, one octave
Hands                 one hand, each hand, hands together
```

Tonic names are prominent enough that the wheel works as a compact catalog for a
learner who does not know the circle of fifths, and a small help affordance
explains the order. Tapping a cell opens the detail sheet focused on that form.

Arpeggios use the same wheel with two rings for root-position major and minor.
Inversions and further families add detail-sheet dimensions, not rings.

## Over time

Weeks, not sittings. A sitting is where someone happened to stop, and a week is
a unit a person recognizes as progress.

**Recall milestones** stacks materials by demonstrated independence per week.
Because demonstration is best-ever, the series only rises, and the title says
milestones so nobody expects forgetting to appear in it.

**Typical tempo** draws one line per hand configuration. Hands together starts
when coordination does. Weeks without practice stay on the axis as gaps.

## Detail sheet

For one tonic, each form with its demonstrated independence, the date last
demonstrated, its review status, its durability in words, and a table of
demonstrated tempo by hand configuration and octave span. Attempt history for a
material, if it is ever exposed, belongs here rather than in the report.

## Fluency history

`FluencyHistory` in `keyrecall_practice` is the projection `history.md`
reserves. It stores **observations rather than report statistics**: a series is
computed when it is read, so presentation policy is never frozen into storage.

Aggregation keeps whatever a later statistic needs. A weekly median cannot be
computed from daily medians, since a day of thirty attempts and a day of two
would weigh the same, so tempo is kept as one observation per attempt rather
than as a daily summary. Per day it holds:

```text
attempts          committed attempts, measured or not
demonstrations    per material, the strongest level that day and when it
                  was last reached
tempo             per completed attempt with a pace and a motor score:
                  material, hands, motion, octaves, guidance rung,
                  requested tempo, tempo ratio, motor score, time
```

Only structural absences are filtered. A tempo observation is kept for an
attempt that was not managed, because managed is a learner-model threshold, and
the projection holds no learner-model interpretation at all. That is why it
needs no model version: a model change cannot invalidate it. Best-ever levels,
qualified tempo, and weekly statistics are all read-time policy, in
`fluency_reading.dart`.

Due for review, durability, skill ranges, and trouble spots are current
inferences and are never projected.

Days are assigned by a `DayPartition`, the device's local date in production.
The journal records instants and not the civil day they fell on, so the day is a
build parameter rather than a fact. The partition's identity is persisted with
the projection, and one built under another partition is rebuilt rather than
extended with days assigned a different way. If the local day at performance
time ever matters as evidence, it has to be captured in the attempt record when
it is committed; it cannot be recovered from UTC later.

The projection records its schema version, its profile, its day partition, and
how many journal records it covers. It is rebuilt whole from the journal when
any of those disagree, and reading refuses an attempt total that does not match
the coverage it claims. Three properties are tested:

- **Equivalence.** Rebuilding from the journal equals applying its records one
  at a time, including across a write and read at every prefix.
- **Prefix stability.** Applying a record never changes an earlier day, and only
  extends the latest one.
- **Irrelevance.** Projecting never writes to the journal. Nothing in learner
  state or scheduling reads the projection, so deleting it changes nothing else.

## Build order

1. The fluency history projection.
2. The key map and detail sheet.
3. The factual time charts.
4. Skill ranges and trouble spots, which depend most on calibration.

The first three are useful on their own while competency calibration moves.

## Open questions

- Which hand configuration the tempo lens shows when several have a value.
- Whether typical tempo reads demonstrated pace, which leaves weak hands empty,
  or playing pace, which always has a value, and how a week resting on one or
  two observations is shown.
- The retrievability threshold for due for review, and whether it should match
  what the scheduler treats as due.
- The reference exercise for each competency's skill zones.
