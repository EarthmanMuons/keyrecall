# Exclusion census

> **Status:** diagnostic, five paired seeds, allocation-only at `k` of 2 and 4,
> protection floor 0.60. When an owed requirement goes unserved, the obstacle is
> almost always a recovery episode in progress. Outside recovery, the obstacle
> is learner readiness, either a curriculum prerequisite or the band execution
> floor, and not the selection pipeline. Only the scale-strong learner's weak
> arpeggios are blocked structurally. They were introduced through the band
> discount with no route onward to managed practice. Nothing is promoted; the
> scheduler stays at v1-14.

The [allocation counterfactual](allocation-counterfactual.md) left hundreds of
decisions per run with an owed requirement and nothing selectable to serve it.
This census asks what kept those requirements out: learner readiness, the form
of the exercise offered, or the selection pipeline.

## What was counted

Every decision at which a requirement was owed under the allocator's bound
counts once for that requirement, classified by the furthest stage it reached:

- **served**, by ranking or by allocation;
- **feasible, no slot**: a fully eligible, admitted, compatible candidate
  survived selection, but the slot belonged to an override stage, a protected
  winner, or another owed requirement;
- **held for recovery**: every compatible candidate was refused only because a
  recovery target held the slot;
- **no feasible candidate**: nothing compatible was generated, admission refused
  it for another reason, it was only provisionally eligible, or a selection
  stage filtered it. The specific refusal, eligibility reason, or first removing
  stage is kept.

Recovery decisions neither extend nor break a requirement's unservable run, so a
run measures how long requirement-specific obstacles persist.

```console
dart run keyrecall_simulation:allocation_counterfactual \
  --player developing --arms alloc-2-0.60,alloc-4-0.60
```

## Results

Share of owed requirement-decisions, summed across five pairs:

| Player          |   k | Served | Feasible, no slot | Held for recovery | No feasible candidate |
| --------------- | --: | -----: | ----------------: | ----------------: | --------------------: |
| True beginner   |   2 |   1.4% |              6.7% |             88.2% |                  3.7% |
|                 |   4 |   0.4% |              1.8% |             94.8% |                  2.9% |
| Developing      |   2 |   1.1% |              8.6% |             82.3% |                  8.1% |
|                 |   4 |   0.4% |              4.3% |             87.0% |                  8.4% |
| Advanced        |   2 |   5.5% |             34.7% |             54.8% |                  5.0% |
|                 |   4 |   2.6% |             19.2% |             72.8% |                  5.4% |
| Scale-strong    |   2 |   1.7% |              9.4% |             69.4% |                 19.5% |
|                 |   4 |   0.6% |              3.0% |             72.0% |                 24.4% |
| Arpeggio-strong |   2 |   2.5% |             17.7% |             74.6% |                  5.2% |
|                 |   4 |   1.0% |              3.8% |             91.2% |                  4.0% |

Recovery's share is a share of requirement-decisions, not of decisions. A
recovery target refuses every other candidate, so each recovery decision holds
the whole owed set at once. Under v1-14 on one seed, recovery took 7% of the
advanced learner's attempts, 18 to 22% of the asymmetric learners', 34% of the
developing learner's, and 42% of the true beginner's.

When no feasible candidate existed, the reason was:

| Player          |   k | Leading reasons                                                     |
| --------------- | --: | ------------------------------------------------------------------- |
| True beginner   |   2 | curriculum 73%, filtered by dose 17%, filtered by pacing 10%        |
|                 |   4 | curriculum 91%, dose 7%, pacing 2%                                  |
| Developing      | 2,4 | curriculum 96 to 99%                                                |
| Advanced        | 2,4 | curriculum 100%                                                     |
| Scale-strong    |   2 | band execution floor 77%, curriculum 20%, direction prerequisite 3% |
|                 |   4 | band execution floor 90%, curriculum 8%, direction prerequisite 2%  |
| Arpeggio-strong | 2,4 | curriculum 96 to 98%                                                |

