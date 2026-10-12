# Early follow-through

> **Status:** counterfactual, five paired seeds, four arpeggio ability offsets,
> allocation at `k` of 2 and 4, protection floor 0.60. One prioritized,
> timing-valid follow-up per introduced strand turns introductions into managed
> execution within a few decisions instead of 143 to 525, and the share that
> converts rises steeply with ability. Prolonged band-floor exclusion exists
> only at the original stress offset, where follow-through all but removes it
> without managing more strands. The cost is scale maintenance, in every pair.
> Nothing is promoted; the scheduler stays at v1-14.

The [exclusion census](exclusion-census.md) traced the scale-strong learner's
prolonged arpeggio exclusions to introductions that never reached managed
execution: too short to time, an early follow-up just short of the threshold,
and then no return while the material was still eligible. The question here is
whether owning that handoff helps, and how much of the problem depends on how
weak the player is.

## The rule

A strand is an execution context: a material, its hands, and their motion. It is
introduced by its first attempt. On a slot ordinary ranking decided and
allocation left alone, whose winner is not protected, the strand introduced
earliest that still has no demonstrated tempo, has not had its follow-through,
and has a fully eligible realization that can carry a motor score in the final
selectable set takes the slot with the best of them. Once per strand. Admission,
eligibility, tempo, guidance, and measurement are unchanged, and an unmanaged
follow-through leaves the strand to ordinary selection.

A trigger is recorded for each follow-through: `neverTimed` when no earlier
attempt on the strand carried a motor score, `timedUnmanaged` when one did and
none was managed. Disabled, the rule leaves the journal byte-identical to
allocation's and only counts what it would have had to work with.

```console
dart run keyrecall_simulation:follow_through --offsets=-1.2,-0.8,-0.4,0
```

The scale-strong player with only its arpeggio offset changed (-1.2, the
original, then -0.8, -0.4, and 0), zero transfer between families throughout, on
the same five seed pairs: allocation alone and with follow-through, at `k` of 2
and 4. 80 trajectories. The offsets are sensitivity levels, not estimates of any
real learner.

## Results

Arpeggio strands, medians across pairs at `k` of 2, allocation alone then with
follow-through; `k` of 4 agrees in direction throughout:

| Offset | Introduced |  Managed | Managed share | Decisions to timed | Decisions to managed | Band-floor requirement-decisions |
| -----: | ---------: | -------: | ------------: | -----------------: | -------------------: | -------------------------------: |
|   -1.2 |   51 to 44 | 25 to 24 |  0.47 to 0.52 |            49 to 2 |           406 to 291 |                      1,860 to 92 |
|   -0.8 |   54 to 55 | 36 to 35 |  0.66 to 0.65 |            53 to 2 |             209 to 8 |                           0 to 0 |
|   -0.4 |   60 to 64 | 43 to 52 |  0.72 to 0.89 |            61 to 2 |             147 to 5 |                           0 to 0 |
|      0 |   60 to 59 | 52 to 58 |  0.85 to 0.98 |            50 to 2 |             143 to 6 |                           0 to 0 |

Gaps are from a strand's introduction, in decisions, for the strands that got
there. Decisions to timed and to managed fell in every pair at every offset and
both `k`. Managed strands rose in every pair at -0.4 and 0, in four pairs at
-0.8 at `k` of 4 and both ways at 2, and both ways at -1.2. At -1.2 fewer
strands were introduced in most pairs, so its higher managed share is partly a
smaller denominator.

How the follow-throughs themselves went, summed over pairs at `k` of 2:

| Offset | Trigger          | Given | Managed | Near miss (0.4 to 0.5) | Below 0.4 | Incomplete | Not started |
| -----: | ---------------- | ----: | ------: | ---------------------: | --------: | ---------: | ----------: |
|   -1.2 | never timed      |   152 |     16% |                     35 |        29 |         51 |          13 |
|        | timed, unmanaged |    58 |     16% |                     12 |        17 |         18 |           2 |
|   -0.8 | never timed      |   212 |     42% |                     29 |        28 |         38 |          28 |
|        | timed, unmanaged |    61 |     44% |                      9 |         7 |         16 |           2 |
|   -0.4 | never timed      |   229 |     64% |                     25 |         6 |         26 |          26 |
|        | timed, unmanaged |    73 |     66% |                      8 |         3 |          8 |           6 |
|      0 | never timed      |   221 |     71% |                      7 |         0 |         17 |          41 |
|        | timed, unmanaged |    78 |     76% |                      3 |         0 |          6 |          10 |

