# Calibrating a synthetic player from a sitting

- **Status:** Estimator implemented and validated against synthetic ground
  truth. One device sitting fitted, September 8, 2026.
- **Written:** September 7, 2026.
- **Scope:** Recovering `SyntheticPlayer` parameters from the attempts of one
  sitting, so a long-run simulation can ask what a learner who plays like this
  person would experience over months.

## Getting a sitting off a device

`exportTrajectory` writes `<stamp>-<profile>-attempts.json` beside the readable
report: schema version, profile, sitting and start time, then one entry per
attempt holding the exercise as presented, the outcome as measured, and the
familiarity known beforehand. The exercise and outcome use the journal's own
encodings rather than a calibration-specific interpretation of them, so the file
carries the journal's facts rather than a view of them, and a version it cannot
read is refused rather than guessed at.

The envelope's profile and timestamps are operational metadata for finding and
ordering exports. Nothing that fits a learner reads them: a fit sees the
exercise, the outcome and the familiarity, which is what makes it a statement
about playing rather than about who was playing.

**The derived profile is not exported.** A device sitting and a synthetic one
both go through `profileOf`, so there is one implementation of the profile
semantics and a difference between the two is a difference in the playing.

Familiarity comes from the immutable history rather than from learner state at
export time, which later attempts have moved. A material with an earlier record
exports as familiar; one without exports as **unknown** rather than unfamiliar,
because the journal begins when the profile does and says nothing about a
lifetime of playing before it. Nothing in the app emits unfamiliar today, so a
first device fit will drop the familiarity contrast, which is the correct answer
rather than a gap.

## What is fitted, and what is not

The player, never the scheduler. A fit reads what was asked and what happened,
which is all a journal records: requested tempo, achieved ratio, motor score,
completion, hand configuration, span, guidance, and whether the material had
been seen. It never reads guidance share, probe counts or family dose
engagement, because those are consequences of policy. The question a fit answers
is what kind of person this is; whether the scheduler treats that person well is
a separate question, asked afterwards by running them.

Candidates are compared by replaying **the exercises the sitting actually asked
for**, so every candidate answers the questions the person answered. Running
each candidate through the scheduler instead would fit the player and the policy
at once.

## Distributions, not attempts

A fit compares [`SittingProfile`]s: median achieved tempo and motor score by
hand configuration, the played-over-requested ratio, the share of attempts well
above what was asked, the completion rate, and performance on unseen material
against familiar. One human sitting is not deterministic, and a candidate that
matched it attempt by attempt would be fitting its noise.

Terms only one profile can answer are skipped rather than defaulted, so a
sitting with no hands-together work is not fitted on a coordination penalty it
never observed.

Whether the learner had met a material before is **provenance carried on the
attempt**, not position in the export. Somebody who played C major for years
before the app existed is not evidence about meeting new material, and inferring
novelty from first appearance in a sitting would say they were. An attempt that
does not know says so, and the whole familiarity contrast drops out rather than
being answered from the wrong fact.

The answer is an **ensemble**, closest first, with a range per parameter. A wide
range is a real answer: it says the sitting did not identify that parameter.

## What one sitting identifies

Validated by recovering players the estimator was not told about, over sixty
attempts:

```text
natural tempo     recovered to within about a fifth, in a wide band
compliance        recovered, including a learner who ignores the count-in
hand ordering     recovered: the weaker hand comes out weaker
absolute ability  not recovered, and biased low
```

The compliance observable is **per hand**, since natural tempo is per hand and
the scheduler need not ask each of them for the same spread of tempos. Pooling
them lets a difference between the hands arrive as a statement about compliance.
A hand whose requested tempo barely varied is absent from the profile rather
than reading as zero, because a sitting that never asked cannot answer.

**Compliance has to be fitted with the tempos, not after them.** The played
tempo is a geometric blend of the requested one and the natural one, so holding
one at a guess makes the fit report a statement about the guess: with compliance
fixed, a learner whose natural pace is 84bpm fits at 116, and with it free,
at 93. `SittingProfile.tempoSlope`, the slope of log played against log
requested, is what separates them, and without it the estimator cannot tell a
fast complier from a slow one who plays their own pace.

