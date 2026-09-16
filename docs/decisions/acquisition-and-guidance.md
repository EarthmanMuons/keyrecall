# Acquisition and guidance

The support ladder, what happens after a failure, how far below the ordinary
floor the system will go, and how an attempt is allowed to end.

## Exactly three guidance rungs

**Decision.** `unguided`, `notesPreviewedOnly`, `continuouslyCued`, with a
private constructor so a fourth cannot be built.

**Why.** Notes previewed _and_ cues left visible describes the same condition as
continuously cued while comparing and hashing differently. Guidance is part of
exercise identity, cache keys, recovery matching, and persisted records, so two
values that mean one thing would silently fragment all of them.

**Evidence.** Faded support outperforms constant support on retention and
transfer [SatoKlemm2025], and concurrent feedback suppresses learning while
flattering performance [WinsteinSchmidt1990, Salmoni1984]. A ladder is the shape
the evidence supports; the number of rungs is our engineering choice.

**Consequences.** `retrievalDemand` is a heuristic mapping onto `[0,1]`, not a
research-established coefficient, and is flagged as such wherever it appears.

## The ladder governs pitch support only

**Decision.** Every exercise gets a count-in at every rung. The metronome is a
separate opt-in choice, not something unlocked by progress.

**Why.** Tempo support and pitch support change different demands. Bundling them
would mean a learner who wants a click has to accept the notes on screen, or
that fading the notes silently removes the pulse they were relying on.

## Moving down a rung is a response, not a penalty

**Decision.** Recovery is an exclusive admission exception immediately after a
factual retrieval failure, targeting the same material and motor task with
exactly one more step of guidance.

**Why.** The failure has already told us the demand was too high. Offering
anything else in that slot spends it on a question we did not just ask.

**Consequences.** Exclusive means only the recovery target survives the stage,
which is a strong claim for one slot and deliberately expires after it.

## Declining is evidence

**Decision.** "I don't remember" is an outcome: never started, retrieval failed,
memory evidence at the rung's weight, no execution evidence, and a recovery
context opened.

**Why.** Before it existed, the only way for a learner to say this was to play
something wrong, which manufactures execution evidence for a performance that
never happened.

**Consequences.** Two boundaries, both the session's rather than the screen's.
Offered only at a rung that tests retrieval, since there is nothing to fail to
retrieve when the material is on screen; and only before anything has been
played, since once notes have arrived what happened is measurement's question.
`closeDeclined` takes the transcript and refuses a non-empty one, so the caller
shows what arrived rather than being trusted to have called at the right moment.

It is deliberately **not a skip**. A skip writes no learner evidence and is an
operational action about the session rather than a poor outcome. Nothing has
demonstrated a need for one.

## Non-evaluative termination only, under a neutral condition

**Decision.** Silence and elapsed duration may end an attempt under any feedback
condition. Counting errors, noticing lost alignment, and predicting failure may
not.

**Why.** The first two are facts about the observation stream, computable from
timestamps and the requested tempo, and say nothing about whether a note was
right. The third are judgments, and ending the attempt on one delivers that
judgment through the loudest channel there is. Under a neutral feedback
condition that is a leak.

## Prompt rather than seize

**Decision.** Silence and duration surface an offer while input keeps being
accepted. A much larger absolute limit closes an abandoned attempt.

**Why.** A long pause is ambiguous on its face: thinking, an interruption, a
page turn, or simply slower execution than was asked for. Continuing to accept
input while showing "still working?" resolves none of that wrongly.

**Consequences.** That larger closure is a fact about the app rather than about
the performance, and is recorded as such.

## The termination reason sits beside the outcome

**Decision.** Reason is evidence metadata, never part of the outcome. There is
deliberately no `learnerCompleted`.

**Why.** So that `inactivityTimeout -> completed: false -> the learner failed`
is not available as an accidental inference. An attempt the learner stopped at
six moments and one a timeout closed at six moments are different observations.

Completion is measurement's to establish. "Done" means only that the learner
ended it, which is a weaker claim.

## Below-floor acquisition relaxes the task, not the support

**Decision.** An `AcquisitionTask` may relax the portion played, the timing
demand, or who advances the sequence. It observes evidence about the **relaxed
task and nothing else**, and is not an `Exercise`.

**Why.** The guidance ladder changes how much support accompanies an exercise
that is still an ordinary realization of its material. Once the task itself
changes, so does what an attempt at it can claim, and the only reliable way to
enforce that is to make it a different type that no ordinary path can consume.

The contract:

| Contract           | Rule                                                                                                                             |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Relationship       | Every task names its parent exercise and which notes or transitions it rehearses.                                                |
| Observable success | The learner produces the required pitches in order under explicitly recorded assistance and timing conditions.                   |
| Corrections        | Completing through retries counts as practice. A clean pass is recorded separately.                                              |
| Evidence earned    | Local, supported sequence evidence, limited to what was actually attempted.                                                      |
| Evidence withheld  | No retrieval credit under continuous cues, no tempo frontier from unmetered work, no full-traversal credit from a fragment.      |
| Exit               | Criterion success makes the unchanged parent eligible for a probe. Only that probe establishes ordinary readiness or a frontier. |

**Consequences.** MIDI cannot verify fingering, so no acquisition task may claim
anything about it.

### Four axes, held apart

**Decision.** Portion, timing, advancement, and presentation are separate, not
one scaffold level.

