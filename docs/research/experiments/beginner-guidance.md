# Beginner guidance

> **Status:** diagnosis. The true beginner stays supported because it fails, not
> because the ladder withholds independent work; what keeps it from covering
> Foundations is the timing it plays with. No policy is changed.

The goal census found the true-beginner archetype, placed as a beginner,
covering almost none of Foundations in 200 slots, with most of its attempts cued
or previewed. A learner can stay supported for three reasons, and each calls for
something different:

1. the unguided realization is not eligible or not admitted;
2. it is admitted and loses the ranking;
3. it is chosen and fails.

## Method

The true beginner under Foundations over ten daily sittings of twenty slots,
four seeds. Each attempt records its rung, how it was admitted, how it went,
and, for a supported attempt, what became of the unguided realization of the
same material and hand.

```console
dart run keyrecall_simulation:guidance_ladder --player true_beginner \
  --scope foundations --seeds 4
```

## Results

| Half          | Cued | Previewed, retrieved | Unguided, retrieved | Retrieved and meeting coverage |
| ------------- | ---: | -------------------: | ------------------: | -----------------------------: |
| Sittings 1-5  |  131 |             27 / 115 |              6 / 27 |                              2 |
| Sittings 6-10 |   98 |             45 / 113 |             20 / 66 |                              3 |

For a supported attempt, the unguided version of it was refused by recovery
after a failure 215 times, fell outside the challenge band 154 times, and was
refused for band and introduction tempo together 75 times. It was admitted and
lost the ranking 13 times. Every unguided attempt that did happen was admitted
through a bypass, a guidance probe or execution progression; none came through
the ordinary band, where this learner's predicted success of 0.03 to 0.29 never
reaches the floor of 0.60.

## What it shows

**Not eligibility, and not the ranking.** Unguided work is offered through the
probes built for exactly this learner, 93 times in 550 attempts, and it grows as
recall improves: 27 in the first half, 66 in the second. It almost never loses a
ranking it enters.

**The learner fails, and the ladder answers that.** Unguided retrieval succeeds
28% of the time and previewed 32%, rising to 40% in the second half. Recovery
stepping down after a failure is the largest single reason a supported rung was
chosen, and is what it is for.

**Coverage waits on timing.** Of 26 unguided retrievals, 17 had the pitch
accuracy coverage asks for and 4 the timing, and 1 had both. This archetype's
mean motor score moves from 0.19 to 0.23 over ten sittings, because its
execution learns slowly, and coverage asks for 0.5. No change to the ladder
would cover Foundations for it inside 200 slots.

So the question the census raised is not a defect in guidance. It is two
calibration questions that synthetic players cannot answer: whether a real
beginner's timing moves this slowly, and whether 0.5 is the timing a from-memory
requirement should ask of someone at the start.

## Interpretation boundary

One archetype, whose abilities and learning rates are chosen rather than fitted.
The same trace pointed at real sittings is the test that would matter.
