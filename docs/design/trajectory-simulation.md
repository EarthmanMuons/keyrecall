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

### Playing, rather than scores

`play` samples an `Outcome` directly, so nothing it produces has a position: no
attempt it can express hesitates at the fourth degree. That is adequate for the
ordinary path, where every reading is an aggregate anyway, and inadequate for
anything localized.

`performAcquisition` answers with a `PerformanceTranscript` instead, and the
readings come from the alignment and observation path device MIDI takes. It
produces four phenomena and no others: uneven but complete playing, a hesitation
localized to a moment, a wrong note with or without a repair, and stopping
partway. None of them is a switch that selects a diagnosis; each is what the
corresponding failure looks like from the instrument.

Where the difficulty sits comes from the exercise rather than the player. A
crossing is a moment, so `opportunityPenalty` lands on that moment and nowhere
else. The player knows which moment it was and nothing downstream is told, which
is the property that keeps a policy fed from here honest: it can only respond to
what the instrument would have shown.

`executionEffortFor` shares that cost with ordinary `play`, whose aggregate
reading uses the hardest opportunity in the exercise. The knob is zero on every
archetype in `all`; `crossingLimited` remains a separate localization fixture.

`performAcquisition` is observation-only unless `practising: true` is supplied.
Explicit practice uses the same hand-and-family learning state as ordinary work,
so a held-out parent probe can assess the resulting change. Tests establish
shared difficulty and transfer within this provisional model; they do not
establish pedagogical benefit or compare acquisition with ordinary practice.

## What supported work does to a sitting

`censusOfSitting` drives the production decision loop with a synthetic player
answering both paths from one latent ability: ordinary attempts through an
outcome, supported ones through a transcript read back by the observation path
device MIDI takes. It counts and concludes nothing.

The first pass, over three scales and forty slots, is descriptive and one number
in it is a finding rather than a datum.

| Player                        | Supported share | Longest run | Probes served |
| ----------------------------- | --------------- | ----------- | ------------- |
| `trueBeginner`                | 0.73            | 13          | 7             |
| `arpeggioStrongScaleWeak`     | 0.33            | 1           | 1             |
| every other shipped archetype | 0.00            | 0           | 0             |

Advanced, intermediate and developing learners never reach supported work, which
is what it is for. A true beginner spends nearly three quarters of the sitting
in it, in runs of thirteen.

The repetition guard is not violated: consecutive offers are different parents,
and the gap between two offers of the same parent is never one. Six declared
floors are stuck at once, so supported work rotates among them and satisfies a
rule that only forbids the same parent twice running. The rule does what it says
and does not bound supported work in aggregate.

Latency reads sensibly. One to three slots from a context's first ordinary
attempt to its floor being asked for, one slot from a floor attempt to
acquisition on it, and one slot from earning a probe to that probe being served.
Seven of twenty-nine supported attempts came out cleanly, three through
corrections, and nineteen not at all.

What it displaced is recorded per material and hand, which is the cost stated as
what was chosen instead.

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

**A worked example is part of a detector's contract, not an illustration of
it.** Incidence is the part that always looks respectable: a plausible number
against a plausible name, with nothing in it that can be wrong out loud. Every
detector mistake this repository has made was invisible in the table and obvious
in the first example printed under it, and the count is now four.
`exclusive_target_emptied` fired on every recovery slot, `progression_stall`
counted a run of introductions, the first `unsupported_novelty_stack` counted
the absence of a history at slot zero, and the second counted one newness twice
in the way the production comment it was checking documents avoiding.

The same reading caught an intervention rather than a detector. Charging an
unsupported span a rung of guidance produced an identical census, and the
example said why: the candidate was already at the rung the charge would have
moved it to. **An intervention that cannot change the example it was built for
is not a weak fix, it is the wrong instrument**, and the census is what tells
the two apart.

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

## What a first exposure arrives with

`noveltyLoadOf` counts how many ways of playing arrive at once, and asks all of
them of the material in hand. That is deliberate and documented: a learner
playing contrary motion in C major is not meeting contrary motion in G major,
but the state can only answer the local question.

The consequence is that **on a material nobody has played, the span is not
counted at all**. A hand configuration with no record has no span to have
covered, so counting both would say one newness twice, and the load reads one
whatever span arrives. Tempo is outside the count entirely, priced by the
challenge band. A device sitting met D harmonic minor at two octaves and a
hundred and thirty-two beats with a novelty load of one.

`unsupported_novelty_stack` asks the wider question the load cannot: on a first
exposure, how many dimensions arrive that the learner has demonstrated **nowhere
in the run**? Evidence rather than a rule about beginners, so an established
learner's history collapses the count, which is what separates level-setting
from throttling.

### Getting the question right took three censuses

The first fired thirty-four times on a true beginner, and its worked example was
slot zero: the first attempt of a run is unsupported on every axis because
nothing has happened yet. That is counting the absence of a history rather than
the scheduler ignoring one, so it is silent now until the learner has managed
something.

The second reported a left hand at one octave as two unsupported dimensions,
hands and span. Those are not two things, and it is the same double-count the
production comment says it is avoiding: a hand nobody has used has no span to
have covered. Each axis is now asked independently, span of the octave count
alone rather than of the hand and span together.

Both were wrong the way this file has recorded detectors being wrong before, and
both times the census made it obvious on one read while the incidence table
looked fine.

### What the third one says

Twenty findings across nine archetypes, three seeds, forty slots each:

```text
by slot   1: 15, then 2, 3, 4, 5, 6 once each
by axes   hands and span: 17, span and tempo: 3
```

