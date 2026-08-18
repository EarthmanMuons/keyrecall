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

The major- and natural-minor normalization pass confirms that a flat
one-octave digit string is insufficient as the authoritative
representation. Internal octave boundaries can use a different tonic
finger from an outer endpoint, and the initial tonic can likewise differ
from the recurring internal tonic.

The current representation is therefore:

``` text
FingeringPattern
    hand
    direction
    entry
    cycle
    terminal_override
```

- `entry`: how traversal begins at the initial tonic.
- `cycle`: the repeating seven-note continuation from one tonic to the
  next internal tonic.
- `terminal_override`: an optional replacement for continuation behavior
  when the final tonic is an endpoint rather than an internal octave
  boundary.

For example, C-major RH ascending is normalized as:

``` yaml
entry: [1]
cycle: [2, 3, 1, 2, 3, 4, 1]
terminal_override:
  final_finger: 5
```

This generates one, two, four, or arbitrary octave counts without storing
separate exercise fingerings. The internal tonic uses finger 1 so the
scale can continue; the final tonic is overridden to finger 5.

B-flat major RH demonstrates the complementary boundary case: the
practical initial tonic uses finger 2 while an internal B-flat uses
finger 4. Thus `entry` and `terminal_override` are independent boundary
conditions around the repeating cycle.

For the major and natural-minor scales normalized so far, conventional
descending fingering can be generated by reversing the complete
ascending finger stream. This remains a tested property of the current
dataset rather than a universal domain invariant until all scale forms
have been normalized.

## 8. Fingering Patterns, Motor Families, and Technical Events

The normalization work supports three distinct concepts:

``` text
FingeringPattern
    exact tonic-relative entry/cycle/boundary behavior

MotorFamily
    shared recurring physical or spatial organization

TechnicalEvent
    a specific transition generated while performing an exercise
```

The canonical `FingeringPattern` is authoritative domain data.
`MotorFamily` is derived only after comparing normalized patterns and
their keyboard geometry. A motor family therefore need not require
identical tonic-relative digit arrays.

For example, B, D-flat, and G-flat major use different tonic-relative
patterns but share the same broader two-black-key/three-black-key
physical organization. Likewise, B-flat, E-flat, and A-flat major share
a pedagogically meaningful flat-key organization even though their RH
patterns begin at different phases.

Technical events should also be derived from the canonical pattern. A
transition such as `4 -> 1` can have different structural roles depending
on the scale: it may be a within-octave crossing in one pattern and an
octave-continuation crossing in another.

The final motor-family taxonomy remains intentionally deferred until
harmonic and fixed-form melodic minor have also been normalized.

## 9. Major-Scale Canonical Fingering

**Status: 12/12 scales and 24/24 hand-specific patterns normalized.**

The major-scale pass validated the `entry + cycle + terminal_override`
representation and identified substantial pattern reuse.

The table below uses one-octave terminal fingering strings for compact
human readability. These strings are summaries; the canonical model is
the normalized generative representation described above.

| Scale(s) | RH ascending | LH ascending |
|---|---|---|
| C, G, D, A, E | `12312345` | `54321321` |
| F | `12341234` | `54321321` |
| B | `12312345` | `43214321` |
| Db | `23123412` | `32143213` |
| F# | `23412312` | `43213214` |
| Bb | `21231234` | `32143213` |
| Eb | `31234123` | `32143213` |
| Ab | `34123123` | `32143213` |

Important boundary behavior:

- C/G/D/A/E/B RH use finger 1 on an internal upper tonic but finger 5
  at the terminal upper tonic.
- F RH similarly requires continuation/terminal distinction.
- B-flat RH uses finger 2 at the initial tonic while recurring internal
  B-flats use finger 4.
- Several black-key patterns require no terminal override because the
  recurring tonic fingering is also suitable at the endpoint.

The major-scale research also supports broader pedagogical organizations
that should inform later `MotorFamily` derivation:

- C/G/D/A/E form the conventional CAGED group.
- F RH and B LH are hand-specific exceptions to that system.
- B/D-flat/G-flat share the two-black-key/three-black-key spatial
  organization.
- B-flat/E-flat/A-flat share a flat-key spatial organization; their LH
  pattern is identical.

These are not yet frozen as runtime motor-family identifiers.

## 10. Natural-Minor Canonical Fingering

**Status: 12/12 scales and 24/24 hand-specific patterns normalized.**

Natural minor reuses much of the major-scale fingering vocabulary. The
canonical one-octave terminal summaries are:

| Scale(s) | RH ascending | LH ascending |
|---|---|---|
| C, D, E, G, A | `12312345` | `54321321` |
| F | `12341234` | `54321321` |
| B | `12312345` | `43214321` |
| C#, G# | `34123123` | `32143213` |
| Eb | `31234123` | `21432132` |
| F# | `23123123` | `43213214` |
| Bb | `21231234` | `21321432` |

Notable exact reuse across major and natural minor includes:

