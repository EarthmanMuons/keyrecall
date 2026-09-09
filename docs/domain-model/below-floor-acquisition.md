# Below-floor acquisition

- **Status:** Representation, observation, repeated-transition aggregation,
  synthetic performance, the entry rule, durable progress, and an append-only
  acquisition log implemented, including what discharges an earned probe.
  Nothing presents an acquisition attempt, and nothing makes the scheduler serve
  an owed probe.
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

`earnsParentProbe` requires a clean completion and
`AcquisitionContinuity.unbroken`. Changing the shared break threshold affects
probe eligibility as well as ordinary continuity. An empty stall list alone does
not establish continuity.

### Continuity needs an assessable baseline

Gaps are compared against the upper quartile of the same short performance they
came from. A one-octave ascending traversal has seven intervals, and an attempt
that stops early has fewer, so one or two long waits move the quartile that is
supposed to say what normal looks like for this attempt. A hesitation can then
fail to read as a stall precisely because it was long enough to redefine the
baseline.
`packages/keyrecall_measurement/test/acquisition_observation_test.dart` keeps
that property as a demonstrated case rather than a surprise.

With fewer than five intervals, the interpolated upper quartile includes the
largest gap. For a four-note ascending arpeggio, the maximum ratio cannot exceed
two, so the standard break threshold of three is unreachable even after a
minute-long pause. A short traversal with no detected stall therefore has
`AcquisitionContinuity.unestablished` and cannot earn a probe. Detected stalls
still count as interruptions; the gap series remains available for diagnosis.

Automatic acquisition is limited to scale entries, whose complete ascending
traversals supply seven intervals. Arpeggios remain on the ordinary path until
their shorter traversals have a usable continuity baseline. Multiple long waits
can still distort a scale's baseline. Device traces should settle whether the
reference belongs to the attempt, the learner, or the exercise.

## Contractual outcome and observation profile

Two outputs, kept apart. The contractual outcome is `AcquisitionCompletion`: not
completed, completed with corrections, completed cleanly. The observation
profile is everything else, and it is what says a traversal is nowhere near
ready for a 60 BPM probe even though every note eventually arrived.

`earnsParentProbe` is criterion success, not completion: a clean first pass the
learner did not stop inside. Completion through correction is practice and is
recorded as practice.

One criterion success currently earns a probe. The scheduler serves it ahead of
ordinary ranking when the parent remains in scope and admissible.

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
| Repeated trouble at the same transition?          | Yes. `TransitionCensus` aggregates gaps in memory; the acquisition journal preserves the gap series, but does not yet rebuild the census.          |
| Incomplete versus deliberately ended?             | Yes, outside measurement. Termination is its own concern; see [`attempt-termination.md`](attempt-termination.md).                                  |
| Continuity independent of the beat grid?          | Yes. Dispersion and the interval ratios are read from the learner's own onsets, never from metric offsets.                                         |

The gap that mattered was localization. Before `momentGapsOf` the measurement
carried one worst gap and where it ended, which can say a performance was
interrupted but cannot say the same transition is in the way every time.

## When acquisition begins

Entry requires an exact scale exercise declared by the family's
`AcquisitionFloor`, an informative ordinary attempt at that same exercise, and
no frontier in its execution context. Direction, tempo, span, and guidance all
belong to the exposure identity. The broader bootstrap admission shape does not
define the acquisition floor.

`attemptedAcquisitionParents` in the practice package reconstructs exposures
from ordinary attempt records whose performance started and whose execution
evidence weight is positive. The caller supplies that set to the scheduler
alongside acquisition progress. An interrupted input stream or an attempt at a
harder or less-supported task cannot stand in for a floor exposure. Acquisition
records never establish ordinary exposure.

The current entry policy requires one informative floor attempt. It does not
claim that attempts were repeated; a repetition threshold would need counts from
the same exact-task history. The execution frontier still reads the existing
material, hand, and motion context.

Both a selected stuck floor and an otherwise blocked slot use this rule. The
blocked path preserves the session cap, candidate scope, and admission refusals
other than the challenge band. A missing or out-of-scope family floor cannot
open acquisition.

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