At `k` of 4 the rates were 19% and 16%, 47% and 39%, 62% and 68%, 69% and 80%.
The two triggers convert at much the same rate at each offset. Scale strands
were all `timedUnmanaged`, since their introductions already carry a motor
score.

Without follow-through, a strand awaiting one spent its decisions this way (`k`
of 2, share of strand-decisions):

| Offset | Band floor | Recovery | Frontier step | Free ranking slot | Guidance probe | Protected winner | Allocation |
| -----: | ---------: | -------: | ------------: | ----------------: | -------------: | ---------------: | ---------: |
|   -1.2 |        35% |      14% |           14% |               12% |             8% |               8% |         7% |
|   -0.8 |        <1% |      22% |           23% |               17% |            12% |              13% |         9% |
|   -0.4 |         1% |      22% |           24% |               16% |            12% |              13% |         9% |
|      0 |        <1% |      23% |           25% |               16% |            12% |              13% |         9% |

A free ranking slot with a timing-valid follow-up in the selectable set, which
ranking did not choose, was 12 to 17% of the wait at every offset: the window
the transition audit found is there for every player, not only the weakest.

What it cost, pairs better and worse with follow-through, at `k` of 2 then 4:

| Outcome                        | -1.2     | -0.8     | -0.4     | 0        |
| ------------------------------ | -------- | -------- | -------- | -------- |
| Arpeggios covered              | 2/2, 4/0 | 1/1, 3/1 | same     | same     |
| Retrieval, all in scope, scale | 2/3, 0/5 | 0/5, 0/5 | 0/5, 0/5 | 0/5, 0/5 |
| Retrieval among covered, scale | 3/2, 3/2 | 0/5, 0/5 | 0/5, 0/5 | 0/5, 0/5 |
| Worst missed run, scale        | 4/1, 4/1 | 1/4, 1/3 | 3/2, 2/3 | 0/5, 1/4 |

Median scale retrieval across the scope fell by 0.004 to 0.044. Every scale was
covered in every arm.

### What the follow-throughs displaced

The rule is family-neutral, so the cost above is the combined policy's. A rerun
of the `k` of 2 follow-through arms attributes each follow-through by the
strand's family and by what the displaced winner's requirement needed at that
decision:

| Offset | Follow-throughs | Scale strands | Displaced uncovered work | Displaced covered, healthy | Displaced covered, due |
| -----: | --------------: | ------------: | -----------------------: | -------------------------: | ---------------------: |
|   -1.2 |             233 |           10% |                      82% |                        13% |                     5% |
|   -0.8 |             307 |           11% |                      68% |                        24% |                     7% |
|   -0.4 |             337 |           10% |                      51% |                        38% |                    11% |
|      0 |             323 |            7% |                      64% |                        24% |                    11% |

Scale strands are about a tenth of follow-throughs, so an arpeggio-only rule
would differ little. Maintenance that was due is rarely displaced directly. The
scale retrieval cost more likely comes from practice of healthy covered scales
that would have refreshed them, and from the extra owed service allocation does
once uncovered work is pushed back; this attribution does not separate the two.

## What this establishes

Selection continuity is a real gap for every offset, not just the stress case.
Without a rule that owns it, the first managed attempt on an introduced arpeggio
comes 143 to 525 decisions after the introduction, and a free ranking slot with
a valid follow-up goes unused for a sixth of that wait. One prioritized
follow-up closes the gap to a handful of decisions.

Whether that follow-up succeeds depends on the learner, as it should. Conversion
runs from about one in six at -1.2 to about three in four at 0, the same for
strands that had never been timed and strands that had and fell short. At
moderate weakness, follow-through manages more strands; at -0.8 it manages about
as many, much sooner; at -1.2 it manages no more of them.

Prolonged exclusion by the band floor is specific to the -1.2 stress case.
Allocation alone produced none at -0.8, -0.4, or 0, which matches the
[exclusion census](exclusion-census.md)'s finding that it was the one structural
case. At -1.2, follow-through cut it from 1,860 requirement-decisions to 92
(2,480 to 39 at `k` of 4) without managing more strands. The mechanism is not
isolated here; the likeliest reading is that timed evidence on harder
realizations moved readiness by more than the untimed introductions could.

## What it does not establish

That follow-through is worth its cost. It takes slots from scale maintenance in
every pair at moderate offsets, where nothing was excluded to begin with, and
its benefit there is earlier demonstration rather than more coverage. Whether
earlier demonstration matters to a learner is a product question these runs
cannot answer. The offsets are sensitivity levels on one zero-transfer player,
and these are synthetic players.
