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

-   `entry`: how traversal begins at the initial tonic.
-   `cycle`: the repeating seven-note continuation from one tonic to the
    next internal tonic.
-   `terminal_override`: an optional replacement for continuation
    behavior when the final tonic is an endpoint rather than an internal
    octave boundary.

For example, C-major RH ascending is normalized as:

``` yaml
entry: [1]
cycle: [2, 3, 1, 2, 3, 4, 1]
terminal_override:
  final_finger: 5
```

This generates one, two, four, or arbitrary octave counts without
storing separate exercise fingerings. The internal tonic uses finger 1
so the scale can continue; the final tonic is overridden to finger 5.

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
transition such as `4 -> 1` can have different structural roles
depending on the scale: it may be a within-octave crossing in one
pattern and an octave-continuation crossing in another.

The final motor-family taxonomy remains intentionally deferred until
harmonic and fixed-form melodic minor have also been normalized.

## 9. Major-Scale Canonical Fingering

**Status: 12/12 scales and 24/24 hand-specific patterns normalized.**

The major-scale pass validated the `entry + cycle + terminal_override`
representation and identified substantial pattern reuse.

The table below uses one-octave terminal fingering strings for compact
human readability. These strings are summaries; the canonical model is
the normalized generative representation described above.

  Scale(s)        RH ascending   LH ascending
  --------------- -------------- --------------
  C, G, D, A, E   `12312345`     `54321321`
  F               `12341234`     `54321321`
  B               `12312345`     `43214321`
  Db              `23123412`     `32143213`
  F#              `23412312`     `43213214`
  Bb              `21231234`     `32143213`
  Eb              `31234123`     `32143213`
  Ab              `34123123`     `32143213`

Important boundary behavior:

-   C/G/D/A/E/B RH use finger 1 on an internal upper tonic but finger 5
    at the terminal upper tonic.
-   F RH similarly requires continuation/terminal distinction.
-   B-flat RH uses finger 2 at the initial tonic while recurring
    internal B-flats use finger 4.
-   Several black-key patterns require no terminal override because the
    recurring tonic fingering is also suitable at the endpoint.

The major-scale research also supports broader pedagogical organizations
that should inform later `MotorFamily` derivation:

-   C/G/D/A/E form the conventional CAGED group.
-   F RH and B LH are hand-specific exceptions to that system.
-   B/D-flat/G-flat share the two-black-key/three-black-key spatial
    organization.
-   B-flat/E-flat/A-flat share a flat-key spatial organization; their LH
    pattern is identical.

These are not yet frozen as runtime motor-family identifiers.

## 10. Natural-Minor Canonical Fingering

**Status: 12/12 scales and 24/24 hand-specific patterns normalized.**

Natural minor reuses much of the major-scale fingering vocabulary. The
canonical one-octave terminal summaries are:

  Scale(s)        RH ascending   LH ascending
  --------------- -------------- --------------
  C, D, E, G, A   `12312345`     `54321321`
  F               `12341234`     `54321321`
  B               `12312345`     `43214321`
  C#, G#          `34123123`     `32143213`
  Eb              `31234123`     `21432132`
  F#              `23123123`     `43213214`
  Bb              `21231234`     `21321432`

Notable exact reuse across major and natural minor includes:

-   C/D/E/G/A natural minor reuse the CAGED hand patterns.
-   F natural minor reuses the F-major RH exception and CAGED LH.
-   B natural minor reuses the B-major hand patterns.
-   E-flat natural minor RH matches E-flat major RH.
-   F-sharp natural minor LH matches G-flat major LH.
-   B-flat natural minor RH matches B-flat major RH.
-   C-sharp and G-sharp natural minor share identical RH and LH
    patterns.

Natural minor introduces only a small number of apparently new exact
tonic-relative patterns, principally:

``` text
C#/G# RH: 34123123
F# RH:    23123123
Eb LH:    21432132
Bb LH:    21321432
```

These may still prove to be phases or variants of broader motor
families, so no new `MotorFamily` identifiers are assigned yet.

