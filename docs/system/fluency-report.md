# The fluency report

- **Status:** partly built. The fluency history projection, its storage, its
  queries, the key map with its detail sheet, and both time charts are built.
  The summary header, review marks, and skills panel are proposed.

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

### Playing pace

How fast a hand configuration has actually been playing, week by week. An
observational trend rather than a capability claim, so it is not qualified:
every completed attempt with an authorized measured pace counts, whatever its
motor score, at the pace played rather than capped at the request. The
structural requirements stay, since an attempt that was not completed or
established no pace says nothing about playing speed.

Each week reads **one guidance rung**, the most independent with at least one
observation, and never pools rungs or combines daily summaries. The number of
attempts behind a week is carried with it. A week of one or two attempts is
drawn lighter or labeled with its count, never given an interval: the learner
did only play that often. Learner-facing copy calls it playing pace, never
demonstrated, achieved, or best tempo, and says "playing pace this week" rather
than median. It is uncapped on purpose: an attempt asked for at 80 and played at
99 did not demonstrate 99, but it was played at 99.

Demonstrated tempo and playing pace answer different questions, so they read
different rules. Characterization showed why: a beginner's weaker hand can
collect weeks of measured attempts without one clearing the qualification bar;
see
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
dimension (hands, span, tempo, guidance) belongs in the detail sheet. Every key
keeps its sector whether or not the catalog holds a scale on it, and each sector
is labeled with its major spelling and, where different, its minor one.

Fill encodes a demonstrated fact, and a lens switches what the fill means
without moving any cell:

```text
Recall   from memory, notes previewed, with cues, not yet
Tempo    demonstrated tempo from memory, one octave, for the hands selected
```

The tempo lens has an explicit right hand, left hand, and together selector
rather than one representative value. A learner at 100 with the right hand, 72
with the left, and 60 together has no single honest tempo for that scale, and
switching hands is cheap because no cell moves. Its bands, under 72, 72 to 99,
and 100 and up, are a reading aid for small cells; the exact tempo is one tap
away.

**Proposed:** a secondary mark for due for review. Hatching is avoided at phone
cell sizes; an outer-edge notch or a thin contrasting border is the candidate. A
hands lens is also proposed.

Tonic names are prominent enough that the wheel works as a compact catalog for a
learner who does not know the circle of fifths, and a help sheet explains the
order. It is a pitch-class wheel arranged by fifths rather than a notation
circle: a slice groups the scales starting on one piano key, so D flat major and
C sharp minor share one, and its labels give both spellings.

Tapping a cell opens the detail sheet focused on that form. Assistive technology
finds the wheel one key at a time instead: the innermost ring is too narrow for
cell-sized targets that do not overlap, so each key is a single button, about 50
logical pixels square at phone width and clear of its neighbors, whose label
reads every form and whose sheet lists them. The same targets accept keyboard
focus in circle order, show a focus outline, and open with Enter or Space.

Arpeggios are not yet on the map. They would use the same wheel with two rings
for root-position major and minor; inversions and further families add
detail-sheet dimensions, not rings.

## Over time

Weeks, not sittings. A sitting is where someone happened to stop, and a week is
a unit a person recognizes as progress.

**Recall milestones** is built, above playing pace. It stacks the catalog's
scales by the strongest level each had reached by the end of each of the last
eight weeks, from memory at the base. The counts are cumulative over the whole
history rather than the window, and best-ever, so the bars only grow and the
title says milestones so nobody expects forgetting to appear in it. Tapping a
week gives its count at each level. Each week also has a screen-reader entry
with those counts. It shares the key map's shade ramp, so a level is one color
throughout the report.

**Playing pace** is built, below the key map after a section break rather than
as another lens, since it answers a different question. It draws the last eight
weeks, ending with the current one, as one line per hand configuration across
all materials, restricted to one octave in parallel motion. The description and
empty state name that restriction. The window is presentation policy; the weekly
series underneath accepts any range.

A week without a value breaks its line rather than being drawn across, so hands
together simply starts when coordination does. A week resting on one or two
attempts is a hollow point. Tapping a point gives its pace, how many attempts it
rests on, and the rung it was read from; the rung can change between weeks and
is not drawn, because the simulations showed it mostly stops mattering. There is
one screen-reader entry per week with every hand's pace, count, and support,
including explicit gaps. There is no smoothing, trend line, or change figure:
sparse weekly medians cannot carry them.

## Detail sheet

For one key, each form with its demonstrated independence and the date it was
last demonstrated, and for the focused form a table of demonstrated tempo by
hand configuration and octave span. Each cell reads the most independent rung
with a tempo and names the support when it was not from memory, so a table never
reads "96" for a tempo shown with cues.

**Proposed:** review status and durability in words. Attempt history for a
material, if it is ever exposed, belongs here rather than in the report.

The key map and the sheet read one `FluencySummary`, so a cell and the sheet it
opens cannot disagree.

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
build parameter rather than a fact. A saved projection is reused only when its
covered journal records still map to the same calendar days under the current
partition. This is checked alongside the prefix digest, including attempts that
produced no demonstration or tempo observation. The partition name is
descriptive; it does not establish equivalence of time zone rules. If the local
day at performance time ever matters as evidence, it has to be captured in the
attempt record when it is committed; it cannot be recovered from UTC later.

The projection records its schema version, its profile, its day partition, how
many journal records it covers, and a digest chained over those records. A count
alone cannot tell this journal from a history an erase replaced with as many
attempts, and the digest can.

It is stored in one overwritable slot per profile. `openFluencyHistory` reads
the saved projection, extends it when it still covers a prefix of the journal,
and otherwise rebuilds it: when it cannot be read, was built under another
partition, covers more than the journal holds, or covers different records. It
saves only when the result covers something the saved one did not. Erasing a
profile takes the slot along, and a retired incarnation cannot write one.

The report reads through `readFluencyHistory`, which reports a failed save
instead of throwing it: the history it computed is already correct, and a cache
that could not be written costs only the next opening's time. Failing to read
the journal still fails the report. A cache-local filesystem read failure is
treated as a cache miss, so the report can rebuild from the readable journal.

Checking coverage rehashes every covered record and validates its day assignment
on each opening. That is the obvious cost to revisit if journals grow large
enough for it to matter.

Four properties are tested:

- **Equivalence.** Rebuilding from the journal equals applying its records one
  at a time, including across a write and read at every prefix, and equals what
  extending a saved projection produces.
- **Prefix stability.** Applying a record never changes an earlier day, and only
  extends the latest one.
- **Staleness.** A saved projection of any other history is rebuilt rather than
  extended.
- **Irrelevance.** Reopening practice with the projection saved, deleted, or
  corrupt yields the same learner state and the same next decision.

## Build order

1. The fluency history projection.
2. The key map and detail sheet.
3. The factual time charts.
4. Skill ranges and trouble spots, which depend most on calibration.

The first three are useful on their own while competency calibration moves.

## Open questions

- The retrievability threshold for due for review, and whether it should match
  what the scheduler treats as due.
- The reference exercise for each competency's skill zones.
