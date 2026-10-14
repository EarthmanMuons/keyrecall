# Memory comparison

> **Status:** stage 1 of 2, seven of 27 configurations, 420 trajectories. Under
> [`retrieval-memory-2`](retrieval-memory.md), allocation at `k` of 2 left more
> materials retrievable 21 days after the last session than v1-14 in 200 of 210
> paired runs, all of it through arpeggios. The three losses are all `cohort_19`
> at the weakest learning and fastest forgetting, and come from a readiness gate
> that v1-14 happened to open, not from allocation diluting retention. The
> remaining 20 configurations are running. Nothing is promoted; the scheduler
> stays at v1-14.

The frozen player's familiarity returns to where it started however it is
practised, which bounds what breadth can buy in retention. This comparison asks
whether allocation's case changes when a material left alone is forgotten and
one retrieved is learned.

## Design

v1-14 against allocation at `k` of 2 with protection floor 0.60, unchanged, on
six cohort players: the two regression cases `cohort_19` and `cohort_13`, and
`cohort_20`, `cohort_11`, `cohort_10`, and `cohort_12`, spanning ability, family
asymmetry, and motor learning rate. The five seed pairs 0:100 to 4:104 run on
the reference calendar, so seed pair 0:100 keeps `cohort_13`'s worst
frozen-model loss.

Each configuration scales every gain by a learning strength, sets the initial
half-life, and sets spacing responsiveness. They are scenarios, not estimates.
Stage 1 is the center of the grid and six corners:

| Learning | Initial half-life | Spacing |
| -------: | ----------------: | ------: |
|        1 |           60 days |     0.5 |
|      0.5 |           15 days | 0 and 1 |
|      0.5 |          240 days |     0.5 |
|        2 |           15 days |     0.5 |
|        2 |          240 days | 0 and 1 |

The primary outcome is expected materials retrievable: the sum over all 72
materials of the player's true retrievability, read a day after the last session
starts and again 21 days later, at the same instants for both arms. Every player
starts at 36.0. Readings never encode, so they cannot move a run.

```console
dart run keyrecall_simulation:memory_comparison
```

## Results

Delayed expected materials retrievable, as medians for v1-14 and allocation, and
paired differences (allocation minus v1-14) as better/worse of 30, median, and
worst. Differences within 0.005 count as neither.

| Configuration | All, v1-14 / alloc | All, paired        | Scales, of 48 | Arpeggios, of 24 | Arpeggios, paired  |
| ------------- | -----------------: | ------------------ | ------------: | ---------------: | ------------------ |
| 1:60:0.5      |        59.0 / 62.8 | 29/0, +4.10, -0.00 |   47.3 / 47.8 |      12.3 / 15.1 | 29/0, +3.55, -0.00 |
| 0.5:15:0      |        54.7 / 61.4 | 29/1, +8.54, -3.71 |   46.8 / 47.2 |       9.0 / 13.9 | 28/2, +8.51, -8.67 |
| 0.5:15:1      |        54.9 / 61.7 | 27/2, +8.51, -6.33 |   47.8 / 47.8 |       8.2 / 13.9 | 26/3, +8.08, -8.88 |
| 0.5:240:0.5   |        63.2 / 65.3 | 29/0, +1.93, +0.00 |   47.8 / 47.8 |      15.9 / 17.5 | 29/0, +1.64, +0.00 |
| 2:15:0.5      |        56.0 / 61.7 | 28/0, +5.82, -0.00 |   47.8 / 47.8 |       9.5 / 13.9 | 28/0, +5.30, -0.00 |
| 2:240:0       |        64.3 / 65.5 | 29/0, +0.72, -0.00 |   47.7 / 47.8 |      16.9 / 17.7 | 29/0, +0.53, -0.00 |
| 2:240:1       |        64.0 / 65.5 | 29/0, +0.88, +0.00 |   47.7 / 47.8 |      16.8 / 17.7 | 29/0, +0.65, +0.00 |