Every one is a new material meeting an unpractised span, and fifteen of twenty
are at slot one. The shape is real: a second attempt that introduces a new
material, a hand never used and a span never covered, scored as a novelty load
of one because the span was skipped.

It is also almost entirely a beginning-of-run phenomenon, where the evidence
base is a single attempt. So the question thread three actually raises is
narrow: **should a span with no support anywhere be free on a material with no
record?** The device sitting had that support and would not have been reported;
these runs do not.

### The guidance ladder cannot answer it

The obvious correction is to charge an unsupported span the way novelty is
charged, taking a rung of guidance back. Built, censused, and reverted: the
counts came back byte for byte identical, because the lever does not reach.

An unseen material is only provisionally eligible unless its guidance supplies
the notes, so **a first exposure is already at notes previewed**. The novelty
allowance of three gives a load of one the right to be unguided and a load of
two the right to notes previewed, which is what the candidate already had. The
charge is arithmetically real and behaviourally inert, and it could only bite a
first exposure carrying two local novelties as well as an unsupported span.

That leaves the question where it belongs. Guidance is the wrong instrument
because support is already at its floor for a first encounter, so a span with no
evidence behind it can only be answered by not offering it, which is an
admission claim rather than a support one. Whether it should be is a product
decision, and the harness has now said everything it can: the case is real,
rare, early, and out of reach of the mechanism nearest to hand.

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

## What a gap does to belief, and what it does to a person

The forgetful returner exists to separate two things a long-gap run used to
confound. Before it, the learner state decayed across a calendar and the
synthetic person did not, so every such run established how the scheduler reacts
to its own aging belief and nothing about whether that reaction suits somebody
who really decayed.

Three people over one schedule, four sittings and then a gap, measured on the
held-out set on arrival, before the return sitting starts moving them again. The
stable player forgets nothing; the matched returner loses execution on a
forty-five day half-life and the notes on a twenty day one; the faster returner
loses them on twelve and six. Retrieval is compared against the model's own
retrieval channel rather than against overall admission probability, because
those two are the same event and the overall probability is a stricter
conjunction carrying a level offset by construction.

| gap | model expects | stable | matched | faster |
| --- | ------------- | ------ | ------- | ------ |
| 1   | 0.844         | 1.000  | 1.000   | 1.000  |
| 2   | 0.712         | 1.000  | 1.000   | 0.958  |
| 7   | 0.313         | 1.000  | 0.958   | 0.833  |
| 14  | 0.106         | 1.000  | 0.833   | 0.625  |
| 30  | 0.011         | 1.000  | 0.792   | 0.625  |
| 60  | 0.000         | 1.000  | 0.625   | 0.625  |
| 120 | 0.000         | 1.000  | 0.625   | 0.625  |
| 240 | 0.000         | 1.000  | 0.625   | 0.625  |

**The model's retrieval decays on a half-life near four days and reaches exactly
zero by sixty**, which is faster than any of the three, including the one built
to forget quickly. At a fortnight it expects 0.106 of a player who delivers
0.625 at worst and 1.000 at best. The failure a returner meets is therefore not
a scheduler asking for April's work; it is one expecting nothing of somebody who
can still play.

What that costs, in the return sitting: the first thing offered is unguided work
the model predicts at 0.00, outside the challenge band and admitted by an
execution-progression bypass. It does not start. The recovery that opens then
walks guidance down, and the attempt at continuous cueing succeeds. The ladder
works, and the returner pays one failed attempt to teach it something the model
could have been less certain about.

Two limits on how far this bounds the learner model. The synthetic decay runs
toward the ability and familiarity the player started with, so none of the three
can express somebody who has genuinely forgotten a scale they once owned; the
comparison bounds the model from one side only. And this is the model at the
evidence level eighty practice slots over four materials produce, not at the one
a learner of several years would carry.

So the next question is retention calibration of the learner model, and the
place to answer it is device data from repeat users with real gaps, compared
against what the model predicted before they came back. Tuning the curve to
these half-lives would replace one assumed shape with another.

### What a return actually costs

A calibration discrepancy is a number about the model. `returnCostOf` asks the
product question next to it: how many attempts a sitting spends before the
learner answers anything. Attempts that never started before the first one that
did, rungs of guidance descended to get there, and attempts before the first
demonstrated execution. Five seeds, averaged.

| gap | stable          | matched         | faster          |
| --- | --------------- | --------------- | --------------- |
| 1   | 0.0 / 0.0 / 1.4 | 0.0 / 0.0 / 1.4 | 0.0 / 0.0 / 0.8 |
| 7   | 0.0 / 0.0 / 1.4 | 0.0 / 0.0 / 1.6 | 0.4 / 0.4 / 2.8 |
| 14  | 0.0 / 0.0 / 1.4 | 0.2 / 0.2 / 3.0 | 0.8 / 0.8 / 5.2 |
| 30  | 0.0 / 0.0 / 1.4 | 0.4 / 0.4 / 4.0 | 0.8 / 0.8 / 5.8 |
| 60  | 0.0 / 0.0 / 1.4 | 0.8 / 0.8 / 4.4 | 0.8 / 0.8 / 4.0 |
| 240 | 0.0 / 0.0 / 1.4 | 0.8 / 0.8 / 6.0 | 0.8 / 0.8 / 5.5 |

False starts, then rungs descended, then attempts played before the first
managed execution. The last is a count of what came before rather than the
number of the attempt that did it, so 1.4 means the second attempt, on average,
is the one that demonstrates execution.

**The stable player pays nothing at any gap.** After two hundred and forty days
the model expects nothing of them, and they still start the first thing offered
and demonstrate execution by the second, exactly as they did after one day. So
the over-decayed belief does not by itself produce a return cost, which is the
opposite of what the collapsed prediction suggested it would.