Absolute execution ability stays unidentified because it trades against natural
tempo: playing above your comfortable pace costs motor quality, so a stronger
player asked to sprint and a weaker one playing comfortably produce the same
score. Ordering survives that, levels do not.

## Sampled is not identified

A fit samples every parameter it is asked to vary, whether or not the sitting
contains anything that speaks to it, so an interval alone means nothing. Each
one is reported against what the sitting could see:

```text
identified            the observable is there, and the ensemble narrowed
weakly identified     narrowed, but not by much
not identified        as wide as it was drawn: sampled, nothing learned
not observed          the sitting never contained the observable
needs several sittings  nothing about one sitting could speak to it
```

The last two print no interval at all. A range nothing constrained is the prior
wearing an answer's clothes, and printing it would be the report arguing against
itself. A sitting with no hands-together work reports coordination ability as
**not observed**; the same fit on a sitting that has some reports it as
unconstrained or identified on its merits.

## Staging

```text
first sitting     tempos, per-hand ability, coordination, familiarity, compliance
                  and sprint probability, fitted together
across sittings   learning rate, from the change between them
```

Learning rate is deliberately last and separate. A single sitting cannot see
improvement at all, and fitting it alongside starting ability would let a fit
explain a weak sitting either way, which is exactly the collapse that made the
old synthetic beginner unable to learn.

## What this does not claim

An ensemble that reproduces a sitting's distributions is a **behavioral
surrogate**, not a measurement of a person. Two learners who play the same way
for an hour may differ in every way that matters over a year, and the ranges are
the honest expression of that.

## The first device sitting

Thirty-five attempts, one sitting, single hands and coordination work, tempos
from 58 to 132. `bin/calibrate.dart` reads the export and prints the sitting,
the fit and what the sitting could speak to.

```text
== the sitting
   played     right 130, left 121, together 114
   motor      right 1.00, left 1.00, together 1.00
   slope      right 0.28, left 0.37, together 0.43
   ratio      1.05
   sprints    26%
   completed  100%
```

```text
== the fit
35 attempts, closest of 40 at 0.130
  naturalTempoRight     110 to 167          weakly identified
  naturalTempoLeft      96 to 186           weakly identified
  rightHandAbility      0.53 to 2.34        weakly identified
  leftHandAbility       0.35 to 2.46        weakly identified
  handsTogetherAbility  0.39 to 1.87        weakly identified
  familiarity           -                   not observed
  tempoCompliance       0.23 to 0.74        weakly identified
  sprintProbability     -                   not identified
```

Familiarity reads as not observed, exactly as the export promised: the sitting
opens on material with no earlier record, so nothing knows whether the person
had played it before.

### Two things the sitting says about the model rather than the player

**Measurement saturates, so motor score carries almost no information.**
Continuity and temporal stability are 1.00 on thirty-one of thirty-five
attempts, and completion is a hundred per cent. The closest ensemble members
reproduce the tempos but land at 0.70 to 0.93 motor and eighty-six per cent
completion, because `SyntheticPlayer` cannot express somebody who never has a
bad attempt: completion is capped by a nine-in-ten draw and motor quality
carries noise on every attempt. **The fit is therefore working almost entirely
from tempo**, and the ability intervals are wide for that reason rather than
because the sitting was short.

**Compliance is low and the slope says so.** The played tempo follows the
requested one with a slope of 0.28 to 0.43, and the ratio distribution is
bimodal rather than centred: about one in four attempts is played well above
what was asked, and the rest near it. The person plays at roughly 120 to 135
whatever the count-in says, which is what the compliance interval of 0.23 to
0.74 is reporting. Sprint probability is unidentified because a sprint and low
compliance produce the same observable here.

That is the first real finding of the calibration work, and it is about the
player model: **a learner who plays this cleanly is outside what the synthetic
player can express**, and closing that gap is a change to the player rather than
to the estimator.
