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

PerformanceTranscript + ExerciseRealization
    -> Alignment
    -> EditScript                             how the two relate

EditScript
    -> evaluative displays, scoring, learner evidence
```

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
align(
  realization: ExerciseRealization,     what the exercise asked for
  transcript: PerformanceTranscript,    what was played
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

## What the policy has to decide

Deliberately not decided here. Each of these is a real pedagogical choice, and
naming them is the point:

- **Sameness.** Pitch class or exact pitch? Is an octave error a substitution or
  a match with a note about register?
- **Hands.** Hands-together material has two notes per moment. Is a moment
  matched when both arrive, and how far apart may they be?
- **Order.** Is a rolled or slightly spread pair two moments or one?
- **Repeats.** A learner who plays a note, hears it is wrong, and plays the
  right one has produced an insertion followed by a match. Does the policy say
  so, or does it absorb the correction?
- **Skips.** How many deletions in a row before the aligner decides the learner
  restarted rather than skipped?
- **Timing.** Alignment can be pitch-only, or use `timestampMs` to prefer
  matches that arrive when they were due. V1 should probably start pitch-only,
  because a tempo model does not exist and a timing-aware aligner would smuggle
  one in.

## What must not happen here

- Alignment must not reach back into presentation. Spelling an observed note
  uses the key, never the expected position (`spellObservedPitch` cannot see a
  realization, and its signature is what guarantees that).
- Alignment must not be run to draw the neutral echo. If a display needs the
  edit script, it is evaluative, and `PresentationConditions` has to say so.
- The aligner must not decide evidence. It says how the sequences relate; what
  that means for a competency is the learner model's job.
