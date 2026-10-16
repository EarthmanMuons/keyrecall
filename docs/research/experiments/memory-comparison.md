# Memory comparison

> **Status:** complete, all 27 configurations, 1,620 trajectories. Under
> [`retrieval-memory-2`](retrieval-memory.md), allocation at `k` of 2 left more
> materials retrievable 21 days after the last session than v1-14 in 779 of 810
> paired runs and fewer in 9, all of the difference through arpeggios. Every
> loss larger than 0.03 is `cohort_19` with a 15-day initial half-life, and each
> comes from a readiness plateau that v1-14 crossed and allocation did not,
> while allocation crosses it more often overall. The effect shrinks with slower
> forgetting and never reverses. The larger cost is in execution: for
> `cohort_20`, allocation's service of hands-together arpeggios it cannot manage
> halves the frontier steps that take its scales hands together. Nothing is
> promoted; the scheduler stays at v1-14.

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

Each configuration scales every gain by a learning strength (0.5, 1, or 2), sets
the initial half-life (15, 60, or 240 days), and sets spacing responsiveness (0,
0.5, or 1), written learning:half-life:spacing. They are scenarios, not
estimates. Seven were run first as a screen, the center and six corners; their
results were coherent, so the other 20 followed unchanged.

The primary outcome is expected materials retrievable: the sum over all 72
materials of the player's true retrievability, read a day after the last session
starts and again 21 days later, at the same instants for both arms. Every player
starts at 36.0. Readings never encode, so they cannot move a run.

```console
dart run keyrecall_simulation:memory_comparison --configs <configurations>
```

The default runs the seven-configuration screen.

## Results

Delayed expected materials retrievable, as medians for v1-14 and allocation;
paired differences (allocation minus v1-14) as better/worse of 30, median, and
worst; and the median lost between the two readings. Differences within 0.005
count as neither.

