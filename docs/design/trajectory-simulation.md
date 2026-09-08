# Trajectory simulation

## Why

Device sittings found real defects, and they were finding them slowly. A person
at a piano covers one point in the space of players: one natural tempo, one pair
of hands, one level of familiarity, one honest answer at placement. Several
recent defects were interactions between locally reasonable rules, visible only
in a trajectory rather than in a decision, and the person best placed to notice
them is the one least able to enumerate the states that produce them.

The existing synthetic profiles could not close that gap. They sample an outcome
from a hidden ability, and their achieved tempo is a quality score in `[0, 1]`,
so **no learner they can express plays faster than they were asked to.** Every
tempo defect the device found lived in exactly that gap, which is why simulation
had been silent about all of them.

## The three kinds of testing

Kept apart deliberately, because they answer different questions.

|                          | asks                                                  | when                  |
| ------------------------ | ----------------------------------------------------- | --------------------- |
| Sweep (`bin/sweep.dart`) | does anything go wrong across many players and seeds? | deliberately, minutes |
| Invariant tests          | do the structural properties still hold?              | every commit, seconds |
| Paired experiments       | does a policy change trajectories for the better?     | while designing one   |
| Device playing           | do the abstractions resemble real playing?            | ecological validation |

A paired experiment runs the same archetype and seed against two pipelines and
compares the trajectories. It is how a policy with no defensible per-slot
criterion is judged at all; see
[`realization-family-pacing.md`](realization-family-pacing.md) for a worked case
and for what that grain of evidence can and cannot establish.

Device sittings stop being a coverage mechanism. They become the check on
whether the model's assumptions correspond to what a person at a keyboard
actually experiences, which is the one thing simulation cannot answer.

## The player

`SyntheticPlayer` receives an exercise and answers what happened, rather than
producing an outcome from a hidden ability. Requested tempo and performed tempo
are separate quantities throughout, related by `tempoCompliance`: one is a
metronome follower, zero is somebody who plays at their own pace whatever the
screen says, and between them the performed tempo is a geometric blend, so being
asked for twice your natural pace and half of it are equally far off.

The knobs are meant to be legible rather than orthogonal: natural tempo per
hand, compliance, per-hand ability, hands-together ability as its own skill,
span penalty, familiarity, noise, learning rate. An archetype is a named
configuration of that one model, never its own implementation, so a defect can
be reported as "this kind of person" and two archetypes that fail the same way
are visibly one failure.

Determinism is total: archetype plus seed plus length reproduces a trajectory
exactly, so a pathological seed is a fixture rather than an anecdote.

## Invariants and observations

Detectors carry a severity, and the distinction is load-bearing.

An **invariant** is a property any healthy scheduler should hold, stated without
a tuned number. `realization_stall` fires when a surpassed realization was
chosen while an equally eligible advancing one of the same material and hand was
admissible: both reached ranking, and one asks for something the learner has
demonstrably outgrown. No threshold makes that the right choice. These are
asserted.

An **observation** is a count against a threshold picked by judgment. "Twelve of
fifty slots below the frontier" is suspicious, and nobody yet knows whether the
right bound is two or fifteen. These are reported by the sweep and read by a
person. Asserting one would freeze today's behavior as the definition of healthy
practice and give the simulation a second specification whose arbitrary numbers
are as hard to reason about as the scheduler's.

## What a slot can and cannot answer

**A slot's `alternatives` are post-admission and post-guard evidence, and cannot
answer what was refused.** They are built from the selectable set, so every
candidate in them already cleared eligibility, challenge admission, and the
repetition guard. A diagnostic that counts refusals over `alternatives` measures
only the survivors, and reports the admission stage as near-total success by
construction.

A sitting evaluates thousands of candidates a slot and retains the selectable
ones, which is why the refused ones have to be read as they go past:
`runTrajectory` takes an `observeTraces` callback that receives every trace for
each slot. Anything asking which stage refused a candidate, or under which
guidance rung, reads that rather than the trajectory.

**An absent rank key means ranking was not reached, not that the data is
missing.** A `CandidateTrace` answers the qualification stages for every
candidate, because "why not that one?" has to be answerable from the trace. It
does not answer ranking for a candidate that never competed: there is no key,
because a key it could not have competed on would be a number presented as
though it meant something. Most candidates are in that position, so the same
contract is what stops a slot computing ranking terms for the ninety-five per
cent that cannot consume them.