What costs is the person having actually forgotten. The matched returner goes
from answering immediately to spending an attempt on work they cannot begin and
six attempts of twenty before demonstrating anything; the faster one is there by
a fortnight. The execution-progression bypass offering unguided work outside the
band is what spends that attempt, and the recovery ladder is what ends it.

That separates the two open questions rather than merging them. The model's
retrieval decay is too aggressive, and it is not the mechanism charging a
returner attempts. Whether execution progression should reach unguided work when
belief has collapsed is a policy question about the return path, and this says
it is worth asking for a person who really decayed rather than for one the model
has merely lost track of.

## Two families, one adaptive system

Scales and arpeggios are allocated from one scheduler, and until now no player
could tell them apart: execution ability was per hand, so a run could not say
whether strength in one family was being read as strength in the other. Ability
is now learned per hand and family, and two archetypes are mirror images,
`scale_strong_arpeggio_weak` and `arpeggio_strong_scale_weak`, matched in
everything else. **The player transfers nothing between families**, so any
transfer a run shows belongs to the scheduler.

Three scales and three arpeggios, four sittings of twenty slots, held-out
readings split by family.

| player                     | seed | share weak | held-out weak | held-out strong |
| -------------------------- | ---- | ---------- | ------------- | --------------- |
| scale_strong_arpeggio_weak | 2    | 0.05       | 0.06 -> 0.00  | 0.61 -> 0.83    |
| scale_strong_arpeggio_weak | 4    | 0.45       | 0.06 -> 0.06  | 0.61 -> 0.78    |
| arpeggio_strong_scale_weak | 2    | 0.07       | 0.06 -> 0.06  | 0.78 -> 0.89    |
| arpeggio_strong_scale_weak | 4    | 0.46       | 0.06 -> 0.00  | 0.78 -> 0.94    |

**Allocation goes to the family already going well, and the weak family never
improves.** In both directions and every seed the strong family takes the larger
share and gains, and the weak family's held-out share ends no higher than it
started. Eighty slots of practice leave the learner exactly as bad at the thing
they were bad at.

The mechanism is a tempo that crosses the family boundary.
`transferableTempoFor` takes the median paced tempo over every material
execution context for a hand, and its own comment calls that "the pace this hand
shows on material it owns", which was written when a hand owned only scales.
With two families the median counts arpeggios as evidence about scales.

One run of the arpeggio-weak player, every arpeggio slot, with the arpeggio
frontier at zero throughout:

```text
slot  1  asked 60   transferable  0   frontier 0
slot  2  asked 72   transferable 72   frontier 0
slot  6  asked 84   transferable 84   frontier 0
slot 25  asked 92   transferable 92   frontier 0
slot 40  asked 96   transferable 96   frontier 0
```

The player never completes an arpeggio at any tempo. The pace they are asked for
climbs anyway, one rung behind their scales. So the weak family is reintroduced
faster and faster, fails every time, accumulates no evidence, falls out of the
challenge band, and the allocation drifts to the family that is working. **First
contact is correct**: the first arpeggio is met at the gentle sixty, because no
pace has been established yet. It is the second onward, once the scales are
moving, that inherit a tempo from them.

### Scoping the evidence to the family

The median now runs over the residuals in the target's own family, and falls
back to the configured entry policy when that family has shown nothing. Within a
family it generalizes exactly as before, so several comfortable scales still set
the pace for an unseen scale.

Which family a residual belongs to is recorded on the residual. It cannot be
recovered any other way: a scale's id does not name its family, and the
candidates one slot is choosing between are not where the learner's evidence
lives, so scoping by them silently drops legitimate same-family transfer. Both
wrong answers were tried and both broke existing tests, which is how the
recorded field earned its place. `checkpointSchemaVersion` is 2 and carries
`family_id`; a version 1 checkpoint is refused rather than upgraded, because
inferring provenance that was never stored is worse than rebuilding from the
attempts, which is what an unreadable checkpoint already asks for.

| player                     | seed | weak share   | weak held-out | fastest weak ask |
| -------------------------- | ---- | ------------ | ------------- | ---------------- |
| scale_strong_arpeggio_weak | 2    | 0.05 -> 0.40 | 0.00 -> 0.06  | 84 -> 69         |
| scale_strong_arpeggio_weak | 4    | 0.45 -> 0.71 | 0.06 -> 0.11  | 96 -> 76         |
| arpeggio_strong_scale_weak | 2    | 0.05 -> 0.07 | 0.06 -> 0.06  | 72 -> 60         |
| arpeggio_strong_scale_weak | 4    | 0.46 -> 0.36 | 0.00 -> 0.00  | 96 -> 84         |

Before and after, in each cell.

**The false transfer is gone.** The weak family is met at what it has itself
played, and at seed 2 the scale-weak player's scales are now asked at exactly
the gentle sixty, where they had been climbing to seventy-two behind the
arpeggios.

**The allocation starvation is only partly downstream of it.** The arpeggio-weak
player's share of the weak family rose sharply and its held-out share moved for
the first time. The scale-weak player's did not: one seed barely moved, one went
down, and neither improved. So keeping the weak family in a learnable region is
necessary and not on its own sufficient, and whether anything should favour a
weak family is still open. What is no longer true is that the question is
confounded by a tempo the family never earned.

### The beginner running dry was partly this

`sitting_ran_dry` was recorded as a true beginner meeting a narrow catalog, out
of reach in production. The scale-weak player reproduced it on the whole v1
scale catalog, and across a calendar the second and later sittings admitted
nothing from their opening slot.

