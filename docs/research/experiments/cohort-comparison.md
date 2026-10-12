# Cohort comparison

> **Status:** counterfactual on the frozen
> [plausibility cohort](plausibility-cohort.md), 24 players on five paired
> seeds, three arms, 360 trajectories. Allocation removes prolonged deferral for
> every player and raises coverage of both families, at a consistent cost to the
> scheduler's estimate of covered scales' retrieval. Follow-through adds faster
> and broader managed execution and less recovery, at a further retrieval and
> switching cost, and on this cohort most follow-throughs go to scale strands,
> which convert least. Nothing is promoted; the scheduler stays at v1-14.

## What was run

v1-14, allocation at `k` of 2 with protection floor 0.60, and the same
allocation with [early follow-through](follow-through.md), on every cohort
player and the five seed pairs (0:100 to 4:104). The v1-14 arm reproduces the
frozen cohort baseline exactly. Three comparisons were declared before the runs:
allocation against v1-14, follow-through added against allocation alone, and the
combined policy against v1-14. Each is reported as paired differences per player
and seed pair, summarized by ability band (the cohort's lower, middle, and upper
thirds on its ability coordinate, 40 pairs each).

```console
dart run keyrecall_simulation:cohort_comparison
```

Retrieval appears twice. Estimated retrieval is the scheduler's own health
estimate, across all in-scope material or across covered material. Observed
retrieval is what the player's retrieval tests outside recovery did. Each policy
chooses what to test, at which rung, after how much practice, so observed
success is a policy-conditioned observation, not a measure of learning; and the
[recovery audit](recovery-episodes.md) showed the synthetic player's retrieval
barely responds to practice in any case.

## Allocation against v1-14

Pairs better and worse, then the median paired difference:

| Outcome                        | Low           | Middle        | High          |
| ------------------------------ | ------------- | ------------- | ------------- |
| Scales covered                 | 38/2, +7      | 33/2, +2      | 20/0, +0.5    |
| Arpeggios covered              | 38/1, +4.5    | 30/3, +3      | 25/6, +1      |
| Worst missed run, scale        | 40/0, -590    | 40/0, -352    | 40/0, -252    |
| Worst missed run, arpeggio     | 40/0, -672    | 40/0, -655    | 39/1, -741    |
| Arpeggio strands managed       | 39/1, +7      | 34/6, +4      | 23/13, +1     |
| Scale strands managed          | 28/8, +6.5    | 21/18, +1.5   | 16/24, -3     |
| Est. retrieval, all scales     | 35/5, +0.050  | 30/10, +0.030 | 37/3, +0.031  |
| Est. retrieval, covered scales | 0/40, -0.053  | 3/37, -0.027  | 3/37, -0.013  |
| Fading share, scales           | 1/39, +0.087  | 3/37, +0.054  | 8/32, +0.014  |
| Observed retrieval success     | 6/34, -0.025  | 14/26, -0.007 | 16/24, -0.003 |
| Switching                      | 13/27, +0.009 | 6/34, +0.018  | 9/31, +0.015  |

Allocation took a median of 120 slots a run (at most 181). Of what it displaced,
67% was uncovered work, 22% healthy covered work, and 11% covered work that was
due. Recovery's share of attempts did not change.

## Follow-through added to allocation

| Outcome                              | Low           | Middle        | High         |
| ------------------------------------ | ------------- | ------------- | ------------ |
| Arpeggio strands managed             | 17/13, +0     | 25/13, +2     | 30/5, +2.5   |
| Attempts to managed, arpeggio median | 26/14, -78.5  | 37/3, -84.5   | 40/0, -79    |
| Scale strands managed                | 24/14, +1     | 28/11, +8.5   | 31/8, +8     |
| Worst missed run, arpeggio           | 13/26, +11    | 21/19, -4.5   | 16/23, +5    |
| Est. retrieval, all scales           | 9/31, -0.015  | 9/31, -0.022  | 4/36, -0.026 |
| Est. retrieval, covered scales       | 12/28, -0.011 | 10/30, -0.017 | 9/31, -0.011 |
| Recovery share of attempts           | 38/2, -0.016  | 31/9, -0.008  | 30/9, -0.012 |
| Switching                            | 5/35, +0.017  | 7/33, +0.016  | 7/33, +0.018 |

Coverage did not move. Follow-through took a median of 85 slots a run on top of
allocation's. Unlike the scale-strong player, where scale strands were a tenth
of follow-throughs, here they were 60% of them, all on strands timed before and
never managed, and only 22% of those were managed. Arpeggio follow-throughs were
managed 36% of the time on strands never timed before and 42% on strands timed
and unmanaged. The family-neutral rule's cost on this cohort is mostly the cost
of following scale strands through.

## Combined against v1-14

Coverage rose by a median of 2 scales and 3.5 arpeggios (91/7 and 101/9 pairs),
every family's worst wait fell by 250 to 720 opportunities in all but two of 240
paired comparisons, and the managed share of introduced arpeggio strands rose by
0.13 to 0.20 in nearly every pair. Estimated retrieval of covered scales fell in
118 of 120 pairs, by 0.025 to 0.065, and switching rose in 113, by about three
points.

Observed retrieval tests fell by a median of 30 a run under the combined policy,
and their success moved by less than two points at every band. It fell
consistently only for the low band (31 of 40 pairs, by 0.017), the band whose
testing shifted most toward newly covered material.

## What this establishes

Breadth-relative allocation does across moderately varied players what it did on
the archetypes: it removes prolonged deferral for every player and raises
coverage most for the weakest. Its cost is the same everywhere: the scheduler's
estimate of covered scales' retrieval falls and their fading share rises,
consistently, and most for the weakest players, who gain the most coverage.

Follow-through accelerates managed execution of arpeggios by about 80 attempts
across the cohort and reduces recovery, but on players without a strong scale
family it spends most of its slots on scale strands that rarely convert. Its
case rests on that acceleration being worth a further consistent loss of
retrieval and continuity.

## What it does not establish

Whether either policy helps a learner retain anything. Estimated retrieval is
the scheduler's belief, and the synthetic player's own retrieval barely responds
to practice, so a lower estimate for covered scales is a cost in what the
scheduler believes, not shown to be a cost in what the player remembers. The
cohort tests allocation and progression under durable, near-daily practice, not
retention under forgetting or irregular calendars. These are synthetic players.