A record holds what happened: the completion class, how the attempt ended, the
extra notes split into repairs, repeats and intrusions, where an unfinished
traversal ran out, and the located gap series with each gap's measured ratio.
Termination sits beside the observation rather than inside it, because an
attempt the learner stopped at six notes and one an input disconnection cut off
at six notes are the same performance and different evidence about the learner.
A later rule about what earns a probe can therefore be asked of an old attempt,
because the attempt did not have to anticipate it.

It also holds `earned_probe`, the verdict as the rule in force read it, for the
same reason a scheduler decision records the admission band it competed in.
Replay uses the stored verdict, so a threshold that moves changes what the next
attempt earns and never what a past one did.

It holds no outcome, no measurement, and no scores. There is nothing in a record
that could be folded into learner state.

Where the performance first departed is not recorded. The completion class and
the three counts say that it did and at what cost; the exact location of the
first wrong note is the one observation-level fact this log currently drops.

## Earning a probe, and discharging it

A criterion success is a fact about the past and stays true. The scheduler's
condition is not that fact but the obligation it opened, which service
discharges:

```text
probe owed = a criterion success happened
             and no probe has been asked since
```

Event order decides the obligation. A presentation records the total criterion
successes it covers in `criterionSuccessesServed`. Three successes before that
presentation are discharged together; a later success opens the obligation even
when both events have the same timestamp. Timestamps remain descriptive.

The append-only log supplies this order during replay. Progress snapshots carry
the service watermark; older snapshots without it must be rebuilt from the log,
because timestamps alone cannot recover equal-time event order.

Reading `earnsParentProbe` as the scheduler's condition would latch. A first
criterion success would suppress acquisition forever, including after the probe
it earned was asked and established nothing, which is exactly the learner
acquisition exists for.

So the cycle is open rather than one-way:

```text
ordinary floor -> stuck -> acquisition -> criterion success
  -> ordinary parent asked -> still stuck -> acquisition again
```

Service is presentation, not success. What acquisition earned is that the
ordinary question be asked; what the answer means is the ordinary path's to
decide, through the attempt journal like any other attempt. A probe that fails
leaves the parent stuck rather than owed again, and the next criterion success
is what reopens the obligation.

Service is written on presentation rather than on scheduler intent. A parent can
reach the learner because the service phase served an owed probe or because
ordinary ranking happened to pick it, and either way the question has been
asked. Discharging only the first would leave the obligation open after the
learner had already answered it, and the next slot would ask it again.

Nothing is written when no probe is owed. A parent whose acquisition history has
earned nothing, or whose obligation a previous presentation already discharged,
is ordinary work like any other, and a record of service that discharged nothing
would say something did not happen.

### Service is not an acquisition-attempt fact

It is an ordinary presentation caused by acquisition history, so it is a second
kind of entry in the acquisition log rather than a counter derived from
attempts. It lives in that log because it is a transition of the acquisition
state machine, and nothing else could say the obligation was discharged.

The record's identity is the ordinary attempt that asked the question, because
service is that presentation rather than an event beside it. That makes it a
reference into the attempt journal and not an ordering invariant, and it means
one ordinary attempt discharges at most one obligation, which the log enforces
by being idempotent on that id.

## Serving an owed probe

Service, not ranking. The scheduler looks for owed probes among the candidates
in scope, admits them through a bypass of their own, and picks one ahead of
ordinary selection.

The bypass exists because the band is exactly what an owed probe must not be
held to. A parent whose context is stuck predicts badly, which is why
acquisition was offered for it, so admitting the probe on prediction would
refuse the question the learner earned.

It is read from what admission allowed rather than from what the later filters
left. Pacing, dose, introductions and novelty decide which useful work is best,
and an owed probe is past that question. Only eligibility and validity may stand
in the way, and a probe they refuse stays owed rather than being consumed.

### Owed, dormant, and lapsed

| State                                   | What happens                                      |
| --------------------------------------- | ------------------------------------------------- |
| Owed, unlapsed, presentable             | Served ahead of ordinary ranking.                 |
| Owed, unlapsed, out of scope or refused | Dormant. Nothing is consumed and nothing written. |
| Owed, and answered by ordinary evidence | Ignored for selection. Still nothing written.     |

