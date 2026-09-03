# Curriculum, goals, and focus

- **Status:** Structural scope resolution, requirement state, terminal practice
  outcomes, and acquisition floor implemented; goal persistence and emphasis
  ranking remain proposed
- **Written:** September 3, 2026
- **Scope:** How a large technical-material domain becomes a small, intentional
  practice surface without changing learner inference or creating
  family-specific scheduler policy

KeyRecall should be able to understand far more technical material than any one
learner needs to see. Domain breadth and practice breadth are therefore separate
concerns:

```text
domain catalog -> curriculum -> goal -> focus -> scheduler -> realization
```

The catalog says what KeyRecall can represent. A curriculum describes a coherent
body of capability. A goal says what outcome this learner is pursuing. A focus
changes what should be drawn from now. The scheduler still decides what is
useful next, and a material family realizes that request as an exercise.

This preserves the product promise at both extremes. A beginner can open a
small, curated practice surface without learning the ontology, while an advanced
learner can ask for a narrow mixture of scales and arpeggios and still let
KeyRecall choose the sequence.

## 1. The catalog is not the candidate pool

The domain catalog contains every installed `TechnicalMaterial`, realization,
and material family KeyRecall supports. It is capability, not learner intent.
Adding modes or arpeggios to the catalog must not make them candidates for every
learner.

Before candidate generation, the active curriculum layer resolves the catalog
into three roles:

```text
target      directly contributes to the learner's stated outcome
support     prepares a target but is not itself required for completion
excluded    takes no part in the active practice scope
```

Candidate generation operates over the target and support envelopes, not the
whole catalog. This is the primary control on pool growth. Admission, challenge,
ranking, and pacing then operate normally over the candidates that remain.

A support relationship must be declared by the domain or curriculum; it cannot
mean "anything easier." An exam curriculum may retain a previously introduced
scale as support for its hands-together requirement. A strict custom request
such as "only these scales and arpeggios" may decline support outside the named
materials while still allowing easier realizations of those materials.

## 2. Curriculum requirements describe capability

A curriculum is a provenance-backed set of requirements. Each requirement
describes an observable capability using the common exercise vocabulary rather
than naming a scheduler route:

```text
CurriculumRequirement
    material family and material identity
    required execution conditions
    acceptable realization constraints
    performance or reliability criterion
    optional tempo criterion
```

For example, an external syllabus requirement might resolve to:

```text
scale / D major / hands together / parallel / two octaves
arpeggio / D major / root position / hands together / two octaves
```

The requirement does not prescribe an ordered lesson, a fixed exercise, or the
next selection. One- and two-handed preparation, cue fading, tempo progression,
and maintenance remain consequences of the existing learner and scheduler
machinery.

Named curricula include their source and edition. A syllabus update creates a
new definition rather than silently changing what a completed goal meant. Custom
curricula use the same requirement representation and differ only in provenance.

## 3. Goals and focus answer different questions

A goal is a durable destination:

> What capability am I trying to establish or maintain?

A focus is a temporary selection constraint or preference:

> What should KeyRecall draw from right now?

Selecting an ABRSM grade can create a goal backed by that edition's curriculum.
Asking for minor scales this week applies a focus without replacing the goal.
Asking to practice a named set and ignore everything else applies an exclusive
focus over a custom curriculum.

Focus has two explicit modes:

```text
exclusive    candidates outside the focus are not generated
emphasis     candidates remain eligible; matching ones receive goal relevance
```

This is not one continuous weighting control. "Only" and "prefer" have different
semantics and the product should say which one it is applying.

Multiple goals combine their target requirements by union. An exclusive focus
then intersects that combined scope; an emphasis does not narrow it. A material
that is a target of any active goal remains a target rather than being demoted
to support by another.

The scheduler boundary is:

```text
scope        controls which candidates may enter
Goal(e)      orders admitted candidates by current emphasis
REQUIRES     decides whether the learner is ready for an introduction
prediction   estimates challenge from learner state
```

Goal relevance must not override eligibility or challenge. It remains the last
key in the established priority order. If stronger focus later proves to need a
different scheduling policy, that policy must be named and evaluated rather than
smuggled into competence, prerequisites, or difficulty.

## 4. Scope never rewrites learner state

Curriculum settings control selection opportunity only. Changing a goal or focus
does not delete, reset, rescale, or reinterpret:

- attempt history;
- transferable competency state;
- exact-material memory;
- material execution state;
- prerequisites; or
- challenge predictions.

If F major leaves the active scope for six months, its state continues to exist.
Restoring it exposes the same history after ordinary elapsed-time propagation.
The learner may have forgotten some of it; KeyRecall has not forgotten having
observed it.

Scope is selection context, so a durable scheduler decision records the goal,
curriculum edition, focus, and resolved scope version that produced it. That
context supports explanation and deterministic decision replay. It does not
become learner evidence. A focus change affects the next undecided slot and does
not alter an outstanding attempt.

Unknown or retired requirement identities are a configuration error, not an
empty practice result. A curriculum definition cannot quietly shrink because the
installed catalog failed to resolve part of it.

