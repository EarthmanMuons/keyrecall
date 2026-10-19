# Allocation

> **Status:** in integration as an opt-in General Fluency pilot at `k` of 2 with
> protection floor 0.60; scheduler v1-14 stays the default. The choice and its
> waiting fold are shared code in `keyrecall_practice`, and attempt and
> acquisition records carry its evidence from schema 11. Every decision records
> shadow evidence; a profile a tester assigns to the pilot is decided by
> allocation in unrestricted General Fluency and by v1-14 anywhere else, and
> each decision records both policies. It answers
> [`service-census.md`](../research/experiments/service-census.md) and
> [`service-pressure.md`](../research/experiments/service-pressure.md).

The scheduler makes each decision defensibly and promises nothing about the next
hundred. Eligibility, admission, ranking, and six selection stages each answer a
local question, and none of them owns the question of how useful work gets
served over time. On the seeded runs that gap is concrete: a developing
learner's uncovered C major arpeggio is choosable at 892 decisions and chosen at
4, losing the ranking mostly on retention, while every rule that touched it was
locally right.

The service pressure counterfactual showed the gap matters and how not to close
it. Giving long-deferred requirements the slot raised the developing learner's
coverage in every seed pair and cut the worst waits by an order of magnitude,
but it took those slots from the maintenance of what was already covered, and
its failure guard abandoned the true beginner's hardest requirements for good.
Three things follow, and this design is built on them:

- Service allocation is a real problem, so it needs an owner.
- Service and retention compete for the same slots, so one rule has to weigh
  them rather than two rules taking turns.
- Failure should change what is offered, never whether a requirement is owed.

## Logical architecture

Four questions, asked in order, each by one owner:

| Question                          | Owner             | Reads                                       |
| --------------------------------- | ----------------- | ------------------------------------------- |
| What does the scope still need?   | requirement need  | coverage, retrieval health (practice layer) |
| What would help each need now?    | action resolution | learner state, attempt history, admission   |
| Which need gets this opportunity? | allocation        | needs, their actions, service history       |
| Exactly what is played?           | realization       | frontier, probes' held axes, shape order    |

A requirement being due says something remains to be done; it does not say what
to do. An unfamiliar arpeggio needs acquiring, one played inaccurately several
times needs support, and a demonstrated scale whose retrieval is fading needs
retrieving. The need persists while the action changes, which is what lets
failure change the action without ending the need.

## Action taxonomy

Five instructional actions cover everything the scheduler does today. Each row
is an existing mechanism, where it lives now, and the action it serves.

