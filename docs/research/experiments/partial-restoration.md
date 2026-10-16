# Partial restoration

> **Status:** one structural sensitivity test, 80 trajectories at 1:60:0.5 under
> [`retrieval-memory-3`](retrieval-memory.md), each paired with its
> `retrieval-memory-2` run. Replacing the reset to full recall after every
> encoding with restoration in proportion to the encoding's gain changes no
> direction: allocation at `k` of 2 still retains more than v1-14 in 28 of 30
> pairs and less in none, and still delays hands-together scales by up to three
> quarters of a run. Its gains shrink slightly, recovery workload doubles in
> both arms alike, and the opening of arpeggio breadth beyond 14 is the most
> sensitive outcome. Nothing is promoted; the scheduler stays at v1-14.

Every earlier comparison under retrieval memory shared one structural rule: any
encoding, even a cued attempt, reset retrievability to 1.0. This asks whether
allocation's advantage depends on it.

## Design

`retrieval-memory-3` restores the gap to full recall by the encoding's gain as a
share of a successful unguided retrieval's, so a retrieval still restores fully,
a previewed attempt half of what was missing, and cued or acquisition work a
sixth. Half-lives grow as before and there is no new parameter; the rule and its
characterization are in [retrieval memory](retrieval-memory.md).

One configuration, the central 1:60:0.5, and no sweep:

- the [memory comparison](memory-comparison.md)'s six players, five seed pairs
  each, v1-14 against allocation, 60 runs;
- the [extended horizon](extended-horizon.md)'s `cohort_10` and `cohort_20`, the
  same two arms to three times the run, 20 runs.

```console
dart run keyrecall_simulation:memory_comparison --configs 1:60:0.5:byGain
dart run keyrecall_simulation:scale_execution --profile 19 \
  --configs 1:60:0.5:byGain --seeds 4:104 --arms v1-14,alloc-2 --horizon 3
```

Every horizon run's manifest names `retrieval-memory-3` with `byGain`
restoration, and its decisions matched its planned slots at every checkpoint.

## Results

Paired allocation minus v1-14 over 30 pairs, as better / worse and median:

| Measure                          | `retrieval-memory-2` | `retrieval-memory-3` |
| -------------------------------- | -------------------- | -------------------- |
| Materials retrievable 21 days on | 29 / 0, +4.10        | 28 / 0, +3.53        |
| Arpeggios retrievable 21 days on | 29 / 0, +3.55        | 26 / 0, +2.81        |
| Scales retrievable 21 days on    | 18 / 3, +0.49        | 17 / 1, +0.42        |
| Lost over the 21 days            | 28 lose less, -0.38  | 26 lose less, -0.35  |
| Arpeggios covered                | 30 / 0, +8.5         | 28 / 0, +9.0         |
| Held-out retrieval               | 27 / 0, +0.04        | 28 / 0, +0.04        |
| Held-out managed                 | 20 / 7, +0.02        | 20 / 8, +0.02        |
| Scale strands managed            | 9 / 20, -7           | 10 / 18, -7          |

**The retention gain survives, slightly smaller.** Allocation retains more in 28
pairs, up to 14.51 materials, and ties the other two, where v1-14 itself reached
13 or 14 arpeggios. The smaller median comes mostly from v1-14 rather than
allocation: allocation's median is 62.87 against 62.84, while v1-14's rises from
59.00 to 59.91 as weaker restoration changes its trajectories and on some
calendars opens more arpeggios, 22 rather than 11 for `cohort_19` on 0:100. The
largest scale loss is 0.04 materials.

**The regression cases stay positive.** `cohort_19` gains 0.00 to 11.81 rather
than 3.07 to 14.32, smaller on three pairs where v1-14 covered 13 to 22
arpeggios. `cohort_13` gains more, 5.47 to 14.51, as allocation reaches all 24
arpeggios on four pairs rather than one.

**Recovery doubles in both arms alike.** Recovery attempts rise from 3% to 6% of
attempts and never-started attempts from 2% to 5% in each arm, with no
consistent paired difference. The learner's estimate stays about 0.37 below
held-out retrieval in both versions.

**Scale strands are as noisy as before.** Allocation manages fewer scale strands
in 18 pairs, by a median of 7, but single trajectories move widely between
versions: v1-14 on `cohort_20` 0:100 manages 79 rather than 170, and allocation
on the same calendar 159 rather than 117.