## 5. One scheduler, heterogeneous families

Scales and arpeggios should share one selection pipeline so the learner does not
have to allocate practice between parallel mini-apps. They must not share a
pretend-homogeneous domain model.

Each material family owns the semantics needed to produce generic candidates:

- topology and material identity;
- canonical fingering and provenance;
- motor realization;
- structural opportunities and observations;
- predictor loadings and difficulty characterization;
- transfer into existing learner states;
- any intentionally new learner states;
- curriculum-requirement matching; and
- family and strand keys used by generic pacing.

The scheduler may read those generic products. It must not ask whether a
candidate is an arpeggio, scale, mode, or advanced regimen pattern. In
particular, adding a family must add no scheduler stage and no concrete-family
branch.

Family introduction is not a special learner level. A new arpeggio may inherit
key familiarity, general keyboard geography, timing capability, and relevant
coordination evidence while remaining uncertain in arpeggio topology, hand-shape
transitions, and fingering. Shared and new state should make its challenge
emerge for this learner instead of relying on the assertion that "arpeggios are
harder than scales."

## 6. Completion, maintenance, and no selection

Curriculum coverage and current scheduling demand are independent:

```text
coverage complete    every requirement has met its completion criterion
caught up            nothing in scope currently warrants practice
blocked              unresolved requirements exist, but no candidate is usable
invalid scope        one or more requirements cannot be resolved
```

Coverage may remain complete while maintenance exercises become due. A narrow
curriculum may also be caught up, in which case inventing work to keep the loop
busy would be a product defect. The learner should be told that nothing in this
focus needs practice and may choose to review anyway, broaden the focus, or
stop.

`blocked` is different. The current scheduler can exhaust a narrow catalog after
repeated supported failures: requirements remain unresolved, but every ordinary
and exceptional admission path is closed. Calling that state caught up would
turn model failure into false progress.

Scheduler selection now returns either `CandidateSelected` or
`SelectionBlocked`; the scheduler cannot claim `CaughtUp` because it does not
receive curriculum requirements or due state. A caller that knows requirements
are unresolved may supply `AcquisitionFloorEntry` realizations. The pipeline
consults them only after ordinary admission blocks and identifies a successful
fallback with the `acquisition_floor` bypass.

The floor:

- stay within the resolved target/support scope;
- ask the family for a safe entry realization through a common interface;
- preserve the factual-retrieval semantics of any guidance it supplies;
- appear as a named admission reason in the trace;
- activate only after ordinary admission has no candidate; and
- remain inactive when the curriculum is genuinely caught up.

This is a scheduler mechanism, not an arpeggio or exam branch. The scale family
supplies continuously cued, one-octave, ascending single-hand realizations, and
simulation establishes that they keep the seven-material acquisition scope
actionable.

`PracticeScopeResolver` now resolves every requirement, support relation,
realization constraint, curriculum edition, and focus reference as one
all-or-nothing structural scope. `PracticeScopeEvaluator` separately derives
coverage and due state. `PracticeSession` invokes the scheduler and acquisition
floor only for due work, returns `PracticeCaughtUp` without consuming a
scheduler opportunity, and returns `PracticeInvalidScope` before scheduling.
General fluency retains its broad scheduling behavior; the due-work envelope and
acquisition floor apply to deliberate narrow scopes.

## 7. The arpeggio proof

Contrary motion is a valuable scale realization but is too close to the current
domain to test family extensibility. A deliberately small root-position major
arpeggio fixture now provides the adversarial second family. The mixed
curriculum proves all of the following:

1. Scale and arpeggio topology remain genuinely distinct.
2. Arpeggios declare both transferred and intentionally new learner state.
3. Both families produce the same generic scheduler candidate contract.
4. Admission, challenge, ranking, recovery, and pacing gain no family branch.
5. A curriculum requirement can target a realization from either family.
6. One goal can contain both families and produce one next-exercise stream.
7. A strict custom focus can name arbitrary members of both.
8. Disabling and restoring either family leaves learner state unchanged.
9. Coverage and maintenance can be derived across the mixed requirement set.
10. Exhaustion distinguishes caught-up from blocked behavior in both families.

The proof contains C, G, and D major root-position arpeggios, and its mixed
pseudo-curriculum contains scale and arpeggio requirements. It is not a product
catalog. Its one-octave fingering, acquisition floor, progression, family
transfer coefficient, and foundation admission band are provisional architecture
fixtures. Each needs provenance and validation before arpeggios become
learner-facing. See [`arpeggio-family-proof.md`](arpeggio-family-proof.md) for
the exact boundary.

## 8. Product surface

The default experience should select a curated general-technique curriculum and
start practice. It should not expose the catalog as an onboarding checklist.

A later goals surface can offer named curricula, a custom material set, and a
temporary focus. Its compact contract is:

> The learner chooses what they are working toward when they care to. KeyRecall
> decides what to practice next.

Progress should report requirements covered separately from work currently due.
When an intentionally narrow focus is caught up, that is a successful outcome,
not pressure to broaden it.