Dormancy needs no code. A parent that is out of scope is not among the
candidates, so nothing finds it and its obligation stays open. A focus change
says what to work on now; it is not a claim about what the learner has earned,
and an append-only log has no way to take that back anyway.

Lapsing does need a rule. An obligation can be answered without being served: if
the parent's own span is demonstrated at or above the parent's own tempo before
the probe is asked, presenting it would offer work the learner has already
exceeded, which ordinary admission would refuse for being too easy. The test is
the parent's own span and tempo, because a frontier below that tempo is not an
answer to this parent's question.

Lapsing is not discharge. Nothing is written, and the history goes on saying a
probe was earned and never served, which is what happened.

`probeOwed` stays reconstructible from acquisition history alone.
`probeWorthServing` combines that history with what ordinary evidence has since
established, so it lives at the scheduler boundary rather than on the progress,
which is the same historical-versus-present split the entry rule uses.

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

These are localization checks, not evidence that acquisition improves learning.
Both transcript generation and ordinary `play` use `executionEffortFor`, so the
same opportunity cost affects the scaffold and its parent. The aggregate parent
reads the hardest opportunity; the transcript applies the cost at its location.

`performAcquisition` observes without teaching by default. With
`practising: true`, it updates the shared hand-and-family ability through
`practiseExecution`, using the weakest quality among attempted moments and
reduced credit for an incomplete traversal. A held-out ordinary probe can read
the resulting change without teaching the player. Tests verify this transfer and
its hand and family boundaries. The learning curve and hardest-opportunity
summary are provisional simulation assumptions, not measured pedagogical
effects.

## Reaching the live path

A verdict answers with a candidate, a block, or a task. An acquisition task is
not a candidate and never becomes one, so it travels beside the chosen one
rather than through it, and neither host can hand it back as ordinary work. The
worker carries it across the port as well.

A host holds no history of its own, so the rebuilt progress and the exact
attempted parents arrive from the caller. A caller that supplies neither reaches
the verdict it reached before any of this existed.

The sitting owns both. Acquisition history is its own file beside the attempt
journal, loaded when the sitting opens and replayed rather than held, so
progress is whatever the durable log produces and cannot drift from it.

An append that threw may still have landed, so nothing concludes from an
exception that nothing was written. The store is asked and the log replaced by
what it holds, and the record for one attempt is built once and kept, so a retry
offers the same event under the same id rather than a fresh one at a sequence
the file already has.

The family's declared floor and the safe entry ordinary admission reaches for
are two questions of one value. Admission asks its question only in a scoped
sitting, which can run out of work; acquisition asks which realizations are the
family's floor at all, which is as true of general practice. Supplying it only
for a narrow scope left general practice unable to reach supported work.

Deciding is not presenting. The next exercise is prepared while the last one's
review is still on screen and can be discarded before anyone sees it, so an
obligation is discharged when the attempt actually reaches the learner rather
than when it is chosen. That acknowledgement is idempotent per attempt and
applies to a decision resumed from an earlier run.

Service is written where the parent is presented, from the presenting attempt's
own identity. A failed write leaves the obligation owed, which costs a redundant
probe later; failing the attempt instead would cost the learner their practice,
which is worse. The asymmetry with an ordinary attempt append is deliberate: a
lost attempt loses evidence, and a lost service costs one repeated question.

Non-blocking is not invisible. A service write that does not land is recorded in
the diagnostics channel under a key derived from the attempt, saying which
parent it was about and that the obligation was left owed. Nothing retries,
because the next ordinary presentation of that parent tries again on its own.

## Closing an acquisition attempt

Not a transaction, because there is nothing to make consistent. There is no
pending decision to clear, no learner state to advance, and no outcome to
derive; the whole of what an acquisition attempt does is add an event to its own
log.

An attempt the learner stopped partway is recorded as readily as one that
finished. Where it ran out, what it cost to get that far, and how long the waits
were are exactly the observations acquisition exists to keep, and discarding
them for being incomplete would throw away the reading of the learner the task
was offered for.

