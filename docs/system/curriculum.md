# Curriculum, goals, and focus

How a large catalog becomes a small, intentional practice surface without
changing what the learner model believes or adding family-specific policy to the
scheduler.

KeyRecall can represent far more technical material than any one player needs to
see. Domain breadth and practice breadth are therefore separate concerns:

```text
domain catalog -> curriculum -> goal -> focus -> scheduler -> realization
```

The catalog says what KeyRecall can represent. A curriculum describes a coherent
body of capability. A goal says what outcome this player is pursuing. A focus
says what to draw from right now.

> **Status:** structural scope resolution, requirement state, terminal outcomes,
> the acquisition floor, goal persistence, emphasis ranking, and the first focus
> surface are built. Named external curricula are proposed.

## The catalog is not the candidate pool

Adding modes or arpeggios to the catalog must not make them candidates for every
learner. Before candidate generation, the curriculum layer resolves the catalog
into three roles:

```text
target      directly contributes to the stated outcome
support     prepares a target but is not itself required for completion
excluded    takes no part in the active practice scope
```

Candidate generation operates over the target and support envelopes rather than
the whole catalog, and that is the primary control on pool growth. Admission,
challenge, ranking, and pacing then run normally over what remains.

A support relationship must be **declared** by the domain or curriculum. It
cannot mean "anything easier". An exam curriculum may retain a previously
introduced scale as support for its hands-together requirement; a strict custom
request may decline support outside the named materials while still allowing
easier realizations of those materials.

## Requirements describe capability, not lessons

A curriculum is a provenance-backed set of requirements, each describing an
observable capability in the common exercise vocabulary:

```text
CurriculumRequirement
    material family and material identity
    required execution conditions
    acceptable realization constraints
    performance or reliability criterion
    optional tempo criterion
```

A requirement does not prescribe an ordered lesson, a fixed exercise, or the
next selection. One- and two-handed preparation, cue fading, tempo progression,
and maintenance all remain consequences of the existing learner and scheduler
machinery.

Named curricula carry their source and edition. A syllabus update creates a new
definition rather than silently changing what a completed goal meant.

## Goals and focus answer different questions

A **goal** is a durable destination: what capability am I trying to establish or
maintain? A **focus** is a temporary constraint or preference: what should
KeyRecall draw from right now?

Focus has two explicit modes, and they are not two ends of one slider:

```text
exclusive    candidates outside the focus are not generated
emphasis     candidates stay eligible; matching ones gain goal relevance
```

"Only" and "prefer" have different semantics, and the product should say which
one it is applying.

Multiple goals combine their target requirements by union. An exclusive focus
then intersects that combined scope; an emphasis does not narrow it. A material
that is a target of any active goal stays a target rather than being demoted to
support by another.

The scheduler boundary:

```text
scope        controls which candidates may enter
Goal(e)      orders admitted candidates by current emphasis
REQUIRES     decides whether the learner is ready for an introduction
prediction   estimates challenge from learner state
```

Goal relevance must never override eligibility or challenge. It stays the last
weighted key in the priority order. A stronger focus that turns out to need
different scheduling has to be named and evaluated as policy, not smuggled into
competence, prerequisites, or difficulty.

## Scope never rewrites learner state

Changing a goal or focus controls selection opportunity and nothing else. It
does not delete, reset, rescale, or reinterpret attempt history, competency
state, exact-material memory, execution state, prerequisites, or challenge
predictions.

A material dropped from scope and restored later is exactly where it was.

## Caught up is not the same as blocked

Coverage and current scheduling demand are independent:

```text
coverage complete    every requirement has met its completion criterion
caught up            nothing in scope currently warrants practice
blocked              unresolved requirements exist, but no candidate is usable
invalid scope        one or more requirements cannot be resolved
```

A narrow curriculum can genuinely be caught up, and inventing work to keep the
loop busy would be a product defect. The player is told nothing in this focus
needs practice, and may review anyway, broaden, or stop.

`blocked` is a different thing entirely. A narrow catalog can be exhausted after
repeated supported failures: requirements remain unresolved, but every ordinary
and exceptional admission path is closed. **Calling that caught up would turn a
model failure into false progress.**

The scheduler cannot claim caught-up, and structurally could not: it sees
exercises, not curriculum requirements or due state, so it returns either
`CandidateSelected` or `SelectionBlocked`. `PracticeScopeEvaluator` derives
coverage and due state separately, and `PracticeSession` returns
`PracticeCaughtUp` without consuming a scheduler opportunity at all.

## The acquisition floor

A caller that knows requirements are unresolved may supply
`AcquisitionFloorEntry` realizations. The pipeline consults them only after
ordinary admission has produced nothing, and records the `acquisition_floor`
bypass when one wins.

The floor must:

- stay within the resolved target and support scope;
- ask the family for a safe entry realization through a common interface;
- preserve the factual-retrieval semantics of any guidance it supplies;
- appear as a named admission reason in the trace;
- activate only after ordinary admission has no candidate; and
- stay inactive when the curriculum is genuinely caught up.

This is a scheduler mechanism, not an exam or arpeggio branch. The scale family
supplies continuously cued, one-octave, ascending single-hand realizations.

Not to be confused with below-floor acquisition in [`practice.md`](practice.md),
which relaxes the task itself. The acquisition floor offers ordinary exercises.

## One scheduler, several families

Nothing above is scale-specific. A second material family enters through the
same catalog, curriculum, learner, and scheduling contracts, and a source-level
test prevents family policy from entering the scheduler package at all.

That claim is tested rather than asserted; see
[`../decisions/curriculum-and-progression.md`](../decisions/curriculum-and-progression.md).
