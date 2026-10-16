# Context relief

> **Status:** simulation-only counterfactual, 60 trajectories, run with a
> classifier that counted incomplete attempts carrying a motor score as
> unmanaged evidence, against the rule below; a rerun with the corrected
> classifier is pending. At the tested setting, bounding repeated allocation
> service without demonstrated execution cut hands-together arpeggio
> interventions from up to 204 a run to 11 to 41 while preserving breadth, but
> did not restore hands-together scale progression for `cohort_10` and
> `cohort_20`. Nothing is promoted; the scheduler stays at v1-14, and
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
| `cohort_10`, 0:100 | 0 / 109 / 18                          | 331 / 248 / 256      | 1,193 / 921 / 990 | 0.51 / 0.03 / 0.06       |
| `cohort_10`, 2:102 | 0 / 166 / 41                          | 294 / 211 / 224      | 1,134 / 852 / 924 | 0.28 / 0.01 / 0.02       |
| `cohort_20`, 0:100 | 0 / 85 / 14                           | 338 / 230 / 238      | 1,234 / 947 / 993 | 0.99 / 0.70 / 0.87       |
| `cohort_20`, 1:101 | 0 / 82 / 13                           | 338 / 162 / 189      | 1,125 / 852 / 925 | 0.96 / 0.07 / 0.38       |
| `cohort_20`, 4:104 | 0 / 136 / 13                          | 362 / 191 / 166      | 1,218 / 886 / 984 | 0.95 / 0.26 / 0.21       |

**Relief does what it bounds.** Hands-together arpeggio interventions fall to 11
to 41 a run in every profile, and stay there: no group rebounds to take the next
run of opportunities. Most withheld opportunities went to another realization of
the same requirement outside the group, for `cohort_10` 35 to 215 of 38 to 292.
The evidence that triggered it was almost all timed and unmanaged; never-started
attempts were 2 to 15 a run, untimed 0 to 7, incomplete 0 to 3.

**Breadth survives.** Arpeggio coverage is never lower than allocation's, 14 in
every run but three, which reach 18 or 24. Worst arpeggio waits stay at 54 to 97
opportunities, against 53 to 102 for allocation and 130 to 1,395 for v1-14, and
held-out right-hand arpeggios stay within 0.01 of allocation's and arpeggio
retrieval is never lower.

**The scale frontier does not recover.** On the losing pairs relief returns 88
to 144 slots a run to ordinary selection, mostly to scale ranking, but scale
frontier steps move by -25 to +27 and hands-together scales come back only for
`cohort_20` on 0:100 and 1:101, in part. Scale attempts stay 17 to 20% below
v1-14 on every losing pair, because allocation's remaining arpeggio service, 74
to 143 interventions a run, and the arpeggios its breadth opens both keep
drawing ordinary ranking and the arpeggio frontier: arpeggio frontier steps rise
from none under v1-14 to 26 to 86 under relief. Hands together is the last stage
of a scale's progression, so a fifth fewer scale attempts within the same run
removes most of it.

Relief also moved other outcomes. On `cohort_20` 4:104, held-out left-hand
scales fell from 0.93 to 0.65; on `cohort_20` 2:102 and 3:103, arpeggio coverage
reached 24 and arpeggio retrieval 0.99. `cohort_11` and `cohort_12`, which lost
at most 0.06 of hands-together scales to allocation, lose at most 0.06 under
relief too.

## Reading

Of the three outcomes declared before the runs, this is the second:
hands-together arpeggio interventions fall and the scale frontier does not
recover. That shows this reduction was not enough, not that capacity is
irrelevant: scale attempts stay 17 to 20% below v1-14 while other arpeggio work
keeps drawing ordinary ranking, so relief never returned the scale practice
whose loss it was meant to test, and progression may depend on which
opportunities return and when. The service relief bounds was 37 to 56% of
allocation's interventions on the losing pairs, and bounding it cost no breadth
in these runs. Whether it cost preparatory learning is open: unmanaged attempts
still teach this player's execution, so service without demonstrated execution
is not practice that taught nothing.

## What it does not establish

One setting of trigger, budget, and window, on one memory configuration, four
cohort players, and five calendars each. Whether hands-together scales or
arpeggio breadth is worth more to a learner is a product question these runs
cannot answer, and a run of this length may end before either player would reach
both.
