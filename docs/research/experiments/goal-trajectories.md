# Goal trajectories

> **Status:** characterization of the three production goals. Nothing blocks.
> The finite goals scoped material but did not steer realization; the
> realization envelope that followed is measured at the end.

The altered-form census asked whether narrow scopes can finish. This one asks
what the goals KeyRecall offers actually do to practice: General technique,
Foundations, and 24-key fluency, each also with a narrow focus inside it.

## Method

Thirteen archetypes, four seeds, ten daily sittings of up to twenty slots, each
sitting a fresh practice session over the same store, as the app opens one. A
sitting that is caught up or blocked ends early and the next day carries on.
Coverage is read from the journal against the goal, as the product reads it.

| Scope                       | Plan                                                      |
| --------------------------- | --------------------------------------------------------- |
| `general`                   | General technique                                         |
| `foundations`               | Foundations                                               |
| `keyFluency`                | 24-key fluency, version 2                                 |
| `generalFocusedOnDHarmonic` | General technique, exclusive focus on D harmonic minor    |
| `foundationsFocusedOnBFlat` | Foundations, exclusive focus on B flat major              |
| `keyFluencyFocusedOnD`      | 24-key fluency, exclusive focus on D major, both families |

```console
dart run keyrecall_simulation:goal_trajectories --seeds 4 --sittings 10 --slots 20 --jobs 8
```

A pick is **target-shaped** when its hands, span, and direction match one of the
goal's target requirements; guidance is not part of the shape.

## Results

52 runs per scope, about 193 picks per unfocused run. Slots are means over the
runs that reached them, with that count.

| Scope          | Covered | Complete | Half covered | Target-shaped | Hands together | Two octaves | Arpeggio |
| -------------- | ------: | -------: | -----------: | ------------: | -------------: | ----------: | -------: |
| general        |       - |        - |            - |             - |          0.210 |       0.285 |    0.477 |
| foundations    |   0.441 |     0/52 |     151 (26) |         0.168 |          0.375 |       0.456 |    0.000 |
| keyFluency     |   0.009 |     0/52 |            - |         0.019 |          0.226 |       0.253 |    0.577 |
| D harmonic     |   0.942 |    49/52 |      30 (49) |         0.475 |          0.317 |       0.344 |    0.000 |
| B flat, Found. |   0.837 |    36/52 |      21 (51) |         0.339 |          0.174 |       0.398 |    0.000 |
| D, 24-key      |   0.154 |     4/52 |      38 (12) |         0.018 |          0.188 |       0.279 |    0.514 |

No run in any scope blocked. General technique met 36 materials in 193 picks,
with no material above 7% of them, arpeggios at about half, and altered forms
first appearing near slot 74 in 39 of 52 runs.

## What it shows

**The finite goals narrow material and not realization.** A goal's requirements
name a shape, and nothing in selection reads it: goal emphasis weights a
material, so every realization of a target material is equally wanted. Under
Foundations, whose every target is one hand over one octave up and down, 46% of
picks were two octaves and 38% hands together, work the goal neither asks for
nor needs as preparation. Only 17% of picks had a target's shape. Under 24-key
fluency the scheduler chose almost exactly what it chose under General
technique, minus the altered forms: for the true beginner the two rows are
identical.

**So coverage is slow, and not for want of ability.** No Foundations run
finished in 200 slots. The advanced archetype reached 79% while spending 55% of
its picks on two octaves. Coverage arrives as a long tail rather than steadily,
which is what a scheduler that has moved past one octave would produce, though
the census does not trace which targets were left.

**A true beginner covers nothing in Foundations in 200 slots.** 41% of its picks
are continuously cued and 17% unguided, so from-memory coverage has almost no
attempts to come from. That is the cold-start regime the roadmap describes, seen
through a goal, and a question for the placement work rather than for the goal
definitions.

**24-key fluency is a long goal, as expected.** Target-shaped attempts first
appear near slot 107, hands together over two octaves being several
prerequisites away, and coverage reaches 1%. Arpeggios take 58% of picks and
appear in the first two slots; that share is a property of the catalog's
arpeggio candidates under the information term, and General shows the same.

**Narrow focuses finish.** D harmonic minor completes in 49 of 52 runs by about
slot 30, with 53% of picks spent on its declared support. B flat major under
Foundations completes in 36. D major as scale and arpeggio under 24-key fluency
completes in only 4, for the same reason the whole goal is slow.

## After the realization envelope

A finite goal now offers a material only in the shapes on the declared way to
its targets: a span no wider, ascending before up and down, and each hand alone
before both where the material requires it. The same census, rerun:

| Foundations         | Before | After |
| ------------------- | -----: | ----: |
| Hands together      |  0.375 | 0.000 |
| Two octaves         |  0.456 | 0.000 |
| Target-shaped       |  0.168 | 0.429 |
| Covered             |  0.441 | 0.762 |
| Complete            |   0/52 | 29/52 |
| Fully covered, slot |      - |   139 |

The advanced, reliable, compliant, coordination-limited, and forgetful
archetypes complete Foundations in every seed; the intermediate in three of
four. What remains slow is the learner rather than the route: the true beginner
covers 1%, the scale-weak arpeggio player 26%, and the uneven-handed player
half, the first two with most of their picks cued or previewed. The B flat focus
completes in 34 runs rather than 36 and reaches full coverage by slot 31 rather
than 54.

General technique is unchanged, as it should be, since it names no shape. 24-key
fluency is unchanged too: removing four-octave arpeggios leaves every precursor
of its hands-together, two-octave targets in place, and 200 slots is short for
48 of them. Whether it reaches its targets steadily is a question for a longer
horizon.

The census also ran in 920 seconds rather than 1928, on five workers rather than
nine; per-decision cost is dominated by the number of candidates scored, which
the envelope shrinks for a finite goal, and grows only mildly with history,
about 115 ms a decision at 50 slots and 200 ms at 400.

## Interpretation boundary

Synthetic players over ten short sittings. The census says what the goals ask
the scheduler to do and what it did; it does not say that a Foundations learner
held to one octave learns the keys faster, only that the goal as defined is not
what their practice was aimed at.
