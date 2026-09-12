# Curriculum and progression

What precedes what, when new material may be introduced, and how a second
material family enters without a scheduler branch.

## The test an edge has to pass

**Decision.** An axis gets a `REQUIRES` prerequisite edge only if it passes at
least one of three tests. Otherwise it is a _difficulty_, belongs to prediction,
and gets no gate.

**Why.** Three things distinguish a prerequisite from a difficulty:

1. **The evidence would be uninterpretable.** Hands together before either hand
   is established produces an attempt nobody can read: the coordination score is
   real, but which hand failed is not recoverable, and execution evidence is
   attributed to two competencies at once.
2. **The conceptual object changes.** Harmonic minor is not a harder natural
   minor; it is a different idea about what minor means. A learner whose idea of
   a scale is still unsettled gets a second thing to learn rather than an
   alteration of a first.
3. **Difficulty does not restrain it.** The information term actively _prefers_
   the condition nobody has attempted, precisely because nobody has. That is
   correct behavior for an active-learning scheduler, and it means an untried
   axis is sought out rather than deferred. Where the ordering is unanimous
   across sources, something has to counterbalance that.

**Consequences.** An edge that passes none of these and gets a gate anyway
denies the learner material the model already believes they can handle. The test
is what keeps the graph small.

## The graph

```text
                 goal scope (what is the destination)
                          |
    +---------------------+---------------------+
    |                                           |
 MATERIAL                                  CONDITIONS
    |                                           |
 foundation -> early -> intermediate -> adv   1 octave -> 2 octaves
 C G F a d    D A E Bb  Eb B F# Ab      Db    [REQUIRES]
              e g c     b f f#          c# g#
                                        eb bb  one hand -> hands together
    |                                          [REQUIRES]
    |  [REQUIRES: execution floor per band]
    |                                          up -> up and down
 major -> natural minor -> harmonic -> melodic   [prediction only]
          [no gate]       [REQUIRES]  [REQUIRES]
                                               slower -> faster
 unseen material -> cued first encounter         [prediction only]
                   [REQUIRES]
                                               parallel --- contrary
                                               [no edge; ranked preference
                                                inside the transition]
```

Solid `REQUIRES` edges are enforced at the eligibility stage and make the later
side provisionally eligible until the earlier side is established. Everything
else is governed by prediction.

One qualification matters. **Provisional means deferred while something better
exists, which is right for an execution condition and wrong for a curriculum
phase.** Two octaves of an appropriate scale is material the learner should be
on, played a way they have not earned; harmonic minor before its foundation is
not material they should be on at all. So the altered forms are a barrier to
first _introduction_ rather than a ranking disadvantage. A device sitting
introduced harmonic and melodic minor six times before hands-together work
appeared once, every time through the introduction exception, because "not fully
eligible" was never the same claim as "not to be introduced".

## Key difficulty bands

**Decision.** `REQUIRES`, as a conservative prior: foundation, early transfer,
intermediate keyboard, advanced keyboard, enforced by `AdmissionBand` plus a
per-band single-hand execution floor, **discounted by one band at the gentlest
conditions the catalog offers** (one octave, one hand, slow).

**Why.** The discount is the difference between a band and a wall. Difficulty is
compositional, and the floor was reading only half of it: new keyboard geography
is one thing to take on and a harder way of playing is another, and what the
floor protects against is meeting both at once.

**Evidence.** ABRSM, Faber, and Piano Marvel converge on a rough introductory
ordering and disagree on the details; several orderings are defensible, and
Faber groups by keyboard shape rather than by the circle of fifths. So the bands
are a defensible prior, not a discovered truth. Without the discount, a beginner
had five scales, and the next appropriate material after them was a _two-octave_
early-transfer key rather than a one-octave one: new geography and a new span,
when only the first was the point.

**Consequences.** This is the one place a `REQUIRES` stands in for something
else. The fingering-family axis has no competency, so the band carries it. If
fingering family ever earns state, this prior should shrink rather than being
kept alongside it.

## The minor forms

**Decision.** Major and natural minor are unordered with respect to each other.
Harmonic minor and then melodic minor each require breadth, not mastery: a
breadth of major and natural-minor material actually retrieved, spread over more
than one band, per hand. The wait is lifted for a learner already fluent in the
hand the exercise asks for.

