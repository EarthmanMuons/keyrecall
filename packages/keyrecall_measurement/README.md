# keyrecall_measurement

Turns an aligned performance into what was observed, and into the outcome the
learner model consumes.

```text
Alignment                  correspondence, settled first
    +
matched-note onsets        timing, now interpretable
    ↓
TimingEvidence             the waits, and which of them could be judged
    ↓
PerformanceMeasurement     factual observations
    ↓
Outcome                    model-facing semantics
```

Alignment decides which played note corresponds to which expected one. Once that
is settled, the timestamps of the matched notes are properties of the
performance rather than further evidence about correspondence, so measurement is
free to read them. Every channel here is read after correspondence is fixed, and
changing how the same notes sat in time does not move a pitch-derived channel.

Correspondence itself is mostly a question about pitch, and not entirely.
Grouping the arrivals into performed moments is part of settling it, and where
two readings of the same pitches are otherwise equally good, timing contributes
a bounded preference between them; see
[`keyrecall_alignment`](../keyrecall_alignment/README.md). Two-hand material is
where that shows: a lone arrival of a pitch both a moment's right hand and the
next moment's left hand ask for belongs to whichever it arrived beside, and the
channels then read the correspondence that was chosen. So the guarantee is about
timing not reaching a settled correspondence, not about ambiguous correspondence
being immune to timing.

## What the channels mean

An octave slip is the clearest case, because it separates four things that are
easy to conflate:

```text
topologyAccuracy    unaffected     the scale degree was right
materialRetrieval   unaffected     the material did appear
retrieval           unaffected     factual scale memory is about the degrees
pitchIntegrity      reduced        the sounded pitch was wrong
```

There is no register competency, and inventing one because the measurement
system can see register would be letting the sensors write the ontology.

`retrieval` is categorical and strict: any wrong degree, any missing note, any
extra note that is not a repeat, and it failed. A threshold would make two
nearly identical performances move the memory clock in opposite directions, and
the continuous channels already carry how well it went. A repaired attempt is
therefore complete, high in `materialRetrieval`, and a retrieval failure, which
is the supported-practice reading we wanted.

A repeat is exempt from that, because replaying the note just played is
producing the right material twice rather than producing the wrong material. The
classification is structural, not attributed: what caused it, a double trigger,
a bounced finger, a deliberate reiteration, is not observable here. It still
costs timing if it delayed the note that followed.

Each contiguous run of extra notes is read once, against the moments on either
side of it rather than the note edits next to it. A note struck four times is
four repeats rather than one repeat and three intrusions, and a moment is one
event however many hands realize it, so repeating the left hand's note is a
repeat whichever hand the traceback left adjacent. Every note in a run is read
on its own, which leaves a foreign note foreign however many repetitions
surround it.

## Timing

Two scores that must not collapse into one:

- **temporal stability** reacts to spread across the traversal;
- **continuity** reacts to a single interruption.

Both use robust statistics so those stay independent, and the thresholds come
from real playing rather than round numbers; see
[`analysis/timing-calibration/`](../../analysis/timing-calibration/README.md).
They are provisional, and they are engineering calibration rather than a
pedagogical boundary.

Robust against one anomalous wait needs enough waits for one of them to be the
anomaly. `TimingEvidence` is where that is decided, once, for everything that
reads timing: below five waits the interpolated quartiles include the extremes
they exist to ignore, so the performance establishes no baseline and both scores
are absent. Three notes at 0, 500, and 60000 ms would otherwise read as badly
broken and totally unsteady at the same time, from a single wait measured
against itself.

## Availability

Measurement says what the observation model read, never whether the attempt was
any good. Fifty wrong notes measure fine, and every exercise V1 generates can be
read, so nothing a learner plays goes unmeasured. Otherwise the worst
performances would go missing exactly where the evidence is strongest.

What can be absent is a channel rather than a measurement. Coordination needs a
moment where both hands corresponded to something that arrived, and where no
moment did, it is absent rather than zero: an attempt nobody could read for
togetherness has not been read as ragged. Continuity and temporal stability are
absent the same way, and for the same reason, when the playing supplied too few
waits to judge one against the others.

Achieved tempo is the exception, and deliberately: its raw field reports an
unobserved pace as zero, because a ratio has no null to report.
`measuredTempoRatio` is that sentinel's one interpretation, and every reader
asking what pace was observed goes through it, so a performance too short to
time enters no tempo statistic rather than entering it as a stop.

An absent channel is absent all the way through. `Outcome` carries the null, the
evidence weights leave the channel out, the update path leaves its state
untouched, and the record omits it rather than writing a zero, so a channel
nothing observed cannot accumulate into evidence that the learner was bad at it.