**The difference is arpeggios, and scales are at the ceiling.** Both arms end
with 46.8 to 47.8 of 48 scales retrievable, so this outcome can only
discriminate through arpeggios. Allocation covers a median of 14 arpeggios
against 5.5 to 8 under v1-14.

**The size of the gain follows forgetting.** With a 15-day initial half-life an
arpeggio never practised is forgotten by the end, so what is retained is close
to what was covered, and allocation's median gain is 5.8 to 8.5 materials. With
240 days, unpractised arpeggios keep much of their start and the gain is 0.7 to
1.9. Learning strength and spacing move it less than the half-life does, and at
240 days spacing barely moves either arm.

**21 days costs little.** Either arm loses under one material between the two
readings. Allocation loses less in six configurations and more at 0.5:15:0 (0.88
against 0.51).

### The regression cases

`cohort_19` has every loss: -3.71 at 0.5:15:0 on seed pair 3:103, and -6.33 and
-3.98 at 0.5:15:1 on 2:102 and 3:103. In each, allocation retained more scales
(+0.97 to +4.97) and covered 14 arpeggios while v1-14 covered 22 or 23 and
retained 21.3 to 22.8. Allocation's arpeggio coverage sits at 14 in 155 of 210
runs and at 24 in 35: the ten others are the requirements the
[service census](service-census.md) found due and never actionable, a readiness
limit. The frozen model shows the same plateau, at 14 in 78 of its 120 reference
allocation runs. Under memory v1-14 occasionally crosses it for `cohort_19` and
allocation, on those calendars, does not. Which arm crosses is fragile: on seed
pair 2:102, allocation covered all 24 with spacing at 0 and 14 with spacing at

1. In its 32 other pairs `cohort_19` gains from 0.22 to 15.50 materials.

`cohort_13` on seed pair 0:100, the frozen model's worst loss (-1.26), gains in
all seven configurations, from 0.43 to 17.70. That follows from the model rather
than from luck: a frozen player returns to its start, so allocation's breadth
could not raise retention while its narrower scale practice could lower it; a
player who forgets an unpractised arpeggio is paid for being shown it.

### Execution, workload, and the scheduler's estimate

- **Motor execution moves toward arpeggios.** Allocation managed a median of 11
  more arpeggio strands and 6 to 8.5 fewer scale strands, with the worst pair
  108 fewer. Held-out managed play 21 days on is higher by a median of 0.01 to
  0.05, but lower in 4 to 12 pairs of 30, by up to 0.16.
- **Recovery and never-started attempts are unchanged.** Recovery is 3 to 7% of
  attempts and never-started 2 to 6% in both arms, with paired medians of 0 to
  +0.01. Under the frozen model recovery was about a third.
- **The scheduler underestimates this player by a third or more.** Its expected
  retrieval for the held-out questions is 0.45 to 0.51 in both arms, against
  0.76 to 0.91 observed, a gap of 0.31 to 0.42. The learner model was built
  against the frozen player. This does not separate the policies, but neither
  scheduler's belief tracks this memory.

## Reading

Against the implication table declared before the runs: in five of seven
configurations allocation improves breadth without harming delayed retrieval for
any profile. Under the weakest learning and fastest forgetting, one profile
loses in three of ten pairs, through a readiness gate rather than a retention
cost. That is the row for losses only under extreme settings, which calls for
the sensitivity check the full grid is. Nothing reverses with the parameters,
and neither policy collapses.

## What it does not establish

Any of the 27 configurations as the right one, or the full grid's result before
it is run. Every encoding resets retrievability to 1.0, including cued practice
and recovery, which inflates success right after supported work in both arms.
Scales at the ceiling mean the outcome cannot show a scale retention cost
smaller than about one material. The memory model's own limits are in
[retrieval memory](retrieval-memory.md).