The practical consequence for anything reading traces, in telemetry or analysis:
a property of a candidate is asked of the candidate, and only what the scheduler
_decided_ is read off the trace. A diagnostic wanting to know whether a refused
candidate was advancing calls `realizationRankFor` itself rather than reaching
for a rank term, which keeps instrumentation from requiring production to
compute things it does not need.

## The census

Every trip carries the candidate census for its slot: the winner, everything it
was chosen over in rank order, eligibility tier and reason, the full rank key
including realization rank, the frontier and paced tempo, and what the player
actually did.

This is the deliverable rather than a convenience. Three separate diagnoses in
this repository were wrong because the pipeline was reasoned about instead of
observed, and each was corrected by building exactly this table by hand. An
anomaly that cannot show its working is not worth raising.

## What the first sweep found

Eight archetypes, a hundred seeds each, fifty slots: forty thousand decisions.

`realization_stall` fired **zero times**, which is the strongest evidence
available that splitting `RankKey` into a material question and a realization
question fixed the generation-order pathology rather than making one device
trajectory look better. `below_frontier_share` and `guidance_regression` were
also silent throughout.

`entry_tempo_ignores_pace` fired about five thousand times, across every
archetype past a beginner and none below. One cause: the band cap in
`entryTempoFor` discarding the transferable pace. Beginners never reach the
capped bands, which is why a person testing at a piano as a beginner could not
have found it.

`hands_together_stall` needed decomposing rather than believing, and the first
decomposition was itself wrong. It measured slots from both hands completing a
material to the first slot where _any_ hands-together candidate survived
admission. But the catalog is wide, most of it is provisionally eligible on the
hands-together prerequisite, and provisional candidates still survive admission
and rank last, so that clock started at slot zero in nearly every run on a
material unrelated to the one whose hands were ready. It reported instant
availability and concluded the delay was all ranking. Neither half was
established.

Repeated against fully eligible candidates for the _same_ material, with
readiness read from the scheduler's own prerequisite verdict rather than
reconstructed from outcomes, and with impossible orderings counted rather than
clamped to a plausible zero, it separates into two different defects.

For a player whose hands are close in ability, the offer latency is zero at both
the median and the ninetieth percentile: the slot that first satisfies the
prerequisite also carries a fully eligible candidate that survives admission.
Coordination work is then chosen in fifteen to twenty-five runs of forty, a
median of twenty to twenty-five slots later. Available immediately, unchosen for
a third of a sitting, and in a good many sittings never chosen at all. That is a
ranking question.

For a player with one weak hand it is not. The prerequisite is satisfied in two
runs of forty, and for a true beginner in none: the frontier only advances on an
attempt completed at or above `demonstratedMotorScore`, a weak hand rarely
clears that, so its frontier stays empty and hands-together never qualifies. The
first instrument reported this archetype as offered in every run and chosen in
one, which read as the strongest ranking evidence in the sweep and was the exact
opposite of what was happening.

Being roughly right for five archetypes while inverted on the two that motivated
the investigation is the worst available way to be wrong, and only a clock
sourced from stage 2a on the same material could tell them apart.

The lesson worth keeping is about the detectors rather than the scheduler. Two
of the first definitions were wrong in the same way: `exclusive_target_emptied`
fired on every recovery slot, because recovery is _meant_ to narrow a slot to
one candidate, and `progression_stall` counted a run of introductions as a
frontier that would not move. Both encoded "what the scheduler currently does"
as a property. The census made both obvious on one read, which is the argument
for the census.

## Sittings and simulated time

A run is a list of sittings rather than a single unbroken sequence of slots.
Each names the instant somebody sat down and how many attempts they made, and
`runSittings` plays them in order; `runTrajectory` is the one-sitting case of
it. Slot indices run across the whole run and every slot carries the sitting it
belonged to, so a detector reads one ordered history and can still ask where the
breaks were.

**What crosses a break is what crosses it in the app.** Learner state persists
and keeps decaying through the gap, which is the whole question a run across
weeks asks. The sitting's own scheduling context is rebuilt on the far side
through `SessionState.resuming`, which is the same function `PracticeSession`
uses when the app reopens: the recency and pacing windows carry over from the
tail of the history, and the attempt cap, the recovery context, the waiting
tempo probe and the guidance counters do not.