The parallel-major relationship is useful pedagogical provenance, but it
should not be encoded as a software rule that derives minor fingering
from major fingering. Canonical fingering remains explicit domain data.

## 11. Harmonic-Minor Canonical Fingering

**Status: 12/12 scales and 24/24 hand-specific patterns normalized.**

The seven white-key-tonic harmonic minors retain the conventional
fingering of their parallel major scales. The five black-key-tonic cases
were then normalized individually.

Canonical one-octave summaries:

  Scale(s)        RH ascending   LH ascending
  --------------- -------------- --------------
  C, D, E, G, A   `12312345`     `54321321`
  F               `12341234`     `54321321`
  B               `12312345`     `43214321`
  C#, G#          `23123123`     `32143213`
  F#              `23123123`     `43213214`
  Eb              `21234123`     `21432132`
  Bb              `21231234`     `21321432`

As elsewhere in this document, these one-octave strings are compact
human-readable summaries rather than the authoritative runtime
representation. Continuation and terminal behavior are represented by
`entry`, `cycle`, and `terminal_override`.

Notable reuse across scale forms includes:

-   C/D/E/G/A harmonic minor reuse the CAGED hand patterns.
-   F harmonic minor reuses the F-major/F-natural-minor hand patterns.
-   B harmonic minor reuses the B-major/B-natural-minor hand patterns.
-   F-sharp harmonic minor is identical to F-sharp natural minor in both
    hands.
-   B-flat harmonic minor is identical to B-flat natural minor in both
    hands.
-   C-sharp and G-sharp harmonic minor share identical RH and LH
    patterns.
-   C-sharp/G-sharp harmonic-minor RH (`23123123`) is already present as
    F-sharp natural-minor RH.
-   C-sharp/G-sharp harmonic-minor LH (`32143213`) is already present in
    the major/natural-minor catalog.
-   E-flat harmonic-minor LH is unchanged from E-flat natural minor.
-   E-flat harmonic-minor RH shares the same recurring cycle as E-flat
    natural minor but uses a different initial entry finger.

The E-flat case is particularly useful for the domain model:

``` yaml
eb_natural_minor_rh:
  entry: [3]
  cycle: [1, 2, 3, 4, 1, 2, 3]

eb_harmonic_minor_rh:
  entry: [2]
  cycle: [1, 2, 3, 4, 1, 2, 3]
```

This demonstrates that two canonical fingerings can share the same
recurring motor structure while differing only at a boundary condition.

Harmonic minor therefore adds very little new exact motor vocabulary.
Its principal novelty is pitch topology, especially the characteristic
augmented second between scale degrees flat-6 and 7.

This further supports keeping pitch topology, exact fingering pattern,
motor family, and generated technical events as separate concepts.

## 12. Fixed-Form Melodic-Minor Canonical Fingering

**Status: 12/12 scales and 24/24 hand-specific patterns normalized.**

KeyRecall uses the fixed-form/jazz melodic-minor pitch collection:

``` text
1 2 b3 4 5 6 7
```

in both directions. The canonical fingering set is based on contemporary
piano pedagogy together with the established Schotte/Hanon convention
that harmonic- and melodic-minor fingerings generally coincide, with
C-sharp and F-sharp melodic minor as notable RH exceptions.

Canonical one-octave summaries:

  Scale   RH ascending   LH ascending
  ------- -------------- --------------
  C       `12312345`     `54321321`
  C#      `23123412`     `32143213`
  D       `12312345`     `54321321`
  Eb      `21234123`     `21432132`
  E       `12312345`     `54321321`
  F       `12341234`     `54321321`
  F#      `23123412`     `43213214`
  G       `12312345`     `54321321`
  G#      `23123123`     `32143213`
  A       `12312345`     `54321321`
  Bb      `21231234`     `21321432`
  B       `12312345`     `43214321`

These strings are compact terminal one-octave summaries. The
authoritative representation remains
`entry / cycle / terminal_override`.