When a feasible candidate existed but had no slot, the slot went to another owed
requirement (18 to 45%), a frontier step (14 to 41%), a guidance probe (17 to
23%), a protected winner (9 to 29%), and, for the true beginner, acquisition (9
to 13%).

Persistence separates the transient from the structural. Every player but one
had 12 to 40 requirements unservable at some point in a run, and every one of
those runs lasted under 10 decisions. The scale-strong learner had 20 (`k` of 2)
and 24 (`k` of 4) runs of 100 decisions or more, up to 590, all root-position
arpeggios in the remote keys (E-flat, B-flat, A-flat, and D-flat major; B-flat,
F-sharp, C-sharp, and G-sharp minor). All but two had a single reason
throughout, and 43 of 44 led with the band execution floor. At `k` of 4 every
one was last served within the first 274 decisions and never again. At `k` of 2
they were last served that early in two pairs; in the other three, service came
back only after decision 1,260, which is how six of them ended covered.

A run here counts consecutive owed decisions, so a decision where the
requirement is not owed restarts it; recovery holds do not. The lengths above
understate how long these arpeggios went without a feasible candidate.

## How the prolonged exclusions began

```console
dart run keyrecall_simulation:exclusion_transitions
```

The scale-strong runs again, at `k` of 2 and 4 on the same pairs, tracking every
arpeggio's single-hand readiness at every decision and joining each attempt on
it to its recorded outcome. Readiness is the scheduler's own reference
prediction (one octave, ascending, at the gentle tempo), so it does not move
with the realization attempted. An exclusion span runs from the first decision
without a feasible candidate until the next service or feasible candidate,
through recovery holds and decisions where it was not owed. There are 68 spans
of 100 decisions or more, with a median of 704; 46 were still open when the run
ended.

Every one began the same way. The material was admitted only through the
one-band discount for its gentlest realization: readiness was at most 0.014
above the discounted floor of 0.528 and never reached the full floor of 0.625.
Two to eight attempts preceded each span. None was ever managed (completed, at a
motor score of at least 0.5), so no span had a demonstrated tempo, which would
have made the band floor moot. In 66 of 68, the last attempt was played 10% or
more above the asked tempo, and it was completed with pitch integrity of 0.8 to
1.0 in most. In 23 spans the last three attempts carried no execution evidence
at all; the most common last attempt was the introduction itself.

The step below the discounted floor came two ways:

- **At an attempt (18 spans).** A scored attempt lowered readiness by 0.002 to
  0.015, from just above the floor to just below it.
- **Afterward, with no attempt (50 spans).** The material stayed fully eligible
  for a median of 305 decisions after its last attempt (at least 114), was not
  chosen again, and then drifted below by a median of 0.012. Readiness has no
  time decay, so the drift is transfer: shared competencies moved by other
  practice.

## What this establishes

The selection pipeline is not what keeps owed work out. Filtering removed a
feasible candidate only for the true beginner, and only for a minority of its
infeasible decisions. Feasible owed work loses its slot to override stages and
to other owed work in roughly equal parts, which is contention for capacity, not
exclusion.

Outside recovery, the obstacle is readiness. Curriculum prerequisites hold most
infeasible requirements for four of five players, and those clear within a few
decisions: they are the ordinary order of the curriculum. The scale-strong
learner's weak arpeggios are the exception and the only structural case.

That case is introduction without a route onward, not failure of an eligible
exercise. Each of those arpeggios was admitted only through the band discount,
on a margin a hundredth wide, and then went hundreds of decisions without the
follow-up that could have demonstrated it. Once a hair of failure or transfer
took it under the discounted floor, nothing in v1-14 owned it: under v1-14 on
one seed, that learner's run had no acquisition decision.

## What it does not establish

Why the synthetic learner overshoots the asked tempo on these arpeggios is a
property of the player model, not shown here; it is why the attempts that were
made never counted as managed. Whether a follow-up during the eligible window
would have been managed is not shown either. The recovery shares are from one
seed under v1-14, and these are synthetic players.