Over three times the run:

| Player, seed pair  | HT scales 0.9, v1-14 / alloc | 20th HT scale strand, v1-14 / alloc | Arpeggios retrievable at 3x, of 24 | Right-hand arpeggios at 3x |
| ------------------ | ---------------------------- | ----------------------------------- | ---------------------------------- | -------------------------- |
| `cohort_10`, 0:100 | 2.25 / 2.75                  | 2,371 / 3,024                       | 9.6 / 23.9                         | 0.43 / 1.00                |
| `cohort_10`, 1:101 | 2.25 / 2.75                  | 1,993 / 2,892                       | 8.4 / 17.3                         | 0.29 / 0.78                |
| `cohort_10`, 2:102 | 2.0 / 2.25                   | 1,841 / 2,336                       | 9.0 / 14.1                         | 0.38 / 0.58                |
| `cohort_10`, 3:103 | 1.75 / 2.5                   | 1,784 / 2,956                       | 8.9 / 23.9                         | 0.38 / 1.00                |
| `cohort_10`, 4:104 | 1.75 / 2.0                   | 1,702 / 2,034                       | 9.1 / 23.9                         | 0.36 / 1.00                |
| `cohort_20`, 0:100 | 1.25 / 1.0                   | 1,307 / 999                         | 5.2 / 23.9                         | 0.03 / 1.00                |
| `cohort_20`, 1:101 | 1.0 / 1.0                    | 938 / 1,147                         | 6.9 / 23.9                         | 0.15 / 1.00                |
| `cohort_20`, 2:102 | 1.0 / 1.25                   | 1,134 / 1,534                       | 6.3 / 23.9                         | 0.31 / 1.00                |
| `cohort_20`, 3:103 | 1.0 / 1.0                    | 1,077 / 1,116                       | 5.1 / 23.9                         | 0.11 / 1.00                |
| `cohort_20`, 4:104 | 0.75 / 1.25                  | 939 / 1,466                         | 7.3 / 23.9                         | 0.25 / 1.00                |

**Hands-together scales are still delayed, not lost.** Allocation reaches 0.9
later in seven pairs, at the same checkpoint in two, and earlier in one, by a
quarter to three quarters of a run where it is later; under `retrieval-memory-2`
it was later in nine. Its 20th hands-together scale strand comes 39 to 1,172
decisions later in nine pairs and 308 earlier in one. By three times both arms
hold 0.92 or more.

**Breadth beyond 14 is the sensitive outcome.** Allocation's arpeggios sit at
about 14 for most of the run and the remaining ten open together late. Under
`retrieval-memory-2` they opened for `cohort_10` at 2.5 to 3 times, the last
pair at the final checkpoint. Under `retrieval-memory-3` two `cohort_10` pairs
open later: one partly by three times, at 17.3, and one not at all, at 14.1.
`cohort_20` opens all 24 in every pair under both versions. v1-14 ends with 5.1
to 9.6 arpeggios retrievable rather than 4.1 to 8.4, still fading from 10.2 to
12.9 at the original end.

**Scale retrieval holds.** Scales retrievable 21 days after the three-times
checkpoint are 44.1 to 47.8 of 48 under v1-14 and 47.7 to 47.8 under allocation.

## Reading

The reset to full recall is not what produces allocation's advantage. Under
weaker restoration it still retains more on every pair it does not tie, still
covers more arpeggios, and still costs hands-together scale progression on the
same scale. What moves is size and timing: the gain is about half a material
smaller at the median, both arms spend about twice as much on recovery, and
whether allocation's breadth passes 14 within three runs depends on the calendar
for `cohort_10`. The trade-off the [extended horizon](extended-horizon.md)
priced is unchanged in kind: a delay of up to three quarters of a run for
hands-together scales against arpeggio breadth v1-14 never builds.

Further synthetic contrasts would test this simulator rather than learners. What
these runs cannot settle, the form of forgetting, how much a cued or previewed
attempt restores, where a learner's readiness plateaus, and whether breadth or
hands-together progression is worth more, needs real practice data.

## What it does not establish

One configuration, one alternative restoration rule, six cohort players, two of
them over the longer horizon, and five calendars each. The gain-share rule is as
uncalibrated as the reset it replaces, and the late opening of breadth beyond 14
is a property of this player's readiness that real learners may not share.