That boundary is load-bearing rather than a convenience. A harness that kept one
`SessionState` for a whole run would let a probe opened in March be answered in
April because an object survived, and every long-run conclusion drawn from it
would be about the harness. Holding the two implementations to one function is
what makes a longitudinal trajectory a claim about the product.

Time advances two ways, and they are different questions. Within a sitting a
slot is a minute; between sittings it is the calendar. A probe waits a bounded
number of decisions by construction, so its latency is only ever interesting in
elapsed time, and a detector that mixes the two measures neither.

**A new scheduler mechanism ships with a detector or an invariant, not only a
fixture test.** A test pins the case that motivated the mechanism; a detector is
what makes the sweep able to say anything about it over a population. The tempo
probe is the worked example: `probe_echo` asserts that a fresh probe never wins
the slot after the attempt that opened it, and `probe_verification_share`,
`probe_stranded` and `probe_defer_blocked` count what the mechanism does with
the probes it opens.

The first thing those counters said is that probes almost never open in
simulation. Requests converge on the pace a player is already showing, so an
attempt that is clean, complete and well above what was asked is rare, and the
`compliant_then_sprints` archetype exists because no constant `tempoCompliance`
produces one at all. The device found the echo because a person does this
occasionally rather than proportionally.

## Characterizing a run across the calendar

Five named schedules, in `LongitudinalSchedules`, rather than a sweep over gap
lengths: `dense_week`, `normal_month`, `interrupted`, `sporadic` and
`return_after_long_break`. The same twelve sittings dense, spread, interrupted
or sporadic are four different questions, and the days are attendance rather
than policy, since nothing in the app schedules a sitting.

`censusOfRun` summarizes a trajectory one sitting at a time: slots that advanced
a frontier, slots that met an unseen material, slots on known work that moved
nothing, slots asking for less independence than that material has already
shown, probes opened, answered and stranded, coverage, and the sitting each
milestone was first reached in. `bin/longitudinal.dart` runs every archetype
against every schedule and reports it.

The reason this exists rather than more detector incidence is that a count of
returning sittings that crossed a threshold cannot answer the question worth
asking, which is whether a break costs a learner one sitting or traps them. So
the census reports, for every gap, the share of the returning sitting spent
reacquiring **and** how many sittings passed before anything moved forward
again.

### What the first characterization said

Ten slots a sitting, four seeds, every archetype and schedule.

Every archetype but one resumes progression in the returning sitting itself. The
median sittings-to-progress after a break is zero across `normal_month`,
`interrupted`, `sporadic` and `return_after_long_break`, so a gap costs a share
of one sitting rather than a trajectory. The share itself scales with the
learner: an advanced player spends ten to twenty per cent of a returning sitting
on old work, an uneven-handed one about half.

`true_beginner` looked like the exception. It spent effectively the whole
returning sitting on known work, and in roughly a third of its returns nothing
progressed for the rest of the run. Its sittings never ran dry, so it was not
the pinned narrow-catalog defect.

It was not a defect in the scheduler either, and finding that out is what the
census is for. The returning sitting was decomposed into the two ways a slot
that moves nothing happens: something that would have moved the learner on was
selectable and lost, or nothing progressing survived to the selectable set at
all. The beginner split about evenly between them, which explained nothing, so
the run either side of the gap was read instead.

**The beginner never progressed, gap or no gap.** Over three hundred attempts
across sixty days it produced two outcomes the model accepted as demonstrated
execution, and its motor score did not rise: 0.12 at the start and 0.14 at the
end. Sitting length ruled out the other reading; at five, ten and twenty slots
the returning share stayed at essentially a hundred per cent, so it was not
failing to climb out of a sitting that ended too early.

The cause was in the player. `SyntheticPlayer` improved only on an attempt that
completed with a motor score above one half, which this archetype reached about
twice in three hundred attempts. Low starting ability was therefore an inability
to learn, and the two were impossible to tell apart.

### Practice below the evidence threshold

The two are different claims, and the simulator has to keep them apart:

```text
evidence credit   what KeyRecall has been shown, and may act on
human learning    what happened to the person, shown or not
```

