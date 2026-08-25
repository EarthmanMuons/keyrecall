# Attempt termination policy

- **Status:** Design only. Today an attempt ends when the learner taps Done.
- **Written:** August 25, 2026

How an attempt ends is its own concern rather than part of alignment, because
two of the three ways it can end need no notion of correctness at all.

## Three categories

```text
Attempt termination
├── learner initiated
│   └── Done / abandon
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

## Prompt rather than seize

Silence and duration should surface an offer, not take the instrument away. A
long pause is ambiguous on its face: thinking, an interruption, a page turn, a
slower execution than the one requested. Continuing to accept input while
showing something like "still working?" resolves none of that wrongly.

A much larger absolute safety limit may eventually close an abandoned attempt,
and that closure is a fact about the app rather than about the performance.

## Termination reason is evidence metadata, not outcome

Once more than one path exists, the record has to say which one ended the
attempt, roughly:

```text
learnerStopped
inactivityTimeout
durationLimit
evaluativeCutoff
```

Deliberately no `learnerCompleted` yet. Nothing can establish completion until
measurement exists, and today's Done button means the learner ended it, which is
a weaker claim.

The reason must stay beside the outcome rather than inside it, so that

```text
inactivityTimeout -> completed: false -> the learner failed
```

is not available as an accidental inference. An attempt the learner stopped at
six moments and one a timeout closed at six moments are different observations.

## Three readings of one attempt

Once measurement exists, an attempt carries three independent readings:

```text
termination reason      how it ended
learner report          what the learner says happened
measured outcome        what alignment says happened
```

They can disagree, and the disagreement is evidence rather than noise. A learner
who stops and reports a clean attempt that measurement says contained an
insertion is telling you something about self-monitoring; one who reports a
breakdown that measurement says was completed after an omission and a recovery
is telling you something about confidence. Storage must keep the three apart so
those cases stay representable.

A timeout in particular may leave no valid self-report at all, and the absence
of an outcome has to remain an absence rather than being coerced into a
breakdown.

**`ReportedResult` currently conflates the first two.** `brokeDown` says both
how the attempt ended and how it went, which is tolerable only while Done is the
one way to end one. When termination reasons become real, split the lifecycle
event from the learner's characterization and keep `brokeDown` as the latter.

## What is deliberately not decided

The windows. How many beats of silence, what multiple of the expected duration,
and how long the safety limit is are all uncalibrated, and the same discipline
applies as to the grouping window: no constant before something supports it.

Recovery is also the better answer to struggle in most cases. The scheduler
already responds to a broken-down attempt by offering the same material one rung
more supportive, which produces cleaner evidence than truncating the attempt,
because the breakdown point is observed rather than imposed. Evaluative cutoff
is mainly useful for stopping unproductive thrashing in supported practice, not
as the ordinary end of a retrieval attempt.