| Action          | Existing mechanism                                   | Lives in           |
| --------------- | ---------------------------------------------------- | ------------------ |
| **Acquire**     | new material admission, introductory accommodation   | admission          |
|                 | acquisition floor                                    | admission fallback |
|                 | supported acquisition task, acquisition probe        | slot override      |
|                 | floor check (a family's safe entry, owed an attempt) | slot override      |
|                 | introduction breadth                                 | selection stage    |
| **Recover**     | recovery (one rung more guidance, exclusive)         | admission          |
|                 | pulse support and withdrawal cycle                   | slot override      |
| **Retrieve**    | retention term `R(e)`                                | rank term 5        |
|                 | guidance, bootstrap, and observation probes          | admission          |
|                 | diagnostic fairness guard for independence probes    | selection stage    |
| **Consolidate** | consolidation (met, not yet retrieved, previewed)    | admission          |
| **Progress**    | execution progression (one axis)                     | admission          |
|                 | tempo probe                                          | admission          |
|                 | coordination transition, contrary coordination       | rank terms 2, 3    |
|                 | arriving at a finite goal's target                   | rank term 4        |
|                 | stepping past demonstrated shapes                    | slot override      |

Information `I(e)`, diversity, goals, and the realization terms are not actions;
they order within one. Repetition, pacing, dose, and novelty are hygiene on what
may follow what, and stay filters.

Three overlaps matter. **Retrieve has three mechanisms that never compare
notes**: retention ranks, the probes admit, and the fairness guard overrides,
each reading its own clock. **Progress is split across three layers**, so a
frontier step can replace a ranking pick that arriving already biased, and
neither knows the other ran. **Acquire has two entrances**, the ordinary
introduction and the floor, with introductory accommodation now bridging the
first meeting to its follow-up; supported acquisition is a third path that only
the slot override can reach. None of them is wrong. What is missing is one place
where "this requirement has needed acquiring for 800 decisions" is visible.

## Decision sequence

```text
1  scope evaluation      coverage and due state per requirement       practice layer, as now
2  obligations           recovery target, pulse cycle, owed probe      hard, as now
3  action resolution     for each due requirement: its useful actions,
                         each with its feasible realizations, or a
                         blocked reason
4  allocation            one requirement and action for this slot
5  hygiene               repetition, pacing, dose, novelty             over requirements
6  realization           the exercise within that action                existing realization terms
```

**Obligations stay above allocation.** Recovery is exclusive because the exact
failed exercise with one more rung of support is the only defensible next slot;
an allocator does not get to outvote it. The same holds for a pulse cycle in
progress and an acquisition probe owed.

**Action resolution never declares a requirement unserviceable because its
ordinary work is too hard.** It walks a support path first: the ordinary
realization; a gentler one (one octave, one hand, entry tempo, more guidance);
the acquisition floor's safe entry; a supported acquisition task. Only when all
of them are closed is the requirement blocked, with the reason that closed the
last one. A requirement barred on a prerequisite resolves to acquiring or
progressing that prerequisite, which generalizes live support from narrow scopes
to every scope: the census's ten due-but-never-actionable arpeggios become owed
work on what their band waits for.

**Hygiene moves from exercises to requirements.** Repetition and pacing ask
whether the same thing keeps winning, and the thing that matters is the need
being served, not the exercise drawn for it.

**Realization keeps everything it has.** Once allocation has chosen a need and
an action, the frontier, realization fit, shape progression, and each probe's
held axes choose the exercise exactly as now.

## Allocation contract

Allocation chooses among `(requirement, action)` pairs that resolution produced.
It answers to four promises.

**1. Breadth-relative service priority.** A requirement that is actionable
becomes owed once it has missed more than `k` times as many actionable
opportunities in a row as there are requirements actionable now. A learner with
forty things to work on cannot see each one every slot, and one with four can; a
fixed threshold would treat them alike. Waiting is counted in actionable
opportunities, as the census counts it, so time away from the instrument costs
nothing. `k` is the slack ordinary ranking keeps.

It is a priority, not a guarantee, for three reasons the experiment has to
measure rather than assume. Breadth changes, so a requirement's bound can grow
while it waits; the bound in force at each decision is logged, and so is every
decision on which growth alone postponed service. Obligations consume capacity:
allocation only ever acts on a slot ordinary ranking decided, so service is
promised only out of what recovery, probes, and acquisition leave, and misses
are counted against allocatable opportunities as well as actionable ones. And a
requirement with no feasible action is not owed an exercise that does not exist:
its need stands, and it is reported as unservable rather than served.

**2. Protected maintenance.** Protection belongs to a candidate, not to the
scope. A candidate is protected when it is feasible, fully eligible, can observe
retrieval, and serves a covered requirement whose retrieval health has fallen
below a floor lower than the 0.75 that makes maintenance due. A protected
candidate that ordinary ranking chose is never displaced by owed service.
Protection keeps a slot and never claims one: the rank key has already chosen
among protected candidates, not whichever is weakest, and a fading material
elsewhere in the scope neither blocks service in an unrelated slot nor takes it
over.

A floor does not guarantee maintenance at v1-14's level: health can fall a long
way before crossing it, and protected work may not win often enough to reverse
the fall. That is why the maintenance outcomes, not the floor, are what the
experiment reads. This is still the reconciliation the pressure counterfactual
lacked: there, service took slots from retention unconditionally, and retrieval
among covered scales fell in every developing and advanced pair.

**3. Ordinary ranking decides the rest.** When nothing is owed or protected, the
existing lexicographic key chooses, unchanged. When several requirements are
owed, the one furthest past its bound goes first, and the rank key breaks ties.
Nothing acquires a weight it does not have today.

**4. Scoped to the goal.** Service history belongs to the requirement in the
active scope. A requirement leaving scope, by a focus or goal change, keeps its
count but is never owed while it is out, and resumes the count if it returns, so
narrowing practice never inherits a debt from material it no longer asks for and
widening it again does not erase one. One exercise that serves several
compatible requirements serves all of them, and an owed requirement is served
only by an exercise in its own structure.

What this does not do: it sets no family quota, it does not demote retention
globally, it does not add a rank term, and it does not promise any requirement a
slot within a fixed number of decisions. Arpeggios receive service because an
arpeggio requirement is owed, not because arpeggios are behind scales.

## Failure and recovery contract

**Failure changes the action, never the obligation.** After a served attempt
that did not manage its execution, the requirement stays owed, and resolution
moves it one step along its support path: more guidance, a gentler realization,
the safe entry, a supported acquisition task. Recovery already does the first
step for a retrieval failure; this extends the same idea to execution and makes
it the allocator's business to return.

**Temporary unavailability is bounded and visible.** A requirement may cool down
after an unproductive service, so the next slot is not the same failure again,
but a cooldown is a number of opportunities, not a state that waits on someone
else to end it. The pressure experiment's suspension ended only when ordinary
selection served the requirement, which for 44 of 46 suspended beginner
requirements was never.

**Blocked is a state with a reason and a way out.** When every step of the
support path is closed, the requirement is blocked and says why: nothing
admitted at any rung, supported acquisition exhausted, a prerequisite not yet
met, or no measurement possible on this input. Each reason names its exit: new
evidence on the material or hand, a competency crossing the floor that closed
it, the prerequisite covered, or a set number of opportunities after which
supported acquisition is offered again. A blocked requirement is reported, never
silently dropped, and counted apart from deferral in the census.

**Persistent avoidance is detectable.** A requirement that keeps moving down its
support path without ever producing managed execution is a signal about the
support path, not about the learner's worth practicing for. It is surfaced as
such rather than buried by a guard.

## State

Everything allocation needs is derivable except one thing, and that one can be
derived too, at a stated approximation.

| Needed                          | Source                                                     | New state? |
| ------------------------------- | ---------------------------------------------------------- | ---------- |
| coverage, due, retrieval health | journal and learner state, as the evaluator reads now      | no         |
| useful actions, feasibility     | learner state, attempt history, admission                  | no         |
| last service, and its outcome   | journal: the last compatible attempt and its closure       | no         |
| position on the support path    | journal: consecutive unmanaged attempts since a success    | no         |
| waiting in actionable decisions | evidence on each committed attempt and acquisition attempt | yes        |

Exact waiting is folded from what each decision recorded when it was made: which
requirements its exercise served and which actionable ones it left waiting.
Nothing is recomputed from the catalog, eligibility, or predictions, so a later
scheduler or curriculum cannot reinterpret it. An ordinary decision carries its
evidence in the pending slot saved before presentation and commits it with the
attempt; an acquisition offer holds it until its attempt is recorded. Either way
evidence lives inside the record it describes, which the store writes whole or
not at all, so no event is durable without its evidence or the reverse. A
retried commit is the same record, which both logs already absorb by attempt id.

The two logs fold in one order without a shared sequence. An acquisition attempt
records how many ordinary attempts history held when it was offered, and replay
places it after the last of them and before the next. The store checks that
count against the attempts actually on disk in the same serialized write as the
append, after idempotence. Within a session decisions resolve one at a time, so
the check only fires when another session for the profile committed an ordinary
attempt meanwhile, as a profile switch during an acquisition close can. Then the
attempt is still recorded, at the true place, with its evidence replaced by an
explicit `staleAcquisition` gap: a learning event is never lost to scheduler
accounting, and evidence is never invented to repair an ordering race. An
ordinary decision whose counters missed an acquisition attempt that landed first
commits as made, and the fold counts it as a stale decision rather than altering
it.

A decision reads allocation from one request: the requirement states the
evaluation scoping it produced, in scope order, and the counters with the
history they were folded from. Either host resolves it the same way and returns
the evidence with that history, which is what the decision records, so its claim
about what it read is what it read. Under v1-14 the request is observed and
never chosen from.

A record without evidence names why, `legacy` before schema 11, and contributes
nothing; it is not a decision that served and missed nothing. Counters before
the first observed event are unavailable rather than zero.

## Two ways to build it

**Full action-first.** An action layer between scope evaluation and admission
produces `(requirement, action, realizations)`, and the pipeline's bypasses,
overrides, and selection stages become action resolution, obligations, or
hygiene. This is the logical architecture above made literal. It is a large
change to a pipeline whose correctness is pinned by many tests, and it is only
worth making if the smaller version shows the decomposition earns its keep.

**A requirement-aware allocator stage.** Keep the pipeline. After admission and
the existing obligations, group the selectable set by requirement, apply the
allocation contract to choose one, and hand that requirement's candidates back
to ordinary ranking for realization. Action resolution's support path reuses
what exists: recovery's extra rung, the acquisition floor, and supported
acquisition. Introduction breadth and the diagnostic fairness guard become
special cases of bounded waiting and could later retire.

The second is the minimum change that tests the design's claims, and the first
is where it leads if they hold.

## Migration boundary

| Component                                | Fate under the allocator stage                |
| ---------------------------------------- | --------------------------------------------- |
| scope evaluation, coverage, due          | reused unchanged                              |
| eligibility, admission, all bypasses     | reused unchanged                              |
| recovery, pulse cycle, owed probes       | reused, ahead of allocation                   |
| ranking terms                            | reused, for ties and realization              |
| repetition, pacing, dose, novelty        | reused, read per requirement                  |
| acquisition floor, supported acquisition | reused as steps of the support path           |
| introduction breadth, fairness guard     | kept for the first test, candidates to retire |
| live support                             | generalized to every scope                    |
| service ledger                           | not built; exact counts in simulation only    |

The counterfactual runs in the simulation package, beside the scheduler as
service pressure did, and in three stages so that each change can be credited on
its own, each keeping the one before as a comparator:

1. **Allocation only.** Breadth-relative priority and protected maintenance over
   the existing selectable set, with ordinary ranking realizing the chosen
   requirement. No new acquisition or recovery path.
2. **Support-aware.** Bounded cooldowns and a change of action after an
   unmanaged service, through the existing recovery, floor, and acquisition
   mechanisms.
3. **Prerequisite-aware.** Whether existing safe-entry mechanisms give the
   requirements that are due and never actionable useful work on what they wait
   for.

## Device gates

The pilot opens to testers once these hold on a device, in a release or profile
build. The fold timing, the policy switch, and the pilot report are on the
developer screen.

| Check                                                                      | iPhone 15 Pro | Android      |
| -------------------------------------------------------------------------- | ------------- | ------------ |
| Fold p50 and p95 at 5,000 attempts, and no visible hitch between exercises | not verified  | not verified |
| The pilot assigned mid-exercise: that exercise by v1-14, the next by it    | not verified  | not verified |
| A profile switch while an acquisition attempt saves: recorded once, usable | not verified  | not verified |
| The assignment held across restarts                                        | not verified  | not verified |

The acquisition check passes with either a record carrying its evidence or one
marked `stale_acquisition`, whichever the interleaving produced: what has to
hold is that the attempt is history exactly once and practice goes on.

## How it is judged

The same five seed pairs and three archetypes, plus the scale-strong,
arpeggio-weak and arpeggio-strong, scale-weak players, against v1-14 and service
pressure at threshold 100 as comparators. Threshold 100 is the benchmark because
it kept most of the deferral reduction at lower cost, not because it is a
candidate. The first stage sweeps `k` over 2, 4, and 8 and the protection floor
over 0.60 and 0.70: exploratory settings, not defaults, and every cell is
reported rather than the best.

What comes out is a frontier, not a verdict. KeyRecall may not be able to
introduce, demonstrate, and maintain a growing catalog at once within the same
practice time, and a configuration that modestly raises coverage, removes
pathological waits, and costs a small, interpretable amount of maintenance could
be better for a learner than v1-14 without matching its retention. The outcomes
read are the ones the pressure comparison read: coverage and time to first
demonstration, worst and 90th-percentile waits counted both ways, retrieval
across all and across covered requirements, fading, faltering, incomplete
attempts, and switching. Each stage also reports its own contract: decisions
where breadth growth postponed service, owed requirements with nothing feasible
to serve them, protected selections, and how often the journal counter would
have decided differently.

These are synthetic players. The policy that ships should follow from what
KeyRecall wants a learner to experience, which the frontier informs and does not
settle.