Evidence credit stays strict. A weak attempt must not establish a frontier, and
`LearnerModel.demonstratedTempoBpm` still caps attribution at the tempo that was
asked for. Human learning is now graded rather than gated: an attempt improves
the player in proportion to `4q(1 - q)` in its motor quality, largest where the
task sits at the edge of what they can do, halved when the attempt broke down
before the end, and nothing at all when it never started. **Not demonstrated is
not nothing learned.**

No ceiling is needed. As ability grows the same task is executed better, which
moves it away from the edge, so improvement slows unless the scheduler keeps
asking for something harder.

The shape that produces, over three hundred attempts across sixty days:

| archetype       | frontier advances | first advance | milestones          |
| --------------- | ----------------- | ------------- | ------------------- |
| `true_beginner` | 11 to 19          | sitting 1-11  | hands together 9-14 |
| `developing`    | 64 to 69          | sitting 0     | hands together 0-2  |
| `advanced`      | 241 to 245        | sitting 0     | all by sitting 1    |

The beginner learns slowly rather than not at all, and does not rocket: its
motor score stays near 0.15 throughout, because the scheduler keeps pace with
the improvement and asks for harder work. It falls in the last fifth of the run,
which is worth returning to: coordination work arriving at sitting nine costs
this learner more than they can execute.

`learningRate` is now a knob worth fitting. Starting ability and rate of
improvement are two hypotheses about a learner rather than one, which is the
distinction a calibration from device data would otherwise silently collapse.

### What arriving at coordination costs

The beginner's execution quality falls late in a long run, shortly after
hands-together work first appears. Coincidence and cause are indistinguishable
from one trajectory, so the same player and seed were run twice against the same
schedule with the second arm's candidate set holding no hands-together work at
all. Nothing else differs: same learner model, same scheduler, same player.
Sixteen sittings of ten across seventy days, six seeds, measured from the slot
the baseline first reached coordination.

| archetype              | motor baseline / withheld | completed |
| ---------------------- | ------------------------- | --------- |
| `true_beginner`        | 0.14 / 0.19               | 30% / 41% |
| `developing`           | 0.35 / 0.46               | 63% / 61% |
| `uneven_hands`         | 0.70 / 0.78               | 72% / 72% |
| `coordination_limited` | 0.70 / 0.79               | 49% / 75% |

**It is composition rather than shock.** The milestone shock at coordination is
real and short: the median motor score falls from 0.20 to 0.12 for the beginner
and recovers within five slots in five of five runs. What persists is the share
of every later sitting spent on work the learner cannot execute, and it persists
because nothing withdraws coordination when it keeps failing.

The effect is not specific to the beginner, which is the argument against
reading the table as a defect. Withholding coordination raises execution quality
for every archetype, including the two whose whole difficulty is coordination.
It also raises frontier advances, and that comparison is unfair by construction:
the withheld arm is practising an easier catalog, and single hands advance a
frontier more readily than two do. Removing the hard thing always looks better
on quality.

`coordination_limited` is the row worth returning to. Completion falls from
seventy-five per cent to forty-nine when coordination is available to a learner
defined by not having it, and its supported-guidance share is the highest of any
archetype. That is the scheduler continuing to ask a question this learner keeps
answering the same way, which is a policy question rather than a defect, and one
the harness can now pose.

`milestoneShocks` reports this generically, for coordination, contrary motion,
two octaves and unguided alike, as a delta and a recovery time rather than a
warning. A dip that recovers is desirable difficulty. One that does not is the
scheduler asking for something out of reach, and the two are only separable
after the fact.

### Whether the dose responds to the answer

Support adapts already: a family that keeps failing gets more guidance. Nothing
adapts the other quantity. `bin/family_exposure.dart` asks whether a family's
**share of the sitting** contracts when the learner keeps giving the same
answer, by reading each family's attempts, managed yield, longest run of
attempts that yielded nothing, and its share of the ten slots following such a
run. Sixteen sittings of ten across seventy days, four seeds.

| archetype              | family           | share | after | yield | longest run | set-asides |
| ---------------------- | ---------------- | ----- | ----- | ----- | ----------- | ---------- |
| `coordination_limited` | `hands:together` | 36%   | 45%   | 0%    | 53          | 3          |
| `developing`           | `hands:together` | 42%   | 31%   | 0%    | 60          | 24         |
| `true_beginner`        | `hands:left`     | 56%   | 60%   | 0%    | 89          | 59         |
| `uneven_hands`         | `hands:left`     | 22%   | 28%   | 4%    | 24          | 0          |
| `advanced`             | `hands:together` | 21%   | 0%    | 86%   | 1           | 0          |

