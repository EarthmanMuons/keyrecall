# The progression graph

- **Status:** Current. The authority for what precedes what, and for where each
  edge is enforced.
- **Written:** August 28, 2026

`material-admission.md` answers one question — is this material appropriate yet
— and answers it well. This document is the wider one it sits inside: across
every axis KeyRecall varies, what precedes what, how strong the evidence for
that edge is, and which mechanism enforces it.

The three questions that document separates still hold, with a fourth that this
one makes explicit:

```text
allScales
   |
   +-- goal scope        what is the learner trying to learn?
   |
   +-- REQUIRES          what is appropriate to introduce now?
   |
   +-- prediction        how hard would this be for them today?
   |
   +-- ranking           what should they practice next?
```

The distinction that does the most work here is the one between the third and
the second. **A prerequisite is not the mechanism for "this is harder."**
Difficulty already has a mechanism: every axis below loads a competency, the
prediction channel scores it, and the challenge band admits only what lands
between `pMin` and `pMax`. An edge earns a `REQUIRES` only when attempting it
early is wrong for a reason difficulty does not capture.

## The test an edge has to pass

Three things distinguish a prerequisite from a difficulty:

**The evidence would be uninterpretable.** Hands together before either hand is
established produces an attempt nobody can read: the coordination score is real,
but which hand failed is not recoverable, and the execution evidence is
attributed to two competencies at once.

**The conceptual object changes.** Harmonic minor is not a harder natural minor;
it is a different idea about what minor means. A learner whose idea of a scale
is still unsettled gets a second thing to learn rather than an alteration of a
first.

**Difficulty does not restrain it.** The `information` term actively prefers the
condition nobody has attempted, precisely because nobody has. That is correct
behavior for an active-learning scheduler, and it means an untried axis is
sought out rather than deferred. Where the ordering is genuinely unanimous
across sources, something has to counterbalance that.

An edge that passes none of these is a difficulty. It belongs to prediction, and
adding a gate for it would deny the learner material the model already believes
they can handle.

## The graph

```text
                 goal scope (what is the destination)
                          |
    ┌─────────────────────┴─────────────────────┐
    │                                            │
 MATERIAL                                  CONDITIONS
    │                                            │
 foundation ──► early ──► intermediate ──► adv   1 octave ──► 2 octaves
 C G F a d     D A E Bb   Eb B F# Ab      Db     [REQUIRES]
               e g c      b f f#          c# g#
                                          eb bb  one hand ──► hands together
    │                                            [REQUIRES]
    │  [REQUIRES: execution floor per band]
    │                                            up ──► up and down
 major ──► natural minor ──► harmonic ──► melodic     [prediction only]
           [no gate]        [REQUIRES]   [REQUIRES]
                                                 slower ──► faster
 unseen material ──► cued first encounter             [prediction only]
                    [REQUIRES]
                                                 parallel ─── contrary
                                                 [no edge; ranked preference
                                                  inside the transition]
```

Reading it: solid `REQUIRES` edges are enforced at stage 2a and make the later
side provisionally eligible until the earlier side is established. Everything
else is governed by prediction, and is admitted or held back by whether the
learner is likely to succeed at it today.

One of them is stronger than that. **Provisional means deferred while something
better exists, which is right for an execution condition and wrong for a
curriculum phase.** Two octaves of an appropriate scale is the material a
learner should be on, played a way they have not earned; harmonic minor before
its foundation is not material they should be on at all. So the altered forms
are a barrier to first introduction rather than a ranking disadvantage: a device
sitting introduced harmonic and melodic minor six times before hands-together
work appeared once, every time through the introduction exception, because "not
fully eligible" was never the same claim as "not to be introduced". Recovery of
a form already met is a separate question and is left alone.

## Axis by axis

### Key difficulty tiers

**Edge:** foundation → early transfer → intermediate keyboard → advanced
keyboard.

**Sources:** ABRSM, Faber and Piano Marvel converge on a rough introductory
ordering and disagree on details; several orderings are defensible. Faber groups
by keyboard shape rather than by the circle of fifths.

