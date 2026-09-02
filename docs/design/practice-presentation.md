# Practice presentation

- **Status:** Current. The learner-facing contract for an attempt and its
  review.
- **Written:** September 2, 2026

## During an attempt

`PerformanceFeedback` describes what the learner sees of their playing while
they play: nothing, a neutral echo, or an evaluative display. Prospective pitch
and motor cues and tempo support remain separate channels because they change
different demands.

The practice screen presents one exercise. Guidance changes what information is
placed on its staff and keyboard rather than replacing the task or instrument
with a different screen.

The neutral echo lights the keys that are currently held on the keyboard
diagram, at Ready and throughout the attempt. The staff is static until the
traversal starts. From then on it lights the note each hand has reached, for
as long as that key is held.

The staff locator is an orientation aid rather than a reading of the
performance, and the two are deliberately not the same thing. Each hand
travels its own line, so one hand's mistake leaves the other's highlight
alone. A hand takes an arrival that is the note it expects; failing that, one
that uniquely matches either of the next two notes, so a skipped note costs a
note rather than the rest of the run; failing that, one in another octave, so
a scale played an octave out still travels. Two hands are offered every
arrival, since the input stream does not say which hand played it, and a hand
that matches exactly takes it before one that matches only by octave.

What the tolerances never do is light anything. A notehead lights only while
the key it is written for is down, so the staff never stands for a note that
was not played. Measurement is unaffected: it reads the same arrivals
strictly and keeps every departure, including the octave errors and omissions
the locator travels through.

## After an attempt

The review has three outputs:

```text
attempt diagnosis   what happened
attempt summary     what the major measurements looked like
progress evidence   what this attempt established over time, if anything
```

`AttemptDiagnosis` selects one useful true interpretation. It prioritizes the
principal fault rather than listing every departure, and may name a count or
traversal location when the measurement supports one.

The summary reports observations of this performance:

- **Notes:** how closely the played notes matched the exercise;
- **Flow:** whether the traversal continued without stopping or breaking up;
- **Pulse:** how evenly the notes were spaced;
- **Coordination:** for a measured hands-together attempt, how closely the hands
  arrived together; and
- **Tempo:** achieved playing speed against the requested target.

These values are not learner-state deltas or overall mastery scores. The entire
summary is one tap target. It opens a bottom sheet that explains only the
dimensions visible for this attempt in plain musical language and states that
they describe the attempt rather than the learner's overall skill.

When the transient performance reading is still available, Details locates the
attempt's evidence along its traversal. Pulse and hands-together Coordination
use centered traces. Notes and Flow remain discrete departures and gaps, and
Tempo remains an overall achieved-versus-target statement. The reading and its
traces are discarded with the review rather than persisted.

Note departures are named with the exercise realization's musical spelling and
a traversal landmark. Insertions name the observed note and its expected
neighbors. Flow names the expected note after the longest measured break. Raw
realization positions remain display coordinates and are not learner-facing.

Opening Details is recorded separately from the automatically shown review as a
detailed diagnostic feedback exposure. Reopening it does not create another
exposure for the same attempt.

## Progress evidence

Progress statements come from named events with explicit truth conditions. The
current events are:

- first clean completion;
- first independent completion, for a completed unguided attempt; and
- repeated reliability, established when the last three comparable attempts were
  clean.

Comparable attempts have the same material, pattern, and execution conditions,
including tempo. Guidance may vary. An event is emitted only when its condition
first becomes true, so most reviews have no progress statement.

All events established by an attempt are retained. When events coincide, the
review combines them into one sentence rather than discarding one or stacking
notices. The rendered events are recorded in the companion feedback exposure
stream described in [The five data products](data-products.md).