**A learner can be asked the same unanswerable question fifty-three times in a
row.** `coordination_limited` attempts hands-together work fifty-three times
after it first appears, yields managed execution on none of them, and the
family's share of the slots after a failed run is _higher_ than its share
overall. `true_beginner` does the same with its left hand, eighty-nine times.
The strong archetypes never reach a run of two, so nothing here is about the
work being hard.

Realization-family pacing is the mechanism that could answer this, and its
trigger is the wrong shape for the case. Pressure is
`share above the floor x unproductive fraction`, and the floor is half the
window, so a family holding thirty-six per cent of a sitting accumulates no
pressure however little it yields. That is why `coordination_limited` sees three
set-asides across a run where nothing it coordinated ever worked.

Where the floor is cleared the response is still weak rather than absent.
`developing` clears it, is set aside twenty-four times, and its share falls from
forty-two to thirty-one per cent. `true_beginner` clears it by more, is set
aside fifty-nine times, and its share does not fall at all. Why relief does not
translate into a smaller share is the open question: a set-aside substitutes one
slot, and something appears to return the family immediately afterwards.

Two things follow, and neither is settled here. The trigger a dose mechanism
needs is **yield over recent attempts of a family**, independent of how much of
the sitting it holds, since the family that most needs contracting is a minority
of the sitting by the time it is failing. And a mechanism should contract rather
than remove: the same evidence would justify a cooldown that relaxes on managed
execution, on productive work in the prerequisites, and on time, with the family
always able to surface when nothing else is useful.

### Reacquisition, in the strict sense, does not happen

The census partitions every slot that moved nothing into work with no frontier
yet, work below a frontier the hand has demonstrated, and work at or past one
that failed to move it. Across every archetype and schedule, the middle category
is **zero**.

A demonstrated frontier is a maximum, and it does not decay. So decay never
produces work below one: what a break actually produces is retrieval support on
material the learner still owns, and consolidation at a frontier they cannot yet
pass. The reacquisition burden a weak learner appeared to carry was acquisition
all along, on material they had seen but never demonstrated anything on.

Whether a frontier should decay is a product question this does not answer. It
does say that nothing in the current model expresses losing ground, and that a
detector counting known material as reacquisition will report every weak learner
as one who keeps losing it.

`dense_week` reports nothing about returning at all, by construction: no gap in
it reaches two days, so it has no returns to summarize. It is there as the
control.

The tempo probe reads as a mechanism that opens and is not answered. The
advanced player opens seven to ten probes across four seeds of `interrupted` and
answers none of them, stranding one or two at a sitting boundary. Too few
openings for `probe_verification_share` to trip on any single run, which is
worth remembering: a mechanism that fires rarely needs the census rather than a
per-run threshold.

## A slot decided by a difference too small to mean anything

The rank key is a dictionary ordering, so the first term that differs at all
settles a slot however little it differs by and however much better the
alternative is on everything after it.

A device sitting produced the shape. An exercise at sixty beats, on material
whose frontier was a hundred and thirty-two, beat a waiting tempo probe because
its retention read 0.000122 against 0.000101. That is a fifth of nothing,
decided four terms before the realization rank, which knows what the learner has
demonstrated, could speak at all.

**Nothing in the harness was looking for it.** `realization_stall` asks whether
a better realization of the _same material and hand_ was passed over, and the
two candidates here were different scales. The relationship between the
exercises was never the problem; the margin was.

`hairline_rank_decision` asks the general question: did a continuous term decide
this slot by a hair, over a candidate that ranked better on the realization? It
reports which term did it and by what proportion. An observation rather than an
invariant, because that a near-tie decided a slot is a fact while deciding it
was wrong is a judgment, and the threshold for near is exactly the kind of
number this file refuses to assert on.

It fires eleven to twenty-five times per archetype over a hundred and twenty
slots, on every archetype but the true beginner, so the device sitting was not
unlucky.

### Two populations, not one

The findings split, and the split is the useful part. Over the same runs, by the
term that decided:

| term          | findings | absolute p10 | absolute p50 | relative p50 |
| ------------- | -------- | ------------ | ------------ | ------------ |
| `information` | 126      | 1.2e-6       | 1.5e-1       | 7.0%         |
| `retention`   | 31       | 1.6e-4       | 1.9e-4       | 7.3%         |

