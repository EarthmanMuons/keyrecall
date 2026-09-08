# Below-floor acquisition

- **Status:** Representation and observation implemented. No scheduler selects
  an acquisition task yet, and no simulated player can attempt one.
- **Written:** September 8, 2026

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
| Repeated trouble at the same transition?          | Derivable, not yet derived. Nothing persists the gap series across attempts.                                                                       |
| Incomplete versus deliberately ended?             | Yes, outside measurement. Termination is its own concern; see [`attempt-termination.md`](attempt-termination.md).                                  |
| Continuity independent of the beat grid?          | Yes. Dispersion and the interval ratios are read from the learner's own onsets, never from metric offsets.                                         |

The gap that mattered was localization. Before `momentGapsOf` the measurement
carried one worst gap and where it ended, which can say a performance was
interrupted but cannot say the same transition is in the way every time.

## What the simulator cannot yet express

`SyntheticPlayer.play` samples an `Outcome` from latent ability: aggregate
continuity, stability, pitch integrity, and a completion draw. It produces no
transcript and nothing positional, so no synthetic attempt can have a stall at
the fourth degree, and no synthetic run can distinguish uneven timing from a
localized breakdown from difficulty finding successive notes.

Any acquisition policy that branched on those distinctions today would be
reading a latent cause the simulator leaked, not an observation. Extending the
player to emit positional structure comes before a second acquisition task.

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
- **Persistence.** Nothing journals an acquisition attempt yet.

The eventual validation target is improved performance on the unchanged parent
exercise, not a higher completion rate on the scaffold. A scaffold that only
manufactures easy success fails that test.