**Verdict: `REQUIRES`, as a conservative prior.** Enforced by `AdmissionBand`
plus a per-band single-hand execution floor, **discounted by one band when the
exercise is at the gentlest conditions the catalog offers**: one octave, one
hand, at the slow end of ordinary practice.

That discount is the difference between a band and a wall. Difficulty is
compositional, and the floor was reading only half of it: new keyboard geography
is one thing to take on and a harder way of playing is another, and what the
floor protects against is meeting both at once. Without it a beginner had five
scales, and after meeting them the scheduler's next appropriate material was a
two-octave early-transfer key rather than a one-octave one — new geography _and_
a new span, when only the first was the point. With it, D major at one octave in
one hand is where the scales after the foundation come from, and D flat major
stays where it was. This is the one place where a `REQUIRES` is standing in for
something else: the fingering-family axis has no competency, so the band carries
it. See `material-admission.md` for the fourteen hand patterns and what the band
is approximating.

### Major to the minor forms

**Edge:** major and natural minor (no ordering between them) → harmonic minor →
melodic minor, with breadth rather than mastery as the gate.

**Sources:** the curricula give no support for a universal natural → harmonic →
melodic ladder. ABRSM lets candidates choose the form at lower grades and
narrows later; Faber teaches the three forms as one related concept.

**Verdict: `REQUIRES` on the altered forms only.** Natural minor asks for
nothing, because it is where minor topology comes from. Harmonic and melodic
minor pass the _conceptual object_ test, and what they wait on is a curriculum
phase rather than a threshold:

```text
major + natural minor
        ↓
both hands observed separately
        ↓
some hands-together work on ordinary material
        ↓
harmonic minor
        ↓  more ordinary-form breadth
melodic minor
```

Every one of those conditions asks whether a channel has been **observed**, not
where its mean sits. Placement seeds means from what a learner said about
themselves at onboarding, so a mean test lets a self-report stand in for
demonstrated musicianship: choosing "comfortable with scales" once opened
every altered form before a note was played. `LearnerState.isObserved` is the
question policy asks instead.

Breadth is counted **per hand**. Memory is keyed by material and knows a scale
was retrieved without knowing which hand was playing, so the count is joined
with the execution residual for that hand, which is the one part of learner
state keyed by hand as well as material. It is a projection rather than a record
— a scale retrieved by one hand and merely played by the other counts for both —
but it is enough to stop twelve right-hand scales speaking for a left hand that
has played none of them.

The hands-together condition applies to one-hand candidates too, deliberately.
Nothing about harmonic minor mechanically needs two hands; two hands is being
used as the marker of the phase, and a phase a learner has not reached is not
reached for right-hand work either.

Not per-tonic: A harmonic minor is admitted on the strength of A natural minor
and of minor topology generally, and no source supports a per-key form ladder.

**The waiver is an escape from this graph, not part of it.** Somebody who
arrived playing scales should not be marched through a curriculum they know, so
one condition waives the whole foundation:

```text
hands-together coordination observed AND fluent
```

The two halves do different work. Observed, because placement seeds the mean
from the onboarding answer and a mean alone would let a self-report skip the
phase. Fluent, because mere exposure is what the ordinary path asks for, and one
ragged first attempt proves somebody has been in the two-hand regime rather than
that they are past it.

It reads the coordination channel rather than a hand's execution deliberately.
The ordinary path establishes the phase developmentally; the waiver establishes
that a learner is already beyond it, so it asks about the dimension that defines
the phase. One fluent hand is a single channel and not that dimension, and
waiving a phase without observing what defines it would be internally
inconsistent. A scale played hands together well is a scale played with two
hands that each work, which is why the waiver does not also check them
separately — strictly that is evidence rather than proof, since two mediocre
hands can be well synchronized, but a curriculum waiver needs evidence strong
enough that the prerequisites would be artificial, not a proof of every latent
competency.

Anyone reading this graph literally and tempted to remove the waiver should know
it is deliberate. And anyone tempted to justify the phase itself from a syllabus
should not: ABRSM introduces minor scales at Initial Grade, hands separately and
one octave, so no published curriculum makes hands-together a prerequisite of
altered minor forms. The claim here is narrower and about KeyRecall's own
machinery — what evidence justifies **skipping a phase of this progression** —
which is a question a syllabus does not answer.