| Configuration | All, v1-14 / alloc | All, paired        | Arpeggios, of 24 | Arpeggios, paired  | Lost in 21 days |
| ------------- | -----------------: | ------------------ | ---------------: | ------------------ | --------------: |
| 0.5:15:0      |        54.7 / 61.4 | 29/1, +8.54, -3.71 |       9.0 / 13.9 | 28/2, +8.51, -8.67 |     0.51 / 0.88 |
| 0.5:15:0.5    |        54.9 / 61.7 | 27/2, +8.66, -3.86 |       8.2 / 13.9 | 27/1, +8.54, -8.76 |     0.41 / 0.38 |
| 0.5:15:1      |        54.9 / 61.7 | 27/2, +8.51, -6.33 |       8.2 / 13.9 | 26/3, +8.08, -8.88 |     0.41 / 0.27 |
| 1:15:0        |        55.0 / 61.7 | 29/0, +7.28, +0.00 |       8.5 / 13.9 | 29/0, +6.91, +0.00 |     0.55 / 0.26 |
| 1:15:0.5      |        55.0 / 61.7 | 28/1, +7.10, -4.77 |       8.9 / 13.9 | 28/1, +6.61, -9.49 |     0.53 / 0.26 |
| 1:15:1        |        55.9 / 61.7 | 27/2, +6.87, -5.25 |       9.0 / 13.9 | 27/2, +5.58, -9.95 |     0.50 / 0.26 |
| 2:15:0        |        56.2 / 61.7 | 29/0, +5.81, -0.00 |      10.0 / 13.9 | 29/1, +5.24, -0.01 |     0.63 / 0.26 |
| 2:15:0.5      |        56.0 / 61.7 | 28/0, +5.82, -0.00 |       9.5 / 13.9 | 28/0, +5.30, -0.00 |     0.65 / 0.26 |
| 2:15:1        |        55.8 / 61.7 | 29/0, +7.07, -0.00 |       9.1 / 13.9 | 29/0, +6.28, +0.00 |     0.63 / 0.26 |
| 0.5:60:0      |        57.8 / 62.9 | 29/0, +5.12, -0.00 |      11.4 / 15.1 | 29/0, +4.85, +0.00 |     0.97 / 0.57 |
| 0.5:60:0.5    |        58.0 / 62.9 | 29/0, +5.09, -0.00 |      11.5 / 15.1 | 29/0, +4.60, -0.00 |     0.97 / 0.54 |
| 0.5:60:1      |        57.9 / 62.9 | 30/0, +5.10, +0.46 |      11.5 / 15.1 | 30/0, +4.84, +0.45 |     0.97 / 0.54 |
| 1:60:0        |        59.0 / 62.8 | 29/0, +3.98, -0.00 |      12.3 / 15.1 | 29/0, +3.23, -0.00 |     0.91 / 0.53 |
| 1:60:0.5      |        59.0 / 62.8 | 29/0, +4.10, -0.00 |      12.3 / 15.1 | 29/0, +3.55, -0.00 |     0.92 / 0.53 |
| 1:60:1        |        58.8 / 62.8 | 29/1, +4.18, -0.01 |      12.2 / 15.1 | 29/0, +3.64, -0.00 |     0.91 / 0.53 |
| 2:60:0        |        60.5 / 62.8 | 30/0, +2.46, +0.17 |      13.4 / 15.1 | 29/0, +1.93, -0.00 |     0.76 / 0.52 |
| 2:60:0.5      |        60.3 / 62.8 | 30/0, +2.63, +0.13 |      13.3 / 15.1 | 29/0, +2.06, -0.00 |     0.77 / 0.52 |
| 2:60:1        |        60.0 / 62.8 | 30/0, +3.00, +0.11 |      13.1 / 15.1 | 29/0, +2.34, -0.00 |     0.80 / 0.53 |
| 0.5:240:0     |        63.2 / 65.3 | 29/0, +1.94, +0.00 |      15.9 / 17.5 | 29/0, +1.62, +0.00 |     0.66 / 0.45 |
| 0.5:240:0.5   |        63.2 / 65.3 | 29/0, +1.93, +0.00 |      15.9 / 17.5 | 29/0, +1.64, +0.00 |     0.66 / 0.45 |
| 0.5:240:1     |        63.2 / 65.2 | 29/0, +1.95, +0.00 |      15.8 / 17.4 | 29/0, +1.61, +0.00 |     0.66 / 0.45 |
| 1:240:0       |        63.8 / 65.3 | 29/0, +1.31, +0.00 |      16.5 / 17.6 | 29/0, +1.02, +0.00 |     0.59 / 0.45 |
| 1:240:0.5     |        63.7 / 65.3 | 29/0, +1.37, +0.00 |      16.5 / 17.6 | 29/0, +1.02, +0.00 |     0.59 / 0.45 |
| 1:240:1       |        63.6 / 65.3 | 29/0, +1.44, +0.00 |      16.4 / 17.6 | 29/0, +1.04, +0.00 |     0.60 / 0.45 |
| 2:240:0       |        64.3 / 65.5 | 29/0, +0.72, -0.00 |      16.9 / 17.7 | 29/0, +0.53, -0.00 |     0.51 / 0.45 |
| 2:240:0.5     |        64.3 / 65.5 | 29/0, +0.76, +0.00 |      16.8 / 17.7 | 29/0, +0.56, +0.00 |     0.52 / 0.45 |
| 2:240:1       |        64.0 / 65.5 | 29/0, +0.88, +0.00 |      16.8 / 17.7 | 29/0, +0.65, +0.00 |     0.53 / 0.45 |

**The difference is arpeggios, and scales are at the ceiling.** Both arms end
with 46.8 to 47.8 of 48 scales retrievable in every configuration, so this
outcome can only discriminate through arpeggios. Allocation covers a median of
14 arpeggios in every configuration, against 5.5 to 8 under v1-14.

**The size of the gain follows forgetting.** With a 15-day initial half-life an
arpeggio never practised is forgotten by the end, so what is retained is close
to what was covered, and allocation's median gain is 5.8 to 8.7 materials. At 60
days it is 2.5 to 5.1 and at 240 days 0.7 to 2.0, as unpractised arpeggios keep
more of their start. Stronger learning narrows it, since v1-14's fewer arpeggios
are then learned better. Spacing moves it less than either.

**21 days costs little.** Either arm loses under one material between the two
readings. Allocation loses less in 26 configurations and more at 0.5:15:0 (0.88
against 0.51).

### The regression cases

`cohort_19` has every loss larger than 0.03: seven of its 45 pairs with a 15-day
half-life and learning at 0.5 or 1, from -3.56 to -6.33. In each, allocation
retained more scales and covered 14 arpeggios, while v1-14 covered 21 to 24.
Allocation's arpeggio coverage sits at 14 in 596 of 810 runs and at 24 in 139:
the ten others are the requirements the [service census](service-census.md)
found due and never actionable, a readiness limit. The frozen model shows the
same plateau, at 14 in 78 of its 120 reference allocation runs. Allocation
crosses it more often than v1-14 does, for `cohort_19` in 79 of 135 runs against
28, but which arm crosses on a given calendar is fragile: on seed pair 2:102 at
learning 0.5 and a 15-day half-life, allocation covered all 24 with spacing at 0
and 14 with spacing at 1. When v1-14 crosses and allocation does not, a fast
forgetter loses the difference; with a 60-day half-life or longer, the same
calendars cost allocation nothing. In its other 128 pairs `cohort_19` gains,
with a median of 6.64 across all 135.

