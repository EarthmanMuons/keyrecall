# Retrieval memory

> **Status:** a separately versioned retrieval model for the synthetic player
> (`retrieval-memory-1`), built and characterized on fixed practice schedules
> with no scheduler. Its contracts are tested. No policy has been compared under
> it. Every parameter is an uncalibrated hypothesis; the frozen cohort and every
> earlier result are unchanged.

The [calendar retention](calendar-retention.md) study found that the frozen
player's familiarity starts at 0.4 to 0.6, gains a few hundredths per material
from practice, and decays back to where it started. That bounds what any policy
could cost or gain in retention. This model removes the bound, so a later
comparison can ask whether allocation's results depend on it.

## The model

Each material holds a trace: a half-life and the instant it was last encoded.
Retrievability halves every half-life since then and decays toward zero, so
forgetting can take back what practice gave and what the player came with, and
two materials left alone keep their own histories rather than returning to one
baseline. At the start, each material's trace is placed so that it is
retrievable with the player's starting familiarity, at an initial half-life.

An attempt encodes the material by what it asked of the player, lengthening the
half-life by a factor of one plus a gain and resetting retrievability:

| Event                          | Default gain |
| ------------------------------ | ------------ |
| Unguided retrieval, succeeded  | 0.6          |
| Notes previewed, started       | 0.3          |
| Notes cued throughout, started | 0.1          |
| Acquisition work, played       | 0.1          |
| Unguided retrieval, failed     | none         |
| Not started                    | none         |

A failed unguided attempt shows the player nothing, so it teaches nothing.

Spacing responsiveness is the share of each gain that depends on the time since
the material was last encoded: the gain is scaled by `1 - w + w * 2g / (g + p)`
for a gap `g` and a pivot `p` of one day. At zero it is the control, in which
massed and spaced encodings teach the same. At any setting, encodings a pivot
apart teach the plain gain, so the knob moves massed and spaced practice apart
without changing what daily practice teaches. Half-lives stop growing at ten
years.

Execution is learned and forgotten exactly as in the frozen player. The model
replaces only how familiarity moves.

```console
dart run keyrecall_simulation:retrieval_memory
```

### Contracts

A player opts in by carrying the model; one without it runs as before, and the
pinned journal and census digests are unchanged. Tests pin that, under the
model:

- repeated successful retrieval strengthens later recall;
- forgetting takes a material below where it started, toward zero;
- materials left alone keep their own histories;
- with spacing at zero, massed and spaced encodings leave identical traces, and
  with spacing on, daily encodings leave the same trace as without it while
  massed ones teach less and weekly ones more;
- a failed unguided retrieval leaves the memory as it was, and cued practice and
  acquisition work strengthen later unguided recall;
- every attempt carries its own instant, and practice or a reading before the
  last practice is refused, since that trace already contains what came after;
- a held-out reading teaches nothing and moves no clock, so later outcomes are
  identical with or without it.

The tests for failed retrieval, the clock, and the reading were each checked by
breaking the model and watching them fail.

## Characterization

One material, six attempts on one guidance rung, massed into minutes or spread
daily or weekly, all ending on the same day 43 days after the start, read
afterwards. Means over 400 seeded players of the `developing` archetype, whose
execution is otherwise unchanged. Unless a table varies it, the initial
half-life is 60 days, learning strength 1 (the default gains), spacing 0.5, and
starting familiarity 0.6.

Forgetting, by initial half-life, unguided daily practice against none:

| Initial half-life | Schedule        | At the end | 30 days | 90 days | A year |
| ----------------- | --------------- | ---------- | ------- | ------- | ------ |
| 15 days           | none            | 0.08       | 0.02    | 0.00    | 0.00   |
| 15 days           | unguided, daily | 0.48       | 0.36    | 0.24    | 0.08   |
| 60 days           | none            | 0.37       | 0.26    | 0.13    | 0.01   |
| 60 days           | unguided, daily | 0.96       | 0.92    | 0.84    | 0.62   |
| 240 days          | none            | 0.53       | 0.49    | 0.41    | 0.18   |
| 240 days          | unguided, daily | 1.00       | 0.99    | 0.97    | 0.90   |

Spacing, retrievability a year after unguided practice:

| Schedule | Spacing 0 | Spacing 0.5 | Spacing 1 |
| -------- | --------- | ----------- | --------- |
| Massed   | 0.57      | 0.41        | 0.14      |
| Daily    | 0.58      | 0.62        | 0.65      |
| Weekly   | 0.65      | 0.78        | 0.85      |

With spacing at zero the schedules differ only through how many retrievals
succeeded: weekly practice starts earlier, when more is remembered.

Learning strength, which scales every gain, a year after daily practice:

| Schedule  | Strength 0.5 | Strength 1 | Strength 2 |
| --------- | ------------ | ---------- | ---------- |
| None      | 0.01         | 0.01       | 0.01       |
| Unguided  | 0.33         | 0.62       | 0.80       |
| Previewed | 0.16         | 0.40       | 0.74       |
| Cued      | 0.05         | 0.10       | 0.27       |

Three properties matter for any comparison under this model:

- **Support performs better and teaches less.** Previewed practice ends at 1.00
  where unguided ends at 0.96, and retains 0.40 against 0.62 a year later. A
  policy judged by success during practice would prefer support that this model
  says costs retention.
- **Failed retrieval teaches nothing, so support matters more to a player who
  knows less.** Starting at 0.3, unguided daily practice succeeds 2.8 times in
  six and retains 0.39 a year later, about what previewed practice retains
  (0.37). Starting at 0.6, unguided retains 0.62 against 0.40.
- **What the player came with is forgotten.** Left alone, a material known at
  0.6 falls to 0.37 by the end of the schedule and to nearly nothing within a
  year at a 60-day half-life. That is a strong assumption about adults who
  learned scales long ago, and it is the opposite of the frozen player's.

## What comes next

A compact comparison of v1-14 against allocation at `k` of 2, across learning
strength, initial half-life, and spacing responsiveness, before anything wider.
It keeps two named regression cases from the frozen model: `cohort_19`, which
retained less under allocation in every re-dated pair, and `cohort_13` on seed
pair 0:100, the worst paired loss on the reference calendar (-1.26 materials). A
better player model should not make either disappear without an explanation. The
frozen model's 720 calendar trajectories stay the reference for it.

## What it does not establish

That people learn or forget like this. The decay is exponential, where
measurements of human forgetting are often closer to a power law; the gains, the
pivot, and the ceiling are guesses; and the model has no notion of interference
between similar materials. It exists to find out whether a scheduler result
depends on how retrieval is modeled, not to say how it should be.
