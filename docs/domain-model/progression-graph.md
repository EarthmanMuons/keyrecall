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
behaviour for an active-learning scheduler, and it means an untried axis is
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
```

Reading it: solid `REQUIRES` edges are enforced at stage 2a and make the later
side provisionally eligible until the earlier side is established. Everything
else is governed by prediction, and is admitted or held back by whether the
learner is likely to succeed at it today.

## Axis by axis

### Key difficulty tiers

**Edge:** foundation → early transfer → intermediate keyboard → advanced
keyboard.

**Sources:** ABRSM, Faber and Piano Marvel converge on a rough introductory
ordering and disagree on details; several orderings are defensible. Faber groups
by keyboard shape rather than by the circle of fifths.

**Verdict: `REQUIRES`, as a conservative prior.** Enforced by `AdmissionBand`
plus a per-band single-hand execution floor. This is the one place where a
`REQUIRES` is standing in for something else: the fingering-family axis has no
competency, so the band carries it. See `material-admission.md` for the fourteen
hand patterns and what the band is approximating.

### Major to the minor forms

**Edge:** major and natural minor (no ordering between them) → harmonic minor →
melodic minor, with breadth rather than mastery as the gate.

**Sources:** the curricula give no support for a universal natural → harmonic →
melodic ladder. ABRSM lets candidates choose the form at lower grades and
narrows later; Faber teaches the three forms as one related concept.

**Verdict: `REQUIRES` on the altered forms only.** Natural minor asks for
nothing, because it is where minor topology comes from. Harmonic and melodic
minor pass the _conceptual object_ test: they change what minor means, so they
wait on a breadth of ordinary scales retrieved across more than one band, and on
some familiarity with another minor topology. Not per-tonic: A harmonic minor is
admitted on the strength of A natural minor and of minor topology generally, and
no source supports a per-key form ladder.

### One octave to two

**Edge:** one octave → two octaves.

**Sources:** unanimous. No source teaches two octaves before one, and Piano
Marvel treats span as a difficulty axis of its own. This is the strongest single
edge in the graph.

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
one. Both hands' execution means must clear a threshold before hands-together
work is fully eligible.

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
direction and tempo as execution conditions precisely so they can vary
independently, and importing grade boundaries as admission tiers would re-bundle
exactly what the architecture pulled apart. A syllabus overlay narrows
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
