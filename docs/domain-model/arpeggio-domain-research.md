# Arpeggio domain research

- **Status:** Working research specification; not a learner-facing catalog
- **Date:** September 3, 2026
- **Scope:** Piano tonic-triad arpeggios and the boundary around later families

## 1. Outcome

The architecture proof established that arpeggios can enter the generic
curriculum and scheduler. This document settles the domain vocabulary that the
proof was not meant to answer and records which claims are supported strongly
enough to guide a product implementation.

The initial product domain should begin with major and minor tonic-triad
arpeggios in root position. Hands, octave span, traversal direction, tempo, and
guidance are realization conditions. Inversion changes the ordered pitch
topology and remains part of material identity.

The complete root-position fingering corpus is now represented by
`allRootPositionArpeggios`. It is a supported domain catalog for policy
characterization, not approval to add arpeggios to the product's active
learner-facing catalog. Family-specific motor characterization and observational
validation still precede that promotion.

## 2. Deliberate boundary

The arpeggio family initially means a triad's chord tones traversed successively
over one or more octaves. It excludes:

- blocked and broken-chord patterns;
- dominant-, diminished-, and other seventh-chord arpeggios;
- articulation and dynamic variants;
- contrary-motion arpeggios; and
- accompaniment figures or repertoire-derived patterns.

This is a semantic boundary, not a claim that those materials lack pedagogical
value. The Royal Conservatory syllabus lists broken chords and arpeggios as
separate technical tests at the same levels. A broken chord must therefore not
be introduced invisibly as an easier realization of an arpeggio requirement.

## 3. Sources and what they establish

### 3.1 Examination curricula