For ten of the twelve scales, fixed-form melodic minor retains the
corresponding harmonic-minor fingering. The notable RH exceptions are
C-sharp and F-sharp:

``` text
C# melodic RH: 23123412
F# melodic RH: 23123412
```

The raised sixth changes the physical geometry near the upper end of
these scales. For example, F-sharp melodic minor uses:

``` text
C#3 -> D#4 -> E#1 -> F#2
```

rather than the harmonic-minor continuation through D natural.

### C-sharp and F-sharp provenance

The C-sharp and F-sharp RH choices deserve explicit research provenance
because modern sources are not perfectly uniform.

KeyRecall selects `23123412` for both C-sharp and F-sharp fixed-form
melodic minor because:

-   the Schotte-revised Hanon tradition identifies C-sharp and F-sharp
    melodic minor as fingering exceptions relative to harmonic minor;
-   an independent all-key melodic-minor fingering source gives the
    `23123412` RH pattern for both scales; and
-   the pattern has a coherent keyboard-geometric rationale around the
    raised sixth and seventh degrees.

For F-sharp in particular, an alternative RH pattern `23123123` is
reported by a contemporary piano reference. This should remain in the
research provenance as a legitimate reported alternative, but it is not
the KeyRecall V1 canonical fingering.

Suggested provenance record:

``` yaml
f_sharp_melodic_minor:
  right_hand:
    keyrecall_canonical: 23123412
    status: CANONICAL_SELECTED
    rationale:
      - Schotte/Hanon tradition identifies F# melodic minor as an
        exception relative to harmonic minor
      - independent all-key melodic-minor source reports 23123412
      - pattern fits the raised-sixth/raised-seventh keyboard geometry
    alternatives:
      - fingering: 23123123
        status: ALTERNATIVE_REPORTED
```

The same provenance principle applies to C-sharp where conflicting
modern material is encountered.

## 13. Complete V1 Scale Catalog

All four initial scale forms are now normalized: **48 scale definitions
and 96 hand-specific canonical fingering records**.

  --------------------------------------------------------------------------
  Tonic          Major          Natural minor  Harmonic minor Fixed melodic
                                                              minor
  -------------- -------------- -------------- -------------- --------------
  C              Normalized     Normalized     Normalized     Normalized

  C#/Db          Db normalized  C# normalized  C# normalized  C# normalized

  D              Normalized     Normalized     Normalized     Normalized

  D#/Eb          Eb normalized  Eb normalized  Eb normalized  Eb normalized

  E              Normalized     Normalized     Normalized     Normalized

  F              Normalized     Normalized     Normalized     Normalized

  F#             Normalized     Normalized     Normalized     Normalized

  G              Normalized     Normalized     Normalized     Normalized

  G#/Ab          Ab normalized  G# normalized  G# normalized  G# normalized

  A              Normalized     Normalized     Normalized     Normalized

  A#/Bb          Bb normalized  Bb normalized  Bb normalized  Bb normalized

  B              Normalized     Normalized     Normalized     Normalized
  --------------------------------------------------------------------------

The enumeration phase is complete. Subsequent work should derive
`MotorFamily` and `TechnicalEvent` structure from this corpus rather
than continue adding hand-authored fingering classifications.

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

The referenced pattern contains normalized entry/cycle/terminal-override
behavior required to generate arbitrary exercises.

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

## 20. Research Conclusions

1.  The V1 canonical enumeration is complete: 48 scale definitions and
    96 hand-specific fingering records.
2.  One canonical fingering per scale/hand remains the correct V1
    constraint.
3.  Canonical means KeyRecall's pedagogically grounded choice, not the
    only legitimate fingering.
4.  Source authority matters more than agreement count; meaningful
    disagreements should be preserved as provenance rather than exposed
    as competing V1 runtime choices.
5.  `entry + cycle + terminal_override` cleanly represents initial,
    recurring, and terminal behavior and generates arbitrary octave
    counts.
6.  Exact `FingeringPattern` and broader `MotorFamily` are distinct
    concepts.