Scoping the pace to the family removed that reproduction entirely. The
scale-weak player now trips no structural invariant, in a sitting or across
months, and the characterized exception names the true beginner alone again. A
learner asked repeatedly for work above anything they had managed demonstrates
nothing, and a sitting with nothing demonstrated eventually has nothing left it
can admit. What survives for the true beginner is a narrower question than it
looked, and it is now the only one.

### Where the mirror stops being a mirror

Scoping the pace left one asymmetry standing: the arpeggio-weak player recovers
and the scale-weak player does not. The two archetypes are mirror images, so a
stage census of the same seeds says where the pipeline stops treating them as
one. Counts are traces summed over eighty slots, and the weak family is the one
the player is bad at.

| case                   | evaluated | eligible | in band | admitted | chosen |
| ---------------------- | --------- | -------- | ------- | -------- | ------ |
| weak arpeggios, seed 2 | 47676     | 12740    | 0       | 871      | 32     |
| weak arpeggios, seed 4 | 51948     | 18366    | 0       | 1749     | 57     |
| weak scales, seed 2    | 46080     | 22720    | 0       | 400      | 6      |
| weak scales, seed 4    | 48792     | 25188    | 0       | 1756     | 29     |

**Eligibility is not where they part.** The weak family is fully eligible tens
of thousands of times in every case, and the scale-weak player is eligible more
often than its mirror, not less, while ending with a fifth of the slots.

**The weak family is never in the ordinary challenge band.** Zero, in all four,
against thousands for the strong family. Everything a weak family gets is a
bypass, so admission is where the two stop matching.

The bypass mix says which one. `new_material` is nearly constant across the four
cases, between two hundred and five hundred, because introduction is capped and
the cap does not care how good you are. `execution_progression` is the whole
variable: 648, 1578, 0, and 1236. The one case with none is the scale-weak
player at seed 2, which is also the case that never recovers and takes six of
eighty slots.

So the structure to look at is that **a family with prior evidence has a wide
door and a family without one has only the capped introduction**. That is
rich-get-richer at admission rather than in ranking, and it is family-neutral in
the code: it reads how much has been demonstrated, and a family you cannot play
demonstrates nothing.

One thing that census does not explain, left as the next thread rather than
smoothed over: the weak-arpeggio case at seed 2 shows 648 execution-progression
admissions while no arpeggio context in the final state holds a demonstrated
frontier at either hand motion. Either progression can admit on evidence that is
not a frontier, or a frontier existed and did not survive to the end of the run.
Until that is answered the rule above is a description of three cases out of
four, not a mechanism.

Nothing about allocation changed on the strength of this. What it establishes is
that the remaining skew is an admission-stage question about how a family
without evidence earns its first evidence, not a ranking question about whether
weakness should be favoured.

### What execution progression actually reads

The bypass enum said progression fired and not on what, so `CandidateTrace` now
carries the `ExecutionAdvance` behind it. Censusing the four mirror runs by rule
answers the case the frontier census could not.

| case               | weak family progression admissions |
| ------------------ | ---------------------------------- |
| weak arpeggios, s2 | hands together 648                 |
| weak arpeggios, s4 | span 180, tempo 798, together 600  |
| weak scales, s2    | none                               |
| weak scales, s4    | span 618, tempo 618                |

**The 648 are hands-together admissions, every one.** They read
`coordinationReadyTempoAt`, which is a different record from the demonstrated
frontier and deliberately a lower bar: a hand that produced the right pitches is
ready to put the hands together, and waiting for it to clear the frontier's
motor bar is waiting for the wrong thing. So the earlier census was reading the
wrong variable, and there is no anomaly to explain. A family can have an
adjacent step with no frontier anywhere in it.

That gives progression two footholds rather than one. Tempo and span steps need
a demonstrated frontier; a hands-together step needs only both single hands
ready. The scale-weak player at seed two has neither, which is why it has no
progression admissions at all and takes six slots of eighty.

**The returner's failed attempt back is the same rule.** Slot eighty of that run
is `execution_progression`, hands together, unguided, at eighty-eight, with a
frontier of zero, and it does not start. What follows is recovery walking the
guidance down until it does. So the two open puzzles were one seam, and the
single bypass label had been hiding it.

The seam stated plainly: **a hands-together step is admitted on execution-side
readiness and says nothing about retrieval.** Both failures are that silence. A
returner whose retrieval belief has decayed to nothing, and a weak family that
has never retrieved its material unaided, are both handed work whose motor
precondition is satisfied and whose notes are not there.

So the remaining skew is bootstrap asymmetry rather than an allocation
preference, and the question it raises is not whether ranking should favour
weakness. It is whether an execution-side foothold should carry an exercise
whose retrieval is unevidenced, or whether that step owes a guidance level the
way an introduction does. Nothing changed on the strength of it.

### Separating the two axes

Coordination readiness earns hands together. It says both hands produced the
right pitches and says nothing about whether the notes come unaided. The step
was carrying both: an unguided realization went along with the new execution
shape, and only the shape had evidence behind it. A hands-together progression
step is now admitted only at a guidance rung the material has established, and
tempo and span steps are untouched, since they already move along the axis their
frontier is evidence for.

The rung is the material's rather than this execution shape's. Guidance is about
recalling the notes, and requiring hands-together retrieval before offering
hands-together work would be circular.

What it fixed, and what it cost:

| run                             | before        | after         |
| ------------------------------- | ------------- | ------------- |
| matched returner, seed 8        | 1 false start | none          |
| faster returner, seed 8         | 1 false start | 1 false start |
| weak arpeggios, seed 2 share    | 0.40          | 0.11          |
| weak arpeggios, seed 4 share    | 0.71          | 0.30          |
| weak arpeggios, seed 4 held-out | 0.06 -> 0.11  | 0.06 -> 0.06  |