The other two losses are `cohort_11` on seed pair 4:104, by 0.03 and 0.01.

`cohort_13` on seed pair 0:100, the frozen model's worst loss (-1.26), gains in
all 27 configurations, from 0.43 to 18.46. That follows from the model rather
than from luck: a frozen player returns to its start, so allocation's breadth
could not raise retention while its narrower scale practice could lower it; a
player who forgets an unpractised arpeggio is paid for being shown it.

### Execution, workload, and the scheduler's estimate

- **Motor execution moves toward arpeggios, mixed by profile.** Allocation
  managed a median of 10.5 to 12 more arpeggio strands and 4 to 9 fewer scale
  strands, with the worst pair 112 fewer. Held-out managed play 21 days on is
  higher by a configuration median of 0.005 to 0.06, but lower in 4 to 11 pairs
  of 30, by up to 0.20. By player, `cohort_13`, `cohort_19`, and `cohort_12`
  gain in nearly every pair; `cohort_10` and `cohort_11` are lower in half their
  pairs by a few thousandths at the median, and `cohort_20` swings with the seed
  pair, from -0.11 to +0.05, as its scale strands fall by a median of 58.
- **Recovery and never-started attempts barely move.** Recovery is 2.5 to 6.7%
  of attempts and never-started 1.7 to 5.6% in either arm, with paired medians
  of +0.1 to +0.9 points under allocation. Under the frozen model recovery was
  about a third.
- **The scheduler underestimates this player by about a third.** Its expected
  retrieval for the held-out questions is 0.45 to 0.51 in both arms, against
  0.76 to 0.91 observed. The learner model was built against the frozen player.
  This does not separate the policies, but neither scheduler's belief tracks
  this memory.

## Scale execution for `cohort_20`

`cohort_20` is the weakest of the six, favors scales by 0.24 logits, with
arpeggios weaker by the same. Under memory it manages a median of 58 fewer scale
strands with allocation, on every seed pair, where under the frozen player
allocation managed more on four of five. A strand is a material in one hand
configuration and motion, counted once managed, so the loss is in contexts never
reached rather than execution demonstrated and then lost.

```console
dart run keyrecall_simulation:scale_execution --profile 19 \
  --configs 1:60:0.5,frozen --seeds 4:104,1:101,3:103
```

The diagnostic tallies each arm's decisions by stage and purpose, its attempts
and strands by hands, its busiest strands, and held-out managed play by family
and hands 21 days after the end. At 1:60:0.5:

| Seed pair | Arm        | Scale frontier steps | Arpeggio progression by allocation | Scale strands managed together | Held-out scales together | Held-out arpeggios, right hand |
| --------- | ---------- | -------------------: | ---------------------------------: | -----------------------------: | -----------------------: | -----------------------------: |
| 4:104     | v1-14      |                  362 |                                    |                             73 |                     0.95 |                           0.15 |
| 4:104     | allocation |                  191 |                                165 |                              8 |                     0.26 |                           0.60 |
| 1:101     | v1-14      |                  338 |                                    |                             75 |                     0.96 |                           0.25 |
| 1:101     | allocation |                  162 |                                121 |                              0 |                     0.07 |                           0.61 |
| 3:103     | v1-14      |                  471 |                                    |                             84 |                     1.00 |                           0.19 |
| 3:103     | allocation |                  443 |                                 38 |                             76 |                     1.00 |                           0.61 |

**Allocation keeps serving arpeggio progression the player cannot reach.** On
4:104 its busiest strand is the E minor arpeggio hands together, 88 attempts and
4 managed, followed by A minor and F major hands together, 29 and 25 attempts
and none managed. On 1:101 its two busiest are C major and A minor hands
together, 47 and 36 attempts, none managed. Allocation records each of these
services as execution progression for the arpeggio's requirement.

**What it displaces is the scale frontier.** Frontier steps are the stage that
carries a scale into the left hand and hands together, and on the losing seed
pairs they fall by about half, so allocation never takes the scales hands
together. At 1:60:0.5 held-out right- and left-hand scales stay at 0.93 to 1.00.
On 3:103 allocation's progression service is 38 decisions, mostly right-hand
arpeggios that converge, the frontier keeps its steps, and allocation gains the
same right-hand arpeggios at no scale cost. The worst grid pair, 4:104 at
2:60:0, shows the same: 457 frontier steps against 175, and hands-together
scales 1.00 against 0.13.