**Why.** The _conceptual object changes_ test. Meeting a new idea of what minor
means while ordinary scales are still unsettled enlarges the vocabulary faster
than the base under it.

**Evidence.** The curricula give **no** support for a universal natural →
harmonic → melodic ladder; ABRSM lets candidates choose the form at lower
grades. So the gate is justified by the vocabulary argument, not by curriculum
convention, and it is deliberately breadth rather than a mastery threshold.

**Consequences.** Per hand, by the same reading the bands use: a fluent right
hand is not evidence about the left. The rule exists so a beginner's vocabulary
does not outrun their base, not to make an experienced player re-earn what they
arrived with, which is why fluency lifts it.

## One octave to two

**Decision.** `REQUIRES`, gated on generic single-hand execution for the hand
playing, at a value halfway between a self-reported beginner and someone with
some experience.

**Why.** The _difficulty does not restrain it_ case, and the evidence is direct.

**Evidence.** Unanimous in the sources: no source teaches two octaves before
one, and this is the strongest single edge in the graph. Before the gate
existed, a synthetic beginner reached two octaves of F major unguided on their
eighth attempt, having played one octave of it only in the other hand. A profile
with weak execution across the board was at two octaves on its second attempt
and unguided at two by its fifth. The information term was reaching for
`MULTI_OCTAVE_CONTINUATION` because its uncertainty was maximal, which is
exactly what it is built to do.

**Consequences.** The floor is generic rather than per-material, for the same
reason the bands are not a per-key ladder, and is read off execution rather than
off multi-octave continuation itself, which would be self-referential.

Like the bands, it reads the model's belief, which is seeded at placement from
self-report. A learner who reports some experience clears the floor from their
first attempt whatever their playing later shows. That is the trade every rule
here makes, and it is the right one: the alternative is an artificial beginner's
path through material somebody already has.

### Entry tempo

**Decision.** A scale nobody has played is met at the tempo that learner's
playing hand has shown on scales they own, as a **median rather than a
maximum**, capped to the slow end of ordinary practice when the key's geography
is new.

**Why.** A new shape and a new speed at once is the compounding this graph
avoids everywhere else. Somebody who has shown nothing meets their first scale
unhurried.

**Evidence.** This was previously an accident rather than a decision. An
introduction was offered at every tempo generation listed, nothing in the
ranking key read tempo, so 60 always won and it looked like policy.

## Separate hands to hands together

**Decision.** `REQUIRES`. Both hands must have shown **coordination readiness**
on this material at this span before hands-together work is fully eligible.

**Why.** The _uninterpretable evidence_ case, and the clearest one.

**Evidence.** Universal in method books, and structurally obvious.

**Consequences.** This replaced a floor on the two hand-execution means, which
made playing together a reward for general fluency rather than an early
coordination skill. The edge now asks about the work in front of the learner
rather than their hands in general, and about the notes rather than the polish.

### The coordination transition

> **Status:** proposed. The admission policy is not built. Contrary-motion
> realization, generation, and the transition ranking terms are current
> production behavior.

**Decision.** Hands-together work should become admissible on viable components
rather than on polished ones, and the first such slot should be spent on
contrary motion.

**Why.** The trajectory audit closed three apparent scheduler defects by showing
they were policy rather than mechanism. The hands-together result was that
neither the `developing` nor the `uneven_hands` archetype ever reached a fully
eligible hands-together contest _at all_, so nothing was losing a ranking it
entered. What blocked them was admission, which is a pedagogical choice the
project had never made deliberately.

**Evidence.** Unimanual training does prepare bimanual skill, and the transfer
is real but partial [HayashiNozaki2016, Yokoi2016]. Asymmetry between the hands
is expected in piano practice rather than a defect to correct first [Pang2023].
Mirrored, homologous movement is easier to coordinate than non-homologous
[Franz2001], and common pedagogy introduces hands together through contrary
motion for exactly that reason. Cued pitch integrity is admissible evidence only
for a supplied attempt; familiarity is material-specific rather than general.

Contrary motion won **none of 710 measured transition slots** before the ranking
term existed, purely because `HandMotion.values` lists parallel first.