Recording one advances the decision epoch, because acquisition progress is a
scheduler input and a verdict computed before it is no longer about the current
inputs.

## The screen

The same practice screen with one demand removed, not a mode of its own. The
material, the hand, the direction and the span are stated as they always are,
the cues are the parent's, and Ready is still how the learner starts.

No tempo appears anywhere, on the statement or on the bar. A stated tempo reads
as a target, and this task removed the obligation rather than lowering it.

Ready goes straight to playing. No count-in state is entered, not even an empty
one: a pulse of zero beats would be a fiction, and anything later that assumed a
count-in had happened would be reasoning about a pulse this task removed.

The line under the task says only that pace is the learner's. Not slowly, not
easier, not take your time: each of those is an interpretation of why the
ordinary attempt did not go well, and nothing has made one.

Nothing ends the attempt but the traversal being covered or the learner saying
so. The watchdog does not run, so neither the duration limit nor the inactivity
window applies and the attempt is never asked whether it is over. While it runs
the screen says so, because a wait of any length is the reading and a screen
that looked finished would be wrong exactly when it mattered.

### The probe explains itself

An acquisition attempt leaves no ordinary record, so no review screen runs after
it and there is nothing to carry a line forward on. The parent probe states the
restoration on its own screen instead: its task statement shows the tempo, as
ordinary work always does, and a line under it says the tempo is back.

Read off the probe rather than handed forward. The fact belongs to the exercise
being presented, so it is still right when the probe arrives long after the work
that earned it, across a restart, a deferred service, or a spell out of scope. A
note carried out of the acquisition screen would be a guess about what the
scheduler chooses next, and would need transient state to carry it.

The wording is the review's, from one function, so the two cannot drift.

There is no pause once observation starts. Discarding a partial transcript would
throw away the localized evidence the task exists to keep, and resuming one
would put interface time into the gap series, where it would read as a
hesitation at whichever transition the learner happened to stop on. Stop closes
the attempt and records it; leaving before Ready records nothing, because
nothing was observed.

## Reaching the offer at all

The rule is about the family's declared floor, and ordinary ranking prefers a
more independent rung of the same material as soon as one is admissible. Half of
what that costs is answered, and half is not.

The offer is asked of every declared floor in scope rather than of the slot's
winner. Requiring the floor to win the slot as well made a question about the
floor answerable only when nothing else was worth doing, which for a learner
with a catalog in front of them is never. Where several floors are stuck at
once, the ordinary ranking among that subset decides, so acquisition does not
wander to a different material than the sitting would have worked on.

What remains is that the exposure the rule reads may never happen. Ranking
prefers the previewed rung from a material's first slot onward, so the exact
declared floor can go unpresented for its whole life, and a question about
whether it was attempted then has one permanent answer.

Guaranteeing one exposure of the declared floor before ordinary progression
leaves it behind is the obvious fix and is not free: it makes the first
presentation of every material its declared floor, for every learner, which
contradicts placement behaviour that deliberately does not hold back somebody
who arrived able to play. That is a pedagogical choice about what a first
meeting with a material should be, and it has not been made.

The rejected alternatives stay rejected. Counting a harder rung as floor
exposure would blur the exact-exercise evidence the exposure reconstruction
exists to keep, and redefining the floor once introduction is past would make a
domain declaration depend on scheduler history and could make the scaffold
harder precisely because the learner is struggling.

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
- **Failure-specific selection.** The scheduler can offer acquisition, but its
  unmetered task is a default rather than a diagnosis of a particular obstacle.
- **Census replay.** The acquisition journal preserves gaps; no adapter yet
  reconstructs `TransitionCensus` from those records.
- **Located repairs.** The census aggregates stalls only.
- **Hands together.** `performAcquisition` refuses a two-hand parent. Two onset
  streams and the distance between them are a coordination model, and
  acquisition has no business having a second one.

The eventual validation target is improved performance on the unchanged parent
exercise, not a higher completion rate on the scaffold. A scaffold that only
manufactures easy success fails that test.
