# Below-floor acquisition

- **Status:** Representation, observation, repeated-transition aggregation, and
  synthetic performance implemented. No scheduler selects an acquisition task
  yet.
- **Written:** September 8, 2026
- **Revised:** September 8, 2026

The guidance ladder changes how much support accompanies an exercise that is
still an ordinary realization of its material. Below-floor acquisition can relax
the task itself, so what it observes is evidence about the relaxed task and
nothing else.

The sentence the design rests on:

> Supported acquisition of a specific part of the normal task, with success
> earning a normal-task probe.

Both halves matter. Without the first, a scaffold has no stated relationship to
the work it exists to prepare. Without the second, completing an easier exercise
starts to read as evidence about the harder one.

## The minimum-success contract

| Contract                      | Rule                                                                                                                                                      |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Relationship to ordinary work | Every task names its parent exercise and which of its notes or transitions it rehearses.                                                                  |
| Observable success            | The learner produces the required pitches in order under explicitly recorded assistance and timing conditions.                                            |
| Corrections                   | Completing through retries counts as practice. A clean pass is recorded separately.                                                                       |
| Evidence earned               | Local, supported sequence evidence, limited to what was actually attempted.                                                                               |
| Evidence withheld             | No retrieval credit under continuous cues, no tempo frontier from unmetered work, no full-traversal credit from a fragment. MIDI cannot verify fingering. |
| Exit                          | Criterion success makes the unchanged parent eligible for a probe. Only that probe establishes ordinary readiness or frontier evidence.                   |

## Four axes, held apart

Folding these into one scaffold level would hide changes to the task behind what
looks like a support setting, and there is no defensible universal ordering to
fold them into.

| Axis         | Ordinary floor        | Acquisition values                                                 |
| ------------ | --------------------- | ------------------------------------------------------------------ |
| Portion      | full ascending octave | full traversal, transition-centered fragment                       |
| Timing       | 60 BPM                | metered, continuity-only, unmetered                                |
| Advancement  | learner-driven        | learner-driven, assisted                                           |
| Presentation | continuously cued     | whatever the guidance rung and presentation conditions already say |

Presentation stays where it is. Continuous pitch cues are a presentation
condition on any task, ordinary or not, and `AcquisitionTask` carries its
parent's `GuidanceContext` unchanged.

`unmetered + learner-driven + continuously cued` and
`unmetered + assisted + continuously cued` are different tasks producing
different evidence, and both would read as "maximum guidance" on a single
ladder.

## What V1 offers

One task: `AcquisitionTask.unmeteredTraversal`. Same hand, same octave, same
ascending traversal, same continuous cues, no tempo obligation.

The scale floor
(`packages/keyrecall_scheduler/lib/src/candidate_generation.dart`) is already
single-hand, one-octave, ascending-only, continuously cued, at 60 BPM, so one
direction is spent as a simplification before acquisition begins. Almost nothing
about the material changes here. The question narrows to one thing: can the
learner produce this sequence when time is not the limiting resource?

An unmetered task states no tempo, so nothing may sound one.
`AcquisitionTask.suitsPresentation` refuses a count-in or a metronome, the way
`PresentationConditions.suitsGuidance` refuses a cue the rung does not carry.

A task that asks for the whole parent, at its tempo, sequenced by the learner is
the parent, and constructing one is rejected. Admitting it would fence off
evidence the attempt actually earned.

## The boundary is the type

`AcquisitionTask` is not an `Exercise` and is not convertible to one. Candidate
generation, ranking, the frontier, and the learner model all take exercises, so
none of them can reach an acquisition task by a route that already exists. That
is stronger than a flag on an exercise, which every future composition would
have to remember to check.

`AcquisitionObservation` is the counterpart on the observation side. It does not
carry the `PerformanceMeasurement` it was built from, so there is no value to
hand to `outcomeFor`, and it exposes no `Outcome`. What it keeps is local:

- whether the sequence came out, and at what cost, as three values rather than a
  score;
- extra notes, split into repairs, repeats, and intrusions;
- where the performance first departed, and where an unfinished one ran out;
- the wait before every moment that arrived, located by the transition it spans.

Gaps are measured against the upper quartile of the performance's own playing,
so the reading is unchanged if the learner plays the whole thing twice as fast.
Nothing about a requested tempo enters, which is what makes it honest to read
continuity from an attempt that was never asked to keep time.

A stall is a gap the measurement policy already calls a break
(`MeasurementPolicy.brokenIntervalRatio`). Reusing that threshold keeps a stall
here and an interruption in ordinary continuity the same event read at two
altitudes, rather than a new constant chosen to make acquisition look
reasonable.

Treat that as a contract rather than a convenience. `earnsParentProbe` depends
on `stalls.isEmpty`, so changing what ordinary continuity calls broken also
changes who is offered a probe of their parent exercise. That coupling is
intended, because the two are one phenomenon in two contexts, and it means the
threshold cannot be retuned for continuity alone.

### The baseline is endogenous, and that is a calibration question

Gaps are compared against the upper quartile of the same short performance they
came from. A one-octave ascending traversal has seven intervals, and an attempt
that stops early has fewer, so one or two long waits move the quartile that is
supposed to say what normal looks like for this attempt. A hesitation can then
fail to read as a stall precisely because it was long enough to redefine the
baseline.
`packages/keyrecall_measurement/test/acquisition_observation_test.dart` keeps
that property as a demonstrated case rather than a surprise.