**The frozen player hides it.** Without memory, neither arm takes `cohort_20`'s
scales hands together (held-out 0.01 to 0.15 on 4:104 and 1:101), v1-14 makes
110 to 160 frontier steps, and allocation serves arpeggio progression 16 to 29
times. The cost appears once the player retrieves well enough for v1-14's
frontier to move, which is the player this model asks about.

This is the exclusion census's arpeggio shape, a strand introduced with no route
onward to managed practice, meeting a player whose scale frontier now competes
for the same slots. It is a policy limitation for this kind of player, not a
retention effect, and these runs do not say whether other profiles show it at
smaller size.

### Across profiles

The same diagnostic at 1:60:0.5 on all five seed pairs for `cohort_10`,
`cohort_11`, and `cohort_12` as well as `cohort_20`, 40 trajectories. It pairs
every selecting decision with the attempt it wrote, checking their materials
agree, and counts allocation's interventions per strand. A strand is newly
managed when it had no managed attempt before its first intervention and has one
by the end.

| Player      | Hands-together arpeggio interventions per run | Newly managed by them, all runs | Single-hand arpeggio interventions per newly managed strand | v1-14 hands-together scales | Pairs losing more than 0.1 of it |
| ----------- | --------------------------------------------: | ------------------------------: | ----------------------------------------------------------: | --------------------------: | -------------------------------- |
| `cohort_10` |                                    109 to 204 |                               0 |                                                 6.0 to 10.6 |                0.01 to 0.51 | 2 of 5 (-0.49, -0.26)            |
| `cohort_11` |                                      19 to 43 |                              13 |                                                  1.8 to 3.5 |                0.82 to 0.93 | none (worst -0.06)               |
| `cohort_12` |                                      30 to 66 |                               3 |                                                  2.4 to 3.6 |                0.94 to 1.00 | none                             |
| `cohort_20` |                                     13 to 136 |                               3 |                                                  5.1 to 8.3 |                0.95 to 1.00 | 3 of 5 (-0.89, -0.69, -0.29)     |

**Hands-together arpeggio service rarely becomes execution.** Across the 20
allocation runs, 1,548 hands-together arpeggio interventions newly managed 19
strands, 81 each, while 1,111 single-hand arpeggio interventions newly managed
221, 5.0 each. `cohort_10` has the starkest case: 109 to 204 a run, none ever
managed, with two or three strands per run taking 20 or more, up to 140 on the E
minor arpeggio hands together.

**The scale cost needs a frontier to displace.** `cohort_10`'s service is the
largest, but on three of its pairs v1-14 never takes its scales hands together
either, and nothing is lost. On the two where v1-14 does, allocation loses
nearly all of it. `cohort_11` and `cohort_12` see 19 to 66 such interventions a
run and lose at most 0.06. The cost appears where heavy hands-together arpeggio
service meets a player whose scales could go hands together.

**Concentration on a few strands does not predict it.** The share of
interventions on the three busiest strands is 0.47 to 0.66 for `cohort_10`
whether or not scales lose, and 0.38 on `cohort_20`'s largest loss, on 1:101,
where the service spreads over several hands-together arpeggios. A relief scoped
to one strand could therefore move the same service to a sibling strand; the
measure of a relief has to be the family's hands-together service and the scale
frontier, not the busiest strand alone.

## Reading

Against the implication table declared before the runs, retention reads as
breadth improving without harming delayed retrieval: no reversal across the
grid, no collapse, and in 22 of 27 configurations no loss beyond 0.03 for any
profile. The exception is one profile at the fastest forgetting, through a
readiness plateau allocation crosses more often than v1-14, not a retention cost
of allocation itself. Motor execution reads as a consistent loss for one kind of
profile: for `cohort_20` on calendars where allocation's arpeggio progression
stalls, the scales never reach hands together. That is the policy limitation
row, and the case to resolve before promotion.

## What it does not establish

Any of the 27 configurations as the right one. Every encoding resets
retrievability to 1.0, including cued practice and recovery, which inflates
success right after supported work in both arms. Scales at the ceiling mean the
outcome cannot show a scale retention cost smaller than about one material. Six
profiles on one calendar is not the cohort. The memory model's own limits are in
[retrieval memory](retrieval-memory.md).
