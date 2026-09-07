# Calibrating a synthetic player from a sitting

- **Status:** Estimator implemented and validated against synthetic ground
  truth. **No device sitting has been fitted yet.**
- **Written:** September 7, 2026.
- **Scope:** Recovering `SyntheticPlayer` parameters from the attempts of one
  sitting, so a long-run simulation can ask what a learner who plays like this
  person would experience over months.

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
