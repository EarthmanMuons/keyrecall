# Fluency tempo policies

> **Status:** characterization. `TempoQualification.v1` and the three rung
> policies exist in `keyrecall_practice`. **No report rule promoted.**

Which rule the fluency report's typical-tempo chart should read, measured on
histories the production loop produced rather than argued from the design.

## What was run

`keyrecall_simulation/bin/fluency_tempo.dart`: twelve seeds of four archetypes
(`true_beginner`, `developing`, `intermediate`, `uneven_hands`), eight weeks of
three sittings of twenty slots each, through `PracticeSession` over the 48-scale
catalog. Each journal is projected to `FluencyHistory`, and every rule reads the
same projection at one octave, parallel motion, per hand configuration:

```text
pooled     every rung in one median, a baseline and not a candidate
unguided   rung 2 only
best       each week, the most independent rung with a minimum of
           qualifying observations, run at minimum 3 and minimum 1
```

Every cell reports the share of seeds with a value, the mean median, and the
mean number of observations behind it.

## Findings

**The guidance rule barely matters.** The scheduler reaches the unguided rung
quickly, so `best` reads rung 2 in almost every week that has a value. Pooled
and unguided differ only in the first two or three weeks, and only for the
weakest players:

```text
true_beginner, right hand, share of seeds with a value
week          1     2     3     4     5
pooled       50%   67%   83%   83%  100%
unguided      0%   17%   50%   83%  100%
best (min 1) 50%   67%   83%   83%  100%   rungs 0/3/3, 2/2/4, 6/2/2, ...
```

So "the most independent rung with evidence" fills the early weeks without
pooling, but those weeks rest on one or two observations.

**An evidence minimum costs more than the guidance rule.** At a minimum of three
observations, `best` leaves weeks empty that unguided fills, because a hand
configuration rarely collects three qualifying attempts in a week:

```text
developing, left hand, share of seeds with a value
week          3     4     5     6     7     8
unguided     58%   92%   92%   83%  100%   75%
best (min 3) 42%   33%   50%   67%   50%   42%
```

**Most of the dead space comes from qualification, not guidance.** Observations
exist; they do not clear the motor bar:

```text
one-octave observations per seed over eight weeks, and how many qualified
                     right          left          together
true_beginner     96.3 / 33.3    19.8 / 0.1    19.4 / 0.0
uneven_hands      73.5 / 73.5    23.3 / 2.3    41.5 / 27.8
```

A true beginner's left hand and hands together show nothing for eight weeks
under any guidance rule, which is exactly the learner a development chart is
meant to encourage.

## Caveats

Synthetic players invent their own motor scores and tempo behavior; see
[`player-calibration.md`](player-calibration.md). The near-zero qualifying rate
for a beginner's left hand is partly an artifact of that model, and the
direction of the result, not its size, is what carries over. Three sittings of
twenty attempts a week is one schedule among many.

## What it leaves open

The chart's rule is less a choice between guidance policies than a choice
between two questions:

- **demonstrated pace**, qualified attempts only, which is honest and empty for
  weak hands; or
- **playing pace**, every completed attempt with a measured pace, which always
  has a value and says nothing about whether the playing was controlled.

Whichever is chosen, a week should be read from one rung, and a value resting on
one or two observations needs a presentation that says so.
