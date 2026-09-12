# Trajectory simulation

Device sittings found real defects, and they were finding them slowly. A person
at a piano covers one point in the space of players: one natural tempo, one pair
of hands, one level of familiarity, one honest answer at placement. Several
defects were interactions between locally reasonable rules, visible only in a
trajectory rather than in a decision, and the person best placed to notice them
is the one least able to enumerate the states that produce them.

The existing synthetic profiles could not close that gap. They sampled an
outcome from a hidden ability, and their achieved tempo was a quality score in
`[0,1]`, so **no learner they could express played faster than they were asked
to**. Every tempo defect the device found lived in exactly that gap, which is
why simulation had been silent about all of them.

## Four kinds of testing, kept apart

|                          | Asks                                                  | When                  |
| ------------------------ | ----------------------------------------------------- | --------------------- |
| Sweep (`bin/sweep.dart`) | Does anything go wrong across many players and seeds? | Deliberately, minutes |
| Invariant tests          | Do the structural properties still hold?              | Every commit, seconds |
| Paired experiments       | Does a policy change trajectories for the better?     | While designing one   |
| Device playing           | Do the abstractions resemble real playing?            | Ecological validation |

Device sittings stop being a coverage mechanism and become the check on whether
the model's assumptions correspond to what a person at a keyboard actually
experiences, which is the one thing simulation cannot answer.

## The player plays, rather than scoring

`SyntheticPlayer` receives an exercise and answers **what happened**. Requested
and performed tempo are separate quantities throughout, related by
`tempoCompliance`: one is a metronome follower, zero is somebody who plays at
their own pace whatever the screen says, and between them the performed tempo is
a geometric blend, so being asked for twice your natural pace and half of it are
equally far off.

The knobs are meant to be **legible rather than orthogonal**: natural tempo per
hand, compliance, per-hand ability, hands-together ability as its own skill,
span penalty, familiarity, noise, learning rate. An archetype is a named
configuration of that one model, never its own implementation, so a defect is
reportable as "this kind of person" and two archetypes that fail the same way
are visibly one failure.

Determinism is total: archetype plus seed plus length reproduces a trajectory
exactly, so a pathological seed is a fixture rather than an anecdote.

## Invariants and observations are different severities

An **invariant** is a property any healthy scheduler should hold, stated without
a tuned number. `realization_stall` fires when a surpassed realization was
chosen while an equally eligible advancing one of the same material and hand was
admissible: both reached ranking, and one asks for something the learner has
demonstrably outgrown. No threshold makes that the right choice. These are
asserted.

An **observation** is a count against a threshold picked by judgment. "Twelve of
fifty slots below the frontier" is suspicious, and nobody knows whether the
right bound is two or fifteen. These are reported and read by a person.

Asserting an observation would freeze today's behavior as the definition of
healthy practice, and give the simulation a second specification whose arbitrary
numbers are as hard to reason about as the scheduler's.

## What a slot can and cannot answer

**A slot's `alternatives` are post-admission and post-guard evidence, and cannot
say what was refused.** Every candidate in them already cleared eligibility,
admission, and the repetition guard, so a diagnostic counting refusals over
`alternatives` measures only the survivors and reports the admission stage as
near-total success by construction.

Anything asking which stage refused a candidate reads the traces as they go
past, through `runTrajectory`'s `observeTraces` callback.

**An absent rank key means ranking was not reached, not that data is missing.**
A trace answers the qualification stages for every candidate, because "why not
that one?" has to be answerable. It does not answer ranking for a candidate that
never competed: a key it could not have competed on would be a number presented
as though it meant something. Most candidates are in that position, which is
also what stops a slot computing ranking terms for the ninety-five percent that
cannot consume them.

So: **a property of a candidate is asked of the candidate, and only what the
scheduler decided is read off the trace.**

## What the first sweep found

Eight archetypes, a hundred seeds each, fifty slots: forty thousand decisions.

`realization_stall` fired **zero times**, which is the strongest available
evidence that splitting `RankKey` into a material question and a realization
question fixed the generation-order pathology rather than making one device
trajectory look better. `below_frontier_share` and `guidance_regression` were
silent throughout.