**The matched returner's first attempt back now starts.** It is a tempo step
rather than the hands-together one that used to be offered unguided at
eighty-eight with a frontier of zero.

**The faster returner still spends one.** Its established rung is a historical
record and does not decay, so a learner who once played this material unguided
still counts as established at that rung however long they have been away. That
is the policy as specified, and the case for ageing establishment alongside
retrieval belief is now a separate question with a reproduction attached.

**The weak family lost share.** Hands-together admissions at full independence
were a large part of its foothold, and refusing them takes those slots away.
Held-out weak performance was already flat in three of the four runs, so most of
what was lost was work the learner could not do; the exception is the one run
where the weak family had been improving, which is now flat. So this bought
answerable work at the price of the weak family's only observed gain, and
whether the cued hands-together candidate deserves to win a slot more often is
the next allocation question rather than a settled one.

### Whether the foothold deserves a slot

Once only the supported rung survives, does the scheduler give it enough
opportunity to matter? Six seeds per player, twelve runs, counting supported
hands-together progression candidates in the weak family at each stage.

| player                     | admitted | selectable | chosen |
| -------------------------- | -------- | ---------- | ------ |
| scale_strong_arpeggio_weak | 1796     | 1736       | 20     |
| arpeggio_strong_scale_weak | 708      | 686        | 13     |

**Narrowing removes almost none of it.** Ninety-seven per cent of what is
admitted is still there when ranking runs, so what happens to the foothold is a
ranking outcome and not an echo, pacing, dose or novelty one. That is the
condition under which a rank preference would be the right instrument.

It is also the condition under which the marginal value question decides
everything, and it answers no.

| weak-family selections | n   | managed | frontier advanced |
| ---------------------- | --- | ------- | ----------------- |
| hands-together step    | 43  | 0.00    | 0.00              |
| everything else        | 247 | 0.08    | 0.09              |

**Forty-three of them across twelve runs, and not one demonstrated execution or
moved a frontier.** The rest of the weak family's work manages roughly one
attempt in twelve. So the foothold survives to ranking, loses there, and
produces nothing on the occasions it wins. Giving it rank would restore the weak
family's activity without restoring its learning, which is the case that
disqualifies the change rather than motivating it.

Hands together is the hardest execution shape a family offers, and a learner
weak in that family is the least likely to manage it. Offering it more often is
not what would help them; what would is unclear, and it is not this.

So no ranking preference was added, and the question is not closed so much as
answered in the negative with the evidence attached. The general form worth
keeping is that an adjacent execution step earns its slot by what it teaches,
and this one, for this learner, teaches nothing yet.

### What a weak family actually learns from

Splitting the weak family's non-hands-together work by shape and guidance, six
seeds per player, twelve runs.

| shape                      | n   | started | managed | frontier advanced |
| -------------------------- | --- | ------- | ------- | ----------------- |
| right, 1 octave, cued      | 9   | 1.00    | 0.33    | 0.33              |
| right, 1 octave, previewed | 31  | 0.81    | 0.13    | 0.13              |
| right, 1 octave, unguided  | 54  | 0.72    | 0.15    | 0.15              |
| left, 1 octave, cued       | 6   | 1.00    | 0.17    | 0.17              |
| left, 1 octave, previewed  | 19  | 0.89    | 0.11    | 0.11              |
| left, 1 octave, unguided   | 40  | 0.72    | 0.05    | 0.05              |
| either hand, 2 octaves     | 87  | 0.76    | 0.01    | 0.01              |
| hands together, any        | 44  | 0.76    | 0.00    | 0.00              |

**One octave and one hand is the whole of it.** Two octaves produces one managed
attempt in eighty-seven, and hands together none in forty-four at any guidance
rung. Everything the weak family has to progress from comes from the narrowest
shape it is offered.

**The most supported rung has the best yield and the smallest supply.** Cued
single-hand work at one octave is fifteen of two hundred and ninety weak-family
selections, five per cent, and manages a quarter of them. Unguided work at the
same shape is six times the supply at half the rate. Cued work tests no
retrieval, so what it builds is the execution frontier rather than the
established rung, which is exactly the evidence tempo and span progression need.

### The beginner is not the same defect

If a weak family is starved of the shape it learns from, a true beginner is the
limiting case and should be starved of it too. It is not.

| player                     | share of slots that are cued, single hand, one octave | managed there |
| -------------------------- | ----------------------------------------------------- | ------------- |
| weak family in mirror runs | 0.05                                                  | 0.27          |
| true beginner              | 0.37                                                  | 0.03          |

The beginner is offered that work constantly and cannot do it: its left hand
manages nothing in ninety-nine attempts at one octave, cued or previewed. Three
of six seeds still run dry.

So the two converge on nothing. The weak family is short of the work that
teaches it; the beginner has that work and is below the floor it asks for.
Whatever the beginner needs is not more of the same shape, which is what
`sitting_ran_dry` has been saying and is now separated from the family question
rather than merged into it.

The bootstrap hypothesis worth testing next is therefore narrow and family
neutral: a learner with no execution frontier in a family gets very little of
the one shape that could give them one, because everything else about them is
strong enough to win the slot. That is an acquisition question about supply
rather than a ranking preference, and nothing has been changed on it.

### Why the productive shape is scarce

Tracing the bootstrap shape while the predicate holds, meaning no execution
frontier exists anywhere in the target family. Six seeds per player.

