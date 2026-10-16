# Calendar retention

> **Status:** counterfactual on the frozen
> [plausibility cohort](plausibility-cohort.md), 24 players on five paired
> seeds, three calendars, two arms, 720 trajectories. Calendar gaps activate the
> synthetic player's forgetting, but only of what practice had gained, which is
> small against where it started. Allocation leaves the median player's retained
> gain after time away nearly unchanged, moves it from scales to arpeggios, and
> costs some players and seeds much more than the median. The scheduler's belief
> falls far faster across a gap than the player does. Nothing is promoted; the
> scheduler stays at v1-14.

The [cohort comparison](cohort-comparison.md) found allocation lowers the
scheduler's estimate of covered scales' retrieval in nearly every pair, on
near-daily practice where forgetting had little room to act. This experiment
gives it room: the same practice, re-dated around absences, read by a held-out
assessment that asks both arms the same questions.

## What was run

v1-14 and allocation at `k` of 2 with protection floor 0.60, on every cohort
player and the five seed pairs (0:100 to 4:104). Each pair's drawn calendar is
re-dated three ways, keeping every session and its slots, so the calendars
differ in when practice happens and not in how much is offered:

| Calendar       | Change                                             | Days | Absences of 4+ days |
| -------------- | -------------------------------------------------- | ---- | ------------------- |
| Reference      | none                                               | 116  | 3                   |
| Interrupted    | an added 5 to 10 days away after every 8th session | 179  | 12                  |
| Extended break | an added 21 days away at the middle of the slots   | 137  | 4                   |

Days and absences are medians over seed pairs. Attempts per run differ by at
most 43 of about 1,300 between arms or calendars, since acquisition tasks take a
slot and write no attempt. The reference runs reproduce the cohort comparison's
attempts and outcomes exactly.

```console
dart run keyrecall_simulation:calendar_retention --profiles 0,1,2
```

Without `--profiles`, the tool runs six players spanning ability and durability.

All 720 trajectories are kept as the frozen player's reference in
[`calendar-retention.csv`](data/calendar-retention.csv), one row per run,
projected from the tool's JSON lines (24 profiles, `--profiles 0,...,23`). It
holds coverage, health, and the closing and delayed readings by family, the
lowest true retrieval at any arrival, and return-session tests. A rerun of the
reference calendar on every profile, and of `cohort_19` interrupted and
`cohort_13` extended break, matched its source in every value.

A held-out reading closes the session before each absence, opens the session
after it, and closes that session; two more close the run and follow it after 21
days away. Each reading asks every material with each hand and hands together,
unguided, three times, from its own fixed draws, and practices nothing; a test
pins that readings leave the run's journal byte-identical. A reading reports
three things:

- **Held-out**: retrieval and managed execution on the assessment.
- **Estimated**: the scheduler's expected retrieval of the same questions, from
  a copy of its belief.
- **True**: the player's familiarity with each material, which is its retrieval
  probability. Retained gain is the sum, over all 72 materials, of familiarity
  above where the player started: the expected number of extra materials
  retrieved, beyond the player's starting point, if each were asked once.

## Forgetting is activated, within what was gained

Under v1-14, players ended the run with a retained gain of 2.2 to 11.4
materials. By familiarity half-life, medians per run:

| Half-life         | Players | Gain lost in 21 days | Lost across interrupted absences | Held-out retrieval lost there |
| ----------------- | ------- | -------------------- | -------------------------------- | ----------------------------- |
| Under 100 days    | 5       | 17%                  | 2.4 materials                    | 0.029                         |
| 100 to 300 days   | 10      | 8%                   | 1.3 materials                    | 0.015                         |
| 300 days and more | 9       | 3%                   | 0.4 materials                    | 0.005                         |

On the held-out reading this is small. The player's familiarity decays toward
where it started, 0.4 to 0.6 for every material, not toward zero, and practice
had moved it a few hundredths per material on average. The largest loss in any
run, across the interrupted calendar's twelve absences, was 0.057 of held-out
retrieval and 0.079 of held-out managed execution. A player can lose no more
than practice gave it, so this model cannot show a learner who forgets below
where they began.

## Allocation against v1-14

Pairs better and worse, then the median paired difference, over all 120 pairs
per calendar. Coverage is read from the committed state after the last session:

| Outcome                         | Reference     | Interrupted   | Extended break |
| ------------------------------- | ------------- | ------------- | -------------- |
| Scales covered                  | 91/4, +2      | 84/15, +2     | 85/8, +2       |
| Arpeggios covered               | 93/10, +2     | 94/10, +2     | 95/13, +3      |
| Retained gain, all, after delay | 54/66, -0.012 | 65/55, +0.015 | 57/63, -0.003  |
| Retained gain, scales           | 40/80, -0.098 | 42/78, -0.111 | 35/85, -0.082  |
| Retained gain, arpeggios        | 79/41, +0.101 | 76/44, +0.074 | 81/39, +0.080  |
| Held-out retrieval, after delay | 68/43, +0.002 | 53/56, +0.000 | 46/60, -0.001  |
| Held-out managed, after delay   | 44/70, -0.002 | 57/61, -0.002 | 45/69, -0.003  |
| Gain lost across absences       | 79/41, +0.001 | 80/40, +0.010 | 81/39, +0.004  |

