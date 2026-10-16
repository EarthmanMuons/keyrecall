# Opportunity clock

> **Status:** an integration compatibility check, not a policy experiment, on
> 180 trajectories. Counting ordinary attempts and acquisition offers reproduces
> allocation's characterized runs exactly, decision by decision, in all 60
> player, model, and calendar combinations. Counting ordinary attempts alone
> does not: it diverges in 52 of 60, usually at allocation's first substitution.
> The production clock is therefore ordinary attempts plus acquisition offers.
> Blocked slots never occurred.

Allocation's waiting advances once per decision at which a requirement was
actionable and not served. In every simulation so far a decision was any slot:
an ordinary exercise, an acquisition offer, or a blocked slot. In production
only an event that becomes durable may advance it, and blocked slots and
acquisition offers do not write an attempt record. Porting the allocator must
not quietly change which decisions count, so the clocks were compared first.

## Design

`RequirementAllocator` takes an `OpportunityClock`, which decides whether a
decision's observations reach the waiting counters:

| Clock                    | Ordinary exercise | Acquisition offer | Blocked slot |
| ------------------------ | ----------------- | ----------------- | ------------ |
| `everySlot`, as before   | counts            | counts            | counts       |
| `ordinaryAttempts`       | counts            | ignored           | ignored      |
| `attemptsAndAcquisition` | counts            | counts            | ignored      |

Allocation at `k` of 2 with protection floor 0.60 ran under each, on the six
cohort players of the [memory comparison](memory-comparison.md) and five seed
pairs each, with both the frozen familiarity model and
[`retrieval-memory-2`](retrieval-memory.md) at 1:60:0.5. A test pins that, on a
seeded fortnight, the clock that counts acquisition reproduces every slot and
the one that does not departs from it; dropping the clock's check and counting
acquisition only under `everySlot` each fail it.

```console
dart run keyrecall_simulation:opportunity_clock
```

## Results

**No slot was blocked.** General Fluency always has ordinary work to offer, so
across 80,364 decisions the only non-ordinary slots were 529 acquisition offers,
none to 29 a run. A blocked result also arises only when nothing survived
selection, so whether a blocked slot could ever hold an actionable requirement
is not something these runs could show.

**Counting acquisition reproduces every slot exactly.** Decision sequences and
substitutions under `attemptsAndAcquisition` match `everySlot` in all 60 runs.

**Ignoring acquisition changes trajectories, without a direction.** Acquisition
offers carry about 1% of the waiting increments, but an offer often comes at the
second decision, and once allocation first acts, 52 to 1,458 decisions in, the
runs part. Under `ordinaryAttempts`, 52 of 60 runs differ, most within the first
80 decisions. Paired against every slot, substitutions change by -117 to +36 a
run with medians of 0 and -1, arpeggio coverage by -10 to +10 with a median of
0, and the worst allocatable wait moves either way in about equal numbers. These
are different trajectories rather than a systematically better or worse policy,
but they are not the policy that was characterized.

One property of the characterized clock carries over: an acquisition offer
serves no requirement, so a requirement whose material is being acquired counts
that slot as a missed opportunity.

## Contract

Production advances waiting exactly once for each ordinary attempt committed and
each acquisition attempt durably recorded, with the evidence the decision
computed. A decision abandoned before commit, a blocked slot, and a replay of an
event already recorded advance nothing, and a resumed pending decision commits
the evidence it was made with. On every characterized run this is the policy
that was measured.
