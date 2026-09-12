# Fingering

Which fingerings KeyRecall treats as canonical, and what counts as evidence for
one.

The canonical corpus itself, the per-scale patterns, and the provenance behind
each are in
[`../research/foundations/fingering.md`](../research/foundations/fingering.md).
This file is the policy the corpus was built under.

## One canonical fingering per material and hand

**Decision.** KeyRecall teaches exactly one fingering for each supported scale
and hand. Alternatives may be documented where reputable sources disagree, but
they take no part in exercise generation, displayed fingering, expected
technical-event generation, scoring, diagnostic attribution, or learner-state
inference.

**Why.** Consistency is the pedagogical point. A practice partner that varies
the fingering it asks for is not building a motor pattern, and the motor
opportunity structure the learner model reads is derived from the fingering, so
two fingerings for one scale would mean two different sets of observable events
for the same material.

**Consequences.** "Canonical" means **KeyRecall's selected canonical
fingering**, grounded in established pedagogy. It is not a claim that no
legitimate alternative exists, and the documents say so wherever a real
disagreement was found.

Alternative fingerings are recorded as a deferred extension rather than an
omission; see [`../roadmap.md`](../roadmap.md).

## Fingering is domain structure, not presentation

**Decision.** Fingering lives in `keyrecall_domain` and determines motor
opportunities, rather than being metadata the UI draws.

**Why.** It decides which technical events an exercise contains. If it were
presentation, the Q-matrix would depend on a display choice.

**Consequences.** `Exercise.linear` derives motor opportunities from the same
hand paths and canonical fingerings that realize the exercise, so the notes and
the events can never disagree. `CanonicalFingering` refuses to guess at an
unsupported material rather than interpolating one.

## A source-quality ladder, not a vote

**Decision.** Fingering choices are made from a ranked ladder of source types.
Agreement count is explicitly not evidence.

```text
1  Primary authority       published pedagogy texts and methods; university and
                           conservatory curricula; established contemporary
                           scale methods from recognized publishers
2  Institutional           keyboard-proficiency requirements, class-piano
   corroboration           curricula, similar institutional materials
3  Specialist              well-established authored teaching references
   corroboration
4  Secondary verification  commercial apps and reputable educational sites, to
                           check common practice or expose a disagreement
5  Non-authoritative       unattributed charts, forums, copied web tables
```

**Why.** Fingering choices should not be made by counting search results or
adopting whichever online chart is easiest to transcribe. Web fingering tables
copy each other, so agreement among them is evidence of copying rather than of
independent practice.

**Consequences.** Level 5 sources may reveal that a disagreement _exists_ and
may never determine the canonical data. Every canonical entry carries compact
provenance, so the source behind any one of them is recoverable.

## Scale-form conventions

**Decision.** Four forms: major, natural minor, harmonic minor, and
**fixed-form** melodic minor.

**Why.** Fixed-form means the same ascending pattern is used descending, rather
than reverting to natural minor on the way down. That is the jazz and
contemporary convention, and it keeps one material's traversal symmetric, which
the realization and alignment paths both assume.

**Consequences.** A classical melodic minor that differs descending would be a
second material rather than a variant of this one. That is a domain extension,
not a fingering change.

## The one case that took real work

**Decision.** C-sharp and F-sharp melodic minor take the exceptional right-hand
pattern `23123412` rather than sharing their harmonic-minor fingering.

**Why.** The general convention is that harmonic and melodic minor share
fingering. These two are documented exceptions to it.

**Evidence.** Four independent lines, from different traditions:

- The Schotte-revised Hanon editions document the convention and name these two
  as the exceptions [Funnell_Schotte].
- An all-key melodic-minor reference independently reports the same `23123412`
  pattern.
- Peer-reviewed historical analysis of Hanon's scale pedagogy supports the
  exception [BrownLee2026].
- A university curriculum that groups scales by fingering pattern separates
  C-sharp and F-sharp melodic minor from the corresponding natural and harmonic
  minor patterns [PDMPiano].

A contemporary reference reports `23123123` for F-sharp melodic minor instead.
That is retained as research provenance rather than adopted, because it stands
alone against the four above.

**Consequences.** This is the strongest-evidenced fingering decision in the
corpus, and it is worth knowing it was also the most contested. A future
disagreement here needs at least this weight of evidence to reopen.

## Multi-octave continuation is read, not inferred

**Decision.** Where a source's diagrams expose more than one octave, the
continuation pattern is taken from them directly rather than derived by rotating
a one-octave pattern.

**Why.** The entry, cycle, and terminal structure of a fingering are genuinely
different concepts, and a rotation can produce a pattern nobody teaches.

**Evidence.** Baylor's keyboard diagrams for C-sharp, F-sharp, and G-sharp
harmonic minor expose more than one octave, and the right-hand pattern in all
three normalizes to `34123123` [Clark_PianoBasics]. Multi-octave pedagogical
material independently supports `34123123` and `43213214` for F-sharp natural
minor.

**Consequences.** `CanonicalFingering` records `entry / cycle / terminal`
explicitly rather than storing one octave and a rule for extending it.

## Fingering family has no competency

**Decision.** Motor families such as `DIATONIC_3_4_CYCLE` are analysis
vocabulary. Nothing in the packages implements them, and no competency exists
for fingering family.

**Why.** Persistent latent state has to be earned by being empirically distinct,
transferable, and identifiable. Nothing has established that yet for fingering
geometry.

**Consequences.** The admission band approximates the fingering-family axis in
the meantime, which is the one place a prerequisite stands in for missing state;
see [`curriculum-and-progression.md`](curriculum-and-progression.md). The
residual census exists to ask whether the model leaves repeatable error that
such a state would explain, and its answer so far is a validated null; see
[`../research/experiments/arpeggio-policy.md`](../research/experiments/arpeggio-policy.md).

## KeyRecall does not verify fingering

**Decision.** No claim anywhere in the system asserts which finger was used.

**Why.** MIDI reports which key was struck, when, and how hard. It does not
report which finger struck it.

**Consequences.** An [opportunity](../GLOSSARY.md#opportunity) says a scalar
crossing _occurs at this point in this exercise_. It does not claim the expected
fingering was used. Crossing-related problems can be inferred from timing and
error location, and that inference is what the competency learns from; the app
may display and teach fingering, and may not verify it.
