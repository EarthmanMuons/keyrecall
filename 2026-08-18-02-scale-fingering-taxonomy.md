# KeyRecall Scale Fingering Taxonomy and Research

**Status:** Working research specification\
**Date:** August 18, 2026\
**Scope:** Canonical piano scale fingerings for the initial KeyRecall
scale domain\
**Related document:** `keyrecall-v1-domain-model.md`

------------------------------------------------------------------------

## 1. Purpose

This document records the research basis, conventions, provenance
policy, unresolved cases, and eventual canonical fingering taxonomy for
KeyRecall.

It is intentionally separate from the V1 domain-model document:

-   `keyrecall-v1-domain-model.md` describes **how fingering
    participates in the software and learner model**.
-   This document describes **which fingerings KeyRecall considers
    canonical and why**.

The eventual runtime fingering dataset should be a distillation of this
research rather than the research being reconstructed from whatever
happened to be implemented.

The initial taxonomy covers 48 scale definitions: 12 major, 12 natural
minor, 12 harmonic minor, and 12 fixed-form melodic minor. Each
definition requires canonical right-hand and left-hand fingering.

## 2. V1 Canonical-Fingering Policy

KeyRecall V1 teaches **one canonical fingering** for each supported
scale and hand.

Alternative fingerings are deliberately out of scope for V1. They may be
documented where reputable sources disagree, both to preserve the
research trail and to avoid designing the data model into a corner, but
they do not participate in exercise generation, displayed fingering,
expected technical-event generation, scoring, diagnostic attribution, or
learner-state inference.

> KeyRecall teaches a consistent conventional fingering for each scale.

"Canonical" means **KeyRecall's selected canonical fingering**, grounded
in established piano pedagogy. It does not claim that no legitimate
alternative fingering exists.

## 3. Source-Quality Policy

Fingering choices should not be made by counting search results or
adopting whichever online chart is easiest to transcribe.

### 3.1 Primary authority

Prefer established published piano pedagogy texts and methods,
university or conservatory piano curricula and instructional materials,
and established contemporary piano-scale methods from recognized
music-education publishers.

### 3.2 Institutional corroboration

University keyboard-proficiency requirements, class-piano curricula, and
similar institutional materials can corroborate that a fingering is part
of conventional pedagogical practice.

### 3.3 Specialist corroboration

Well-established, authored piano-teaching references may corroborate a
canonical choice or expose a legitimate alternative.

### 3.4 Secondary verification

Commercial apps and reputable educational websites can be used to check
common practice, identify disagreements, or verify a specific pattern
when stronger sources are incomplete.

The user's **Piano Chords and Scales** iOS app is available as a
targeted secondary check if a small number of exact fingerings remain
uncertain.

### 3.5 Non-authoritative discovery sources

Unattributed fingering charts, forums, copied web tables, and
miscellaneous scale websites may reveal that a disagreement exists, but
should not determine KeyRecall's canonical data. Agreement count is not
evidence of independence.

## 4. Current Primary Research Sources

### 4.1 Michael Clark, *Piano Basics* --- Baylor University

Baylor's open class-piano text is a strong contemporary institutional
source for conventional major-scale fingering and harmonic-minor
fingering.

Relevant material includes one- and two-octave major scales, black-key
major-scale fingering principles, harmonic-minor instruction, and a
harmonic-minor fingering appendix.

Source: <https://openbooks.library.baylor.edu/pianobasics/>

### 4.2 *Class Piano* --- Indiana University Press

The Indiana University Press open text explicitly discusses **standard
scale fingering**, scale groups, relationships between major and minor
fingerings, and irregular/mixed fingerings.

Project: <https://publish.iupress.indiana.edu/projects/class-piano>

Standard scale fingering:
<https://publish.iupress.indiana.edu/read/class-piano/section/4e2e66be-9b92-44f1-88e9-fa30ae88c7f6>

Continued:
<https://publish.iupress.indiana.edu/read/class-piano/section/b3af4d54-0165-4de8-8136-5680eb6623bf>

Irregular/mixed fingerings:
<https://publish.iupress.indiana.edu/read/class-piano/section/f039d7d1-597f-4b17-87bd-95408ef56d20>

### 4.3 Suzanna Sifter, *A Modern Method for Piano Scales* --- Berklee Press

Suzanna Sifter is a professor of piano at Berklee College of Music.
Berklee Press describes *A Modern Method for Piano Scales* as a
scale-study method covering essential and widely used scales.

Author/source:
<https://berkleepress.com/berklee-authors/suzanna-sifter/>

