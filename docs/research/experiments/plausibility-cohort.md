# Plausibility cohort

> **Status:** cohort built, frozen, and baselined under v1-14 on five paired
> seeds. Behavior is coherent with its parameters, ability dominates nearly
> everything, and three of seven dimensions are close to inert over the demo
> window. The weakest profiles are unstable from pair to pair, and recovery
> holds about a third of decisions for every profile throughout the run. No
> policy has been compared on it yet.

The archetypes were built to expose failures, and the asymmetric ones exaggerate
the difference between families. This cohort asks a different question: does a
scheduler behavior hold across moderately varied players, or only at the
extremes? It is a sensitivity cohort, not a sample. The ranges below are
assumptions, and no population distribution stands behind them. The thirteen
archetypes stay as regression and stress cases.

## Construction

24 players around the developing archetype, drawn as the most spread of 200
Latin hypercubes from a fixed seed, so each of 24 strata on every dimension
holds exactly one player. A test pins the drawn parameters.

| Dimension        | Range                                                              | Developing    |
| ---------------- | ------------------------------------------------------------------ | ------------- |
| Ability          | hands shifted by -0.5 to +0.5 logits; tempo and familiarity follow | 0             |
| Family asymmetry | up to 0.3 logits to one family and away from the other             | 0             |
| Noise            | 0.07 to 0.14                                                       | 0.10          |
| Durability       | familiarity half-life 60 to 720 days, execution twice that         | no forgetting |
| Learning rate    | 0.005 to 0.02                                                      | 0.01          |
| Tempo            | natural pace 10% either way beyond what ability sets               | 84 and 76     |
| Tempo compliance | 0.55 to 0.85                                                       | 0.7           |

Ability moves natural tempo and scale familiarity with it, since faster and more
familiar go together in every archetype; the other dimensions vary
independently. Asymmetry tops out at a 0.6-logit gap against 2.0 for the
asymmetric archetypes. Cross-family transfer is not a dimension: the player
model has none, by design, so varying it would be a model change rather than a
parameter.

```console
dart run keyrecall_simulation:cohort_baseline
```

## Baseline under v1-14

Each player on the five seed pairs (0:100 to 4:104), 120 trajectories. Per
player, medians across pairs:

| Behavior                   | Across the cohort | Leading dimension (rank correlation) |
| -------------------------- | ----------------- | ------------------------------------ |
| Attempts started           | 0.65 to 0.74      | not computed                         |
| Attempts completed         | 0.44 to 0.65      | ability (+0.83)                      |
| Pitch integrity, completed | 0.90 to 0.95      | ability (+0.64), learning (+0.62)    |
| Motor score, timed         | 0.48 to 0.75      | learning (+0.75), ability (+0.55)    |
| Managed share of timed     | 0.46 to 0.90      | ability (+0.78)                      |
| Chosen tempo ratio         | 1.01 to 1.04      | tempo (+0.54), compliance (+0.51)    |
| Guided attempts            | 0.40 to 0.53      | ability (-0.92)                      |
| Decisions in recovery      | 0.29 to 0.38      | ability (-0.86)                      |
| Scales covered, of 48      | 11 to 48          | ability (+0.90)                      |
| Arpeggios covered, of 24   | 5 to 16           | ability (+0.68), asymmetry (-0.62)   |

Over the run, guidance falls by 13 to 23 points from the first third to the last
for every player, and the managed share of timed attempts rises by up to 50
points, most for the weakest players. Both are what learning should look like.

Three things in it need care before any policy is compared:

- **Three dimensions barely matter.** Durability and noise correlate with no
  behavior beyond 0.35, and tempo compliance only with the chosen tempo ratio,
  which stays between 1.01 and 1.04. Near-daily sessions over four months give a
  half-life of two months or more little to act on, and the scheduler sets tempo
  near the player's own pace, so compliance has little to correct. The cohort
  does not test retention under forgetting; that needs shorter half-lives or
  calendar gaps.
- **The weakest profiles are unstable across pairs.** Scale coverage for the
  player with the lowest effective scale ability ran 3, 18, 11, 10, and 28 over
  its five pairs, and in the pair with 3 it covered all 24 arpeggios. Another
  weak, balanced player ran from 8 to 35. Stronger players vary by a few scales.
  At the weak end, which trajectory a player falls into matters more than its
  parameters, so comparisons there need paired seeds and per-pair reporting.
- **Recovery holds a third of decisions for everyone, and does not decline.**
  From 29% for the strongest profile to 38% for the weakest, with the first and
  last thirds within a few points of each other, while a quarter to a third of
  attempts are never started. This may be the challenge band holding success
  near its target as the learner improves, which would be by design, or a
  recovery loop. These runs do not tell the two apart.

Arpeggio coverage under v1-14 stays at 16 of 24 or below even for players who
cover all 48 scales, which matches the deferral the
[allocation counterfactual](allocation-counterfactual.md) found.

## What it does not establish

That any of these players resembles a real learner. The ranges were chosen
before the baseline ran and were not adjusted to it; the one device-fitted
player, `reliableSelfPaced`, is a single session, not a distribution. 24
profiles on shared seeds are 24 points in the model's assumed space, not 24
independent observations.
