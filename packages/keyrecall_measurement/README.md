# keyrecall_measurement

Turns an aligned performance into what was observed, and into the outcome the
learner model consumes.

```text
Alignment                  correspondence, from pitch alone
    +
matched-note onsets        timing, now interpretable
    ↓
PerformanceMeasurement     factual observations
    ↓
Outcome                    model-facing semantics
```

Alignment decides which played note corresponds to which expected one, using
pitch and nothing else. Once that is settled, the timestamps of the matched
notes are properties of the performance rather than further evidence about
correspondence, so measurement is free to read them. The same notes played at a
different speed align identically and measure differently, and there is a test
that says so.

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

## Timing

Two scores that must not collapse into one:

- **temporal stability** reacts to spread across the traversal;
- **continuity** reacts to a single interruption.

Both use robust statistics so those stay independent, and the thresholds come
from real playing rather than round numbers; see
[`analysis/timing-calibration/`](../../analysis/timing-calibration/README.md).
They are provisional, and they are engineering calibration rather than a
pedagogical boundary.

## Availability

Measurement says what the observation model read, never whether the attempt was
any good. Fifty wrong notes measure fine, and every exercise V1 generates can be
read, so nothing a learner plays goes unmeasured. Otherwise the worst
performances would go missing exactly where the evidence is strongest.

What can be absent is a channel rather than a measurement. Coordination needs a
moment where both hands corresponded to something that arrived, and where no
moment did, it is absent rather than zero: an attempt nobody could read for
togetherness has not been read as ragged.
