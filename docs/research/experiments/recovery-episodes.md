# Recovery episodes

> **Status:** audit of the frozen v1-14 cohort baseline, five paired seeds.
> Recovery's steady third of attempts is neither churn in the scheduler nor
> instruction that works. Episodes are short and always end, but they leave the
> next retrieval test no likelier to succeed than after a success, because the
> synthetic player's retrieval barely learns. Nothing is promoted; the scheduler
> stays at v1-14.

The [plausibility cohort](plausibility-cohort.md) spent 29 to 39% of its
attempts in recovery, with no decline over four months while guidance fell and
managed execution rose. This audit asks whether that is healthy challenge
regulation, repeated remediation without progress, or an artifact of the
synthetic player.

## What recovery is in v1-14

An episode opens on a tested retrieval failure: an unguided or notes-previewed
attempt where the notes did not come. The next decision admits exactly one
candidate, the same exercise one step more supported. A previewed failure steps
to continuous cueing, which tests no retrieval and so cannot fail. An episode is
therefore at most two recovery attempts, and it always ends.

```console
dart run keyrecall_simulation:recovery_episodes
```

The audit reruns the 120 cohort trajectories, which reproduce the baseline
exactly, and rebuilds episodes from each attempt's own recorded decision. Census
decisions are not used: an acquisition task is a decision with no attempt
record, so the two sequences drift apart wherever acquisition is offered.

## Results

Across all 120 trajectories:

| Measure                                                  | Value          |
| -------------------------------------------------------- | -------------- |
| Episodes per 100 attempts, first third to last third     | 28.6 to 26.4   |
| Recovery attempts per episode, 0 / 1 / 2                 | 5% / 63% / 32% |
| Entry attempt never started                              | 93%            |
| Exit: retrieved with preview                             | 44%            |
| Exit: reached continuous cueing                          | 49%            |
| Exit: session ended first                                | 7%             |
| Recovery attempts that were never started                | 17%            |
| Next retrieval test on the strand succeeded              | 58%            |
| Control: next test after a success succeeded             | 59%            |
| Next test managed                                        | 37%            |
| Strands never retested                                   | 13%            |
| Episodes per strand, median / p90 / max                  | 2 / 6 / 23     |
| Episodes that were a strand's third or later             | 44%            |
| Longest run of episodes each followed by a failed retest | 9              |

By ability band, the low third of the cohort entered 28.6 episodes per 100
attempts and the high third 25.3; their retests succeeded 53% and 64% of the
time, against controls of 54% and 63%. A strand's third or later entry was 55%
of the low band's episodes and 34% of the high band's.

The weak profiles' coverage swings between seed pairs are not recovery's doing.
Their episode rate stayed between 24 and 29 per 100 attempts in every pair. What
differed was where practice went: in the pair where the weakest scale player
covered 3 scales and all 24 arpeggios, 85% of its episodes were on arpeggios,
against 39 to 52% in the other pairs.

## Why the share does not fall

Episodes end and rarely consume attempts without evidence, so this is not the
scheduler looping. Nor does recovery visibly help: a strand's next test after an
episode succeeds at the same rate as its next test after a success.

The cause is in the synthetic player. It retrieves a material's notes with
probability equal to its familiarity with that material, drawn independently on
every attempt, and that familiarity grows only through motor practice, by at
most the learning rate (0.005 to 0.02) per attempt, starting from 0.4 to 0.6. A
strand practiced a few dozen times over four months gains a few tenths at most.
Retrieval therefore stays close to a fixed coin, independent of whether the last
attempt succeeded or was supported, and recovery has nothing in the player to
act on. Almost every episode opens on an attempt that never started, which is
how the player represents notes that did not come.

## What this means for the cohort comparison

Recovery's workload under any policy will reflect this retrieval process, and
retrieval outcomes (coverage, which needs a retrieved attempt, and retrieval
health) are measured against a player whose knowledge of the notes barely
responds to practice. Policies can still be compared on them, since every arm
faces the same player, but a difference in retrieval cannot be read as one
policy teaching the notes better.

## What it does not establish

How real learners' retrieval responds to supported repetition. The player model
ties retrieval learning to motor learning by construction; whether to give
retrieval its own learning, and from what evidence, is a model decision for its
own experiment, not a change to make under the frozen cohort.
