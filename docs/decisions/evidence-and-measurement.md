# Evidence and measurement

What an observation may claim, what it may not, and why alignment costs are the
policy rather than a tuning knob.

## Alignment is the only place correctness is decided

**Decision.** One aligner, one result, and every evaluative display and every
learner update reads it.

**Why.** Deciding that an observed F sharp _is_ the sixth note of the scale
rather than a wrong third note is the same decision as saying the attempt was
going well. Any display that places an observation into an expected position,
advances expected progress, or omits an observation that does not fit has
performed that comparison and is showing its result, whatever it looks like.

**Consequences.** The neutral echo on the practice screen cannot use alignment,
and does not: it lights held keys and travels a per-hand locator with tolerances
that never _light_ anything. Three separate pieces of matching logic would
otherwise drift apart and leak an evaluative judgment under a neutral feedback
condition.

## The locator is contingent feedback, not a neutral display

**Decision.** Locator highlighting is recorded on a channel of its own,
`LocatorFeedback`, and is not counted as absent feedback.

**Why.** The rule above says that placing an observation into an expected
position, or omitting one that does not fit, is a comparison whose result is
being shown. The locator does exactly that: a matching arrival lights the note
it matched and an unmatched one lights nothing, so the display is contingent on
agreement with the target. Exempting it while the rule named it was a
contradiction, and calling it neutral was the part that was wrong.

**Consequences.** It is still permitted, and nothing about the display changes.
What changes is what may be said about an attempt that ran under it: the locator
is low-bandwidth contingent feedback, not evaluative outcome feedback, because
it says "that note is here in what you were asked for" and never that anything
was right, wrong, or late. It runs only where a cue staff is on screen during
the attempt, which today is the continuously cued rung alone, so no attempt that
observes independent retrieval has ever carried it. An attempt under a locator
must not be attributed as one under no feedback.

## Rejected: a single grouping threshold

**Decision.** Grouping produces _proposals_ that enter alignment as costs, never
a partition alignment must obey.

**Why.** The first plan was to measure hands-together playing and pick a
tolerance.

**Evidence.** Five takes on a real instrument rejected that model, recorded in
[`analysis/onset-grouping/`](../../analysis/onset-grouping/README.md). Three
were mis-played on purpose, which is enough to show a failure mode is reachable
and not enough to say how common it is.

Comfortable playing separates cleanly: pairs within 30 ms, moments 254 ms apart.
But a faster take with a stumble stretched intended-together pairs to 134 ms
while its consecutive moments came as close as 121 ms, so the two populations
overlap **exactly where a stumble makes measurement interesting**. Pooled over
70 pairs and 65 steps, no threshold avoids both errors, and scaling the
tolerance with tempo does no better.

The decisive case is the take where the hands drifted a whole step out of phase.
There, notes 23 ms apart belonged to _different_ moments while notes of one
moment arrived a second apart. A timing threshold would not have been uncertain
there; it would have been **confidently wrong**, and alignment would have been
handed a corrupted partition to explain with insertions and deletions.

**Consequences.** A grouper may lean hard at the extremes, which is what keeps
the search tractable. What it may not do is decide, at any gap, that the
question is closed. Pairing two observations 25 ms apart is a strong prior and
still overridable, because the reading that costs less overall may be the one
where they belong to different moments.

The ambiguous region's width is still uncalibrated. More takes would settle it:
people genuinely finding the material hard, more players, other instruments. Not
to decide whether ambiguity is necessary, which these takes settle, but to
characterize how wide it has to be.

### Also rejected: octave-based grouping

Grouping observations an octave apart would work well for scales, because the
hands play in octaves. It is correspondence knowledge leaking backward into
observation, and would have to be unwound the first time material is not in
octaves.

## The costs are the policy

**Decision.** One substitution is cheaper than one deletion plus one insertion.

**Why.** Those are two accounts of the same wrong note, and they are the
load-bearing comparison. A learner who plays one wrong note has played a wrong
note, not skipped one and added another.

**Decision.** The search is global, and traceback ties break toward the earliest
minimum-cost explanation.

**Why.** A single extra note early in a scale has one cheap explanation and one
expensive one, and deciding locally picks the expensive one and never recovers.
The tie rule makes a partial traversal read as "played the first few notes"
rather than "skipped to the end", which is load-bearing: a scale played up and
back down begins and ends on the same note, so a single played tonic would
otherwise explain as the final one.

**Consequences.** Determinism here is a production gate, not a nicety. Evidence
derived from an aligner that could return either of two equal-cost readings
would not be reproducible, and replay compares recomputed values exactly.

## Sameness is exact pitch, but the anchor is not part of the task

