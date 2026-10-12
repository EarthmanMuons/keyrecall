# Allocation

> **Status:** proposed. Nothing here is built, and scheduler v1-14 is the
> policy. It answers
> [`service-census.md`](../research/experiments/service-census.md) and
> [`service-pressure.md`](../research/experiments/service-pressure.md), and it
> is to be tested as a counterfactual before anything moves into production.

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

**1. Bounded waiting, relative to breadth.** A requirement that is actionable
should not miss more than `k` times its fair share of opportunities in a row,
where its fair share is the number of requirements concurrently actionable. A
learner with forty things to work on cannot see each one every slot, and one
with four can; a fixed threshold would treat them alike. The waiting is counted
in actionable opportunities, as the census counts it, so time away from the
instrument costs nothing. `k` is the slack ordinary ranking keeps: large enough
that the existing ordering decides almost everything, small enough that nothing
waits indefinitely. This is a deficit rule from fair scheduling, not a quota:
nothing is guaranteed a share, only a bounded wait.

**2. Protected maintenance.** A covered requirement whose retrieval health has
fallen far enough is protected from displacement by owed service. Due for
maintenance already starts at 0.75; protection starts lower, where forgetting is
close enough that losing the slot would cost a demonstration rather than delay a
review. Above that, maintenance competes on the existing retention term like any
other work. This is the reconciliation the pressure counterfactual lacked:
there, service took slots from retention unconditionally, and retrieval among
covered scales fell in every developing and advanced pair.

**3. Ordinary ranking decides the rest.** When nothing is owed or protected, the
existing lexicographic key chooses, unchanged. When several requirements are
owed, the one furthest past its bound goes first, and the rank key breaks ties.
Nothing acquires a weight it does not have today.

**4. Scoped to the goal.** Service history belongs to the requirement in the
active scope. A requirement leaving scope, by a focus or goal change, leaves its
history behind, and one entering starts fresh, so narrowing practice never
inherits a debt from material it no longer asks for. One exercise that serves
several compatible requirements serves all of them, and an owed requirement is
served only by an exercise in its own structure.

What this does not do: it sets no family quota, it does not demote retention
globally, and it does not add a rank term. Arpeggios receive service because an
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

| Needed                          | Source                                                  | New state? |
| ------------------------------- | ------------------------------------------------------- | ---------- |
| coverage, due, retrieval health | journal and learner state, as the evaluator reads now   | no         |
| useful actions, feasibility     | learner state, attempt history, admission               | no         |
| last service, and its outcome   | journal: the last compatible attempt and its closure    | no         |
| position on the support path    | journal: consecutive unmanaged attempts since a success | no         |
| waiting in actionable decisions | not in the journal: past actionability is not recorded  | see below  |

Exact actionable-opportunity counts would need a persisted service ledger,
versioned with the scheduler model and rebuilt by replaying decisions, which is
costly and couples allocation to a second history. The proposed alternative
counts **attempts since last service while the requirement was due**, which the
journal reproduces exactly, and checks actionability only at the current
decision. The difference is time spent blocked, which this counts as waiting;
the census can measure how often that changes a decision before anything is
persisted. No learner estimate is added: allocation reads the learner model and
never infers ability of its own.

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
| service ledger                           | not built; journal-derived waiting instead    |

The smallest counterfactual that tests the architecture: the allocator stage in
the simulation package, beside the scheduler as service pressure was, with
bounded waiting, protected maintenance, and the support path through existing
recovery, floor, and acquisition mechanisms, and no suspension.

## How it is judged

The same five seed pairs and three archetypes, plus the scale-strong,
arpeggio-weak and arpeggio-strong, scale-weak players, against v1-14 and service
pressure at threshold 100 as comparators. Threshold 100 is the benchmark because
it kept most of the deferral reduction at lower cost, not because it is a
candidate.

It succeeds if it keeps pressure's reduction in worst and 90th-percentile waits,
leaves no requirement actionable and never served, and holds retrieval among
covered requirements at v1-14's level in most pairs where pressure lowered it in
every pair. It also has to show its own contracts working: blocked requirements
with reasons and exits taken, unmanaged services followed by a different action
rather than the same one, and switching and difficulty no worse than pressure's.
Time to first demonstration joins coverage, since an allocator can raise
coverage late and still serve a learner slowly.

It fails, and the logical architecture should be revisited before any of it is
built, if protected maintenance and bounded waiting cannot both hold: if keeping
covered material as healthy as v1-14 means giving back the reduction in waits.
That would say the two promises conflict at this catalog's breadth and the
contract has to choose, which is a product decision rather than a tuning one.
