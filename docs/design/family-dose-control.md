# Family dose control

- **Status:** Implemented behind `SchedulerConfig.dose`, and **not in the V1
  policy**. Mechanism pinned by invariant tests; every constant provisional.
- **Written:** September 7, 2026.
- **Scope:** How often a realization family is offered, given what its recent
  attempts produced. Distinct from realization-family pacing, which relieves
  concentration.

Support already adapts to a family that keeps failing: guidance climbs, and
recovery targets the exact exercise one rung more supported. Nothing adapts the
other quantity. A family that has produced nothing for fifty attempts is offered
at the same cadence as one that produces something every time.

## What the harness found

Sixteen sittings of ten attempts across seventy days, four seeds, every
archetype. `share` is a family's share of the run after it first appeared, and
`after` is its share of the ten slots following a run of five attempts that
yielded no managed execution.

| archetype              | family           | share | after | yield | longest run |
| ---------------------- | ---------------- | ----- | ----- | ----- | ----------- |
| `coordination_limited` | `hands:together` | 36%   | 45%   | 0%    | 53          |
| `developing`           | `hands:together` | 42%   | 31%   | 0%    | 60          |
| `true_beginner`        | `hands:left`     | 56%   | 60%   | 0%    | 89          |
| `uneven_hands`         | `hands:left`     | 22%   | 28%   | 4%    | 24          |
| `advanced`             | `hands:together` | 21%   | 0%    | 86%   | 1           |

A learner can be asked the same unanswerable question fifty-three times in a
row, and the family holds **more** of the sitting after a failed run than it
holds overall. The strong archetypes never reach a run of two, so this is not
about the work being hard. It is about the dose not responding to the answer.

## Why pacing cannot answer it

Pacing pressure is `share above the floor x unproductive fraction`, and the
floor is half the window. A family holding a third of a sitting accumulates no
pressure however little it yields, which is why `coordination_limited` was set
aside three times across a run in which nothing it coordinated ever worked.

The two mechanisms are kept apart deliberately. **Pacing asks whether a family
is crowding the sitting. Dose control asks whether it is worth asking this
often.** Folding the second into the first would need pressure to mean two
things at once, and a family can legitimately be subject to one and not the
other.

## The mechanism

Contraction is read from the same recent-selection window pacing uses, and
nothing else:

```text
evidence     at least minAttempts of the family in the window (six of twelve)
yield        managed executions over those attempts
contraction  (yieldFloor - yield) / yieldFloor, zero at or above the floor
relief       halved when productive prerequisite work is in the window
cadence      1 + (maximumGap - 1) x contraction, in slots
```

A family over its cadence is held back from the selectable set for that slot. It
keeps its eligibility, its rank and its place; it is asked for less often, and
nothing else about it changes.

**Evidence is required before contracting.** A family with fewer than
`minAttempts` in the window is left alone, so one or two failed introductions
cannot throttle a strand the learner has barely met.

**Prerequisites are declared, not inferred.** `familyPrerequisites` states that
separate-hand work is evidence for hands together, because the coordination
prerequisite is stated in those terms. Nothing establishes parallel motion as
evidence for contrary, so contrary is absent rather than guessed at. Somebody
whose hands are improving separately is a different learner from one whose hands
are not.

**Time relaxes the contraction, and only the contraction.** A family's evidence
counts half as much after `evidenceHalfLifeDays`, measured from its last attempt
to the decision being made. What ages is the confidence that the family is still
over its cadence, not the record of what it produced: the attempts stay
unproductive however long ago they were, and a family returning from a break
comes back at an ordinary cadence rather than a favored one. A half-life rather
than an expiry, so nothing hinges on a boundary date, and time before the
evidence is not relief, since a window that starts before its own history is a
corrupt clock rather than a fresh start.

**Contraction never removes.** A slot holding only contracted work returns it
untouched. A learner with nothing else useful to do keeps being offered the hard
thing, which is also why the mechanism cannot empty a sitting.

## Pinned invariants

Asserted, because each states a direction rather than a strength:

- managed execution can only lower a contraction;
- productive prerequisite work can only lower a contraction;
- a family under its minimum evidence is not contracted at all;
- the cadence never exceeds `maximumGap`, and is one at no contraction;
- a slot whose every candidate is contracted keeps them;
- time away can only lower a contraction, and can never manufacture yield;
- a learner whose families all yield practises the identical trajectory to one
  with no dose policy at all.

