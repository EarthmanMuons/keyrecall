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

## What alignment deliberately does not do

- **Timing.** Relating arrival times to expected times needs a tempo model that
  does not exist, and inventing one inside an aligner would hide it.
- **Evidence.** Turning an edit script into an outcome is a further step and a
  separate set of judgments.
- **Interpretation.** `AlignmentReading` counts repair-shaped patterns rather
  than naming intentions, and lives beside the correspondence rather than inside
  it.
