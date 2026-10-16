# Context relief

> **Status:** simulation-only counterfactual, 60 trajectories, rerun with the
> corrected classifier; the first run, which counted incomplete attempts
> carrying a motor score as unmanaged, is kept below as superseded. At the
> tested setting, bounding repeated allocation service without demonstrated
> execution cut hands-together arpeggio interventions from up to 204 a run to 13
> to 39 while preserving breadth, but did not restore hands-together scale
> progression for `cohort_10` and `cohort_20`. Practiced on to three times the
> run, in [extended horizon](extended-horizon.md), it moved neither milestone
> consistently. Nothing is promoted; the scheduler stays at v1-14, and
> allocation's default has no relief.

The [memory comparison](memory-comparison.md) found allocation at `k` of 2
serving hands-together arpeggios at about 81 interventions per newly managed
strand, against 5 for single hands, and losing hands-together scales for two
players. This asks whether bounding that service gives the scale frontier back.

## The rule

A group is a family and a hand configuration, so hands-together arpeggios share
one budget whatever the material. An allocation-served attempt that was
completed, timed, and not managed counts against its strand until that strand is
managed by any route. Never-started, incomplete, and untimed attempts are
recorded and count for nothing. Once a group's strands hold the trigger between
them, the group is relieved: it may be served at no more than the budget of its
last window of opportunities, an opportunity being an allocatable decision at
which allocation would otherwise have served it. A withheld requirement may
still be served by a realization outside the group, and otherwise allocation
moves to the next owed requirement or leaves ranking's winner.

Relief changes only allocation's priority. Coverage, eligibility, waiting,
ranking, recovery, and the learner's estimates are untouched, and the window
moves only with opportunities, never with time or outcomes. Tests pin that only
timed unmanaged service counts, that siblings share a group and other groups are
unaffected, that a managed attempt clears only its own strand, the budget over
the window, that an unreachable trigger leaves the run byte-identical, and that
a zero budget never serves a relieved group. The evidence rule, the grouping,
the clearing, and the record of service were each checked by breaking them.

The arm here uses a trigger of 10, a budget of 1, and a window of 5: arbitrary
experimental values, not taken from the single-hand ratio.

```console
dart run keyrecall_simulation:scale_execution --profile 19 \
  --configs 1:60:0.5 --seeds 4:104 --arms v1-14,alloc-2,relief:10:1:5
```

v1-14, allocation, and allocation with relief, on `cohort_10`, `cohort_11`,
`cohort_12`, and `cohort_20` at 1:60:0.5 of
[retrieval memory](retrieval-memory.md), five seed pairs each.

## Results

The five pairs where allocation cost hands-together scales, as v1-14 /
allocation / relief:

| Player, seed pair  | Hands-together arpeggio interventions | Scale frontier steps | Scale attempts    | Held-out scales together |
| ------------------ | ------------------------------------- | -------------------- | ----------------- | ------------------------ |
| `cohort_10`, 0:100 | 0 / 109 / 21                          | 331 / 248 / 275      | 1,193 / 921 / 990 | 0.51 / 0.03 / 0.11       |
| `cohort_10`, 2:102 | 0 / 166 / 39                          | 294 / 211 / 232      | 1,134 / 852 / 944 | 0.28 / 0.01 / 0.03       |
| `cohort_20`, 0:100 | 0 / 85 / 29                           | 338 / 230 / 261      | 1,234 / 947 / 995 | 0.99 / 0.70 / 0.88       |
| `cohort_20`, 1:101 | 0 / 82 / 39                           | 338 / 162 / 204      | 1,125 / 852 / 920 | 0.96 / 0.07 / 0.36       |
| `cohort_20`, 4:104 | 0 / 136 / 34                          | 362 / 191 / 198      | 1,218 / 886 / 958 | 0.95 / 0.26 / 0.47       |

**Relief does what it bounds.** Hands-together arpeggio interventions fall to 13
to 39 a run in every profile, and stay there: no group rebounds to take the next
run of opportunities. Relief withheld 8 to 187 opportunities a run for
`cohort_10` and `cohort_20` and at most 14 for the others, and nearly every
withheld opportunity went to another realization of the same requirement outside
the group. Incomplete attempts, which count for nothing, were 6 to 60 a run of
allocation's service, against 15 to 63 completed and unmanaged; never-started
attempts were 2 to 15 and untimed 0 to 7. When relief first engaged was not
recorded.

**Breadth survives.** Arpeggio coverage is never lower than allocation's, 14 in
every run but one, which reaches 24. Worst arpeggio waits stay at 53 to 102
opportunities, as under allocation, against 130 to 1,395 for v1-14, and held-out
right-hand arpeggios and arpeggio retrieval are never lower than allocation's.

**The scale frontier does not recover.** On the losing pairs relief returns 59
to 137 slots a run to ordinary selection, and scale frontier steps rise by 7 to
42, but hands-together scales come back only in part, for `cohort_20` on all
three pairs and barely for `cohort_10`. Scale attempts stay 17 to 21% below
v1-14 on every losing pair, while allocation's remaining arpeggio service, 99 to
124 interventions a run, and the arpeggios its breadth opens keep drawing
ordinary ranking and the arpeggio frontier: arpeggio frontier steps rise from
none under v1-14 to 27 to 82 under relief. Hands together is the last stage of a
scale's progression, so a fifth fewer scale attempts within the same run leaves
most of it unreached.

`cohort_11` and `cohort_12`, which lost at most 0.06 of hands-together scales to
allocation, end within 0.06 of v1-14 under relief too.

## Superseded run

The first run of the relief arm classified an incomplete attempt by its motor
score when it had one, so incomplete hands-together service counted toward
relief: it recorded 0 to 3 incomplete attempts a run where the corrected run
records 6 to 60. All 20 corrected runs differ from it. It engaged relief sooner
and harder, withholding up to 292 opportunities in a run against 187, and held
hands-together arpeggio interventions at 11 to 41. Its headline did not change:
breadth held and hands-together scales did not recover. Two of its side effects
did not survive correction: arpeggio coverage reaching 24 on `cohort_20` 2:102
and 3:103, and held-out left-hand scales falling from 0.93 to 0.65 on
`cohort_20` 4:104.

## Reading

Of the three outcomes declared before the runs, this is the second:
hands-together arpeggio interventions fall and the scale frontier does not
recover. That shows this reduction was not enough, not that capacity is
irrelevant: scale attempts stay 17 to 21% below v1-14 while other arpeggio work
keeps drawing ordinary ranking, so relief never returned the scale practice
whose loss it was meant to test, and progression may depend on which
opportunities return and when. The service relief bounds was 37 to 56% of
allocation's interventions on the losing pairs, and bounding it cost no breadth
within the run, though at three times it ended with fewer arpeggios on two
`cohort_10` pairs. Whether it cost preparatory learning is open: unmanaged
attempts still teach this player's execution, so service without demonstrated
execution is not practice that taught nothing.

## What it does not establish

One setting of trigger, budget, and window, on one memory configuration, four
cohort players, and five calendars each. Whether hands-together scales or
arpeggio breadth is worth more to a learner is a product question these runs
cannot answer, and a run of this length may end before either player would reach
both.
