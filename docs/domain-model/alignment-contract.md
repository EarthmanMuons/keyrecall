# Alignment contract

- **Status:** Partly implemented. `keyrecall_alignment` aligns single-hand,
  pitch-only performances; grouping and everything it gates are still design.
- **Written:** August 25, 2026

This exists so the transcript built today carries what the aligner will need
tomorrow, and so the evaluative displays we have discussed are renderings of one
result rather than three separate pieces of matching logic.

## What alignment is for

```text
Input stream
    -> PerformanceTranscript                  what was played, in order

PerformanceTranscript
    -> observation grouping                   candidate temporal structure
    -> ObservationGrouping
         likely-same boundaries
         likely-separate boundaries
         ambiguous boundaries

ObservationGrouping + ExerciseRealization
    -> global correspondence search
    -> Alignment
         observed moments, in correspondence
         EditScript                           how the two relate

EditScript
    -> evaluative displays, scoring, learner evidence
```

Grouping is its own stage so the aligner is never asked to discover simultaneity
and musical correspondence at once. It is the only place a timing tolerance
lives, and it produces _candidate temporal structure_ over the observations
rather than the moments themselves. Observed moments exist only once alignment
has put them in correspondence with realization moments.

**Everything grouping says is a proposal, not a fact alignment must obey.** A
boundary marked likely-same is timing evidence that two observations belong
together, and alignment may overrule it. That is not a hedge: the out-of-phase
take in the calibration data has observations 23 ms apart that belong to
different moments, so even a very small gap cannot be authoritative. Proposals
enter alignment as costs, never as constraints.

Grouping still knows nothing about keys, octaves, hands, or scale degrees. It
can say only that two observations are plausibly one event and plausibly two.

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
  policy: ObservationGroupingPolicy,    where confidence ends
) -> ObservationGrouping

align(
  realization: ExerciseRealization,     what the exercise asked for
  grouping: ObservationGrouping,        what was played, and what timing suggests
  policy: AlignmentPolicy,              what counts as the same note, and what
                                        each explanation costs
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

- **Hands.** How wide the ambiguous region is: where grouping stops being
  confident that two observations are one moment, and where it becomes confident
  they are two. Both edges are empirical, and only the middle is handed to
  alignment. See below.
- **Order.** Whether a deliberately rolled pair is one moment or two is not
  decidable from timing, so it is alignment's to settle, from whichever reading
  explains the performance better.
- **Repeats.** A learner who plays a note, hears it is wrong, and plays the
  right one has produced an insertion followed by a match. Does the policy say
  so, or does it absorb the correction?
- **Skips.** How many deletions in a row before the aligner decides the learner
  restarted rather than skipped?
- **Timing.** Alignment can be pitch-only, or use `timestampMs` to prefer
  matches that arrive when they were due. V1 should probably start pitch-only,
  because a tempo model does not exist and a timing-aware aligner would smuggle
  one in.

## Rejected: a single grouping threshold

The first plan was to measure hands-together playing and pick a tolerance. Five
takes on a real instrument rejected that model, and the measurements are in
[`analysis/onset-grouping/`](../../analysis/onset-grouping/README.md). Three of
them were mis-played on purpose, which is enough to show a failure mode is
reachable and not enough to say how common it is: what follows rests on the
first, and the ambiguous region's width is still uncalibrated.

Comfortable playing separates cleanly: pairs within 30 ms, moments 254 ms apart.
But a faster take with a stumble stretched intended-together pairs to 134 ms
while its consecutive moments came as close as 121 ms, so the two populations
overlap exactly where a stumble makes measurement interesting. Pooled over 70
pairs and 65 steps, no threshold avoids both errors, and scaling the tolerance
with tempo does no better.

The decisive case is the take where the hands drifted a whole step out of phase.
There, notes 23 ms apart belonged to _different_ moments while notes of one
moment arrived a second apart. A timing threshold would not have been uncertain
there; it would have been confidently wrong, and alignment would then have been
handed a corrupted partition to explain with insertions and deletions.

Hence proposals rather than a constant. A grouper may still lean hard at the
extremes, which is what keeps the search tractable; what it may not do is
decide, at any gap, that the question is closed. The out-of-phase take rules out
even the safe-looking half of that: pairing two observations 25 ms apart is a
strong prior and still overridable, because the reading that costs less overall
may be the one where they belong to different moments.

A tempting alternative was rejected too: grouping observations that sit an
octave apart, which would work well for V1 scales because the hands play in
octaves. That is correspondence knowledge leaking backward into observation, and
it would have to be unwound the first time material is not in octaves.

Still worth recording: attempts by people genuinely finding the material hard,
more players, and other instruments. Not to decide whether ambiguity is
necessary, which these takes settle, but to characterize how wide the ambiguous
region has to be.

## What must not happen here

- Alignment must not reach back into presentation. Spelling an observed note
  uses the key, never the expected position (`spellObservedPitch` cannot see a
  realization, and its signature is what guarantees that).
- Alignment must not be consulted to terminate an attempt **on correctness**
  unless that attempt's presentation conditions already permit evaluative
  feedback. Ending an attempt is the loudest correctness signal available, and a
  learner cut off after four wrong notes has been told they were wrong four
  times whatever the screen says.

  Consulting it for **progress** is allowed anywhere, because progress does not
  depend on correctness: a substituted note covers its position exactly as a
  matched one does, so "the traversal has been covered" cannot tell a learner
  they got it right. That is what ends an ordinary attempt, and it is why
  counting arrivals is the wrong rule: an extra note in the middle would pay for
  the last note of the scale and cut the traversal short.

  It does leak a little, and the leak is worth naming. An attempt with an extra
  note ends one note later than one without, so a learner watching closely can
  infer that something was extra. That is weaker than being told a note was
  wrong, and it buys not truncating corrected attempts.

  Termination on silence or elapsed time needs no alignment at all; see
  [`attempt-termination.md`](attempt-termination.md).

- Alignment must not be run to draw the neutral echo. If a display needs the
  edit script, it is evaluative, and `PresentationConditions` has to say so.
- The aligner must not decide evidence. It says how the sequences relate; what
  that means for a competency is the learner model's job.