Left as it is on purpose. An acquisition-specific constant chosen to make the
short case come out would be worse than a threshold shared with ordinary
continuity, and too few intervals already produce no quartile and no gaps at
all. Device traces are what should settle whether the baseline should come from
the attempt, from the learner, or from the exercise.

## Contractual outcome and observation profile

Two outputs, kept apart. The contractual outcome is `AcquisitionCompletion`: not
completed, completed with corrections, completed cleanly. The observation
profile is everything else, and it is what says a traversal is nowhere near
ready for a 60 BPM probe even though every note eventually arrived.

`earnsParentProbe` is criterion success, not completion: a clean first pass the
learner did not stop inside. Completion through correction is practice and is
recorded as practice.

Eligibility only. How many criterion successes it takes, and when to conduct the
probe, are the scheduler's to decide when acquisition selection exists.

## What the observation stack can already distinguish

Inventory taken before any policy was written, because a scheduler that appears
to diagnose intelligently while reading a signal real MIDI cannot supply is
worse than no scheduler at all.

| Question                                          | Answer                                                                                                                                             |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Did every expected pitch eventually arrive?       | Yes. `AlignmentReading.isComplete`, which is stronger than reaching the last note.                                                                 |
| Were they produced in order?                      | Yes, by construction. Alignment is an ordered edit script.                                                                                         |
| Are corrections distinguishable from extra notes? | Partly. `immediateRepairs` is the shape a repair leaves; repeats and intrusions are structural classes. What caused any of them is not observable. |
| Can a localized stall be identified?              | Yes, now. `momentGapsOf` gives every gap located by the transition it spans.                                                                       |
| Repeated trouble at the same transition?          | Yes, now, in memory. `TransitionCensus` aggregates the gap series across attempts at one task. Nothing persists it.                                |
| Incomplete versus deliberately ended?             | Yes, outside measurement. Termination is its own concern; see [`attempt-termination.md`](attempt-termination.md).                                  |
| Continuity independent of the beat grid?          | Yes. Dispersion and the interval ratios are read from the learner's own onsets, never from metric offsets.                                         |

The gap that mattered was localization. Before `momentGapsOf` the measurement
carried one worst gap and where it ended, which can say a performance was
interrupted but cannot say the same transition is in the way every time.

## Repeated transitions

One attempt says where the playing broke. Only repetition says a transition is
in the way, and that is what a fragment would eventually have to be chosen from.
`TransitionCensus` accumulates the gap series across attempts at one task,
counting how often each transition was played and how often it stalled.

Both counts are kept because the denominators differ. A transition past the
point a learner keeps stopping is played rarely, so a raw stall count
understates it and a rate against attempts understates it further.

It counts and does not conclude. `stalledAtLeast` takes the threshold from the
caller, because nothing yet knows how many stalls make a transition worth
isolating, and choosing that number before there are device traces to choose it
from would be inventing a curriculum.

Only stalls are aggregated. Wrong notes and repairs are counted per attempt but
not located, so a transition that produces errors without hesitation is
currently invisible to the census. Locating them is cheap and is deliberately
not done until something needs it.

## What the simulator can now express

`SyntheticPlayer.play` samples an `Outcome` from latent ability, so nothing it
produces has a position. `performAcquisition` answers with a
`PerformanceTranscript` instead, read back through the same alignment and
observation path device MIDI takes.

Localized difficulty comes from the exercise, not from a label. A crossing is a
moment the domain already names, so `opportunityPenalty` lands on that moment
and nowhere else, and what survives into an observation is a wait, a wrong note,
or an attempt that ended.

Over forty seeded attempts at a one-octave ascending C major, right hand, whose
only crossing is the transition into the fourth degree:

| Player            | Clean | With corrections | Not completed | Probes earned |
| ----------------- | ----- | ---------------- | ------------- | ------------- |
| `advanced`        | 32    | 8                | 0             | 32            |
| `developing`      | 14    | 20               | 6             | 14            |
| `crossingLimited` | 10    | 20               | 10            | 3             |

The census separates the two kinds of difficulty that the aggregate scores
cannot. `crossingLimited` stalls at the crossing in 17 of 40 attempts and
nowhere else more than 3 times. `developing` produces corrections in half its
attempts and stalls nowhere at all: their playing is uneven, and the unevenness
has no address.

That is the distinction the whole slice exists to make, and it is now observable
end to end without a policy having been written.

## Deliberately not built

- **Fragments.** A fixed three-note or five-note entry pattern can end before
  the troublesome crossing, becoming easy while leaving the obstacle untouched.
  A window has to be chosen so the target transition falls inside it, which
  requires knowing which transition is in the way. `TaskPortion` is sealed so
  that value can be added when observations name one.
- **Assisted advancement.** It takes over remembering what comes next, which
  changes execution of a known sequence into chained stimulus and response. Its
  evidence would have to be more local still, and its exit is back to a
  learner-driven unmetered traversal rather than straight to the ordinary floor.
- **Scheduler selection.** Repeated supported opportunities with no frontier
  justify offering a scaffold. They do not identify what is too difficult, so
  the first task is the default rather than a diagnosis.
- **Persistence.** Nothing journals an acquisition attempt yet, so a census
  lives no longer than the process that built it.
- **Located repairs.** The census aggregates stalls only.
- **Hands together.** `performAcquisition` refuses a two-hand parent. Two onset
  streams and the distance between them are a coordination model, and
  acquisition has no business having a second one.

The eventual validation target is improved performance on the unchanged parent
exercise, not a higher completion rate on the scaffold. A scaffold that only
manufactures easy success fails that test.
