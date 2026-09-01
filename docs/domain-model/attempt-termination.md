# Attempt termination policy

- **Status:** Steps 1 to 5 are implemented. `ReportedResult` is gone, so step 6
  is done as well.
- **Written:** August 25, 2026
- **Revised:** August 31, 2026

How an attempt ends is its own concern rather than part of alignment, because
two of the three ways it can end need no notion of correctness at all.

## Three categories

```text
Attempt termination
├── learner initiated
│   ├── Done / abandon
│   └── declined: "I don't remember", before playing
├── observation based, non-evaluative
│   ├── prolonged silence
│   └── excessive elapsed duration
└── evaluative
    ├── repeated errors
    ├── loss of alignment
    └── predicted inability to complete
```

The first two are compatible with `PerformanceFeedback.neutralEcho`: silence and
elapsed time are facts about the observation stream, computable from the
transcript's timestamps and the exercise's requested tempo, and they say nothing
about whether a note was right.

The third is not. Counting errors, noticing that alignment has been lost, or
predicting that the learner cannot finish are all judgments, and acting on one
by ending the attempt delivers that judgment through the loudest channel there
is. Under any other feedback condition it is a leak, which
[`alignment-contract.md`](alignment-contract.md) states as a prohibition.

## Declining is evidence, not an escape hatch

"I don't remember" is a retrieval failure the learner is in a position to
report, and the learner model already has exactly that state: an outcome that
never started, with a failed retrieval, carries memory evidence at the rung's
weight, no execution evidence at all, and opens a recovery context that offers
the same exercise one rung more supportive. Before this existed the only way to
say it was to play something wrong, which manufactures execution evidence for a
performance that never happened.

Two boundaries hold it in place, and both are the session's rather than the
screen's. It is offered only at a rung that tests retrieval, since there is
nothing to fail to retrieve when the material is on screen. And it is offered
only before anything has been played: once notes attributable to the attempt
have arrived, what happened is a question for measurement rather than for the
learner. `closeDeclined` takes the transcript for that reason, the way
`closeFromPerformance` does. The caller shows what arrived rather than being
trusted to have called at the right moment, and a non-empty transcript is
refused.

It is deliberately not a skip. A skip writes no learner evidence at all and is
an operational action about the session rather than a poor outcome; nothing has
demonstrated a need for one yet, so there is none.

## Prompt rather than seize

Silence and duration should surface an offer, not take the instrument away. A
long pause is ambiguous on its face: thinking, an interruption, a page turn, a
slower execution than the one requested. Continuing to accept input while
showing something like "still working?" resolves none of that wrongly.

A much larger absolute safety limit closes an abandoned attempt, and that
closure is a fact about the app rather than about the performance.

## Termination reason is evidence metadata, not outcome

Once more than one path exists, the record has to say which one ended the
attempt, roughly:

```text
learnerStopped
inactivityTimeout
durationLimit
evaluativeCutoff
```

Deliberately no `learnerCompleted`. Completion is measurement's to establish;
Done means the learner ended it, which is a weaker claim.

The reason must stay beside the outcome rather than inside it, so that

```text
inactivityTimeout -> completed: false -> the learner failed
```

is not available as an accidental inference. An attempt the learner stopped at
six moments and one a timeout closed at six moments are different observations.

## Closing an attempt

An attempt that has ended is closed with what is known at that moment:

```text
AttemptClosure
├── terminationReason      required
└── measurement            Measured(outcome) | Unavailable(reason)
```

Unavailability is a value rather than a null. "Nothing measured this attempt,
because nothing can yet" is known information; a null would say only that the
record lacks a field, which is what an incomplete write looks like. Replay has
to tell those apart without guessing.

```dart
sealed class MeasurementResult {}
class Measured extends MeasurementResult { final MeasuredOutcome outcome; }
class MeasurementUnavailable extends MeasurementResult {
  final MeasurementUnavailableReason reason;
}
```

Two reasons: `notAvailable`, for the period before an aligner existed, and
`nothingPlayed`, for a timeout that arrived with an empty transcript. Genuinely
different failures such as insufficient evidence, an indeterminate alignment, or
an input fault can be distinguished when they become reachable, under the same
rule as everywhere else here.

`nothingPlayed` is a claim about attribution rather than about a performance. A
learner who ends an attempt having played nothing measures like any other
attempt, because they said it was over; a timeout says only that the app stopped
waiting, and the silence behind it could as easily be an interruption.

No learner report. If the app can read the performance from the MIDI stream,
asking for a subjective characterization afterwards is friction that buys a
second, noisier evidence source. Measurement that genuinely cannot establish an
outcome should say so as an indeterminate result, not fall back on asking.

A timeout closure is therefore complete and honest on its own, with or without
an aligner:

```text
terminationReason: inactivityTimeout
measurement:       Unavailable(nothingPlayed)
```