Both look identical proportionally and are nothing alike. Information runs from
about 0.4 to 3.5, so a median margin of 0.15 is a real difference on that term
rather than a tie; retention for known material sits near 1e-4, so a margin of
1.9e-4 is the whole quantity. **A proportional detector finds both, and only one
of them is a near-tie.**

The device case is smaller than either: 2.1e-5 in retention, below the tenth
percentile of anything the simulation produced. A retention tolerance of 1e-4
therefore covers it with headroom while leaving the simulated population
untouched, and the census either side confirms exactly that: `advanced` loses
one finding of twenty-five, `reliable_self_paced` gains one progression stall,
and nothing else moves.

That is a safety result rather than a benefit one. **The tolerance is defensible
as a statement of policy, that a retention difference below 1e-4 is not
decision-relevant, and simulation cannot show it helping because simulation
never produced a near-tie that small.** It stays at zero in the V1 policy until
that statement is made deliberately rather than inferred from one sitting.

Tolerating the information findings would be a different act entirely: a
fifteen-hundredth of that term's range is a preference the key is expressing,
not a rounding error, and a tolerance wide enough to tie them would rewrite what
the term means.

## What a sweep costs, and what makes it worse

A parameter sweep is a different shape of cost from the trajectory sweep. It
runs the same jobs many times over, and the first full one was killed by the
machine running out of memory.

Two redundancies did most of it. Every arm re-simulated the baseline for its
parity comparison, so fifteen configurations meant fifteen identical baseline
runs per job, and every arm spawned a fresh set of isolates that each
regenerated the catalog. Both are gone: a worker now lives for the whole sweep,
generates the catalog once, runs each job's baseline once, and keeps only the
baseline's chosen sequence as a digest. That is seventeen trajectories per job
where there were thirty-two.

Parallelism past a point makes it worse rather than better. The same sweep, on
this machine:

| workers | wall  | peak resident |
| ------- | ----- | ------------- |
| 2       | 289 s | 0.6 GB        |
| 4       | 200 s | 0.8 GB        |
| 8       | 459 s | 9.1 GB        |

Eight workers is both slower and an order of magnitude hungrier, which is what
killed the first run. **A worker's heap is the limit, not its CPU**, because
each holds its own catalog and the traces of the slot it is on. Memory scales
badly enough past four that more parallelism is slower, so the default is four
rather than a processor count, and raising it back to one worker per processor
is a change that makes the tool worse.

What was deliberately not done: nothing in the production decision pipeline was
touched to make sweeps faster, and trajectories still carry their full
diagnostic state. The harness is worth having because a surprising row can be
explained without a rerun, and the cost that mattered was doing the same work
twice rather than the work itself.

## Making the sweep fast enough to iterate on

A sweep that takes half an hour is not a development instrument, it is a thing
you run overnight and stop consulting. Profiled rather than guessed at:

```text
advanced, 6 seeds x 50 slots        40.2 ms per slot
  evaluate                          96%
  sort alternatives                  2%
  selectable                         2%
  everything else                   <1%

per candidate, 8190 candidates per slot
  predict                          1.062 us
  information                      1.069 us
  eligibilityFor                   0.212 us
  structuralQ                      0.194 us
  realizationRankFor               0.168 us
```

So the synthetic player, the detectors, the census and the learner update are
all noise. The cost is stage 3 and stage 4 evaluating eight thousand candidates
a slot, and prediction plus information are more than half of it. That is a fact
about the app as much as the sweep: it makes one of these decisions while
somebody waits.

Trajectories are independent and determined by archetype, seed and
configuration, so they run across isolates, dealt round robin rather than one
archetype per isolate: a true beginner's sitting costs a fraction of an advanced
one, and grouping by archetype leaves the slowest gating the sweep. Candidate
generation is hoisted, being learner-blind.

`trajectory_digest_test.dart` pins two benchmark trajectories by digest, so a
performance change that alters a single choice, outcome or anomaly fails rather
than quietly becoming a second implementation. The rule the sweep is worth
nothing without: **optimizations may hoist pure candidate and configuration
facts, and the real state-dependent scheduler logic still runs every slot.**

Two modes, and the default is the fast one: twenty-five seeds for iteration, a
hundred or more to run deliberately either side of a scheduler change.
