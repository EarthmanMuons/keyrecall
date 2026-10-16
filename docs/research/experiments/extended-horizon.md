# Extended horizon

> **Status:** 40 trajectories on `cohort_10` and `cohort_20`, practiced to three
> times the original calendar's slots under
> [`retrieval-memory-2`](retrieval-memory.md) at 1:60:0.5. Allocation at `k` of
> 2 delays hands-together scales rather than preventing them: it reaches
> held-out hands-together scales of 0.9 from 0 to 0.75 of an original run later
> than v1-14 and ends level with it or within 0.08. v1-14 never builds arpeggio
> breadth, and forgets what it has. Corrected context relief moves neither
> milestone consistently. Nothing is promoted; the scheduler stays at v1-14.

[Context relief](context-relief.md) left the hands-together scales allocation
cost two players unrecovered within the original run. This asks whether the loss
is a delay or a lasting divergence, by practicing on.

## Design

Each seed's demo calendar is extended past its end. The generator draws day by
day from one seeded stream, so the longer calendar begins with exactly the
original sessions; a test pins that for five seeds, and another that a census
over a longer calendar writes the shorter run's attempts and decisions
unchanged. The tool refuses an extension that changes an original session.

Readings are taken at the session closing each quarter of the original run's
slots, twelve to three times, a day after it starts and again 21 days on, with
nothing practiced in between: held-out managed play by family and hands,
held-out retrieval, and true retrievability. Checkpoints fall on session
boundaries, so they align within a seed pair but not exactly across pairs. Each
reading's decision count was checked against its planned slots, and the
one-times checkpoint reproduces the [memory comparison](memory-comparison.md)'s
attempts and delayed retrievability exactly in all 20 v1-14 and allocation runs.

```console
dart run keyrecall_simulation:scale_execution --profile 19 \
  --configs 1:60:0.5 --seeds 4:104 \
  --arms v1-14,alloc-2,relief:10:1:5 --horizon 3
```

Arms: v1-14, allocation at `k` of 2 with protection floor 0.60, and allocation
with context relief at trigger 10, budget 1, window 5. The relief arm was run
twice, with the classifier that counted incomplete attempts carrying a motor
score as unmanaged and with the corrected one; only the corrected run is
reported here. One original run is about 1,300 slots and 120 days of this
calendar, so a quarter is about 30 days.

## Results

When held-out hands-together scales first reach 0.9, in multiples of the
original slots, and what each arm holds at three times:

| Player, seed pair  | HT scales 0.9, v1-14 / alloc | 20th HT scale strand managed, v1-14 / alloc | HT scales at 3x | Arpeggios retrievable at 3x, of 24 | Right-hand arpeggios at 3x |
| ------------------ | ---------------------------- | ------------------------------------------- | --------------- | ---------------------------------- | -------------------------- |
| `cohort_10`, 0:100 | 1.5 / 2.0                    | 1,439 / 2,129                               | 0.98 / 0.99     | 5.5 / 23.9                         | 0.17 / 1.00                |
| `cohort_10`, 1:101 | 2.5 / 2.75                   | 2,405 / 2,634                               | 0.98 / 0.92     | 8.4 / 23.9                         | 0.33 / 1.00                |
| `cohort_10`, 2:102 | 1.75 / 2.25                  | 1,672 / 2,226                               | 1.00 / 0.99     | 7.1 / 23.8                         | 0.25 / 1.00                |
| `cohort_10`, 3:103 | 2.0 / 2.5                    | 2,305 / 2,864                               | 1.00 / 0.97     | 6.6 / 23.9                         | 0.25 / 1.00                |
| `cohort_10`, 4:104 | 2.25 / 3.0                   | 2,371 / 3,080                               | 1.00 / 0.92     | 7.3 / 23.9                         | 0.32 / 1.00                |
| `cohort_20`, 0:100 | 1.0 / 1.25                   | 883 / 1,285                                 | 0.98 / 1.00     | 4.1 / 23.9                         | 0.04 / 1.00                |
| `cohort_20`, 1:101 | 1.0 / 1.5                    | 945 / 1,502                                 | 0.94 / 1.00     | 5.4 / 23.9                         | 0.26 / 1.00                |
| `cohort_20`, 2:102 | 0.75 / 1.0                   | 677 / 1,107                                 | 0.96 / 1.00     | 4.2 / 23.9                         | 0.12 / 1.00                |
| `cohort_20`, 3:103 | 0.75 / 0.75                  | 862 / 921                                   | 1.00 / 1.00     | 5.6 / 23.9                         | 0.08 / 1.00                |
| `cohort_20`, 4:104 | 0.75 / 1.25                  | 910 / 1,593                                 | 0.94 / 1.00     | 4.6 / 23.9                         | 0.14 / 1.00                |

The milestone is read at quarter checkpoints, so each delay is good to a quarter
of a run. Strand milestones are in decisions.

**Hands-together scales are delayed, not lost.** Allocation reaches 0.9 later in
nine pairs of ten: by a quarter to three quarters of a run for `cohort_10`,
about 30 to 90 days of this calendar, and by up to half a run for `cohort_20`.
Its 20th managed hands-together scale strand comes 59 to 709 decisions later. By
three times both arms are at 0.92 or more, and `cohort_20` ends higher under
allocation in four pairs as v1-14's own hands-together scales slip to 0.94 to
0.98.

**Arpeggio breadth does not converge.** v1-14 never opens more than a few
arpeggios, and those it has fade: its arpeggios retrievable 21 days after a
checkpoint fall from 9.1 to 11.8 at the original end to 4.1 to 8.4 at three
times. Allocation holds 23.8 to 23.9 of 24 by three times in every pair, and
right-hand arpeggios at 1.00 against 0.04 to 0.33. Neither arm demonstrates
hands-together arpeggios: at most three such strands are ever managed.

**Allocation's own service is front-loaded.** Almost all its interventions fall
within the original run: `cohort_10`'s hands-together arpeggio interventions
grow by at most 13 between one and three times. Over the same stretch ordinary
ranking and the arpeggio frontier keep choosing arpeggios, so by three times
`cohort_10` on 0:100 has 816 arpeggio ranking decisions under allocation against
413 under v1-14.

**Scale retrieval holds in both.** Scales retrievable 21 days after the
three-times checkpoint are 45.0 to 47.8 of 48 under v1-14 and 47.7 to 47.8 under
allocation.

**Corrected relief moves neither milestone consistently.** It reaches
hands-together scales of 0.9 at the same checkpoint as allocation in seven
pairs, earlier in two, and later in one. At three times it holds 14 arpeggios,
not 24, on two `cohort_10` pairs, so on those calendars bounding hands-together
arpeggio service also ended with less of the breadth allocation reaches.

## Reading

Of the outcomes declared before the runs, this is allocation catching up after
an additional practice investment, alongside a breadth difference that never
closes. Neither cancels the other. Allocation costs these two players up to
three quarters of a run, up to about three months of this calendar, before their
scales go hands together; v1-14 costs them nearly every arpeggio, indefinitely.
Which trajectory serves a learner better is the product question of how much
hands-together progression General Fluency should protect while breadth grows,
and these runs can price it in practice but not decide it.

## What it does not establish

Two players, one memory configuration, and one calendar per seed pair. The
readings assume nothing is practiced in the 21 days after a checkpoint, and the
memory model's reset to full recall after any encoding holds throughout. A
learner's time is not interchangeable across a year as the calendar's slots are,
and real learners stop, change goals, or plateau in ways this player does not.
