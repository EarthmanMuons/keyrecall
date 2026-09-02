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

## Progress evidence

Progress statements come from named events with explicit truth conditions. The
current events are:

- first clean completion;
- first independent completion; and
- repeated reliability, established when the last three comparable attempts were
  clean.

Comparable attempts have the same material, pattern, and execution conditions,
including tempo. Guidance may vary. An event is emitted only when its condition
first becomes true, so most reviews have no progress statement.

All events established by an attempt are retained. When events coincide, the
review combines them into one sentence rather than discarding one or stacking
notices. The rendered events are recorded in the companion feedback exposure
stream described in [The five data products](data-products.md).