That last one is the guard against perturbing learners the mechanism has nothing
to say about: `advanced` produces byte-identical runs either way.

## What it does to a trajectory

The same sixteen sittings, with dose control in force:

| archetype              | family           | share    | after    |
| ---------------------- | ---------------- | -------- | -------- |
| `coordination_limited` | `hands:together` | 36 -> 29 | 45 -> 20 |
| `developing`           | `hands:together` | 42 -> 31 | 31 -> 20 |
| `uneven_hands`         | `hands:left`     | 22 -> 21 | 28 -> 16 |
| `true_beginner`        | `hands:left`     | 56 -> 36 | 60 -> 45 |
| `advanced`             | `hands:together` | 21 -> 21 | 0 -> 0   |

The post-failure share now falls below the family's overall share rather than
rising above it, which is the behavior the characterization asked for.

`true_beginner` is the honest exception. Every one of its families yields
nothing, so contraction applies to all of them at once and cannot prefer
anything; its share falls but the post-failure ordering does not invert. A
learner who cannot execute anything is not a dose problem, and the mechanism
correctly declines to invent an alternative.

### What ageing does, and where it shows

Time relaxation is a boundary effect, and the aggregate share cannot see it. Six
seeds of `return_after_long_break`, twelve slots a sitting, comparing a
seven-day half-life against one long enough to be no ageing at all:

| archetype              | family           | share   | slots into a return before it is offered |
| ---------------------- | ---------------- | ------- | ---------------------------------------- |
| `developing`           | `hands:together` | 37 / 36 | 0.0 / 2.5                                |
| `coordination_limited` | `hands:together` | 22 / 21 | 1.0 / 2.0                                |
| `uneven_hands`         | `hands:together` | 12 / 12 | 3.5 / 3.5                                |

The share a family holds over a whole run is unchanged, which is the point:
ageing does not loosen the mechanism inside a sitting, where the attempts are
minutes apart. What changes is how far into a returning sitting the learner gets
before the family is offered again. `sporadic` says the same thing, with
`developing` offered coordination work at the first slot back rather than three
and a half slots in.

## The sweep

One axis at a time from the centre, every archetype, two seeds, seven sittings
of ten on `normal_month`, with the baseline carried alongside so parity is read
rather than assumed. Contracted and changed are the share of slots the mechanism
spoke at and the share it altered; parity is runs identical to the baseline
trajectory.

| arm         | contracted | changed | parity |
| ----------- | ---------- | ------- | ------ |
| baseline    | 0%         | 0%      | 18/18  |
| evidence 3  | 26%        | 18%     | 7/18   |
| evidence 4  | 19%        | 13%     | 7/18   |
| evidence 6  | 10%        | 7%      | 13/18  |
| evidence 8  | 2%         | 2%      | 14/18  |
| floor 0.2   | 16%        | 12%     | 10/18  |
| floor 0.5   | 24%        | 17%     | 6/18   |
| floor 0.67  | 34%        | 25%     | 0/18   |
| gap 3 to 12 | 19% to 22% | 12-16%  | 9-5/18 |

**The engagement columns are what the sweep is for.** At four attempts of
evidence the mechanism spoke at nearly a fifth of all slots and altered an
eighth of them, which is far more intervention than a policy aimed at
persistently failing families should need.

`minAttempts` is the control on that, and `maximumGap` is nearly inert:
engagement holds between nineteen and twenty-two per cent across gaps of three
to twelve, because the gap decides how hard a contraction bites rather than how
often the mechanism has an opinion. The floor runs the other way, and at 0.67 no
run matches the baseline at all, which is the mechanism deciding that almost
every family is unhealthy.

### Where the intervention was landing

Parity per archetype, against each one's overall managed-execution rate:

| archetype                | managed | evidence 4 | evidence 6 |
| ------------------------ | ------- | ---------- | ---------- |
| `true_beginner`          | 1%      | 0/2        | 0/2        |
| `developing`             | 24%     | 0/2        | 0/2        |
| `uneven_hands`           | 44%     | 0/2        | 2/2        |
| `coordination_limited`   | 59%     | 0/2        | 1/2        |
| `fast_but_placed_low`    | 66%     | 1/2        | 2/2        |
| `tempo_noncompliant`     | 71%     | 1/2        | 2/2        |
| `intermediate`           | 72%     | 2/2        | 2/2        |
| `compliant_then_sprints` | 75%     | 1/2        | 2/2        |
| `advanced`               | 83%     | 2/2        | 2/2        |