The
[ABRSM Piano Practical Grades syllabus for 2025 and 2026](https://www.abrsm.org/sites/default/files/2024-06/Piano%202025%20%26%202026%20Prac%20syllabus%2020240524_access.pdf)
is the most compact complete progression. ABRSM has confirmed that the 2027 and
2028 syllabus
[makes no changes to scales and arpeggios](https://www.abrsm.org/en-us/news/new-piano-syllabus-and-free-learning-resources-available-now).
Its requirements show:

- a partial-range, separate-hand C major and D minor pattern at Initial Grade;
- one-octave, separate-hand arpeggios at Grade 1;
- two-octave, separate-hand arpeggios at Grade 2;
- the first hands-together arpeggios at Grade 3;
- two-octave hands-together work throughout Grade 5;
- four-octave hands-together root-position work at Grade 6; and
- second-inversion arpeggios at Grade 8.

ABRSM requires ascent and descent, even notes, memory, and normally root
position. It permits any fingering that produces a successful musical outcome,
so it is curriculum evidence rather than canonical-fingering authority.

The
[Royal Conservatory Piano Syllabus, 2022 Edition](https://teacherportal.rcmusic.com/getattachment/57f3734d-97e5-4777-b67e-4b1111ee31a3/piano-syllabus-2022-edition.pdf)
introduces tonic arpeggios as separate-hand, two-octave, root-position work at
Level 5. Level 7 uses two octaves hands together in root position and
inversions; Level 8 expands these to four octaves. Earlier levels contain broken
triads rather than calling the same activity an arpeggio.

The
[Trinity Piano syllabus, online edition February 2026](https://www.trinitycollege.com/resource?id=9079)
corroborates the main realization ladder: two-octave single-hand arpeggios at
Grades 2 and 3, two-octave hands-together work by Grade 5, and four-octave
hands-together work from Grade 6. Trinity also requires ascent and descent and
treats published fingerings as advisory rather than compulsory.

These curricula are evidence about coherent requirement sets and conservative
ordering. Their grade numbers are not latent difficulty measurements. Each grade
bundles key, hand configuration, span, tempo, articulation, and other skills
that KeyRecall models separately.

### 3.2 Fingering and teaching sequence

Michael Clark's open Baylor University text,
[_Piano Basics_](https://openbooks.library.baylor.edu/pianobasics/), is the
primary current fingering source for the architecture fixture. Its
[one-octave chapter](https://openbooks.library.baylor.edu/pianobasics/chapter/one-octave-arpeggios/)
groups white-key major arpeggios by left-hand geometry:

| Materials        | Right hand | Left hand |
| ---------------- | ---------- | --------- |
| C, F, G major    | `1 2 3 5`  | `5 4 2 1` |
| B, E, A, D major | `1 2 3 5`  | `5 3 2 1` |

The
[two-octave chapter](https://openbooks.library.baylor.edu/pianobasics/chapter/two-octave-major-arpeggios/)
states the continuation explicitly:

```text
RH:          123 + 123 + 5
LH C/F/G:    5 + 421 + 421
LH B/E/A/D:  5 + 321 + 321
```

Its
[minor-arpeggio chapter](https://openbooks.library.baylor.edu/pianobasics/chapter/two-octave-minor-arpeggios/)
gives `123 + 123 + 5` in the right hand and `5 + 421 + 421` in the left for
white-key minor tonics.

The
[St. Olaf College Keyboard Proficiency Requirements Level III](https://wp.stolaf.edu/music-handbook/files/2020/06/ProficiencyL3_052720.pdf),
revision 052720, is the canonical source for the complete root-position corpus.
Appendix 2, pp. 15--16, notates multi-octave ascent and descent for all major
and minor fingering groups. Unlike a terminal one-octave chart, those examples
establish the entry finger, each internal continuation, the terminal finger, and
descending reversal in one source. The appendix uses G-flat major; KeyRecall
normalizes that physical-key pattern to its catalog spelling, F-sharp major.

Two authored teaching charts were retained as comparison sources:

- Joy Morin's
  [_Scale & Arpeggio Fingerings for Piano_](https://colorinmypiano.com/download/Scale__Arpeggio_Fingerings_for_Piano_2_Octave.pdf),
  2011, pp. 1--3; and
- Chad Twedt's
  [_Scale and Arpeggio Fingering Sheet_](https://blog.twedt.com/wp-content/uploads/2012/02/Scale-and-Arpeggio-Fingering.pdf),
  2011, p. 2.

They corroborate the main geometry families but preserve genuine alternatives
for B-flat major and a terminal disagreement for B-flat minor LH. Section 6
records the exact differences and canonical choices.

The book's course sequence places triad recognition and inversions before
one-octave major arpeggios, then expands major arpeggios to two octaves. Minor
triads and inversions similarly precede one-octave minor arpeggios. That is
useful support for topology preparation, but it does not justify adding broken
chords to KeyRecall's exercise domain.

No source reviewed settles inversion fingering to the same acceptance bar.
Inversion records therefore remain absent even though inversion topology is
represented.

### 3.3 Transfer evidence

The curricula routinely place scales and arpeggios in the same technical-work
programs, but do not measure transfer between them. Furuya et al.'s
[piano practice transfer study](https://pmc.ncbi.nlm.nih.gov/articles/PMC4228459/)
found transfer from a trained to an untrained fast finger movement under
specific practice conditions. van Vugt et al.'s
[practice-variability study](https://pubmed.ncbi.nlm.nih.gov/29494670/) likewise
found that practice conditions changed transfer to new tempi and sequences.
Neither study tests scale-to-arpeggio transfer or identifies a coefficient for
it.

The existing prediction-only scale-execution transfer is therefore a model
hypothesis, not a literature-derived constant. Its sign is defensible; its
magnitude is not. Promotion requires the characterization and observational
workflow in
[`competency-extension-guide.md`](../learner-model/competency-extension-guide.md),
not another curriculum citation.

## 4. Canonical material identity

The material identity is:

```text
ArpeggioMaterial
    root
    chord quality
    inversion
```

For triads, topology relative to the starting tone is:

| Quality | Position         | Semitone offsets | Letter offsets |
| ------- | ---------------- | ---------------- | -------------- |
| major   | root             | `0 4 7`          | `0 2 4`        |
| major   | first inversion  | `0 3 8`          | `0 2 5`        |
| major   | second inversion | `0 5 9`          | `0 3 5`        |
| minor   | root             | `0 3 7`          | `0 2 4`        |
| minor   | first inversion  | `0 4 9`          | `0 2 5`        |
| minor   | second inversion | `0 5 8`          | `0 3 5`        |

The offsets normalize each position to its starting chord tone. The root still
names the harmonic object; inversion says which chord tone starts its repeating
ordered topology.

Inversion remains material identity for three reasons:

1. It changes the ordered pitch-class and interval topology.
2. It changes canonical fingering and motor transitions.
3. ABRSM and RCM name positions as distinct curriculum requirements rather than
   incidental performance choices.

The following do not belong to material identity:

| Property                      | Owner                  | Reason                                      |
| ----------------------------- | ---------------------- | ------------------------------------------- |
| hand configuration            | execution              | same topology assigned to one or both hands |
| octave span                   | execution              | repeats the topology across a larger range  |
| up, down, or up-and-down      | execution              | traverses the same ordered topology         |
| tempo                         | execution              | changes demand, not material                |
| guidance                      | presentation           | changes information supplied to the learner |
| exam grade or curriculum role | requirement provenance | external grouping, not musical identity     |

A dominant seventh “in the key of D” would eventually resolve to an A dominant
seventh material plus curriculum provenance. The exam's key label must not
become a second identity for the same pitch topology.

## 5. Product progression contract

The supported evidence justifies these prerequisite edges:

```text
one octave -> two octaves -> four octaves
one hand established -> hands together
root position -> inversions
triadic tonic family -> seventh-chord families
```

The first two mirror established scale conditions but must be evaluated against
arpeggio execution evidence. Scale mastery cannot satisfy an arpeggio span or
hands-together prerequisite by itself.

The runtime expresses this ordering through each material's declarative
progression. Arpeggios declare the `1 -> 2 -> 4` span sequence, separate-hand
readiness for hands together, and root-position material prerequisites for
inversions. Generic scheduler stages evaluate those declarations against exact
material and arpeggio-execution evidence.

Root position before inversion is a family introduction rule, not a claim that
every root-position arpeggio is mechanically easier than every inversion. The
curricula agree on the broad ordering while differing substantially on when
arpeggios begin and which keys appear. KeyRecall should therefore let learner
prediction rank appropriate materials inside the phase rather than copy a grade
sequence.

The acquisition floor remains:

```text
active unresolved requirement
    -> same material and inversion
    -> right hand
    -> one octave
    -> upward
    -> initial tempo
    -> continuously cued
```

All 24 major and minor root-position materials in the supported corpus now have
sourced records for both hands. Right-hand-only, upward-only entry remains a
provisional KeyRecall policy. The floor must never substitute a broken chord or
a different tonic.

## 6. Canonical fingering record

The shared runtime record now uses the same boundary-aware representation for
every material family:

```text
CanonicalFingering
    materialId
    hand
    entry
    cycle
    terminal
    reversesForDescending
    provenance
```

`entry / cycle / terminal` is essential. A one-octave `1 2 3 5` string does not
say that the right hand replaces the internal terminal `5` with `1` before
continuing. The C/G left hand and D left hand also belong to different motor
families despite sharing the same pitch-count topology.

For descent, KeyRecall may reverse the authoritative ascending stream only when
the canonical record establishes that symmetry. It must not install reversal as
a universal rule for future chord qualities and inversions.

Every product catalog entry needs both hands. Unsupported or disputed records
remain absent rather than receiving a rule-derived guess. The record carries
source, edition, location, and status without knowing which material family it
serves.

### 6.1 Canonical root-position corpus

The catalog tonic spellings match the scale catalog:

```text
major: C Db D Eb E F F# G Ab A Bb B
minor: C C# D Eb E F F# G G# A Bb B
```

The compact strings below are one-octave terminal summaries. Runtime records
store the generative boundary form and assert descending reversal individually.

| Materials                 | RH        | LH        | Runtime status     |
| ------------------------- | --------- | --------- | ------------------ |
| C, F, G major             | `1 2 3 5` | `5 4 2 1` | established        |
| D, A, E, B major          | `1 2 3 5` | `5 3 2 1` | established        |
| Db, Eb, Ab major          | `2 1 2 4` | `2 1 4 2` | established        |
| F# major                  | `1 2 3 5` | `5 3 2 1` | canonical selected |
| Bb major                  | `2 1 2 4` | `3 2 1 3` | canonical selected |
| C, D, E, F, G, A, B minor | `1 2 3 5` | `5 4 2 1` | established        |
| Eb minor                  | `1 2 3 5` | `5 4 2 1` | established        |
| C#, F#, G# minor          | `2 1 2 4` | `2 1 4 2` | established        |
| Bb minor                  | `2 3 1 2` | `3 2 1 3` | canonical selected |

F-sharp major is marked selected because St. Olaf states the same physical-key
pattern under the enharmonic spelling G-flat major. B-flat major and minor are
marked selected because the comparison sources disagree:

| Record      | St. Olaf                 | Morin                                  | Twedt                    | Choice   |
| ----------- | ------------------------ | -------------------------------------- | ------------------------ | -------- |
| Bb major RH | `2 + 124...`             | `2 + 124...`; alternative `2 + 312...` | `4 + 124...`             | St. Olaf |
| Bb major LH | `3 + 213...`             | `2 + 142...`; alternative `3 + 213...` | `3 + 213...`             | St. Olaf |
| Bb minor LH | `3 + 213...`, terminal 3 | `3 + 213...`, terminal 2               | `3 + 213...`, terminal 3 | St. Olaf |

St. Olaf is canonical in these cases because its institutional requirement shows
the selected fingering through repeated internal boundaries and through descent.
The alternatives remain research evidence only. No runtime record is created for
G-flat major, A-flat minor, or any inversion.

### 6.2 Mechanical acceptance invariant

For every supported root-position material, both hands, spans 1, 2, and 4, and
upward or up-and-down traversal, tests assert:

- the finger stream and realized moments have equal length;
- every finger is in `1..5`;
- each internal continuation reproduces the record's cycle;
- descending streams exist only from that record's reversal assertion; and
- every derived arpeggio-transition site is exactly an actual fingering
  crossing.

## 7. Motor and observation model

The pitch sequence, fingering stream, and hand path should derive at least:

- arpeggio hand-position transitions;
- thumb-under and finger-over transition sites;
- multi-octave continuation sites;
- direction reversal; and
- hands-together synchronization opportunities.

Each `arpeggioTransition` opportunity is derived at an actual crossing in the
realized fingering stream and records its hand and reached moment. A one-octave
`1 2 3 5` right-hand arpeggio therefore creates no transition opportunity, while
a continued `3 -> 1` boundary does. Ordinary chord-tone intervals do not create
transition evidence merely because the material is an arpeggio.

Standard MIDI can observe pitch, onset, release, velocity, continuity, and
between-hand synchronization. It cannot observe the finger used. Fingering
feedback must therefore remain expected-technique guidance unless another input
channel supplies finger identity; note accuracy alone cannot prove canonical
fingering.

The initial learner-state hypothesis is:

| State                          | Treatment                                             |
| ------------------------------ | ----------------------------------------------------- |
| exact arpeggio material memory | new, per material                                     |
| major/minor arpeggio topology  | new, per quality                                      |
| right/left arpeggio execution  | new, per hand                                         |
| arpeggio transition skill      | new candidate motor state                             |
| multi-octave continuation      | shared existing state plus arpeggio-specific residual |
| direction reversal             | shared existing state plus arpeggio-specific residual |
| hands-together coordination    | shared existing state plus arpeggio-specific residual |
| scale execution                | prediction-only candidate transfer                    |

The table states modeling hypotheses, not admitted production coefficients.
Conditioned error covariance and held-out prediction must decide whether one
arpeggio transition competency is identifiable, whether fingering-family state
is required, and how much generic coordination actually transfers.

## 8. Tempo and difficulty

ABRSM, RCM, and Trinity all increase requested pace across their progressions,
but use different beat units, note groupings, material sets, and performance
conditions. Their metronome marks can populate exact curriculum requirements;
they cannot be averaged into a universal arpeggio difficulty scale.

The product family should continue using local adjacent tempo steps. Before
activation it needs an arpeggio-specific initial tempo and challenge
characterization. The scale family's initial tempo and admission band are not
evidence about arpeggios merely because both are linear exercises.

Difficulty characterization must cross at least:

```text
tonic and key geometry
quality
inversion
hand
octave span
direction
hands together
tempo
guidance
placement prior
```

The output is prediction and transfer calibration. It is not a hardcoded total
ordering of arpeggios.

## 9. Promotion gates

Before adding arpeggios to the active learner-facing catalog:

1. Normalize canonical major and minor triad fingerings for every included tonic
   and hand, with source locations and preserved disagreements.
2. Represent entry, cycle, and terminal fingers so one- and multi-octave
   realizations share one authoritative record.
3. Implement minor and inversion topology without changing scheduler policy.
4. Derive motor opportunities from actual fingering boundaries.
5. Establish separate-hand, span, hands-together, and inversion prerequisites in
   the family-owned admission policy.
6. Characterize initial tempo, challenge, acquisition floor, and candidate-pool
   concentration across learner priors.
7. Run the arpeggio extension workflow for topology, execution, transition,
   residual, and transfer hypotheses.
8. Validate note, timing, continuity, reversal, and coordination observations on
   instrument recordings.
9. Map external curricula only through versioned curriculum requirements.
10. Preserve caught-up, blocked, invalid-scope, replay, and family-boundary
    invariants in mixed scopes.

Gates 1 through 5 are implemented for the supported root-position corpus.
Mixed-family trajectory characterization exercises every placement prior and
selects both families without introducing a family-specific scheduler path.
Full-catalog policy characterization is complete. Learner-model extension
analysis and instrument validation remain open.

The app can offer the arpeggio catalog from a developer-only switch, off on
every launch and absent from a release build. It exists to make the open gates
observable on an instrument rather than to ship them, so a session run under it
is diagnostic and not calibration evidence. Four things are worth watching, in
this order:

1. where progression stalls, since arpeggios generate one ascending realization
   at one tempo while a scale generates a tempo ladder;
2. whether the family transfer coefficient produces obviously overconfident or
   underconfident first predictions;
3. whether pacing interleaves the families rather than alternating them
   mechanically; and
4. where learner-facing copy still says "scale" for material that is not one.

Changing the coefficient to make a device session feel better would turn a
diagnostic into calibration under gates that remain open.

The first policy-sensitivity census is recorded in
[`arpeggio-policy-characterization.md`](arpeggio-policy-characterization.md). It
keeps every production value unchanged and identifies initial tempo as the
fixture's highest-sensitivity assumption because changing generated tempo alone
does not change the scheduler's generic entry-tempo contract.

## 10. Current decisions and open claims

| Question                                       | Decision                                                   |
| ---------------------------------------------- | ---------------------------------------------------------- |
| Is an arpeggio a scale pattern?                | No; it is a distinct material family.                      |
| Is inversion material identity?                | Yes for continuous technical arpeggios.                    |
| Are hand, span, direction, and tempo identity? | No; they are realization conditions.                       |
| Are broken chords an arpeggio floor?           | No; they are a separate family and are currently excluded. |
| Which qualities enter first?                   | Major and minor tonic triads.                              |
| Which positions enter first?                   | Root position; inversions are a later phase.               |
| Are C/G/D fixture fingerings sourced?          | Yes; D left hand is `5 3 2 1`.                             |
| Is the fixture floor proven?                   | No.                                                        |
| Is `rhoFamily = 0.35` evidence-backed?         | No; it remains fixture-only.                               |
| Are exam tempi generic targets?                | No; they belong to curriculum requirements.                |
| May the catalog expand now?                    | No; the promotion gates remain open.                       |