**Decision.** A match requires the same MIDI note. Same pitch class in another
octave is a substitution that records a _register_ error rather than a pitch
error. But the performance is explained against every whole-octave shift of the
realization that could reach the register it was played in, and the cheapest
explanation wins.

**Why.** An octave displacement is plausibly evidence about register planning
rather than about recalling the scale, so collapsing it into a generic wrong
note throws away a distinction the model wants. Meanwhile the realization's
anchor is a _drawing_ decision: the same fingering, the same intervals, the same
shape, wherever on the keyboard it starts.

**Evidence.** Two device sittings scored a scale played correctly an octave from
where the staff drew it as every note wrong, one of them on a hand's first
encounter with the material.

**Consequences.** The shift is whole octaves applied to the whole realization at
once, so a single note in the wrong octave still records a register
substitution: no shift of everything explains it. Hands together move together,
which is what makes the rule say something. The distance between the hands is
the task; where the pair sits is not, and normalizing each hand independently
would read hands two octaves apart as correct.

Separately: **performance sameness is not notation sameness.** Both sides carry
a `SpelledPitch`, which makes `expected.pitch == observed.pitch` easy to write
and wrong to use. Alignment compares `midiNote`. A G sharp observed where an A
flat was expected is the same physical event.

## One script for one hand and for two

**Decision.** A single-hand moment holds one note and produces one
correspondence carrying one note edit. That is the whole difference.

**Why.** There is not a scalar aligner beside a hands-together aligner, and not
a single-hand measurement path beside a two-hand one. Two implementations of the
same judgment drift.

## Retrieval is categorical, and three-valued

**Decision.** `retrieval` fails on any wrong degree, any missing note, or any
extra note that is not a repeat. And it has three values, where `null` means
retrieval was never tested.

**Why.** A threshold would make two nearly identical performances move the
memory clock in opposite directions, and the continuous channels already carry
how well it went.

The three-valued part is the sharper decision. Treating "not tested" as a weak
failure would make repeated fully cued practice accumulate into false evidence
of forgetting. Treating it as a weak success would credit memory for an attempt
that read the answer off the screen.

**Evidence.** The guidance hypothesis [WinsteinSchmidt1990, Winstein1994]:
concurrent feedback supports performance during practice while suppressing
learning, so a cued performance is not evidence about retention. Retrieval
practice moves memory; reading does not.

**Consequences.** All three values must survive serialization exactly, and
`retrieval_succeeded` must never be read, queried, or analyzed as failure. A
repaired attempt is complete, high in `materialRetrieval`, and a retrieval
failure, which is exactly the supported-practice reading the model wants.

A repeat is exempt, because replaying the note just played is producing the
right material twice rather than the wrong material. That classification is
structural, not attributed: a double trigger, a bounced finger, and a deliberate
reiteration are not distinguishable here.

## Absent is not zero

**Decision.** A channel nothing observed is `null` all the way through: the
outcome carries the null, the weights leave the channel out, the update leaves
its state untouched, and the record omits it.

**Why.** Zero is a measurement. Coordination zero says the hands were as far
apart as playing gets; continuity zero says the playing stopped. An attempt
nobody could read for togetherness has not been read as ragged.

**Evidence.** Timing needs enough waits for one of them to be the anomaly. Below
five, interpolated quartiles include the extremes they exist to ignore: three
notes at 0, 500, and 60000 ms would read as badly broken _and_ totally unsteady
at once, from a single wait measured against itself.

**Consequences.** Achieved tempo is the deliberate exception, because a ratio
has no null to report. Its raw field reports an unobserved pace as zero, and
`measuredTempoRatio` is the one interpretation of that sentinel. Every reader
asking what pace was observed goes through it, so a performance too short to
time enters no tempo statistic rather than entering it as a stop.

## Absent is not good either

**Decision.** A positive claim that depends on a channel is made only when that
channel applied to the exercise and was observed. Coordination is inapplicable
to one hand and unobserved in two hands nobody could time against each other,
and only the first may be passed over.

**Why.** Null had been read as "nothing wrong" wherever a presentation needed a
yes or no. A pitch-correct attempt with no timing read as played "steadily
throughout", an unjudged continuity read as "no pronounced break", and two hands
with one of them untimed earned a first clean completion. Each of those turned
evidence nobody collected into praise.

**Consequences.** `AttemptEvidence` carries observed, unobserved, or
inapplicable per timing channel, and the diagnosis, the detail sheet, and the
progress events all read it. The notes can still support "played cleanly" on
their own. A clean milestone needs every applicable channel observed and met.
Unobserved stays neutral in the other direction too: it names no fault.

## The sensors do not write the ontology

**Decision.** No register competency, despite measurement being able to see
register perfectly well.

