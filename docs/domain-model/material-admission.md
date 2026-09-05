# Material admission

- **Status:** The first policy, as built. Two of its rules have since been
  strengthened and one relaxed; see
  [`progression-graph.md`](progression-graph.md) for what is enforced now. The
  fingering-family axis is still approximated by the band prior.
- **Written:** August 26, 2026

This answers **what may be introduced now**, which is one of three questions
that are easy to confuse:

```text
allScales
   |
   +-- goal scope        what is the learner trying to learn?
   |
   +-- REQUIRES          what is appropriate to introduce now?
   |
   +-- scheduler         what should they practice next?
```

The middle one is this document. A goal is a destination and narrows the
material under consideration; choosing a syllabus should not make every scale on
it admissible at once, and material a syllabus omits may still be worth
practising if it prepares for something the syllabus requires. `PracticeGoal`
holds that seam open with one value, general fluency over the whole catalog.
Ranking among what is admissible and in scope is the scheduler's ordinary
machinery.

`offeredScales` was a hand-authored list standing in for all three. It is gone.

## What the published curricula do and do not settle

Graded syllabi and method books converge on a rough introductory ordering and
disagree about the details. ABRSM's piano syllabus centers C, G and F major with
A and D minor early, adds D and A major with E and G minor, then B flat and E
flat with B and C minor, and moves into the black-key-heavy material later.
Faber groups early keys by keyboard shape rather than by the circle of fifths.
Piano Marvel's scale work follows a similar arc and treats one, two and four
octaves as a difficulty axis of its own.

Two things follow, and the second matters more.

**There is no canonical order.** Sources differ on where B flat, E flat and the
minor forms belong, and pedagogy writing on the subject says openly that several
orderings are defensible. So a curriculum-derived ordering is a **conservative
prior**, not a measurement: evidence about what is reasonable to introduce
early, and no evidence at all that D flat major has a latent difficulty of 0.73.

**Grades bundle what this architecture separates.** A grade mixes key, hands
together, octave span, articulation, arpeggios and examination logistics.
KeyRecall already models hands, octaves, direction, hand motion and tempo as
execution conditions, so copying grade boundaries would re-bundle exactly what
was pulled apart. The bands below are about material only.

## Novelty has three axes, and they move independently

```text
material familiarity   pitch and topology knowledge of related material
motor familiarity      whether the fingering family is already established
notation complexity    if and when staff decoding participates
```

The catalog makes the second axis concrete. All 48 scales use **14 hand
patterns**, six left and eight right, derived from `canonicalFingering` rather
than authored here:

| Hand  | entry, cycle, terminal | Scales                                                        |
| ----- | ---------------------- | ------------------------------------------------------------- |
| Right | `1` `2312341` `5`      | C, D, E, G, A, B, in all four forms (24)                      |
| Right | `1` `2341231` `4`      | F, in all four forms                                          |
| Right | `2` `1231234`          | B flat, in all four forms                                     |
| Right | `3` `4123123`          | A flat major; C sharp, F sharp, G sharp minors (8)            |
| Right | `3` `1234123`          | E flat major, E flat natural minor                            |
| Right | `2` `1234123`          | E flat harmonic and melodic minor                             |
| Right | `2` `3123412`          | D flat major; C sharp and F sharp melodic minor               |
| Right | `2` `3412312`          | F sharp major                                                 |
| Left  | `5` `4321321`          | C, D, E, F, G, A, in all four forms (24)                      |
| Left  | `4` `3214321`          | B, in all four forms                                          |
| Left  | `3` `2143213`          | D flat, E flat, A flat, B flat major; C sharp, G sharp minors |
| Left  | `4` `3213214`          | F sharp, in all four forms                                    |
| Left  | `2` `1432132`          | E flat minors                                                 |
| Left  | `2` `1321432`          | B flat minors                                                 |

Two consequences worth stating. **Most of the catalog is one right-hand family
and one left-hand family**, 24 scales each, so the motor axis is far coarser
than the material axis. And **the axes really do separate**: B major's right
hand is the family a learner already knows from C major while its left hand is
new, so "B major is harder" is true of one hand and false of the other.

## Bands, as a conservative prior

| Band                  | Material                                              |
| --------------------- | ----------------------------------------------------- |
| Foundation            | C, G, F major; A, D minor                             |
| Early transfer        | D, A, E, B flat major; E, G, C minor                  |
| Intermediate keyboard | E flat, B, F sharp, A flat major; B, F, F sharp minor |
| Advanced keyboard     | D flat major; C sharp, G sharp, E flat, B flat minor  |

Fixed-form melodic minor carries a product-level introduction delay across every
band. That is a choice about what to teach first rather than a claim that it is
motor-difficult: its fingering is the harmonic minor's everywhere except the two
right hands the raised sixth changes.

Arpeggios are banded by rule rather than by table, because what changes from one
root-position arpeggio to the next is where the hand sits rather than which
syllabus grade names it:

| Band                  | Arpeggios                               |
| --------------------- | --------------------------------------- |
| Foundation            | every tone a white key                  |
| Early transfer        | white root, black keys inside the shape |
| Intermediate keyboard | black root, still a white key inside    |
| Advanced keyboard     | every tone a black key                  |

A white-key triad is played thumb on its root. A black root is what forces the
second finger to start and the thumb to find a white key inside the shape, which
is a new motor pattern rather than a new key signature. The rule places six
arpeggios at foundation: C, G and F major, and A, D and E minor. It is a prior
like the scale table above and not a difficulty measurement, and it stands until
the arpeggio pedagogy pass revisits the memberships.