**Termination does not depend on alignment.** It depends on the closure model
and the schema that persists it. Building it in that order is what gets the
unavailable case exercised at all, rather than leaving it a paper state that
first runs on the day measurement arrives and stops producing it.

Learner reflection, if it ever earns a place, belongs outside the evidence model
as a pedagogical feature rather than as a second evidence channel beside
measurement.

## Pending is not the same as closed without evidence

> Pending means the attempt has not ended. Once it ends, commit the termination
> reason and whatever measured evidence exists.

A timed-out attempt must not become a pending decision. Pending means the system
decided what to present and the interaction is unfinished; a closure is a
finished interaction, whatever evidence it happens to carry. Collapsing the two
would make the recovery path ask a learner to resolve something that is already
over.

Three states, then, and only the third needs an aligner:

```text
1. pending           no closure exists
2. closed, unmeasured  closure exists, termination known, measurement unavailable
3. closed, measured    closure exists, termination known, measurement available
```

Crash recovery is where the distinction earns its keep:

```text
decision persisted, attempt started, app killed
    -> reopens as pending: no termination was recorded

decision persisted, attempt started, timeout fired, closure appended, app killed
    -> reopens as a closed attempt: the lifecycle ended before the crash
```

`PracticeSession.commit` takes an `Outcome` today, which assumes a mandatory
outcome is the central thing an attempt produces. The change is not to make that
outcome nullable, which would keep the assumption and merely permit an absence;
it is that termination is the mandatory lifecycle fact and measurement is
independent evidence beside it.

The closure stays one atomic append: the persisted record gains the termination
reason and the measurement result together, rather than appending a closure and
amending it later.

## What a closure without measurement may and may not move

A closed attempt with no usable measurement is a lifecycle fact, and it can
inform the session and the scheduler: it is a reason not to assume successful
practice occurred, and a slot was still consumed. It must not update
competencies. "Nothing was measured" is not evidence that retrieval failed, and
folding it in as though it were would manufacture exactly the false evidence the
three-valued retrieval encoding exists to prevent.

```text
journal lifecycle fact -> session and scheduler behavior
                       -> no learner competency update
```

## An order that tests what it claims

1. ~~Introduce `AttemptClosure` and the persisted termination semantics.~~ Done:
   schema version 2, with a pure version 1 upgrade.
2. ~~Route today's reporting scaffolding through it.~~ Done:
   `PracticeSession.commit` closes as `learnerStopped` with a measurement.
3. ~~Prove closed-with-unavailable-measurement survives replay.~~ Done:
   `PracticeSession.closeUnmeasured` exists and is covered, though nothing in
   the app calls it yet.
4. ~~Add non-evaluative termination paths, which is what makes `closeUnmeasured`
   reachable outside tests.~~ Done: silence and elapsed duration close an
   attempt, and a timeout with nothing played closes unmeasured with
   `nothingPlayed`.
5. ~~Build alignment, which makes `Measured` reachable from an actual
   performance.~~ Done: `PracticeSession.closeFromPerformance` measures what was
   played, for one hand or two.
6. ~~Delete `ReportedResult`.~~ Done: what an attempt records is measured or
   declined, and nothing else.

Steps 1 to 3 change storage and lifecycle without changing what the learner
sees, so the schema bump lands while the only evidence producer is still the
five buttons, and the evidence producer is replaced later against a lifecycle
that is already correct.

## The windows

`AttemptWindows.forExercise` holds them, and they scale with the tempo the
exercise asked for, because what a learner feels is a bar rather than a number
of seconds. Floors keep a quick exercise from questioning somebody who is
thinking.

```text
afterPlaying    4 beats, at least 3s    silence after a note: the traversal
                                        has probably ended
beforePlaying  12 beats, at least 12s   silence before the first note: hands
                                        are still on their way to the keys
abandon                          45s    nobody is coming back to answer
limit          6x expected, at least 2m playing that never stops
```

The first two raise the question and nothing else: the transcript keeps
recording, the keyboard keeps echoing, and a note arriving takes the question
back down. The last two close the attempt.

The floors and multiples are chosen rather than calibrated. They are one class
of constant the grouping-window discipline does not reach, because the
alternative to a chosen window here is an attempt that only ends when somebody
taps Done, which is what this replaces.

## What is deliberately not decided

Whether an attempt that timed out should be offered again. The scheduler treats
the closure as a consumed slot and no competency change, which is honest but
says nothing about whether the material was practised.

Recovery is also the better answer to struggle in most cases. The scheduler
already responds to a broken-down attempt by offering the same material one rung
more supportive, which produces cleaner evidence than truncating the attempt,
because the breakdown point is observed rather than imposed. Evaluative cutoff
is mainly useful for stopping unproductive thrashing in supported practice, not
as the ordinary end of a retrieval attempt.
