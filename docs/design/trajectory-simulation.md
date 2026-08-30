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
| Device playing           | do the abstractions resemble real playing?            | ecological validation |

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

The measurement is being repeated against fully eligible candidates for the
_same_ material, with readiness read from the scheduler's own prerequisite
verdict rather than reconstructed from outcomes, and with impossible orderings
failing loudly instead of clamping to a plausible zero.

What survives the retraction is what was measured directly from selections: a
player with a strong right hand and a weak left played hands together in one run
out of forty, and a true beginner got both hands through the same material in
three runs out of forty, so its stall trips were never about hands together at
all.

The lesson worth keeping is about the detectors rather than the scheduler. Two
of the first definitions were wrong in the same way: `exclusive_target_emptied`
fired on every recovery slot, because recovery is _meant_ to narrow a slot to
one candidate, and `progression_stall` counted a run of introductions as a
frontier that would not move. Both encoded "what the scheduler currently does"
as a property. The census made both obvious on one read, which is the argument
for the census.