**Why.** An octave slip leaves topology accuracy, material retrieval, and
factual retrieval untouched and reduces pitch integrity. That is four channels
doing their job. Adding latent state for every distinction the measurement
system happens to expose would multiply the ontology on the basis of what is
easy to instrument rather than what transfers.

**Consequences.** The general rule: a new competency has to earn persistent
state by being empirically distinct, transferable, and identifiable. See
[`../research/extending-the-model.md`](../research/extending-the-model.md).

## Timing does not reach a settled correspondence

**Decision.** Measurement reads timestamps only after alignment has fixed
correspondence.

**Why.** Once correspondence is settled, the timestamps of matched notes are
properties of the performance rather than further evidence about which note was
which. Changing how the same notes sat in time then cannot move a pitch-derived
channel.

**Consequences.** The guarantee is about timing not reaching a _settled_
correspondence, not about ambiguous correspondence being immune to timing:
grouping already lets timing express a bounded preference between two otherwise
equally good readings. Two-hand material is where that shows. A lone arrival of
a pitch that both a moment's right hand and the next moment's left hand ask for
belongs to whichever it arrived beside, and the channels then read the
correspondence that was chosen.

## Every timing claim is read from the instrument's clock

**Decision.** Tempo, temporal stability, continuity, and coordination are all
read from `MomentCorrespondence.performanceOnsetUs` and `handAsynchronyUs`. A
moment the performance clock could not place contributes no wait and breaks the
stretch continuity is read from. A moment where either hand could not be placed
contributes no spread. Nothing falls back to arrival time.

**Why.** The arrival clock reported a scale played by hand as 717 ms exactly,
thirteen intervals out of twenty-eight, where the transport clock ranged from
669 to 825. A channel that quietly used it would not be a weaker answer but a
confidently wrong one, and coordination would be the easiest place for it to
come back in after being removed from the other three.

**Consequences.** An attempt on a transport nothing has characterized carries
pitch, order, and completion evidence and no timing evidence at all. That is the
outcome [`performance-timing.md`](performance-timing.md) prefers to a fabricated
one. The arrival-clock `onsetMs` and `handAsynchronyMs` stay on the alignment
operations, because diagnostics, characterization, and the tests that compare
the two clocks all need them; what changed is that no learner-facing channel
reads them.

The attempt is kept and the channel goes absent, rather than the attempt being
invalidated:

```text
a channel was assessed         it carries evidence
a channel was not              it carries none
the other channels             proceed as they are
```

Absence is never a poor score. The execution channel takes no weight from an
attempt that measured no timing, the motor competencies keep their priors,
practice quality averages the channels the attempt established, and acquisition
answers `unestablished` rather than `interrupted`: the sequence was demonstrated
and the evidence one verdict needs was not available. Suppressing the attempt
instead would make timing a prerequisite for learning anything, which is a much
stronger claim than refusing to invent it. The uncharacterized domain is
persistent rather than intermittent, so what a progression that genuinely
requires timing runs into is unavailable evidence, not repeated failure.

## A wait is trustworthy or it does not exist

**Decision.** Timing runs are over **aligned musical moments**. A moment with no
performance onset ends the run it falls in and belongs to none, and no wait is
ever synthesized across it. A note alignment classifies as an intrusion or a
repeat is not a run boundary, because it realized no moment.

```text
moment A timed -- moment B untimed -- moment C timed

A -> B  lost
B -> C  lost
A -> C  never synthesized

moment A timed -- untimed intrusion -- moment B timed

A -> B  kept, because the intrusion realized nothing
```

**Why.** A performance can be partly timed: an attempt begins before the
instrument's clock has been identified, a delivery arrives without a stamp, or
the mapper stops vouching partway through. Dropping the untimed moments and
taking differences over what is left would close the hole and report a wait
nobody played, which is the same fabrication
[`performance-timing.md`](performance-timing.md) refuses one layer down.

The unit is a moment rather than a note because that is where the same question
was already settled for chords and for two hands: alignment decides which played
notes realize one musical moment, and this reads when those moments happened.
Letting an untimed intrusion split a run would put intrusion evidence back into
the timing channel after that separation was made deliberately. What does break
a run is an untimed note that realized a moment and left nothing else to place
it.

An observation boundary needs no representation here. A reset or an integrity
fault closes the capture, so notes from either side of one are never in the same
transcript.

`timingRunsOf` reads the same rule off a transcript, before alignment. It is a
characterization helper for a single stream, not the production definition: it
cannot know which notes realized a moment, so it treats every untimed note as a
boundary and every equal-timed pair as one onset.

**Consequences.** The denominator for any timing claim is usable waits, not
notes. Six timed moments in one run are five waits, and the same six split by a
hole are fewer.

## Two references, and a floor for each claim

**Decision.** Timing is read from two references rather than one:

```text
pace        median wait                      how fast the playing went
reference   upper quartile of the waits      the slow end of ordinary playing
            with the longest left out
```

An interruption is a wait at or above twice the reference. Continuity is the
longest wait over the reference. Stability is the mean absolute deviation of the
waits that are not interruptions from their median, over that median.

Each claim asks for what it needs:

```text
tempo        3 usable waits
stability    5 usable waits
continuity   5 usable waits in one stretch
```

**Why.** The previous model read every timing claim off one upper quartile of
every wait, which cannot be both the reference and contain what it judges. Once
about a quarter of the waits were pauses they set the bar they were measured
against: nine waits with three pauses read as perfectly unbroken, and fourteen
with four read 0.96, while stability collapsed to zero in both. Length was no
defense, because the turn is a proportion rather than a count.

Removing the longest wait from the reference fixes that without asking what
fraction of the waits are allowed to be pauses. What it buys is exact and no
more: the worst wait cannot raise the bar continuity judges it against. The
reference is one number for the performance, so a second long wait is still part
of the quartile that sets its own ratio, which is what makes a hesitation
repeating in every traversal visible rather than absorbed. Judging against the
median instead would fix it too, and break playing that alternates 400 and 1600
ms: the median is then 400, every slow wait reads as an interruption, and the
unevenness disappears out of the spread it belongs in. The pace is still the
median, because how fast the playing went is a question about the middle of it.

Stability changed statistic for a second reason. An interquartile range does not
answer to an individual wait at all, so a 125 ms wait among 500 ms playing was
invisible: rushing was not measured. A mean deviation answers to every wait,
though how loudly still depends on how much of the performance it is.

The floors follow from what each statistic needs. One wait is an interval rather
than a pace and two supply no center either one cannot dominate, so three is the
first count a median can set one aside at. Five is where a spread describes the
playing rather than one wait in it. Continuity asks for its five in one stretch
because it is a claim about playing that did not stop, and eight waits in one
run and in four runs of two are the same arithmetic and not the same evidence.

**Evidence.** The five recorded takes in `analysis/onset-grouping/`. Continuity
reads the comfortable take at 1.08x and the fast one with a pitch stumble at
1.09x, both unbroken; the rolled take at 2.38x and the out-of-phase one at
2.17x, both partly; and the uneven D major at 3.27x, broken. Stability reads
0.045 and 0.072 for the two comfortable takes, 0.093 for the uneven one, and
0.300 and 0.334 for the two dispersed ones.

**Consequences.** A recurring hesitation that repeats in every traversal is now
seen as a stall rather than pooled into the reference and hidden, so acquisition
calls that attempt interrupted instead of unestablished. Constants moved with
the statistics they read and are stated against the takes above rather than
carried over.

## A moment happens where the notes that realized it are centered

**Decision.** A moment's onset is the midpoint of the earliest and latest of the
observations that took an expected note's place. A repeat or an intrusion beside
the moment consumed no expected note, so it cannot move when the moment
happened. A substitution can, since a wrong pitch is still an attempt at that
moment. The same rule on the instrument's clock gives the moment's performance
onset, and one timed contributor is enough: its partner being untimed costs the
spread, not the moment.

```text
moment center = midpoint of the realizing notes
coordination  = latest realizing note - earliest
```

**Why.** The onset was the median of everything the moment consumed, which let a
note that realized nothing decide when the moment was: an extra note 500 ms
after the expected one moved its moment 500 ms late, and the wait after it 500
ms early. Pitch correctness, rhythmic placement, and coordination are separate
channels, and an intrusion belongs to the first two, not the third.

The midpoint rather than either edge. Taking the first note gives the timeline
to whichever hand anticipates and taking the last gives it to whichever lags,
while the midpoint leaves a moment with a neutral center and the full
disagreement in the coordination channel. Half a microsecond is discarded for an
odd spread, which is below the resolution of every characterized clock and,
unlike a fraction, is the same on every replay.

**Consequences.** Which of two identical pitches realized a moment is still
alignment's choice, and it takes the later one, reading the earlier as an extra
note played before the moment. The onset then follows the note it chose. Making
the earlier one the realization is a change to the tie-break in the traceback,
and it costs more than it buys: it also makes a restart match the abandoned
attempt and park the complete one as intrusions, turning every restart into an
interruption in the middle of a performance.

- **Timing.** Relating arrival times to expected times needs a tempo model that
  does not exist, and inventing one inside an aligner would hide it.
- **Evidence.** Turning an edit script into an outcome is a further step and a
  separate set of judgments.
- **Interpretation.** `AlignmentReading` counts repair-shaped patterns rather
  than naming intentions, and lives beside the correspondence rather than inside
  it.