`entry_tempo_ignores_pace` fired about five thousand times, across every
archetype past a beginner and none below. The band cap in `entryTempoFor` was
discarding the transferable pace. **Beginners never reach the capped bands,
which is why a person testing at a piano as a beginner could not have found
it.**

### The detector that was confidently inverted

`hands_together_stall` needed decomposing rather than believing, and the first
decomposition was itself wrong. It measured slots from both hands completing a
material to the first slot where _any_ hands-together candidate survived
admission. But the catalog is wide, most of it is provisionally eligible on that
prerequisite, and provisional candidates still survive admission and rank last,
so the clock started at slot zero in nearly every run, on a material unrelated
to the one whose hands were ready. It reported instant availability and
concluded the delay was all ranking. Neither half was established.

Repeated against fully eligible candidates for the **same** material, with
readiness read from the scheduler's own prerequisite verdict rather than
reconstructed from outcomes, and with impossible orderings counted rather than
clamped to a plausible zero, it separates into two different defects:

- **Hands close in ability.** Offer latency is zero at median and p90.
  Coordination work is then chosen in 15 to 25 runs of 40, a median of 20 to 25
  slots later. Available immediately, unchosen for a third of a sitting, often
  never. That is a ranking question.
- **One weak hand.** The prerequisite is satisfied in 2 runs of 40, and for a
  true beginner in none. The frontier advances only on an attempt at or above
  `demonstratedMotorScore`, a weak hand rarely clears that, so its frontier
  stays empty and hands-together never qualifies. That is an admission question.

The first instrument reported this archetype as offered in every run and chosen
in one, **the exact opposite of what was happening**. Being roughly right for
five archetypes while inverted on the two that motivated the investigation is
the worst available way to be wrong, and only a clock sourced from the
prerequisite stage on the same material could tell them apart.

### The lesson is about detectors, not the scheduler

Two other early definitions were wrong the same way. `exclusive_target_emptied`
fired on every recovery slot, because recovery is _meant_ to narrow a slot to
one candidate. `progression_stall` counted a run of introductions as a frontier
that would not move.

Both encoded "what the scheduler currently does" as a property. The census made
both obvious on one read, which is the argument for running a census before
trusting a detector.

## Reacquisition, in the strict sense, does not happen

The census partitions every slot that moved nothing into work with no frontier
yet, work below a demonstrated frontier, and work at or past one that failed to
move it. Across every archetype and schedule, **the middle category is zero**.

A demonstrated frontier is a maximum and does not decay, so decay never produces
work below one. What a break actually produces is retrieval support on material
the learner still owns, and consolidation at a frontier they cannot yet pass.
The reacquisition burden a weak learner appeared to carry was **acquisition all
along**, on material they had seen but never demonstrated anything on.

Whether a frontier _should_ decay is a product question this does not answer. It
does say that nothing in the current model expresses losing ground, and that a
detector counting known material as reacquisition will report every weak learner
as one who keeps losing it.

Separately: the tempo probe reads as a mechanism that opens and is not answered.
The advanced player opens seven to ten probes across four seeds of `interrupted`
and answers none, stranding one or two at a sitting boundary. Too few openings
for a per-run threshold to trip on, which is worth remembering: **a mechanism
that fires rarely needs the census rather than a per-run threshold.**

## What a gap does to belief, and what it does to a person

The forgetful returner exists to separate two things a long-gap run used to
confound. Before it, learner state decayed across a calendar and the synthetic
person did not, so every such run established how the scheduler reacts to its
own aging belief and nothing about whether that reaction suits somebody who
really decayed.

Three people, one schedule, four sittings then a gap, measured on the held-out
set on arrival. The stable player forgets nothing; the matched returner loses
execution on a 45-day half-life and the notes on a 20-day one; the faster
returner loses them on 12 and 6.

| Gap (days) | Model expects | Stable | Matched | Faster |
| ---------: | ------------: | -----: | ------: | -----: |
|          1 |         0.844 |  1.000 |   1.000 |  1.000 |
|          2 |         0.712 |  1.000 |   1.000 |  0.958 |
|          7 |         0.313 |  1.000 |   0.958 |  0.833 |
|         14 |         0.106 |  1.000 |   0.833 |  0.625 |
|         30 |         0.011 |  1.000 |   0.792 |  0.625 |
|         60 |         0.000 |  1.000 |   0.625 |  0.625 |
|        120 |         0.000 |  1.000 |   0.625 |  0.625 |
|        240 |         0.000 |  1.000 |   0.625 |  0.625 |

