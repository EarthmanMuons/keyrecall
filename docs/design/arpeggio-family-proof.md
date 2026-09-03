# Heterogeneous material-family proof

- **Status:** Implemented architecture fixture; not learner-facing curriculum
- **Last aligned:** September 3, 2026

## Purpose

The arpeggio fixture tests whether a material family with non-scalar topology
can use the existing catalog, curriculum, learner, and scheduling contracts. It
does not establish a piano-arpeggio curriculum.

The proof succeeds when adding the family requires domain semantics but no
scheduler stage, scheduler family branch, practice-session family branch, or
curriculum special case. A source-level scheduler boundary test prevents
arpeggio policy from entering that package.

## Fixture domain

`proofArpeggios` contains C, G, and D major root-position arpeggios. Inversion
is part of material identity even though only root position exists in the
fixture. The available realizations are one octave, upward, at the initial
tempo, in either single hand or hands together, across the ordinary guidance
ladder.

The C, G, and D root-position fingerings are sourced; notably, D major uses
left-hand `5 3 2 1` rather than C and G's `5 4 2 1`. The safe entry remains
provisional. The family supplies a continuously cued right-hand realization as
its acquisition floor, unlike the scale family's two single-hand entries. The
scheduler evaluates and ranks either floor through the same generic path.

## Learner state

Arpeggio topology, right- and left-hand arpeggio execution, the arpeggio
transition, exact-material memory, and material-hand execution residuals are new
state. Hands-together coordination transfers directly because it is an existing
shared competency. Same-hand scale execution contributes a bounded,
uncertainty-shrunk prediction-only adjustment to arpeggio execution; it never
writes scale evidence into arpeggio state.

The transfer coefficient is provisional. The live learner model is versioned
separately from the frozen prototype because the competency registry and
prediction semantics changed.

## Mixed curriculum canary

`PSEUDO_TECHNIQUE_1` exists only as a test fixture. It establishes that:

- one resolved scope and candidate envelope can contain both families;
- stable requirement identity remains distinct from material identity;
- hard focus can retain an arbitrary scale and arpeggio together;
- family assessment aggregates into common coverage and due state;
- acquisition-floor entries remain requirement-directed; and
- the common scheduler presents work across beginner, experienced, and advanced
  placement priors.

Arpeggio inversions, multi-octave work, a complete provenance-backed fingering
dataset, tempo targets, examination requirements, introduction order, and
learner-facing UI remain outside this proof. The evidence, current domain
decisions, and promotion gates are recorded in
[`arpeggio-domain-research.md`](../domain-model/arpeggio-domain-research.md).