Keyboard catalog: <https://berkleepress.com/music/keyboard/>

This is the preferred primary direction for **contemporary/jazz
fixed-form melodic minor**, particularly where traditional classical
sources change the pitch collection on descent. Exact fingering
extraction and cross-checking remains part of the normalization step.

## 5. Scale-Form Conventions

### 5.1 Major

`1 2 3 4 5 6 7`

### 5.2 Natural minor

`1 2 ♭3 4 5 ♭6 ♭7`

### 5.3 Harmonic minor

`1 2 ♭3 4 5 ♭6 7`

### 5.4 Fixed-form melodic minor

KeyRecall deliberately uses `1 2 ♭3 4 5 6 7` in **both directions**.

For example:

``` text
A melodic minor ascending:
A B C D E F# G# A

A melodic minor descending:
A G# F# E D C B A
```

This is the fixed-form or jazz melodic-minor convention. Traditional
classical pedagogy often raises scale degrees 6 and 7 ascending and
reverts to natural minor descending; KeyRecall does not use that
convention.

## 6. Canonical Key Names

The initial catalog uses 12 pedagogically useful tonic spellings rather
than duplicating every enharmonic spelling as a separate physical-key
exercise.

**Major:** `C Db D Eb E F F# G Ab A Bb B`

**Minor:** `C C# D Eb E F F# G G# A Bb B`

The musical-domain layer must retain correct theoretical note spelling
even though MIDI observes pitch numbers. For example, C# harmonic minor
is `C# D# E F# G# A B# C#`.

## 7. Fingering Representation

The authoritative canonical fingering should not be represented as one
arbitrary tonic-to-tonic digit string.

``` text
FingeringPattern
    hand
    direction
    entry
    cycle
    exit
```

-   `entry`: how traversal begins.
-   `cycle`: repeating behavior through internal octave boundaries.
-   `exit`: how traversal terminates or turns around.

An outer tonic may appropriately use finger 5 while the same tonic at an
internal octave boundary requires a continuation finger. Therefore
`4 → 1` at an internal boundary and `4 → 5` at a terminal endpoint are
different technical events.

## 8. Fingering Families Are Derived

The canonical sequence is authoritative domain data. A `FingeringGroup`
is a **derived classification** based on shared motor structure.

``` text
canonical scale fingerings
        ↓
entry / cycle / exit normalization
        ↓
shared cyclic motor structures
        ↓
fingering families
        ↓
derived technical transitions
```

A key research question is whether tonic-to-tonic fingerings that appear
different are rotations or phases of the same underlying alternating
three-/four-finger motor cycle.

## 9. Major-Scale Research Status

**Status: substantially settled.**

The conventional major-scale system is well supported by established
piano pedagogy. Baylor explicitly teaches C, G, D, A, and E as a common
fingering group and treats F and B as hand-specific exceptions.
Black-key scales are taught through the relationship between
two-black-key and three-black-key groups and thumb placement.

Research shorthand for RH continuation structure:

  Scale/group     RH structural pattern
  --------------- ----------------------------------------------------------------
  C, G, D, A, E   `12312341` continuation family
  F               `12341231`
  Bb              `41231234`
  Eb              `31234123`
  Ab              `34123123`
  Db              `23123412`
  F#/Gb           `23412312`
  B               related to CAGED; endpoint/continuation normalization required

These strings are research shorthand, not final runtime records. The LH
system likewise exhibits strong structural grouping but should be
normalized from authoritative multi-octave fingerings.

**Decision:** proceed to canonical encoding from primary pedagogical
sources.

## 10. Natural-Minor Research Status

**Status: structurally well supported; exact normalized table still to
be encoded.**

Indiana's *Class Piano* gives explicit pedagogical relationships between
standard major and minor fingerings. Major scales beginning on white
keys and their tonic/parallel minors are fingered alike, with additional
black-key relationships accounting for other minor scales.

The research dataset should preserve both the explicit canonical pattern
and the pedagogical relationship from which it derives.

## 11. Harmonic-Minor Research Status

**Status: strong primary source identified; exact black-key sequences
require careful normalization/corroboration.**

Baylor provides harmonic-minor instruction and an appendix containing
harmonic-minor fingerings. For white-key tonics, Baylor explicitly
teaches the relationship to parallel-major fingering.

High-confidence conventional cases include C, D, E, F, G, A, and B
harmonic minor.

Give targeted exact verification to:

``` text
F# harmonic minor
C# harmonic minor
G# harmonic minor
Eb harmonic minor
Bb harmonic minor
```