**The model's retrieval decays on a half-life near four days and reaches exactly
zero by sixty**, faster than any of the three, including the one built to forget
quickly. At a fortnight it expects 0.106 of a player who delivers 0.625 at worst
and 1.000 at best.

So the failure a returner meets is not a scheduler asking for April's work. It
is one **expecting nothing of somebody who can still play.**

What that costs in the return sitting: the first thing offered is unguided work
the model predicts at 0.00, admitted by an execution-progression bypass. It does
not start. Recovery then walks guidance down and the attempt at continuous
cueing succeeds. The ladder works, and the returner pays one failed attempt to
teach it something the model could have been less certain about.

**Two limits on how far this bounds the model.** The synthetic decay runs toward
the ability and familiarity the player started with, so none of the three can
express somebody who has genuinely forgotten a scale they once owned: the
comparison bounds the model from one side only. And this is the model at the
evidence level eighty practice slots over four materials produce, not the one a
learner of several years would carry.

**The next question is retention calibration, and the place to answer it is
device data from repeat users with real gaps, compared against what the model
predicted before they came back.** Tuning the curve to these half-lives would
replace one assumed shape with another.

## Arpeggios stop being an experiment

The developer switch is gone and both families are in the production catalog
always. What it held back has been answered: generation is family neutral; entry
tempo and transferable pace are family scoped with the family recorded on the
evidence rather than inferred; progression distinguishes span, tempo, and
hands-together; and pre-frontier acquisition works the same way in either
family. The family-skew work exposed the composition defects a second family was
liable to expose, and they are fixed.

Keeping the switch would cost more than it buys, because it preserves a
production mode in which single-family assumptions can quietly return. Mixed
families are the default tested configuration instead.

**One caveat travels with the graduation.** `rhoFamily` lets arpeggio
competencies borrow from scale ones while their own evidence is thin, and it is
an unvalidated fixture like the rest of the coefficients. The mirror runs show
it working: a learner strong in one family had the other family's gentlest work
predicted at 0.465 when they could not do it at all. The transfer shrinks as
direct evidence arrives, so it is bounded, and it is a calibration target for
device data rather than a reason to keep a family behind a flag.

## Where the relaxed floor should end

The relaxed entry floor ends at a family's first execution frontier. The entry
condition was family-wide because there was no evidence anywhere, and the exit
was made to match it. Three pipeline variants, overriding only when the floor
ends, four seeds per player:

| Exit scope    | Refused with nowhere to go | Slots to first frontier | Held-out weak |
| ------------- | -------------------------- | ----------------------- | ------------- |
| Family        | 5320 / 2881                | 47, none, none, 3       | unchanged     |
| Family + hand | 2848 / 1250                | 47, none, none, 3       | unchanged     |
| Context       | 944 / 600                  | 47, none, none, 3       | unchanged     |

**Narrowing the scope halves the stranding, and then halves it again.**
Family-and-hand is a real improvement and still leaves a learner's other
material in that hand refused on evidence the model did not gain: the prediction
for it is 0.477 before and after.

**But everything else is identical.** Same slot of first frontier, same
bootstrap selections, same held-out reading, in every scope. The exit condition
has no observable behavioral consequence in these runs, because the work it
strands loses at ranking whether or not it is admitted.

So the scope could not be chosen on outcomes and was chosen on semantics:

> Use the relaxed floor while **this candidate's** execution context has no
> demonstrated basis for ordinary progression.

That makes entry ask what progression already asks, which is what stops one
success stranding work it says nothing about. What it costs is that a learner
meeting a second material in a practiced hand is treated as acquiring rather
than progressing, and whether that is right is a pedagogical question the
harness cannot answer.

Recorded because the reasoning is the whole justification: **this change landed
on a semantic argument with no measured gain available to support it**, and that
should be visible to anyone who revisits it.