Allocation covers more of both families on every calendar, most for the low
ability third (+6 to +7 scales, +4 to +4.5 arpeggios). What the player retains
after a delay differs in total by under 0.07 of a material at the median in
every ability third, slightly up for the low third and slightly down for the
high third. Its composition differs more: retained scale gain falls and arpeggio
gain rises, most for the middle third (scales -0.16 to -0.18 after the delay).
The high third gains little coverage and loses a little scale gain (-0.04 to
-0.07), and its held-out managed execution after the delay is lower in 22 to 28
of 40 pairs, by about 0.005.

Allocation loses slightly more gain across absences, on arpeggios, because it
has more arpeggio gain to lose, and less on scales. Held-out readings on arrival
after an absence, which ask both arms the same questions, differ by a mean of
under 0.003. Readings at the end of the run and after the delay differ between
arms in the same way, so a gap does not open a difference that near-daily
practice hid.

The cohort comparison's lower estimate of covered scales therefore corresponds
to a real loss of retained scale gain in this player, about a tenth of a
material at the median and up to a fifth for the middle third, offset by
arpeggio gain of similar size.

## The tails

The medians hide pairs where allocation cost much more. Paired differences in
total retained gain after the delay, allocation minus v1-14, in materials:

| Calendar       | Lowest | 10th percentile | Median | 90th percentile | Highest |
| -------------- | ------ | --------------- | ------ | --------------- | ------- |
| Reference      | -1.26  | -0.21           | -0.012 | +0.22           | +0.67   |
| Interrupted    | -0.74  | -0.22           | +0.015 | +0.29           | +0.80   |
| Extended break | -1.11  | -0.20           | -0.003 | +0.21           | +0.67   |

Most of the spread follows learning rate: a player who learns faster has more
gain for a policy to move, and the gap between its best and worst pair rises
with learning rate (rank correlation 0.72 to 0.81). The three worst pairs on the
reference calendar, from `cohort_13`, `cohort_15`, and `cohort_19`, belong to
three of the five fastest learners, and each of them also has a pair where
allocation retained 0.2 to 0.7 materials more.

One player is consistently worse. `cohort_19`, of middle ability, stronger at
arpeggios, and a fast learner, retained less under allocation in all five pairs
on both re-dated calendars (0.17 to 0.74 materials on the interrupted one),
mostly in scales, and its held-out managed execution after the delay was lower
in every interrupted pair, by up to 0.065. Allocation did not consistently raise
its coverage in return: on those calendars it covered from 3 fewer to 12 more
requirements per pair, and fewer in 3 of 10. No player retained more in all five
pairs on any calendar.

## The scheduler's belief and the player diverge

The scheduler's expected retrieval on the held-out questions, minus the player's
true retrieval, as medians over all readings of each kind:

| Reading           | v1-14            | Allocation       |
| ----------------- | ---------------- | ---------------- |
| Before an absence | +0.017 to +0.026 | +0.038 to +0.051 |
| Arriving after it | -0.142 to -0.156 | -0.130 to -0.145 |
| End of the run    | +0.055 to +0.080 | +0.092 to +0.108 |
| 21 days after     | -0.252 to -0.318 | -0.234 to -0.307 |

Ranges are over the three calendars. Across 21 days, the scheduler's expected
retrieval fell by 0.16 to 0.49 while the player's fell by at most 0.017. The
learner model's memory decays faster and further than the player's, which decays
slowly toward its starting familiarity. Which is closer to a person is not
something this simulation can say, but every decision after a gap here was made
against a belief well below the player it was choosing for.

Under allocation the scheduler expects more of the held-out set at the end of
the run (+0.03 to +0.04), having seen more of it, and its expectation falls
further across absences.

## Return sessions

The session after each absence, under each policy:

| Calendar       | Arm        | Retrieval success | Never started |
| -------------- | ---------- | ----------------- | ------------- |
| Reference      | v1-14      | 0.586             | 0.313         |
| Reference      | Allocation | 0.555             | 0.321         |
| Interrupted    | v1-14      | 0.562             | 0.332         |
| Interrupted    | Allocation | 0.548             | 0.331         |
| Extended break | v1-14      | 0.579             | 0.317         |
| Extended break | Allocation | 0.555             | 0.325         |

Means over return sessions (456, 1,416, and 576 per arm). Each policy chose what
these sessions asked, so the lower success under allocation is not a measure of
what the player recalls; the held-out readings on arrival do not show it.

## What this establishes

Allocation improves coverage across the cohort while leaving median total
retained gain nearly unchanged in this player model. It redistributes retained
gain between families, from scales to arpeggios, and some player and seed
combinations lose much more than the median, one player in every pair. The
held-out assessment moved little under either policy, because the player's
forgetting is bounded by its small gains. Judging allocation needs the paired
distribution, including its lower tail, not only medians of breadth and
retention.

## What it does not establish

That allocation is harmless to a learner who forgets more than this. The
player's familiarity cannot fall below its starting value, and its gains are
small, so any policy's effect on retention is bounded here; a retrieval model
with its own learning and forgetting would bound it differently. The divergence
between belief and player is a disagreement between two models, not a measured
miscalibration against people. These are synthetic players.