### One octave to two

**Edge:** one octave → two octaves.

**Sources:** unanimous. No source teaches two octaves before one, and Piano
Marvel treats span as a difficulty axis of its own. This is the strongest single
edge in the graph.

A scale nobody has played is met at the tempo that learner's playing hand has
shown on scales they own, taken as a median rather than a maximum, and capped to
the slow end of ordinary practice when the key's geography is new: a new shape
and a new speed at once is the compounding this graph avoids everywhere else.
Somebody who has shown nothing meets their first scale unhurried.

That is a decision now rather than an accident. An introduction used to be
offered at every tempo generation listed, and nothing in the ranking key reads
tempo, so which one a learner met was settled by the order of a constant. Sixty
always won and it looked like policy.

Once a scale is owned, going wider is one step of **execution progression**
rather than a prerequisite question at all. The three axes each have an
adjacency relation, exactly one may move per candidate, and material must have
been retrieved rather than merely shown: playing a scale well while looking at
it demonstrates the conditions and not the scale.

**Verdict: `REQUIRES`.** It is the _difficulty does not restrain it_ case, and
the evidence is direct. Before the gate existed, a synthetic beginner reached
two octaves of F major unguided on their eighth attempt, having played one
octave of it only in the other hand; a profile with weak execution across the
board was at two octaves on its second attempt and unguided at two by its fifth.
The information term was reaching for `MULTI_OCTAVE_CONTINUATION` because its
uncertainty was maximal, which is exactly what it is built to do.

The floor is generic single-hand execution on the hand playing, at a value
halfway between where placement puts a self-reported beginner and someone with
some experience. Generic rather than per-material for the reason the bands are
not a per-key ladder. Read off execution rather than off multi-octave
continuation itself, which would be self-referential in the way natural minor
already taught.

One property worth stating: like the bands, this reads the model's belief, which
is seeded at placement from what the learner says about themselves. A learner
who reports some experience clears the floor from their first attempt whatever
their playing later shows, and the estimate moves as evidence arrives. That is
the same trade every rule here makes, and it is the right one: the alternative
is an artificial beginner's path through material somebody already has.

### Separate hands to hands together

**Edge:** both hands individually → hands together.

**Sources:** universal in method books, and structurally obvious.

**Verdict: `REQUIRES`.** The _uninterpretable evidence_ case, and the clearest
one. Both hands must have shown coordination readiness on this material at this
span before hands-together work is fully eligible.

This was a floor on the two hand-execution means, which made playing together a
reward for general fluency rather than an early coordination skill; see
`handsTogetherPrerequisiteSatisfied`. What the edge asks about now is the work
in front of the learner rather than their hands in general, and about the notes
rather than the polish. Whether the gate should also be reachable through an
admission exception is a separate question, specified in
[`../design/coordination-transition-policy.md`](../design/coordination-transition-policy.md).

### Hand motion

**Edge:** none proposed, in either direction.

**Sources:** pedagogy prefers contrary motion for a learner's first
hands-together scale, and ABRSM puts contrary-motion C major a grade before any
similar-motion hands-together scale. See
[`../design/coordination-transition-policy.md`](../design/coordination-transition-policy.md).

**Verdict: no `REQUIRES`, and specifically not a second coordination
transition.** `HandMotion` is a realization condition like span or tempo, not a
new skill state. The coordination transition stays **once per material**: the
event it marks is a learner moving from never having coordinated this scale to
having coordinated it, and meeting the other hand motion afterwards is ordinary
execution progression on a skill that exists. It is spent by execution evidence
rather than by presentation, so an attempt the learner never started leaves it
owed.

The preference belongs in ranking rather than in a gate, and only while the
single transition is unspent, so that the one slot it costs is spent on the
easier realization. It is a claim about which of two otherwise tied candidates
is the better introduction, not a claim that contrary motion is generally
easier: prediction scores the two identically, because nothing measured supports
a quantitative difference between them. Without the term the choice still gets
made, by the order `HandMotion.values` happens to list.