- C/D/E/G/A natural minor reuse the CAGED hand patterns.
- F natural minor reuses the F-major RH exception and CAGED LH.
- B natural minor reuses the B-major hand patterns.
- E-flat natural minor RH matches E-flat major RH.
- F-sharp natural minor LH matches G-flat major LH.
- B-flat natural minor RH matches B-flat major RH.
- C-sharp and G-sharp natural minor share identical RH and LH patterns.

Natural minor introduces only a small number of apparently new exact
tonic-relative patterns, principally:

``` text
C#/G# RH: 34123123
F# RH:    23123123
Eb LH:    21432132
Bb LH:    21321432
```

These may still prove to be phases or variants of broader motor families,
so no new `MotorFamily` identifiers are assigned yet.

The parallel-major relationship is useful pedagogical provenance, but it
should not be encoded as a software rule that derives minor fingering
from major fingering. Canonical fingering remains explicit domain data.

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

Major and natural minor are now normalized. Harmonic minor is the next
research phase; fixed-form melodic minor follows it.

| Tonic | Major | Natural minor | Harmonic minor | Fixed melodic minor |
|---|---|---|---|---|
| C | Normalized | Normalized | High confidence; normalize next | Normalize |
| C#/Db | Db normalized | C# normalized | Verify C# exact fingering | Normalize C# |
| D | Normalized | Normalized | High confidence; normalize next | Normalize |
| D#/Eb | Eb normalized | Eb normalized | Verify Eb exact fingering | Normalize Eb |
| E | Normalized | Normalized | High confidence; normalize next | Normalize |
| F | Normalized | Normalized | High confidence; normalize next | Normalize |
| F# | Normalized | Normalized | Verify exact fingering | Normalize |
| G | Normalized | Normalized | High confidence; normalize next | Normalize |
| G#/Ab | Ab normalized | G# normalized | Verify G# exact fingering | Normalize G# |
| A | Normalized | Normalized | High confidence; normalize next | Normalize |
| A#/Bb | Bb normalized | Bb normalized | Verify Bb exact fingering | Normalize Bb |
| B | Normalized | Normalized | High confidence; normalize next | Normalize |

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

The referenced pattern contains normalized entry/cycle/terminal-override behavior
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

1. One canonical fingering per scale/hand is the correct V1 constraint.
2. Canonical means KeyRecall's pedagogically grounded choice, not the
   only legitimate fingering.
3. Source authority matters more than agreement count.
4. Major and natural minor are fully normalized at the hand-specific
   canonical-pattern level.
5. `entry + cycle + terminal_override` cleanly generates arbitrary
   octave counts while preserving initial, internal, and terminal tonic
   behavior.
6. Descending-by-reversal works for the complete major and natural-minor
   sets; it remains a tested dataset property until the remaining forms
   are normalized.
7. Exact fingering patterns and broader motor families are distinct
   concepts.
8. Major and natural minor show substantial cross-scale and cross-form
   motor-pattern reuse.
9. Motor families should be derived after all four V1 scale forms are
   normalized rather than assigned prematurely.
10. Technical crossing events should be generated from canonical
    fingering data and retain structural role, not merely finger numbers.
11. Harmonic minor has strong institutional coverage, with a small set
    of black-key cases requiring exact verification.
12. Fixed-form melodic minor should be sourced from contemporary/jazz
    piano pedagogy rather than classical descending-melodic-minor
    conventions.
13. Alternative fingerings can remain in research provenance without
    entering V1 runtime behavior.

## 21. Next Research Pass

### Phase C — Harmonic minor

Normalize all 12 harmonic-minor scales using the same representation now
validated by major and natural minor.

Begin with the seven high-confidence white-key tonics:

``` text
C D E F G A B
```

Then give targeted scrutiny to:

``` text
F# C# G# Eb Bb
```

For each hand:

1. establish the canonical fingering from the strongest available
   pedagogical source;
2. normalize it into `entry / cycle / terminal_override`;
3. verify arbitrary multi-octave generation;
4. test descending-by-reversal;
5. record exact pattern reuse with the existing major/natural-minor
   catalog; and
6. defer broader motor-family assignment until the complete V1 scale
   catalog is available.

### Phase D — Fixed-form melodic minor

After harmonic minor, normalize all 12 fixed-form melodic-minor scales
from contemporary/jazz piano pedagogy using the same process.

### Phase E — Derive the taxonomy

Once all 96 hand-specific V1 records exist:

1. compare normalized cycles and boundary behavior;
2. identify identical and rotationally related structures;
3. define `MotorFamily` classifications;
4. derive the technical-transition vocabulary;
5. generate the fingering-family Mermaid diagram; and
6. feed the resulting components back into the KeyRecall Q-matrix.

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

This document now contains normalized canonical fingering results for
all 12 major and all 12 natural-minor scales: **48 of the eventual 96
hand-specific V1 scale records**.

Harmonic minor is the next normalization phase, followed by fixed-form
melodic minor. Broader `MotorFamily` classifications remain provisional
until all four scale forms have been analyzed.