**Consequences.** This is a narrow exception for one transition, not a
relaxation of general execution progression. The second would be a much larger
change and is not what the evidence supports. The ranking terms must sit above
retention and information or they are inert, and must sit below the eligibility
tier or they could pull a provisional candidate past a full one.

## Direction, hand motion, and tempo get no gate

**Decision.** No `REQUIRES` on ascending → up-and-down, none between parallel
and contrary motion, none on tempo.

**Why and evidence.** Direction fails all three tests: the evidence is perfectly
interpretable, no conceptual object changes, and the sources are actively
_against_ deferring it. ABRSM asks for scales ascending and descending from the
first grade. The reversal is a real motor event, `DIRECTION_REVERSAL` exists and
is measured, but nobody teaches the ascent alone for long.

Tempo already has a dedicated mechanism in the tempo probe, which offers a
faster variant when an attempt was clearly too easy, at the speed the learner
actually played. Nothing should also gate it.

**Consequences.** Worth recording as a decision rather than an omission. A
simulated beginner takes up-and-down traversals in roughly two thirds of their
early attempts, driven by the same information term that drove the octave
problem. That looks like the same bug and is not one: two octaves before one
contradicts every source, and descending early contradicts none.

## An unseen material's first encounter is cued

**Decision.** `REQUIRES`: material with no history in this profile may be
introduced, but not tested from memory the first time it appears.

**Why.** Not a claim that the learner cannot play the scale. It is that nothing
here has ever established that they can, so an unguided first attempt would be
testing a memory this app has never seen formed.

**Consequences.** A statement about what has been established in this profile,
which is why it reads factual observation history rather than the model's belief
about that history.

## Grades are not admission bands

**Decision.** Examination curricula supply the _shape_ of progression, never a
threshold.

**Why.** A grade bundles many things: repertoire, aural tests, sight reading,
and technical work, assessed together at a moment. Reading a grade boundary as a
learner-model gate would import all of that into a decision about one scale.

**Evidence.** Three independent syllabi [ABRSM2025, RCM2022, Trinity2026] agree
on rough ordering and disagree on details. Where they agree, the agreement is
informative about sequence; where they disagree, no gate is defensible.

**Consequences.** Curriculum evidence gives progression landmarks and the
per-material shape of a distinction. It does not by itself establish a
learner-model gate, and every edge above had to pass the three tests on its own.

## Novelty has three axes, and they move independently

**Decision.** Track key geography, scale form, and fingering family as separate
sources of novelty rather than one difficulty number.

**Why.** They genuinely move independently: a new key in a familiar form and
familiar hand pattern is a different demand from a familiar key in a new form.

**Consequences.** The fingering-family axis has no competency today, so the
admission band approximates it. That approximation is named rather than hidden,
and it is the one place a prerequisite is standing in for missing state.

## A second material family needs no scheduler branch

**Decision.** Material families are declared keys. Adding one requires domain
semantics and nothing else: no scheduler stage, no scheduler family branch, no
practice-session branch, no curriculum special case.

**Why.** The alternative is a scheduler that accumulates a clause per family,
which is the shape that stops a system from growing.

**Evidence.** Proved rather than asserted, with a deliberately adversarial
fixture. Contrary motion is a valuable realization but is too close to the
current domain to test family extensibility, so `proofArpeggios` supplies a
non-scalar topology. The mixed curriculum establishes that scale and arpeggio
topology stay genuinely distinct; that arpeggios declare both transferred and
intentionally new state; that both families produce the same generic candidate
contract; that admission, challenge, ranking, recovery, and pacing gain no
branch; that one goal can contain both and produce one next-exercise stream;
that disabling and restoring either leaves learner state unchanged; and that
exhaustion distinguishes caught-up from blocked in both.

A source-level scheduler boundary test keeps arpeggio policy out of the
scheduler package.

**Consequences.** The proof is architecture, **not curriculum**. Its acquisition
floor, progression, family transfer coefficient, and admission band are
provisional fixtures. The supported 24-material arpeggio corpus is a separate
thing with its own provenance; see
[`../research/foundations/arpeggios.md`](../research/foundations/arpeggios.md)
for the domain specification and promotion gates.