| player                     | slots | bootstrap needed | eligible | admitted | chosen |
| -------------------------- | ----- | ---------------- | -------- | -------- | ------ |
| scale_strong_arpeggio_weak | 480   | 144              | 5418     | 340      | 8      |
| arpeggio_strong_scale_weak | 480   | 197              | 9456     | 322      | 7      |

**It is not generation, eligibility, narrowing, or ranking.** The shape is
generated constantly and is fully eligible almost every time it is evaluated. It
is admitted for six per cent of that, and three per cent for the scale-weak
player. Admission is the whole bottleneck.

**And admission turns it away for being too hard.** The dominant refusal is the
challenge band, 3134 and 6610 against 750 and 990 for introduction tempo, at a
mean predicted success of **0.465**.

The band is `pMin: 0.60, pMax: 0.90`, and the introduction floor is
`pIntroductionMin: 0.15`.

So the same exercise is admitted at a first exposure and refused at every one
after it, and the gap it falls into is exactly where a learner without a
frontier lives:

```text
0.15  introduction floor      first exposure admitted here
0.465 what the shape predicts  every later exposure refused here
0.60  ordinary floor
```

A learner meets an unfamiliar family, is offered its gentlest work once through
the introduction floor, does not manage it, and thereafter cannot be offered it
again until they can already do it. Nothing in that loop is family-specific, and
nothing in it is a ranking or allocation preference. **It is one number applied
to a learner whose evidence does not yet exist.**

That names which of the three candidate interventions is the live one. Not
relaxing the introduction cap, which is not what refuses this, and not a ranking
weight, which the shape rarely reaches. It is whether the ordinary floor should
apply unchanged while a family has no frontier at all, or whether the forgiving
floor an introduction gets should last until the learner has something to
progress from.

Nothing was changed. The predicate is observable in learner state, the shape has
demonstrated utility, and the intervention is a single threshold, which is
exactly the point at which it is worth deciding deliberately rather than
quickly.

### The relaxed floor works, and collides with the mechanism already there

Built and measured rather than argued about: while a family has no execution
frontier, the narrowest supported shape it offers is held to `pIntroductionMin`
instead of `pMin`. Tied to both conditions, so nothing wider, less supported or
two-handed inherits it, and it ends at the family's first frontier rather than
when the material stops being new.

It does what it claims at the layer it was aimed at.

| run                    | bootstrap shape eligible | admitted before | admitted after |
| ---------------------- | ------------------------ | --------------- | -------------- |
| weak arpeggios, seed 2 | 2910                     | 6%              | 77%            |
| weak scales, seed 2    | 3840                     | 3%              | 80%            |

**And the true beginner stops running dry.** Zero of six seeds, against three of
six. That defect has been pinned as known and unfixed since the sweep found it,
and this is what it was: after a first exposure the gentlest work in the only
family on offer was refused for being too hard, so a sitting eventually had
nothing left it could admit.

**Weak-family outcomes did not move at all.** Selection share, frontier arrival
and held-out managed execution are unchanged to two decimal places. Thousands of
newly admitted candidates reach ranking and one of them is chosen. So admission
was a real bottleneck and not the binding one; ranking is, and unlike the
hands-together foothold this shape is productive when it does win, at better
than a quarter managed. That is now the strongest case in this document for a
ranking change, and it is a different question from the one this section set out
to answer.

**The change was reverted, for a reason worth stating.** It makes four
acquisition-floor tests and three `sitting_ran_dry` tests fail, and not by
breaking them: admission stops exhausting in the scenarios those tests
construct, so the fallback they exercise never fires. The acquisition floor's
entries are single hand, one octave, continuously cued, at the slowest generated
tempo, which is the bootstrap shape exactly. Two mechanisms, one problem: the
floor supplies this work when admission exhausts, and the relaxed floor stops
admission exhausting.

### Which mechanism owns it

The relaxed floor does, and the acquisition floor stays for genuine exhaustion.
They answer different questions. Admission asks whether an exercise is
appropriate enough to compete for a slot; the fallback asks what to supply when
admission produced nothing at all. The bootstrap shape is not emergency work, it
is the ordinary work of a family with no evidence, and routing it through the
fallback means it appears only when everything else collapses. A learner strong
in one family never collapses, which is exactly why the acquisition floor could
protect a true beginner from running dry and do nothing for the same learner's
weak family.

So the pre-frontier floor is ordinary policy, the fallback is unreached in the
cases it used to cover, and the tests for each now construct their own
situation. The acquisition floor's fixtures give the family a frontier
elsewhere, which closes both forgiving paths and leaves admission genuinely
empty, which is what that mechanism is for. The run-dry tests assert the
condition is gone rather than that it reproduces, including for a scoped goal,
which was the stated blocker for shipping goals.

**A fallback preventing a failure is not the same as the fallback being the
right mechanism.** It had been masking an admission boundary that was too strict
for a learner without evidence.

The scoped-goal consequence turned out to be smaller than the note claimed.
`PracticeSession.open` has no refusal to remove: it accepts a scoped goal and
schedules inside its envelope, and the comment saying otherwise was describing
an argument rather than any code. What was missing was coverage, so twelve
combinations of scope and placement now open a session and present an attempt
inside scope: several scales, several arpeggios, a mixed scope and a single
material, each for a beginner, a learner with some experience and an advanced
one.

What this does not settle is the weak family, whose outcomes did not move
because the newly admitted work still loses at ranking. That is the next
question and it is now well posed: a bounded preference for the narrowest
supported shape while a family has no frontier, terminating at the first one,
measured on slots to that frontier, weak-family held-out change, strong-family
held-out change, and how many supported attempts it costs. A learner who
consumes many and produces none has stopped being an allocation problem and
become the beginner's.

