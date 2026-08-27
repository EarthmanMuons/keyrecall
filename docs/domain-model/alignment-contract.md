# Alignment contract

- **Status:** Partly implemented. `keyrecall_alignment` prices what timing
  suggests about a transcript and aligns any material against it, both hands
  included, and `keyrecall_measurement` counts notes and moments apart. The
  coordination channel is not built, so hands-together exercises are still
  withheld from practice.
- **Written:** August 25, 2026
- **Revised:** August 27, 2026, with the hands and order questions resolved

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
  alignmentPolicy: AlignmentPolicy,     what a preference may be worth
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
scores. It is moment-first: the outer script relates expected moments to the
observations that correspond to them, and the note edits ride inside.

```text
MomentCorrespondence  realization moment i  <-  observed run j..k
  Match                 expected note, hand  <-  observed note
  Substitution          expected note, hand  <-  observed note, different pitch
  Deletion              expected note, hand      nothing played
  Insertion                                      observed note, nothing expected
MomentDeletion        realization moment i      nothing arrived for it
MomentInsertion                                 observed run, nothing expected
```

Every operation names the realization position, the observations it consumed, or
both, so a display can walk either sequence and know what happened at each
point. Moment deletions consume no observations by construction, moment
insertions name no realization position.

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

## Settled: one script for one hand and for two

A single-hand moment holds one note, so it produces one correspondence carrying
one note edit. That is the whole difference. There is not a scalar aligner and a
hands-together aligner, and there is not a single-hand measurement path beside a
two-hand one, because two implementations of the same idea are how two readings
of the same performance start to disagree.

A second top-level case for a partly-correct moment was considered and rejected.
It sounds tidier than nesting until it has to answer how many wrong notes make a
moment wrong, which is fractional correctness reappearing in the layer that
exists to keep it out. One correspondence case carries whatever note edits it
carries, and whether that reads as clean is a question for `AlignmentReading`,
where every other such question already lives.

**Observed notes have no hand, and must not acquire one.** MIDI says which key
and when. Register and correspondence usually make the player obvious, and hands
cross, so which hand produced a note is a conclusion alignment reaches by
matching the expected side rather than a fact the observation carries. Hand
identity therefore rides on the expected note of a note edit and nowhere else,
which is the same guarantee `spellObservedPitch` makes by its signature: a stage
that cannot name the thing cannot quietly assume it.

Inside one correspondence, note edits come from the cheapest matching of the
expected notes against the observed run. `RealizationMoment` already refuses to
let a hand play twice at once, which bounds that to a handful of enumerations
and keeps the inner loop free. When material arrives that needs chords, that
invariant is what has to be revisited first.

**Single-hand equivalence is the exit criterion for building this.** For any
single-hand realization, moments and notes are the same count, so every reading
and every measurement must come out identical to what the scalar aligner
produced, operation for operation and number for number. A single-hand number
that moves means the representation is wrong, not that the number was.

## Settled: grouping proposes at a bounded price

For every adjacent pair of observed notes, both the same-moment and the
split-moment reading stay finite and admissible. Grouping evidence may bias
alignment and may not make either reading impossible, and the largest preference
a boundary can contribute is bounded relative to the note-correspondence costs.

This is the invariant rather than the tuning, because the tuning is where it
would be lost. A cost of infinity at some gap is a classifier wearing a cost
function's clothes, and the out-of-phase take is the standing proof that no gap
earns one: notes 23 ms apart there belong to different moments. The clamp itself
is a number and lives in `AlignmentPolicy` with the other numbers.

## Settled: the partition comes out of the search

A correspondence transition consumes one expected moment and a contiguous run of
one to K observed notes, where K is the largest expected note count of any
moment under the active realization contract. K is two for the current scale
model, where a moment holds at most one note per hand, and the rule is written
against the realization rather than against hands so that "two hands" does not
silently become "chords of at most two" the first time the material grows.

The search is one table over expected moments and observed notes, so the run
lengths, the note matchings inside them, and the correspondence they serve are
chosen together, at O(M x N x K). The partition is an output of that search and
never an input to it, which is what makes "grouping never commits" structural
instead of a discipline someone has to keep.

Ties break toward the earliest minimum-cost explanation, as they already do, and
at equal cost a shorter run beats a longer one. Both are policy and both decide
readings: a longer run absorbs a stray note into a moment where nothing shows it
was extra, and the shorter reading leaves it standing as an insertion, which is
what the rest of the contract assumes an extra note does. In full, a moment
takes one observation before an extra is allowed to stand, and an extra stands
before a moment takes a second observation.

Within a correspondence, the notes are assigned in the moment's own order, each
taking the observations in arrival order before going unplayed, and the first
cheapest assignment wins. Two equally wrong notes in one moment therefore
resolve the same way every time, which replay needs and no reading depends on.

## Settled: notes, moments, and the space between hands are counted separately

```text
note           material appeared, pitch integrity, topology accuracy
moment         completed, reached final position, continuity, temporal
               stability, achieved tempo
within moment  coordination
```

These are different claims and one denominator cannot carry them. A two-note
moment with one right note has produced half of what it asked for and has
covered its position exactly once. Degree correctness counts notes even though
completeness counts moments, because being the right scale degree is a fact
about a pitch class rather than about a point in the traversal. So
`expectedNotes` stops meaning the number of moments, and a separate count of
moments joins it.

A moment's onset is the median arrival of the run that corresponds to it, and
the asynchrony between the hands is a second derived quantity taken at the same
time. Both are recorded on the correspondence, so the tempo reading never sees
hand spread as an irregular gap and the coordination reading never goes back to
the transcript to rediscover note times. Median rather than earliest, so a
rolled attack does not drag the moment toward whichever finger led, and
fractional for an even-sized run, since an onset is a derived quantity rather
than an arrival.

Asynchrony is right minus left, and it needs both hands to have corresponded to
something that arrived, not to have played the right note. A wrong pitch still
says when that hand acted.

Asynchrony exists only where both hands corresponded. Everywhere else it is
absent rather than zero, the way dispersion already is for a performance too
short to have a spread.

`HANDS_TOGETHER_COORDINATION` reads a channel of its own: the median absolute
asynchrony and its upper tail. Attributing it from the generic motor channels
would make the competency read as measured when nothing measured it, which is
the one failure the three-valued retrieval encoding exists to prevent elsewhere.
The signed median is kept as description and does not enter the outcome, because
which hand leads is a fact about a take rather than a fault: across the recorded
takes the left led 8 of 12 in one and 2 of 12 in another.

## What the policy still has to decide

Deliberately not decided here. Each of these is a real pedagogical choice, and
naming them is the point:

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