Earlier broad web research exposed alternatives for some of these
scales. Those lower-authority results are useful only as evidence that
the exact canonical choice should be checked carefully.

**Decision:** do not fill unresolved black-key harmonic-minor sequences
from miscellaneous web charts. The user's Piano Chords and Scales app
can be a targeted secondary check if an exact pattern remains ambiguous
after authoritative-source review.

## 12. Fixed-Form Melodic-Minor Research Status

**Status: scale convention settled; exact canonical fingering table
still requires normalization from contemporary/jazz piano pedagogy.**

Traditional classical sources are problematic because they commonly
change to natural minor on descent. KeyRecall does not.

Berklee/Suzanna Sifter therefore provides the preferred primary
direction for the fixed-form melodic-minor fingering system.

The pitch collection is the same ascending and descending, but KeyRecall
should not blindly reverse a convenient one-octave digit string:
`entry`, internal `cycle`, turnaround, and `exit` must be normalized
explicitly.

## 13. Current 48-Scale Catalog

"Normalize" means the musical definition is settled but final
authoritative `entry / cycle / exit` records have not yet been written.

  --------------------------------------------------------------------------
  Tonic          Major          Natural minor  Harmonic minor Fixed melodic
                                                              minor
  -------------- -------------- -------------- -------------- --------------
  C              Major system   Normalize      High           Normalize
                 settled                       confidence     

  C#/Db          Db major       Normalize C#   Verify C#      Normalize C#
                 settled                       exact          
                                               fingering      

  D              Major system   Normalize      High           Normalize
                 settled                       confidence     

  D#/Eb          Eb major       Normalize Eb   Verify Eb      Normalize Eb
                 settled                       exact          
                                               fingering      

  E              Major system   Normalize      High           Normalize
                 settled                       confidence     

  F              Major system   Normalize      High           Normalize
                 settled                       confidence     

  F#             Major system   Normalize      Verify exact   Normalize
                 settled                       fingering      

  G              Major system   Normalize      High           Normalize
                 settled                       confidence     

  G#/Ab          Ab major       Normalize G#   Verify G#      Normalize G#
                 settled                       exact          
                                               fingering      

  A              Major system   Normalize      High           Normalize
                 settled                       confidence     

  A#/Bb          Bb major       Normalize Bb   Verify Bb      Normalize Bb
                 settled                       exact          
                                               fingering      

  B              Major system   Normalize      High           Normalize
                 settled                       confidence     
  --------------------------------------------------------------------------

This table intentionally does **not** invent exact fingering data where
authoritative-source normalization has not yet been completed.

## 14. Development-Time Provenance Record

The research representation should retain more information than the
runtime dataset.

``` yaml
c_sharp_harmonic_minor:
  right_hand:
    keyrecall_canonical: <pattern-id>

    authority:
      primary:
        source: <bibliographic-id>
        fingering: <normalized-pattern>

      corroborating:
        - source: <bibliographic-id>
          fingering: <normalized-pattern>

    alternatives:
      - source: <bibliographic-id>
        fingering: <normalized-pattern>
        note: documented legitimate alternative

    decision:
      status: canonical_selected
      rationale: >
        Selected as the KeyRecall V1 canonical fingering because it
        matches the conventional pedagogical system represented by
        the primary sources.
```

Suggested statuses: `ESTABLISHED`, `CORROBORATED`,
`ALTERNATIVE_REPORTED`, `SOURCE_DISAGREEMENT`, `VERIFICATION_PENDING`,
`CANONICAL_SELECTED`.

## 15. Runtime Data Should Be Smaller

The shipped application should not need the research apparatus.

``` yaml
id: c_sharp_harmonic_minor
tonic: C#
pattern: harmonic_minor

degrees:
  - C#
  - D#
  - E
  - F#
  - G#
  - A
  - B#
  - C#

right_hand:
  fingering_pattern: <canonical-pattern-id>

left_hand:
  fingering_pattern: <canonical-pattern-id>
```

The referenced pattern contains normalized entry/cycle/exit behavior
required to generate arbitrary exercises.

## 16. Derived Technical Events

Once a canonical fingering is known, KeyRecall should derive technical
events mechanically rather than hand-authoring them in the Q-matrix.

``` text
canonical fingering
        ↓
generated expected finger stream
        ↓
generated technical events
        ↓
Q-matrix / evidence mapping
        ↓
learner-component updates
```

For example, `3 → 1` and `4 → 1` internal transitions can generate
crossing events, while a terminal `4 → 5` may instead be classified as
an exit or turnaround event.