A material neither family places falls to the latest band. That is the
conservative reading of having no evidence: before this rule existed, every
arpeggio answered `foundation` by falling through the scale lookup, and a
beginner's first device session was offered C sharp minor and D flat major.

The bands are not a sequence to march through. Interleaving within and across a
band is the point, and both Faber and Piano Marvel argue for working a group of
scales together rather than perfecting one before touching the next.

## What `REQUIRES` would have to express

```text
1. Foundation material          always admissible
2. Familiar fingering family    admit when that hand's family has demonstrated
                                competence on some other material
3. New fingering family         admit above a modest floor of generic
                                single-hand execution
4. Key and geographic novelty   admit progressively, bands as the prior
5. New minor form               require some minor-topology familiarity, not
                                mastery of that same tonic and form
6. Hands together               unchanged: both hands first
7. Octaves, direction, tempo    execution conditions, never reasons to withhold
                                the material itself
```

Rule 7 says _the material_, and the distinction it is making is between
withholding a scale and withholding one way of playing it. Two octaves of C
major later became a prerequisite of its own; one octave of C major stayed
foundation material throughout, which is the rule holding rather than bending.
The wider account of which conditions gate and which only predict is in
[`progression-graph.md`](progression-graph.md).

Rule 5 has since been strengthened, and rule 4 relaxed. An altered minor form
now waits on a curriculum phase rather than a topology floor: both hands
observed separately, some hands-together work, and retrieval breadth counted per
hand. And a band's execution floor is discounted by one band when the exercise
is at the gentlest conditions the catalog offers, because difficulty is
compositional and the floor was reading only half of it. Both are in
[`progression-graph.md`](progression-graph.md). What follows is the reasoning
the first policy was built on, which still holds for the part of rule 5 that
survives.

Rule 5 is worth defending. The curricula give no support for a universal natural
to harmonic to melodic ladder: ABRSM lets candidates choose the form at lower
grades and narrows later, and Faber teaches the three forms as one related
concept. Once A natural minor is known, A harmonic minor shares its topology and
almost all of its motor organization, and only the raised seventh is new. That
is a transfer to exploit rather than a gate to add.

## What the scheduler cannot ask today

`SchedulerPipeline.eligibilityFor` reads `LearnerState` and nothing else, and
that state carries:

- four topology competencies, one per scale form;
- generic `rhScaleExecution` and `lhScaleExecution`;
- `scalarCrossing`, `multiOctaveContinuation`, `directionReversal`;
- `handsTogetherCoordination`;
- per-material _memory_, keyed by material id.

Rules 1, 4, 5, 6 and 7 are expressible with that. Bands are static material
data, minor-topology familiarity is a topology competency, and the
hands-together rule already exists.

**Rules 2 and 3 are not.** There is no motor state per fingering family, and
none per material: execution competence is generic per hand, and
`materialMemory` is memory rather than motor. So "this hand's family is
established" cannot be asked at all, and the fingering axis has to ride on the
band prior until it can be.

That gap is what this document exists to surface. Closing it means a
motor-family dimension in the competency ontology, which has its own admission
workflow in the competency extension guide, and which the fingering research
deliberately stopped short of freezing.

## What was built

A first policy using only what exists: bands as static material data in
`admissionBandOf`, generic execution floors for the later bands, topology
familiarity before harmonic and melodic minor, and the hands-together rule that
was already there. Every rejection is provisional, so material is outranked
rather than forbidden, and each carries an `EligibilityReason` so stalls can be
grouped.

One rule moved during implementation: natural minor asks for nothing, because
requiring minor familiarity to earn the only material that produces it kept
every minor scale outranked forever.

A second rule arrived from the instrument rather than the desk, and it is
deliberately not a band rule. Practising on a real piano turned up a scale being
asked for from memory that had never been presented at all: the new-material
exception admitted it, and candidates are generated at every rung, so nothing
required a first encounter to supply it. The rule added is
`unseenMaterialRequiresCue`, and it answers a different question from the rest
of this document:

| Question                                      | Answered by       |
| --------------------------------------------- | ----------------- |
| Is this part of the destination or the route? | goal scope        |
| Is this material appropriate yet?             | material REQUIRES |
| May it be attempted at this rung yet?         | guidance REQUIRES |
| Which eligible candidate wins?                | ranking           |

A third rule came from the same place, and is also not a band rule. The bands
answer "is this key's geography within reach"; this one answers "should the
learner's vocabulary of scale forms grow yet". A beginner interleaving majors
and natural minors across keys is getting the contextual-interference benefit
while the conceptual object stays stable. Adding harmonic minor also changes
what minor means, and melodic minor changes it again in a fixed form the
classical convention does not use, so an altered form waits on a breadth of
ordinary scales the learner has retrieved, across more than one band.

Interleaved, not blocked: once an altered form is admitted it competes with the
familiar corpus rather than replacing it. The rule is about how fast the
vocabulary grows, never about practising one form to exhaustion before the next.
The thresholds are first guesses, and the reason they are counted as retrievals
across bands rather than as a proficiency average is that the concern is a
learner having a stable idea of a scale, not their being excellent at one.

`unseenMaterialRequiresCue` keys off the absence of material history in this
profile, never off a claim about the learner: someone may arrive knowing the
scale perfectly well, and all that is being said is that KeyRecall has not
established it. It shares the eligibility stage because that stage already sees
the whole candidate, but it is not a property of the material's band.

Whether the fingering-family axis earns a competency of its own then becomes a
question the first policy can help answer: if learners stall specifically where
a band introduces a new family, that is the evidence for it.
