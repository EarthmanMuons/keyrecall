# Goal trajectories

> **Status:** characterization of the three production goals. Nothing blocks.
> The finite goals scoped material but did not steer realization; the
> realization envelope and the arriving term that followed are measured at the
> end, and the arriving term ships.

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

## 24-key fluency over a thousand slots

The same goal over 50 daily sittings of 20 slots, the same thirteen archetypes
and four seeds, with coverage split by family every ten sittings.

```console
dart run keyrecall_simulation:goal_horizon --scope keyFluency --seeds 4 \
  --sittings 50 --every 10 --jobs 5 --out key_fluency.jsonl
```

| Sittings | Slots | Covered | Scales of 24 | Arpeggios of 24 | Target-shaped | Arpeggio picks | Unguided |
| -------: | ----: | ------: | -----------: | --------------: | ------------: | -------------: | -------: |
|       10 |   193 |   0.012 |          0.3 |             0.2 |         0.017 |          0.536 |    0.499 |
|       20 |   389 |   0.053 |          1.4 |             1.1 |         0.041 |          0.515 |    0.684 |
|       30 |   586 |   0.108 |          3.2 |             1.9 |         0.057 |          0.498 |    0.754 |
|       40 |   785 |   0.192 |          5.9 |             3.3 |         0.058 |          0.534 |    0.788 |
|       50 |   984 |   0.280 |          8.2 |             5.2 |         0.061 |          0.557 |    0.820 |

The pick shares are over each interval of ten sittings ending at that row.
Nothing blocked and nothing was caught up; no run finished. A quarter was
covered in 28 of 52 runs, near slot 723, and half in 9, near slot 728. The
advanced and reliable archetypes reached 40 and 39 of 48; the uneven-handed and
coordination-limited ones covered none, as a goal made entirely of
hands-together targets would predict.

**It accumulates rather than stalls.** Coverage grows faster each interval, and
guidance moves the right way, cued picks falling from 14% to 4%. There is no
plateau followed by a burst.

**But target-shaped work stays near 6% of practice.** Hands together, two
octaves, and up and down each settle near 35% of picks, and their conjunction,
which is the only thing that covers a target, is a small fraction of that. The
envelope keeps practice on the way to the targets; nothing within it prefers
arriving. Goal emphasis weights a material, so the shape that would cover it is
one candidate among its many precursors.

**Arpeggios take more practice and cover less.** About half of every interval's
picks are arpeggios, yet 5.2 arpeggios are covered against 8.2 scales. The two
single-family archetypes cover only the family they are strong in, 19 and 0,
which is consistent with the family transfer question the placement work left
open.

The step this points to is the one the envelope deliberately did not take: a
goal term that prefers the realizations matching an uncovered target's shape,
not only the target's material.

## Arriving at the targets

A rank term, above retention, true for a candidate in the shape of a target the
goal has not covered yet, under guidance that target's coverage accepts. It
orders only what admission allowed. Measured against goal relevance reading
material alone, with the same census and a 30-sitting horizon, plus two frontier
variants for General technique, which names no target.

```console
dart run keyrecall_simulation:goal_trajectories --seeds 4 --sittings 10 \
  --slots 20 --jobs 5 --progress target
dart run keyrecall_simulation:goal_horizon --scope keyFluency --seeds 4 \
  --sittings 30 --every 10 --jobs 5 --progress target --out key_fluency.jsonl
```

The first version preferred the shape at any rung. Under Foundations, which
counts only what is played from memory, that pulled continuously cued target
shapes ahead of unguided precursors: target-shaped picks rose from 43% to 66%,
cued picks from 10% to 40%, and completion fell from 29 runs to 26. A shape the
goal cannot count is not arriving, and the term was narrowed to guidance the
coverage accepts.

The census, 200 slots:

| Scope            | Covered, material only | Arriving | Complete, material only | Arriving |
| ---------------- | ---------------------: | -------: | ----------------------: | -------: |
| Foundations      |                  0.767 |    0.781 |                   29/52 |    36/52 |
| 24-key fluency   |                  0.012 |    0.056 |                    0/52 |     0/52 |
| B flat, Found.   |                  0.817 |    0.904 |                   34/52 |    43/52 |
| D, 24-key        |                  0.250 |    0.375 |                    8/52 |    13/52 |
| D harmonic, Gen. |                  0.942 |    0.942 |                   49/52 |    49/52 |

Foundations finishes in fewer picks, 137 rather than 162 a run, with cued picks
at 11% rather than 10%. General technique and its focus are identical, as they
should be.

24-key fluency over 30 sittings, each row the ten sittings before it:

| Sittings | Covered, material only | Arriving | Target-shaped | Arriving | Materials | Arriving | Failed | Arriving |
| -------: | ---------------------: | -------: | ------------: | -------: | --------: | -------: | -----: | -------: |
|       10 |                  0.012 |    0.056 |         0.017 |    0.071 |      33.1 |     32.1 |  0.533 |    0.538 |
|       20 |                  0.053 |    0.224 |         0.041 |    0.156 |      38.2 |     37.5 |  0.498 |    0.503 |
|       30 |                  0.108 |    0.408 |         0.057 |    0.230 |      40.5 |     39.1 |  0.460 |    0.480 |

Coverage at 600 slots nearly quadruples. The first clean, unguided attempt that
is hands together, two octaves or more, and up and down comes near slot 127
rather than 166, in 47 runs rather than 40. Breadth, failure, the guidance mix,
and retrieval of established material, the share of materials demonstrated
earlier that were retrieved unguided again in the interval, 96% against 97%, are
unchanged. Arriving work does not crowd out keeping.

**It ships**, as scheduler model version `v1-7`.

### A frontier does not transfer to General technique

General technique names no destination, and its horizon shows the pattern a
destination would fix: over 30 sittings, the share of picks whose shape an
already demonstrated realization of the same material subsumes rises from 3% to
23%, while picks that are hands together, two octaves, and up and down stay near
5%. Breadth and retrieval are healthy; depth is not.

The scheduler's realization frontier was tried as the destination, and made
things worse both ways:

- **Above retention**, a step past the frontier outranked every other candidate,
  and a material met for the first time has none. General technique met 4
  materials in 200 slots rather than 36, one taking 47% of picks, and
  Foundations covered 13% rather than 77%.
- **Within the material ranking chose**, at the same rung, breadth held, but
  24-key coverage at 600 slots fell to 7%, Foundations completed in no run, and
  in General technique the deepest picks fell from 5% to 1% while subsumed
  shapes rose to 36%.

The reason is what that frontier is: a hand's demonstrated tempo and span on a
material. Stepping past it asks one hand for more of the same, faster or wider,
and never for hands together or a reversal. Two things follow. Which material a
slot serves must stay with ranking, which is what keeps breadth and retrieval;
and the destination General technique lacks is a frontier over shapes, not over
tempo. Both variants remain settings for comparison.

## Interpretation boundary

Synthetic players over ten short sittings. The census says what the goals ask
the scheduler to do and what it did; it does not say that a Foundations learner
held to one octave learns the keys faster, only that the goal as defined is not
what their practice was aimed at.