### A bounded chance, and what it did not buy

Tried through a selection seam rather than in production, so the real pipeline
decides and only its winner is replaced: while the target family has no
execution frontier, and only until it has one, a slot may be spent on the
single-hand, one-octave, continuously cued work. Four seeds per player, three
bounds.

| bound | slots to first frontier, per seed | bootstrap slots consumed |
| ----- | --------------------------------- | ------------------------ |
| 0     | none, 43, 5, 8 / none, 2, 2, 11   | none                     |
| 3     | 63, 2, 2, 13 / none, 2, 2, none   | 3, 1, 1, 3               |
| 8     | 21, 2, 2, 7 / 17, 2, 2, 7         | 8, 1, 1, 6               |

**It does what it was built to do.** At a bound of eight every seed of both
players reaches a first frontier, where without it two never do in eighty slots.
It is cheap: most seeds spend one slot, and the two that spend the bound reach a
frontier shortly after on ordinary work. Nothing runs away, because the first
frontier ends it.

**No improvement was detected in managed success.** Held-out weak-family
execution moves from 0.06 to 0.04 and 0.06 to 0.01 with the bound, against 0.06
to 0.07 and 0.06 to 0.03 without, which is to say it does not move at all at the
resolution a twenty-four attempt reading has. The strong family gives up a
little, 0.79 to 0.78 and 0.90 to 0.88. There is no case here for shipping it.

These runs do not support shipping this bounded allocation preference. Neither
admitting more acquisition work nor spending up to eight preferential slots on
it improved the measured managed-success rate. That threshold measure does not
rule out smaller gains, other allocation policies, or longer practice budgets.

A run that spends its bounded chances and still has no frontier has exhausted
that experiment's budget. This records an observed outcome, not a diagnosis that
the learner cannot benefit from further practice.

### The instrument was pairing readings it should not have

A review found the held-out set drawing every item from one stream. The player
consumes a different number of draws depending on whether retrieval succeeds and
whether the attempt starts, so an earlier item moved the luck of every item
after it. Changing only a scale's familiarity from zero to one moved the
untouched arpeggio's retrieval from 0.333 to 0.556 and its managed execution
from 0.000 to 0.111.

Two fixes, because isolation alone was not enough. Each exercise and repetition
now draws from its own stream derived from the set's seed, so one item cannot
move another. And an attempt now takes a **fixed budget of draws before anything
branches on them**, so the same exercise meets the same numbers in either state:
without that, a learner who now recalls a scale skips the start draw and shifts
its own motor noise, which defeats the pairing a counterfactual needs.

The regression is the reviewer's case stated at full strength: changing only the
scale leaves every arpeggio outcome identical field by field, not merely close.

What that invalidates is narrow. Anything read from scheduler state, traces,
admissions, selections, frontiers or attempt outcomes stands, which is every
structural finding here: cross-family tempo transfer, the guidance a
hands-together step was carrying, the pre-frontier admission gap, the ownership
split, and the hands-together foothold demonstrating nothing. What needed
rerunning was every conclusion resting on a few percentage points of per-family
held-out movement.

Rerun, the bounded bootstrap chance reads differently and better:

| bound | slots to first frontier                 | bootstrap slots spent | weak held-out          |
| ----- | --------------------------------------- | --------------------- | ---------------------- |
| 0     | 47, none, none, 3 / none, none, none, 6 | none                  | 0.056, 0.000 unchanged |
| 8     | none, 5, 8, 3 / none, 5, 8, 3           | 8, 4, 7, 2            | 0.056, 0.000 unchanged |

**The earlier claim that every seed reached a frontier was an artifact.** One
seed spends all eight chances and still has none. Eight opportunities were
insufficient in that run; this does not establish that more would be
ineffective.

**And the weak family's reading is now identical to three decimals with the
preference and without it**, where the contaminated instrument had shown it
drifting by a few points in both directions. The negative conclusion is limited
to managed success at this battery's resolution. Continuous measurements can
move without crossing its threshold: at seed 3 the scale-weak player's mean
temporal stability was 0.3140 without the preference and 0.3197 with it. That
small difference does not establish a worthwhile policy gain, but unchanged
managed success is not an unchanged learner.

Also corrected while in there: coordination was averaging only the
hands-together attempts that began, so a battery where every one failed to start
reported no coordination question asked at all. `coordinationOverall` counts a
non-start as zero and is the honest top line, `coordination` stays as the
conditional diagnostic, and the attempted and started counts are reported beside
them. Predicted retrieval now averages over the same population observed
retrieval does, excluding cued items from both sides. `beliefGap` is gone: it
subtracted demonstrated execution from a stricter conjunction, so it was never a
calibration gap. `retrievalGap` compares one event with itself, and
`overallPredictionMinusManaged` keeps the old quantity under a name that does
not claim to be calibrated.

The `sitting_ran_dry` exceptions are removed rather than re-explained. Both
players run clean across every configuration those exceptions covered, so the
sweep now fails if the condition returns.

### Arpeggios stop being an experiment

The developer switch is gone and both families are in the production catalog
always. What it was holding back has been answered: generation is family
neutral, entry tempo and transferable pace are family scoped with the family
recorded on the evidence rather than inferred, progression distinguishes span,
tempo and hands-together, and pre-frontier acquisition works the same way in
either family. The family-skew work exposed the composition defects a second
family was liable to expose, and they are fixed.

Keeping the switch now costs more than it buys, because it preserves a
production mode in which single-family assumptions can quietly return. Mixed
families are the default tested configuration instead.