**Why.** Folding them into one would hide changes to the _task_ behind what
looks like a support setting, and there is no defensible universal ordering to
fold them into. `unmetered + learner-driven + continuously cued` and
`unmetered + assisted + continuously cued` are different tasks producing
different evidence, and both would read as "maximum guidance" on a single
ladder.

Presentation stays where it is: continuous pitch cues are a presentation
condition on any task, and an `AcquisitionTask` carries its parent's
`GuidanceContext` unchanged.

**Consequences.** An unmetered task states no tempo, so nothing may sound one:
`suitsPresentation` refuses a count-in or a metronome. And a task asking for the
whole parent, at its tempo, sequenced by the learner _is_ the parent, so
constructing one is rejected outright, since admitting it would fence off
evidence the attempt actually earned.

### What is built, and what is not

Built: `AcquisitionTask.unmeteredTraversal`. Same hand, same octave, same
ascending traversal, same continuous cues, no tempo obligation. The scale floor
is already single-hand, one-octave, ascending, continuously cued, so almost
nothing about the material changes and the question narrows to one thing: can
the learner produce this sequence when time is not the limiting resource?

Also built: `TraversalRepetitions`, the same traversal played through more than
once. Continuity is a claim about a stretch of playing that did not stop, and a
pattern too short to supply one asks for more traversals rather than for a lower
bar; a four-moment arpeggio supplies three intervals, and the criterion wants
five, so the arpeggio floor declares two. The repetitions are the parent's
material exactly, never a wider span, so nothing about what is being played
changes.

The boundary between one traversal and the next belongs to neither. The learner
resets their hand there, the task asked them to, and the wait it costs is not a
hesitation: it is neither reported as a gap, nor allowed into the references the
other waits are judged against, nor required to have been timed. Continuity is a
claim about every other transition, the ones inside a traversal.

Every task is self-paced. `TimingDemand.metered` is representable and nothing
presents it, so both `AcquisitionTask` and `AcquisitionScaffold` refuse it at
construction rather than leaving a family free to declare work the app would
show as something else.

Deliberately not built, each for a stated reason:

- **Fragments.** A fixed three- or five-note entry pattern can end _before_ the
  troublesome crossing, becoming easy while leaving the obstacle untouched.
  Choosing the window requires knowing which transition is in the way.
  `TaskPortion` is sealed so the value can be added once observations name one.
- **Assisted advancement.** It takes over remembering what comes next, turning
  execution of a known sequence into chained stimulus and response. Its evidence
  would have to be more local still, and its exit is back to a learner-driven
  unmetered traversal rather than straight to the ordinary floor.
- **Failure-specific selection.** The unmetered task is a default, not a
  diagnosis of a particular obstacle.
- **Hands together.** `performAcquisition` refuses a two-hand parent. Two onset
  streams and the distance between them are a coordination model, and
  acquisition has no business having a second one.
- **Census replay and located repairs.** The acquisition journal preserves gaps,
  but nothing reconstructs a `TransitionCensus` from them, and the census
  aggregates stalls only.

**The validation target is improved performance on the unchanged parent, not a
higher completion rate on the scaffold.** A scaffold that only manufactures easy
success fails that test.

## Two logs, because they answer to different readers

**Decision.** Acquisition attempts go to their own append-only log, not the
attempt journal.

**Why.** The attempt journal is replayed to reconstruct learner state, and
acquisition attempts move no learner state. Putting them in would mean every
replay had to know to skip them, and one that forgot would be reinterpreting
history.

**Consequences.** The acquisition record keeps facts _and_ the verdict it was
written with, since a later criterion change must not silently reinterpret what
an old attempt earned.

## Not demonstrated is not failed

**Decision.** Each acquisition criterion is recorded as **met**, **not met**, or
**unavailable**, and only `notMet` is evidence about the learner.

**Why.** One boolean per attempt collapses two different facts. "The learner did
not manage it" and "this attempt cannot say whether they did" read identically,
and the scheduler suppresses the scaffold on either, so a lost MIDI event or a
transport whose clock nothing has characterized became a durable reason to stop
offering the learner the help they were stuck without.

Where each verdict is settled:

| Criterion  | Reads                                                | `unavailable` when                                              |
| ---------- | ---------------------------------------------------- | --------------------------------------------------------------- |
| Sequence   | Whether the material came out, right the first time. | Capture integrity says events may have been lost.               |
| Continuity | Whether the playing stopped inside a traversal.      | The same, or a transition the criterion covers was never timed. |

Continuity asks for coverage of the transitions themselves, not a count of
waits. Six waits out of seven are enough arithmetic for a pace and are not
evidence that the playing never stopped, because nothing was observed across the
transition that is missing.

Capture integrity is folded in at closure, not in measurement. Measurement reads
a musical observation and has no business knowing the ways a capture can fail;
closure has both in hand. Only `inputInterrupted` is compromised: every other
ending stops the observing without losing what had already arrived.

The record enforces the same rule for the version that can state it. A version 8
`inputInterrupted` record whose criteria are anything but `unavailable` is
refused, so a damaged or hand-built record cannot state a failure over
compromised evidence and have replay suppress the scaffold on it. Older records
keep the verdicts their format meant, since today's integrity rule is not
reconstructible from them.

**Consequences.** `earnedProbe` is every criterion met, not merely none failed.
`evidenceRevisionAtCriterionFailure` is set by a demonstrated `notMet` alone, so
an attempt that judged nothing neither earns a probe nor sets the scaffold
aside. A record that was already observed keeps its gaps whatever its verdicts
say, since what arrived is still what was played.