## 17. Future Fingering-Family Diagram

After all 48 definitions are normalized, add a Mermaid diagram showing:

``` text
Fingering Family
      ↓
Canonical Patterns
      ↓
Scales / Hands / Forms
```

It should be generated from the completed taxonomy rather than designed
manually in advance.

## 18. Modes and Later Scale Families

Modes are outside the first 48-scale enumeration, but the taxonomy must
not assume the initial forms are a closed universe.

Future patterns may include Ionian, Dorian, Phrygian, Lydian,
Mixolydian, Aeolian, Locrian, modes of fixed melodic minor, modes of
harmonic minor, symmetric scales, whole-tone scales, diminished scales,
and other advanced patterns.

Ionian and Aeolian should relate cleanly to major and natural minor
rather than duplicate identical domain information without reason.

## 19. Arpeggios Are a Separate Taxonomy

Arpeggios belong in KeyRecall's overall practice domain but should have
a separate fingering taxonomy. They introduce chord quality, inversion,
hand span, black-key starting positions, competing pedagogical systems,
and potentially stronger dependence on hand geometry.

## 20. Research Conclusions So Far

1.  One canonical fingering per scale/hand is the correct V1 constraint.
2.  Canonical means KeyRecall's pedagogically grounded choice, not the
    only legitimate fingering.
3.  Source authority matters more than agreement count.
4.  Major-scale fingering is sufficiently established to proceed to
    canonical encoding.
5.  Natural minor can be organized through conventional major/minor
    fingering relationships while retaining explicit patterns.
6.  Harmonic minor has strong institutional coverage, with a small set
    of black-key cases deserving exact verification.
7.  Fixed-form melodic minor should be sourced from contemporary/jazz
    piano pedagogy rather than classical descending-melodic-minor
    charts.
8.  `entry / cycle / exit` is preferable to a flat one-octave digit
    string.
9.  Fingering families should be derived from normalized canonical
    patterns.
10. Technical crossing events should be generated from canonical
    fingering data.
11. Alternative fingerings can remain in research provenance without
    entering V1 runtime behavior.
12. Piano Chords and Scales remains available only as targeted secondary
    verification.

## 21. Next Research/Implementation Pass

### Phase A --- Major

For all 12 major scales and both hands: transcribe the authoritative
conventional fingering; normalize `entry / cycle / exit`; verify
descending traversal; assign provisional family IDs; derive transition
events.

### Phase B --- Natural minor

Repeat for all 12 natural-minor scales, preserving documented
relationships to standard major-scale fingering families.

### Phase C --- Harmonic minor

Normalize all 12 harmonic-minor scales, giving targeted scrutiny to F#,
C#, G#, Eb, and Bb. Record authoritative-source disagreement explicitly.

### Phase D --- Fixed-form melodic minor

Normalize all 12 fixed-form melodic-minor scales from contemporary/jazz
piano pedagogy. Flag exact hand/scale combinations for targeted
verification rather than filling gaps from low-authority charts.

### Phase E --- Derive the taxonomy

Once all 96 hand-specific records exist: compare normalized cycles;
identify identical and rotationally related structures; define fingering
families; derive the transition vocabulary; generate the
fingering-family Mermaid diagram; feed resulting components back into
the KeyRecall Q-matrix.

## 22. Bibliographic/Source Notes

### Clark, Michael. *Piano Basics*. Baylor University Libraries.

Open educational class-piano text and current primary source for
conventional major-scale pedagogy and harmonic-minor fingering research.

<https://openbooks.library.baylor.edu/pianobasics/>

### *Class Piano*. Indiana University Press.

Open university piano text containing sections on standard scale
fingering, scale groups, minor-scale forms, major/minor fingering
relationships, and irregular/mixed scale fingerings.

<https://publish.iupress.indiana.edu/projects/class-piano>

DOI: <https://doi.org/10.2979/ClassPiano>

### Sifter, Suzanna. *A Modern Method for Piano Scales*. Berklee Press.

Contemporary piano-scale method by a Berklee College of Music professor.
Preferred primary direction for fixed-form/jazz melodic-minor fingering
research.

<https://berkleepress.com/berklee-authors/suzanna-sifter/>

## 23. Document Status

This document currently records the **research framework and decisions
reached before exact 96-hand normalization**. It should not yet be
treated as the final canonical fingering table.

The next meaningful revision should contain actual normalized
`entry / cycle / exit` records for the major and natural-minor sets,
followed by the resolved harmonic- and fixed-melodic-minor sets.