One caveat travels with the graduation rather than blocking it. `rhoFamily` in
the competency transfer parameters is what lets arpeggio competencies borrow
from scale ones while their own evidence is thin, and it is an unvalidated
fixture like the rest of the v1 coefficients. The mirror runs show it working: a
learner strong in one family had the other family's gentlest work predicted at
0.465 when they could not do it at all. The transfer shrinks as direct evidence
arrives, so it is bounded, and it is a calibration target for device data rather
than a reason to keep a whole family behind a flag.

`CandidateTrace` also records the floor a candidate's prediction was held to and
which regime set it, since `in_band` covers ordinary practice, a first exposure
and a family with no evidence, and a census should not have to reconstruct
which.

### What one success withdraws

The relaxed floor ends at the family's first execution frontier. The entry
condition was family-wide because there was no evidence anywhere, and the exit
was made to match it. One paired state, differing in exactly one demonstrated
frontier on one material, one hand and one motion, says what that costs.

| probe                                | predicted | before        | after         |
| ------------------------------------ | --------- | ------------- | ------------- |
| the hand and material that earned it | 0.477     | bootstrap, in | ordinary, out |
| the other hand of the same material  | 0.477     | bootstrap, in | ordinary, out |
| the same hand of another material    | 0.477     | bootstrap, in | ordinary, out |
| neither the hand nor the material    | 0.477     | bootstrap, in | ordinary, out |

**The prediction does not move for any of them.** The model expects exactly what
it expected before, and all four go from offerable to refused, landing back at
0.477 in the gap between the introduction floor and the ordinary one that the
relaxed floor exists to cover.

**Only the context that earned the frontier has anywhere to go.** It has a tempo
step, because a frontier is something to progress from. The other hand of the
same material, the same hand of another material, and the pair that shares
neither have no step of their own and no relaxed floor either, so a single
success on one context removes the acquisition path from three that it says
nothing about.

That is the second of the two outcomes worth distinguishing, and it makes the
exit condition too coarse rather than broad but harmless. The narrow supported
shape is the productive one for these learners, at roughly a quarter managed
against nothing for anything wider or two-handed, so what is withdrawn is the
work that was teaching them.

What it does not settle is the replacement. `family and hand` is the obvious
next scope and would keep the floor for the opposite hand while withdrawing it
from another material in the same hand, which is defensible because execution
evidence is a fact about a hand. Whether that is enough, or whether the scope
should follow the execution shape rather than the hand, is a question this
experiment poses rather than answers. Going straight to per-material would undo
the generalization the bootstrap exists for.

### Three exit scopes, compared

Not production changes: three pipeline variants overriding only when the relaxed
floor ends. Family-wide is what ships. Family and hand keeps it for the opposite
hand. Context keeps it until this material, hand and motion has a frontier of
its own. Four seeds per player, counting bootstrap-shape candidates refused at
the ordinary floor with no execution step of their own.

| exit scope    | refused with nowhere to go | slots to first frontier | held-out weak |
| ------------- | -------------------------- | ----------------------- | ------------- |
| family        | 5320 / 2881                | 47, none, none, 3       | unchanged     |
| family + hand | 2848 / 1250                | 47, none, none, 3       | unchanged     |
| context       | 944 / 600                  | 47, none, none, 3       | unchanged     |

**Narrowing the scope halves the stranding, and then halves it again.** Family
and hand is a real improvement and, as suspected, still leaves a learner's other
material in that hand refused on evidence the model did not gain: the prediction
for it is 0.477 before and after. Context scope leaves only candidates whose own
context has a frontier at some other rung, which is a different situation, since
those have somewhere to go even when this rung does not.

**Everything else is identical.** Same slot of first frontier, same bootstrap
selections, same held-out reading, in every scope. The exit condition has no
observable behavioural consequence in these runs, because the work it strands
loses at ranking whether or not it is admitted.

So the scope cannot be chosen on outcomes here, and should be chosen on
semantics. The formulation the evidence points at is candidate-relative rather
than global: **use the relaxed floor while this candidate's execution context
has no demonstrated basis for ordinary progression.** That makes entry ask what
progression already asks, which is what stops one success stranding work it says
nothing about. What it costs is that a learner meeting a second material in a
practised hand is treated as acquiring rather than progressing, and whether that
is right is a pedagogical question the harness cannot answer.

### The exit follows the candidate now

Landed on the semantic argument rather than a measured gain, because the runs
show no measured gain to have: the work the broad exit stranded loses at ranking
whether or not it is admitted, which means ranking was masking the defect rather
than the defect being harmless.

`needsExecutionBootstrap` reads the same scope execution progression reads, so a
frontier on one material and hand leaves another material in that hand still
acquiring, and the context that demonstrated something is held to the ordinary
floor and has a tempo step to take. Hands together parallel does not speak for
the single hand, since the motion is part of the context.

The rename is part of the change. `needsFamilyBootstrap` described the scope it
used to have, and a name that says family is an invitation to widen it back.

What it withholds is narrow and worth stating: not that nothing transfers, since
borrowed competence still lifts the prediction through the competency model and
a candidate lifted past the ordinary floor never meets this rule. Only that
borrowed competence is not direct evidence that this execution context is ready
for that floor.

The acquisition floor's fixtures moved with it. Genuine exhaustion now means the
candidate's own context has already demonstrated the tempo being offered, so
neither forgiving path applies and the rung it would progress to is a different
one.

That closes the scheduler side of this thread. The chain is complete: productive
acquisition work was under-admitted, admission was fixed, the work was then
under-selected, forcing selection did not improve anybody, the exit from
acquisition was too broad, narrowing it to the candidate's own context removes
the unrelated stranding, and the learners still fail the narrowest supported
shape there is. What is left is not a scheduler question.