At four, the mechanism was perturbing learners producing managed execution on
three attempts in four. **That is leakage, not dosing.** At six, every archetype
above two thirds is untouched, and what remains is the learners whose families
are actually failing.

`coordination_limited` losing parity on one seed at six is the mechanism working
rather than leaking: that learner's overall yield is fifty-nine per cent while
its hands-together family yields nothing, and the contraction is family-level by
construction.

`minAttempts` is therefore six rather than four. Everything else stays where it
was: the floor at 0.34 sits between an arm that barely engages and one that
engages on everything, and the gap is chosen from the saturation shape rather
than from a difference the sweep could measure.

### Whether six is reachable

Raising the evidence minimum trades one failure mode for another. Too low and a
healthy family is contracted off an unlucky run; too high and a family that is a
small minority of every sitting fails indefinitely without ever holding six of
the last twelve selections, so the mechanism is not slow to answer but unable
to.

`doseLatencies` measures which of those is happening. From the start of a
family's failing run it reports whether the family ever became contractible, how
many slots that took, and what share of the window the family held when the run
began. Read against a baseline run as readily as a dosed one, because it asks
what the policy could have said rather than what it did.

Sixteen sittings of twelve across seventy days, three seeds:

| archetype              | family            | share at onset | reached | slots waited |
| ---------------------- | ----------------- | -------------- | ------- | ------------ |
| `coordination_limited` | `hands:right`     | 42%            | yes     | 3            |
| `coordination_limited` | `hands:together`  | 17%            | yes     | 8            |
| `coordination_limited` | `motion:contrary` | 17%            | yes     | 31           |
| `coordination_limited` | `motion:parallel` | 17%            | never   | -            |
| `uneven_hands`         | `hands:left`      | 40%            | yes     | 5            |
| `uneven_hands`         | `hands:together`  | 8%             | yes     | 12           |

**Six of twelve is slow rather than blind, down to about a sixth of the
sitting.** A family holding forty per cent of the window is contractible within
a handful of slots; one holding a sixth takes eight to thirty-one; one holding
under a tenth may take most of a run or never arrive. On a seventy-slot month
rather than a seventy-day one, the same minority families read `never` where the
long run eventually reaches them, so the reachability answer is a property of
the run length as much as the policy.

Whether that matters is a product question this does not settle. A family
occupying seven per cent of practice and failing is a different situation from
one occupying a third, and it is not obvious that the first wants contracting at
all. If it does, `minAttempts` and `window` are coupled and want a grid of their
own rather than another axis.

### The floor against the gap

Nine cells at six attempts of evidence, on `normal_month`, two seeds, nine
archetypes. Engagement, the share of slots altered, and parity:

| floor | gap 3         | gap 6         | gap 12        |
| ----- | ------------- | ------------- | ------------- |
| 0.2   | 8% / 5% / 14  | 9% / 7% / 13  | 10% / 7% / 13 |
| 0.34  | 10% / 7% / 14 | 10% / 7% / 13 | 11% / 8% / 12 |
| 0.5   | 11% / 7% / 14 | 11% / 8% / 12 | 12% / 9% / 12 |

A plateau rather than a ridge: engagement moves between eight and twelve per
cent across the whole surface, and the centre sits in the middle of it.

The interaction worth recording is with the evidence minimum rather than between
these two. At four attempts the floor was a strong lever, sixteen per cent
engagement at 0.2 against thirty-four at 0.67 with no run matching the baseline;
at six the same floors span eight to twelve. **Requiring more evidence absorbs
most of the floor's influence**, because a family that cannot accumulate six
attempts is untouched whatever the floor would have said about it. Evidence is
the control, and the floor is trim.

### Prerequisite relief

The aggregate sweep says relief does nothing: engagement runs from eight per
cent at zero to ten at one, monotone and tiny. That reading is an artifact of
the run length and of the cadence rounding, since a halved contraction still
contracts, four slots instead of six.

Read where it is meant to act, on coordination work over sixteen sittings of
twelve, it is the strongest lever of the three. Hands-together family, four
seeds:

