# Alignment contract

- **Status:** Design only. Nothing implements this yet.
- **Written:** August 25, 2026

This exists so the transcript built today carries what the aligner will need
tomorrow, and so the evaluative displays we have discussed are renderings of one
result rather than three separate pieces of matching logic.

## What alignment is for

```text
Input stream
    -> PerformanceTranscript                  what was played, in order

PerformanceTranscript
    -> observation grouping                   which notes happened together
    -> ObservedMoment[]

ObservedMoment[] + ExerciseRealization
    -> Alignment
    -> EditScript                             how the two relate

EditScript
    -> evaluative displays, scoring, learner evidence
```

Grouping is its own stage so the aligner is never asked to discover simultaneity
and musical correspondence at once. A realization is already moment-shaped;
grouping is what gives the observations the same shape, and it is the only place
a timing tolerance lives.

The transcript alone supports the neutral case: a literal, append-only record
that discloses nothing about what was expected. Everything that compares the two
lives behind alignment.

## Why it is a boundary rather than a detail

Deciding that an observed F sharp _is_ the sixth note of the scale, rather than
a wrong third note, is the same decision as saying the attempt was going well.
Any display that places an observation into an expected position, advances
expected progress, or omits an observation that does not fit has performed that
comparison and is showing its result. That is `PerformanceFeedback.evaluative`,
whatever it looks like.

So alignment is the single place a correctness judgment is allowed to be made,
and its output is the single thing the displays and the learner model read.

## What the aligner takes

```text
groupObservations(
  transcript: PerformanceTranscript,
  policy: ObservationGroupingPolicy,    how close is "at the same time"
) -> List<ObservedMoment>

align(
  realization: ExerciseRealization,     what the exercise asked for
  observed: List<ObservedMoment>,       what was played, in moments
  policy: AlignmentPolicy,              what counts as the same note
) -> Alignment
```

The transcript already carries what this needs: arrival order, a stable
`sequence`, the spelled pitch, and an uninterpreted `timestampMs`. It carries no
expected positions, which is what keeps it usable before alignment exists.

## What it produces

An edit script over the two sequences, describing relationships rather than
scores:

```text
Match          realization moment i  <-  transcript note j
Substitution   realization moment i  <-  transcript note j, different pitch
Insertion                                transcript note j, nothing expected
Deletion       realization moment i      nothing played
```

Every operation names the realization position, the transcript position, or
both, so a display can walk either sequence and know what happened at each
point. Deletions carry no transcript position by construction, insertions carry
no realization position.

The result should also be able to answer, without recomputing anything:

- **First-pass reading:** the operations in order, so an error that was
  immediately repaired is visible as an error followed by a repair.
- **Final reading:** whether the realization was eventually completed.

Those are different questions, and an attempt that reached the end after three
corrections must not be readable as a clean one. The learner model already
distinguishes genuine retrieval from supported practice; this is where the
evidence for that distinction comes from.

## Settled: sameness is exact sounding pitch

A candidate match requires the same MIDI note. Same pitch class in another
octave is not a match; it is a substitution that records the register error.

```text
same MIDI note                  -> Match
same pitch class, wrong octave  -> Substitution, register
different pitch class           -> Substitution, pitch
```

Both are the same top-level operation, and the kind of difference rides along
rather than splitting the edit script's shape:

```text
Substitution(expected, observed, difference)
```

Two reasons. An attempt played an octave low would otherwise read as clean
retrieval, which would make the register in `ExerciseRealization` unobservable
in principle. And an octave displacement is plausibly evidence about register
planning rather than about recalling the scale, so collapsing it into a generic
wrong note throws away the distinction the learner model would want.

**Performance sameness is not notation sameness.** Both sides carry a
`SpelledPitch`, which makes `expected.pitch == observed.pitch` easy to write and
wrong to use: the learner pressed a key, and the spelling is our reading of that
key in context. Alignment compares `midiNote`. A G sharp observed where an A
flat was expected is the same physical event, and any disagreement about how to
write it is a notation question somewhere else.

## What the policy has to decide

Deliberately not decided here. Each of these is a real pedagogical choice, and
naming them is the point:

- **Hands.** Hands-together material has two notes per moment, and human hands
  do not arrive together to the millisecond. Grouping needs a window, and the
  window is empirical: alignment must not invent a constant before recorded
  performances support one. See the diagnostic below.
- **Order.** Is a rolled or slightly spread pair two moments or one? The same
  window decides it, which is why grouping is one stage rather than two rules.
- **Repeats.** A learner who plays a note, hears it is wrong, and plays the
  right one has produced an insertion followed by a match. Does the policy say
  so, or does it absorb the correction?
- **Skips.** How many deletions in a row before the aligner decides the learner
  restarted rather than skipped?
- **Timing.** Alignment can be pitch-only, or use `timestampMs` to prefer
  matches that arrive when they were due. V1 should probably start pitch-only,
  because a tempo model does not exist and a timing-aware aligner would smuggle
  one in.

## Calibrating the grouping window

The number should come from recordings rather than from intuition, and the
transcript already carries what is needed: every note-on with its arrival time.
The dev panel's onset diagnostic records raw note-ons and reports the gap
between each and the one before it.

Worth recording before choosing anything:

- several comfortable hands-together scales;
- deliberately synchronized attacks;
- deliberately staggered ones;
- rolled pairs that should _not_ group;
- both directions, and at least two tempos, since coordination spreads with
  speed and around the turnaround.

What to look for is whether ordinary asynchrony separates cleanly from
deliberately sequential playing. If it does not, that is a finding too: the
policy would then have to tolerate ambiguity rather than pretend a threshold
exists.

## What must not happen here

- Alignment must not reach back into presentation. Spelling an observed note
  uses the key, never the expected position (`spellObservedPitch` cannot see a
  realization, and its signature is what guarantees that).
- Alignment must not be run to draw the neutral echo. If a display needs the
  edit script, it is evaluative, and `PresentationConditions` has to say so.
- The aligner must not decide evidence. It says how the sequences relate; what
  that means for a competency is the learner model's job.
