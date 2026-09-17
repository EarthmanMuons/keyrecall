# Fluency tempo policies

> **Status:** characterization. **Promoted:** demonstrated tempo keeps
> `TempoQualification.v1`, and the trend chart reads playing pace, unqualified,
> from the most independent rung with one observation.

Which rule the fluency report's tempo trend chart should read, measured on
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

## The rule promoted

The chart and the key map's tempo lens answer different questions, so they no
longer share a rule. Demonstrated tempo stays qualified, because it is a
capability claim. The trend reads **playing pace**: every completed attempt with
a measured pace, at the pace played, from the most independent rung with one
observation. Rerun with that rule beside the others:

```text
share of seeds with a value, mean pace, mean observations
                          week 1           week 4           week 8
true_beginner, left
  best (min 3)             0%               0%               0%
  playing                100%  59 n=2.1    92%  59 n=1.5    67%  59 n=1.9
true_beginner, together
  best (min 3)             0%               0%               0%
  playing                 33%  58 n=1.0   100%  58 n=1.8   100%  57 n=4.7
uneven_hands, right
  best (min 3)           100%  80 n=6.8   100% 146 n=11.1   92% 163 n=5.8
  playing                100%  99 n=6.6   100% 148 n=11.1  100% 165 n=5.4
```

Two consequences to present honestly. A beginner's weaker hand now has a line,
and it is flat just under 60, the slowest tempo candidate generation offers, so
the chart shows a hand that has not moved rather than showing nothing. And
playing pace is uncapped, so a player who runs ahead of the request reads faster
than they demonstrated, as the uneven player's right hand does in its first
week.

Weeks stay sparse. Most beginner weeks rest on one or two attempts, which is why
the count travels with each value.