| relief | `developing` share | `coordination_limited` share | reachability |
| ------ | ------------------ | ---------------------------- | ------------ |
| 0.0    | 44%                | 33%                          | never        |
| 0.5    | 35%                | 29%                          | reached      |
| 1.0    | 32%                | 29%                          | reached      |

At zero, productive separate-hand work cancels the contraction outright, and
since both learners do have improving separate hands, coordination work grows to
nearly half the sitting and `coordination_limited` never becomes contractible at
all. That is relief overwhelming the family's own zero yield, which is the
failure mode the parameter has to avoid. Pacing then picks up what dose control
put down: set-asides for `developing` jump from none to thirty-eight, the two
mechanisms substituting for each other at the extreme.

Half and one differ little, and half sits on the side of asking for slightly
more coordination from a learner whose hands are improving separately, which is
what it is for. It stays at half.

### The half-life

Return delay on the ninety-day break schedule, four seeds, in slots into the
returning sitting before coordination work is offered again:

| half-life | `developing` | `coordination_limited` |
| --------- | ------------ | ---------------------- |
| 1 day     | 0.0          | 1.0                    |
| 7 days    | 0.0          | 0.5                    |
| 30 days   | 0.0          | 0.5                    |
| no ageing | 2.5          | 1.0                    |

One, seven and thirty days are indistinguishable, and only the arm that never
ages differs. The arithmetic says why: ninety days is three half-lives at thirty
and thirteen at seven, so both have decayed to a cadence of one or two slots by
the time the learner returns. **The parameter matters only when it is comparable
to the break it has to survive**, so for breaks of days to months the choice is
binary between ageing and not, and seven days is defensible without being
load-bearing.

## The full longitudinal rerun

Every archetype and schedule, four seeds, ten slots a sitting, run twice with
nothing differing but the policy. The intervention columns count the share of
slots each mechanism changed, and the share where both did.

| archetype              | dose changed | pacing changed, dosed | pacing changed, baseline |
| ---------------------- | ------------ | --------------------- | ------------------------ |
| `true_beginner`        | 37%          | 0%                    | 9%                       |
| `developing`           | 19%          | 0%                    | 1%                       |
| `uneven_hands`         | 4%           | 0%                    | 0%                       |
| `coordination_limited` | 2%           | 0%                    | 0%                       |
| `advanced`             | 0%           | 0%                    | 0%                       |

**The two mechanisms never acted in the same slot, and dose control replaced
pacing rather than adding to it.** Every pacing set-aside the baseline made is
gone, because contraction keeps the concentration that pacing was reacting to
from forming. That is worth knowing before promotion: dose control is not an
additional intervention on top of the existing one for these learners, it is a
different and earlier one.

Against the criteria the mechanism was built for:

```text
low-yield families contract          yes, and the post-failure share falls
high-yield learners unchanged        yes, byte-identical for advanced
low-share families left alone        yes, untouched under a tenth
milestones still occur               yes, and the beginner reaches more
no dry sittings                      none, on any schedule or archetype
returning reflects the half-life     yes, at the boundary only
```

The one row that reads worse is the true beginner, which is the archetype where
every family fails and no alternative is better. Its month schedule moves from
84 to 89 per cent pre-frontier work and from nine to four per cent
consolidation, and its returns that never progress again go from seven to
eleven. Against that, it reaches hands together and two octaves where the
baseline reached neither. A learner who cannot execute anything is not a dose
problem, and contracting every one of its families at once is the mechanism
having nothing useful to say rather than saying something wrong.

## What is unsettled

Every constant. `window`, `minAttempts`, `yieldFloor`, `maximumGap`,
`prerequisiteRelief` and `evidenceHalfLifeDays` are provisional, chosen to be
legible rather than tuned, and a sweep either side of them is the work that
would justify promoting this into the V1 policy.

The one coarse probe run so far is of `maximumGap`, on `coordination_limited`
over `normal_month` at four seeds. Its hands-together share reads 33, 28 and 27
per cent at gaps of three, six and twelve, so the response saturates rather than
running away, which is the shape a stable region would have. One archetype on
one schedule is not that evidence, only a reason to expect it exists.

Why a one-slot pacing set-aside does not reduce a family's share over a run is
still unexplained, and dose control does not explain it: `true_beginner` was set
aside fifty-nine times on its left hand under pacing alone with no contraction
at all. Something returns the family immediately afterwards, and finding out
what is a separate investigation.
