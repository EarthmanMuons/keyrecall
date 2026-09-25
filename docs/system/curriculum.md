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
> the acquisition floor, goal persistence, emphasis ranking, the first focus
> surface, and three KeyRecall goals are built. Examination curricula, several
> goals at once, and a per-requirement completion criterion are proposed; the
> sections below say which is which.

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

What the domain declares is always retained. A material that names another as
its prerequisite, as an inversion names its root position and an altered minor
form names its natural minor, brings that material into scope as support,
through any chain of them. Resolution keeps the curriculum's own requirements
over it where there are any, and otherwise makes one. Without that, an exclusive
focus on an altered form would exclude the one scale it waits for, and could
only end blocked.

Retaining it is not enough on its own, because a narrow scope offers only what
is due and coverage retires a requirement once it is demonstrated. Covered
support therefore stays **live** while a due requirement is barred in every
realization it asks for and waiting on that support's material, and is offered
only in the hand configurations it is waited on in. The scheduler says what a
barred exercise waits on; the session keeps the material live until nothing
does. Coverage itself is unchanged: live support is about what is offered, not
about what has been demonstrated.

A goal narrows realization as well as material. A requirement names a shape, and
a finite goal offers a material only on the way to what its requirements ask of
it: a span no wider than the target's, ascending before up and down, and each
hand alone before both where the material asks for that. Guidance and tempo are
not shape, so every more supported rung stays available. Support is offered on
the way to what it prepares, and a goal naming no shape, such as general
technique, offers everything. Live support is the one exception, drawn from
every realization, because what a barrier waits on need not be anything the goal
targets.

## Requirements describe capability, not lessons

A curriculum is a provenance-backed set of requirements, each describing an
observable capability in the common exercise vocabulary:

```text
CurriculumRequirement
    material family and material identity
    required execution conditions
    acceptable realization constraints
    optional tempo criterion
```

**Proposed:** a criterion per requirement. What is built is one completion
policy shared by every requirement in a build, `RequirementCompletionPolicy`,
which a requirement's own tempo criterion is read against. A requirement that
wanted a different standard of accuracy or reliability than its neighbors cannot
say so yet.

A requirement does not prescribe an ordered lesson, a fixed exercise, or the
next selection. One- and two-handed preparation, cue fading, tempo progression,
and maintenance all remain consequences of the existing learner and scheduler
machinery.

Named curricula carry their source and edition. A syllabus update creates a new
definition rather than silently changing what a completed goal meant.

## The goals KeyRecall offers

Three, each KeyRecall's own destination rather than an examination's.
Examination syllabi informed the material and its order; they are not what a
goal is named after, since no syllabus asks for exactly these sets.

| Goal              | Targets                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| General technique | every material in the catalog, in any realization, with no end point                                     |
| Foundations       | C G D A F Bb major and A E D G natural minor, each hand, one octave, up and down                         |
| 24-key fluency    | every major and natural-minor scale and root-position arpeggio, hands together, two octaves, up and down |

General technique grows with the catalog, so a family added later joins it, and
it makes no completion claim. Foundations is chosen for geography: both of the
two earliest admission bands, and three fingering families rather than one,
which is why it holds B flat major and not E major. 24-key fluency is at version
2, which added the root-position arpeggios once they were generated up and down.
Neither names an altered minor form, which extends a tonality rather than
defining it.

## Goals and focus answer different questions

A **goal** is a durable destination: what capability am I trying to establish or
maintain? A **focus** is a temporary constraint or preference: what should
KeyRecall draw from right now?

The difference is structural. Only the goal is stored, so it survives a relaunch
and a focus does not: a focus lasts as long as the running app, and choosing a
goal that holds none of its material clears it.

Focus has two explicit modes, and they are not two ends of one slider:

```text
exclusive    candidates outside the focus are not generated
emphasis     candidates stay eligible; matching ones gain goal relevance
```

"Only" and "prefer" have different semantics, and the product should say which
one it is applying.

**Proposed:** multiple goals combine their target requirements by union. An
exclusive focus then intersects that combined scope; an emphasis does not narrow
it. A material that is a target of any active goal stays a target rather than
being demoted to support by another. What is built resolves one goal, from a
registry of the goals this build knows; a stored identifier outside it fails
resolution rather than becoming a goal over the whole catalog.

A resolved requirement carries its roles rather than inheriting the one the
curriculum declared. An exclusive focus names the targets, and a requirement
outside it that prepares one is retained as support and takes no part in
coverage. Roles are not exclusive: a selected target that also prepares another
selected target is both.

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

The same holds for a change of goal. Coverage is never stored: it is read from
the journal against the active goal's requirements at each decision, so a switch
recomputes it and switching back reads the same history the same way. Each
hand's retrievals and live support are rebuilt from the journal too.

A focus names material rather than requirements, because requirements belong to
one goal and a focus outlives a change of goal. It resolves to whatever target
requirements the active goal holds over that material: a focus on C major means
both one-hand requirements under Foundations and the one hands-together
requirement under 24-key fluency. Material the goal does not hold is dropped,
and a focus the goal shares nothing with is no focus there. A focus the catalog
holds nothing of still fails, since widening it would read a request nothing can
satisfy as a request for everything.

## Caught up is not the same as blocked

Coverage and current scheduling demand are independent:

```text
coverage complete    every target has been demonstrated
caught up            nothing in scope currently warrants practice
blocked              unresolved requirements exist, but no candidate is usable
invalid scope        one or more requirements cannot be resolved
```

A target is covered when one recorded attempt at its shape met every criterion
the completion policy names: the exercise was played through, the material was
retrieved without cues, the pitches were accurate, the timing was fluent, the
hands were together where both played, and the measured pace reached the
requirement's tempo. Tempo is read as the requested tempo times the achieved
ratio, so what the learner played is what counts rather than what they were
asked for. A criterion the attempt carried no evidence about is unknown rather
than failed, and an unknown criterion does not cover.

Retrieval is read the way the requirement asks. By default any presentation that
tests retrieval will do, which includes notes shown before the attempt; a
requirement that asks for unguided retrieval is covered only when nothing was
shown first. Foundations and 24-key fluency ask for unguided, since they say
"from memory". This is coverage's reading and not the learner model's: a
previewed retrieval still counts as retrieval evidence about memory.

This is the curriculum's own policy and deliberately not the learner model's
evidence predicates. The learner asks what a performance says about the learner;
completion asks whether the performance demonstrated the requirement, which is
why it names pitch accuracy and coordination that the execution channel excludes
on purpose.

**Caught up is a memory claim, not an execution one.** Maintenance for a covered
target reads retrieval health alone. "Nothing needs practice now" therefore
means no retrieval maintenance is due; it does not mean the learner could
currently play every target to the standard that covered it.

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

## Open questions

Intentionally not settled. What is implemented is safe; the evidence to justify
stronger policy does not exist yet, and the current answer should not be read as
the decided one.

- **Pitch integrity and traversal length.** Completion reads a ratio, so the
  same number of wrong notes passes on a longer traversal and fails on a shorter
  one. Whether it should be an absolute allowance, or a ratio with one, is a
  calibration question for real practice data.

- **Cycles in support relationships.** Resolution terminates safely when support
  declarations form a cycle, which is not the same as deciding whether a cycle
  is meaningful, suspicious, or invalid. That belongs with curriculum
  validation, when authored curricula arrive.

- **Per-requirement completion criteria.** One `RequirementCompletionPolicy` is
  shared by every requirement in a build. Letting a requirement name its own
  standard stays proposed, and is worth revisiting alongside authored curricula.
