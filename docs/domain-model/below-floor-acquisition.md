# Below-floor acquisition

- **Status:** Representation, observation, repeated-transition aggregation,
  synthetic performance, the entry rule, durable progress, and an append-only
  acquisition log implemented. Nothing presents an acquisition attempt, and
  nothing schedules the parent probe.
- **Written:** September 8, 2026
- **Revised:** September 9, 2026

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

## When acquisition begins

Four facts the model already keeps, and no counter of its own:

1. the candidate is a bootstrap shape, so it is already the floor;
2. its execution context needs an execution bootstrap, so no frontier exists in
   the scope progression reads;
3. evidence has arrived in that context, so this is not a first exposure nobody
   has tried;
4. therefore the gentlest ordinary question has been asked and demonstrated
   nothing.

The gap between the second and the third is the whole of "repeatedly, with
nothing to show for it". Counting failures separately would be a second
difficulty model beside the one that already answers this, and the scope is the
one the forgiving floor already settled: a frontier in one hand leaves the other
hand acquiring.

It is binary. One informative floor attempt that demonstrated nothing is already
an attempt at the gentlest work the family has, and the forgiving floor has been
offering that work repeatedly by the time this holds. If simulation shows it
fires too eagerly, the missing fact is an exposure count beside `lastEvidenceAt`
in `MaterialExecutionState`, which is evidence history about the context. A
scheduler-local counter would be transient policy state, and residual variance
would buy the same signal for the price of another calibration constant.

Both entry points converge. A slot whose winner is a stuck floor candidate and a
slot whose ordinary path produced nothing at all are the same situation stated
twice, so they reach one rule and one constructor rather than the blocked case
acquiring an escape hatch with evidence rules of its own.

The task is constructed where the stuck condition is found. Candidate generation
may not read learner state, so an acquisition task cannot be generated there;
this is the same exception the next tempo rung already takes.

Offering is opt-in. A decision that passes no acquisition progress behaves
exactly as it did before any of this existed, which is what keeps the recorded
trajectory corpus unchanged.

## What is durable

`AcquisitionProgress` is keyed by the parent exercise, because what a criterion
success earns is a probe of that exact question, and two parents in one context
can be stuck for different reasons.

It is not `LearnerState`. Nothing in it is evidence in the learner model's
vocabulary, and keeping it out of that container is what stops an acquisition
attempt reaching a residual, a frontier, or a memory clock by sharing one.

It is not `SessionState` either, and that is a semantic requirement rather than
a convenience. Every field of a sitting is deliberately a condition of the
sitting it arose in. A criterion success followed by a break is still a
criterion success, so putting acquisition progress there would make the result
depend on where the learner happened to stop.

It records counts and reads them binary. One criterion success earns the probe
today; the attempt, completion, and criterion counts are all kept so that a rule
wanting two of them is a change of policy rather than a change of what was
recorded. That is the same discipline the entry rule follows.

## Two logs, because they answer to different readers

Replaying the attempt journal produces learner state. An acquisition attempt is
deliberately not evidence for that state, so putting one in that log would make
the source of truth for learner state contain records it must ignore.
`AcquisitionJournal` is therefore its own append-only log, and replaying it
produces `AcquisitionProgress` and nothing else. Each reader refuses the other's
records rather than skipping them.

The two share no ordering invariant, because neither derives from the other.
Each carries its own timestamps, its own contiguous sequence, and its own
idempotency by attempt id.

Progress is whatever replaying the log produces. That is what makes it survive a
restart and a sitting boundary, and it is why a checkpoint would have been the
wrong home on its own: checkpoints are disposable acceleration, rebuildable from
history, so acquisition history has to be in history.

### The record keeps facts, and the verdict it was written with

A record holds what happened: the completion class, the extra notes split into
repairs, repeats and intrusions, where an unfinished traversal ran out, and the
located gap series with each gap's measured ratio. A later rule about what earns
a probe can therefore be asked of an old attempt, because the attempt did not
have to anticipate it.

It also holds `earned_probe`, the verdict as the rule in force read it, for the
same reason a scheduler decision records the admission band it competed in.
Replay uses the stored verdict, so a threshold that moves changes what the next
attempt earns and never what a past one did.

It holds no outcome, no measurement, and no scores. There is nothing in a record
that could be folded into learner state.

Where the performance first departed is not recorded. The completion class and
the three counts say that it did and at what cost; the exact location of the
first wrong note is the one observation-level fact this log currently drops.

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
- **Presentation.** Nothing shows an acquisition task or collects a transcript
  for one. The path from an observation to a record exists and is tested; what
  is missing is the screen and the loop that calls it.
- **The probe itself.** Progress can say a parent has earned one. Nothing
  schedules it, and one question is open before anything does: whether an earned
  probe is owed service or merely re-entered into ordinary ranking. If ranking
  can defer it indefinitely then `earnsParentProbe` promises more than it
  delivers, so the probe should be owed the way other services are owed. What
  must not change is the order: acquisition decides which ordinary question is
  asked next, the ordinary attempt answers it, and only that answer moves a
  frontier.
- **A census that outlives its process.** Nothing journals the gap series.
- **Located repairs.** The census aggregates stalls only.
- **Hands together.** `performAcquisition` refuses a two-hand parent. Two onset
  streams and the distance between them are a coordination model, and
  acquisition has no business having a second one.

The eventual validation target is improved performance on the unchanged parent
exercise, not a higher completion rate on the scaffold. A scaffold that only
manufactures easy success fails that test.