7.  The completed corpus shows extensive cross-scale and cross-form
    fingering reuse; 96 canonical records correspond to far fewer than
    96 independent motor skills.
8.  Major, natural minor, and harmonic minor share substantial motor
    vocabulary. Fixed-form melodic minor likewise normally retains
    harmonic-minor fingering.
9.  C-sharp and F-sharp fixed-form melodic minor are notable RH
    exceptions and warrant preserved provenance.
10. Boundary behavior can differ even when the recurring cycle is
    identical, as demonstrated by cases such as E-flat natural versus
    harmonic minor.
11. Pitch topology and fingering must remain independent domain
    concepts: scale-form changes can preserve the entire motor pattern
    while changing required notes.
12. Descending-by-reversal is consistent with the completed V1
    fixed-pitch-collection dataset. Exercise-generation tests should
    still validate this mechanically rather than relying on an
    undocumented assumption.
13. Technical crossing events should be generated from canonical
    fingering data and retain structural role and keyboard geometry, not
    merely finger numbers.
14. `MotorFamily` classifications should now be derived from the
    complete corpus rather than assigned manually from pedagogical
    labels alone.

## 21. Next Analysis Pass --- Derive the Motor Taxonomy

With enumeration complete, the next step is structural analysis of the
96 canonical hand-specific records.

### 21.1 Exact pattern analysis

1.  Normalize every record to `entry / cycle / terminal_override`.
2.  Count distinct exact cycles and complete patterns.
3.  Identify exact reuse across tonics and scale forms.
4.  Identify patterns that differ only in entry or terminal boundary
    behavior.

### 21.2 Cyclic and geometric analysis

1.  Detect rotationally equivalent cycles.
2.  Compare hand- and direction-reversed structures.
3.  Identify shared keyboard-geometric organizations even when
    tonic-relative arrays differ.
4.  Distinguish exact-pattern families from broader physical
    `MotorFamily` relationships.

### 21.3 Technical-event derivation

Generate the transition vocabulary from the complete corpus, including:

-   hand;
-   direction;
-   from-finger and to-finger;
-   within-octave versus octave-boundary role;
-   entry, continuation, turnaround, and terminal roles; and
-   relevant white-key/black-key geometry.

### 21.4 Outputs

The analysis should produce:

1.  the V1 `MotorFamily` taxonomy;
2.  mappings from every canonical `FingeringPattern` to its motor family
    or families;
3.  the derived technical-event vocabulary;
4.  a Mermaid diagram showing motor-family relationships to scales,
    hands, and forms; and
5.  concrete revisions to the KeyRecall Q-matrix and learner-model
    components.

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

### Schotte/Hanon melodic-minor fingering tradition

Jim Funnell's discussion of the Schotte-revised Hanon editions documents
the convention that harmonic and melodic minor generally use the same
fingering, with C-sharp and F-sharp melodic minor as notable exceptions.

<https://funnelljazz.eu/tag/melodic-minor/>

### All-key melodic-minor fingering corroboration

An all-key melodic-minor fingering reference independently reports the
exceptional `23123412` RH pattern for C-sharp and F-sharp.

<https://hearandplay.com/main/the-fingering-of-the-melodic-minor-scale/>

### Reported F-sharp alternative

A contemporary piano reference reports `23123123` RH for F-sharp melodic
minor. This is retained as research provenance rather than the KeyRecall
V1 canonical choice.

<https://piano.org/scales/minor/melodic/f-sharp/>

## 23. Document Status

The V1 scale-fingering enumeration is complete.

This document now records canonical fingering results for all 12 major,
12 natural-minor, 12 harmonic-minor, and 12 fixed-form melodic-minor
scales: **48 scale definitions and 96 hand-specific canonical records**.

The next revision should no longer focus on scale-by-scale enumeration.
It should derive the `MotorFamily` taxonomy, technical-event vocabulary,
and corresponding learner-model/Q-matrix implications from the complete
canonical corpus.