Parallel and contrary hands-together work progress independently:
`ExecutionContext` is `(materialId, hands, handMotion)`, so a frontier reached
in one motion does not certify execution the learner has never demonstrated in
the other. The coordination transition remains shared because it represents
having begun coordinating that scale at all, not mastery of either realization.

### Direction and the reversal

**Edge:** ascending → ascending and descending.

**Sources:** against it. ABRSM asks for scales ascending _and_ descending from
the first grade, and method books add the descent within the first encounters
rather than deferring it. The reversal is a real motor event —
`DIRECTION_REVERSAL` exists and is measured — but nobody teaches the ascent
alone for long.

**Verdict: no `REQUIRES`, deliberately.** It fails all three tests: the evidence
is perfectly interpretable, no conceptual object changes, and the sources do not
defer it, so there is nothing for a gate to protect. Difficulty is carried by
`directionReversal` in the motor channel and admitted or refused by the
challenge band, which is the correct mechanism.

This is worth recording as a decision rather than an omission. A beginner in
simulation takes up-and-down traversals in roughly two thirds of their early
attempts, driven by the same information term that drove the octave problem.
That looked like the same bug and is not one: two octaves before one contradicts
every source, and descending early contradicts none.

### Tempo

**Edge:** slower → faster.

**Verdict: no `REQUIRES`.** Tempo has a dedicated mechanism already — the tempo
probe, which offers a faster variant when an attempt was clearly too easy, at
the speed the learner actually played. Nothing here should also gate it.

### Guidance rungs

**Edge:** material supplied → previewed → unguided, and separately, material
KeyRecall has never seen → its first encounter is cued.

**Verdict: `REQUIRES` on the second only.** The rungs themselves are the probe
machinery's business, not eligibility's. `unseenMaterialRequiresCue` is a
different claim: not that the learner cannot play the scale, but that nothing
here has ever established that they can, so an unguided first attempt would be
testing a memory this app has never seen formed.

## Goal overlays

A goal is a destination. It narrows the universe of material under
consideration; it does not make everything in that universe admissible at once,
and it does not stop the scheduler using easier related material that prepares
for it. `PracticeGoal` holds the seam with one value today, general fluency over
the whole catalog.

Two constraints on any syllabus overlay, and the first is the one that will be
tempting to break.

**A grade is not a band.** Grades bundle key, hands, octave span, articulation,
tempo and examination logistics into one label. KeyRecall models hands, octaves,
direction, hand motion and tempo as execution conditions precisely so they can
vary independently, and importing grade boundaries as admission tiers would
re-bundle exactly what the architecture pulled apart. A syllabus overlay narrows
**material**, and the conditions stay where they are.

**The scope is the destination, not the route.** Selecting a grade should not
withdraw the foundation material that prepares for it. `PracticeGoal.scopeOf`
narrows the catalog; the `REQUIRES` gate still decides what within that scope is
appropriate now, and support material outside the scope has to stay reachable.
The shape to grow into, recorded on `PracticeGoal`, is a target domain, target
execution conditions and a target proficiency, with support material
distinguished from target material.

**Not yet populated.** Encoding a named syllabus means reproducing a published
requirement list exactly, and a list reconstructed from memory would be a
fabricated authority wearing a real name — worse than no overlay, because
nothing downstream could tell the difference. The seam is in place and the
design above is settled; the data needs the actual current syllabus in front of
whoever adds it.

## What this does not settle

The fingering-family axis still has no competency, so the bands approximate it,
and every band-derived floor is a prior rather than a measurement. That gap is
`material-admission.md`'s subject and its closing argument still stands: if
learners stall specifically where a band introduces a new hand pattern, that is
the evidence for promoting a motor-family dimension into the ontology.

The floors and breadth counts here are first guesses to revise against real
sittings. Every rejection is provisional, so a bad guess outranks material
rather than forbidding it, and every rejection carries an `EligibilityReason` so
stalls can be grouped and the guesses can be argued with from data.
