# Roadmap

Ideas KeyRecall has intentionally deferred, and ideas it has closed.

**Not a roadmap commitment, release sequence, or alternative specification.**
What the system does is [`system/`](system/); why it does it is
[`decisions/`](decisions/). This is what it deliberately does not do.

The simplicity of the current design should not erase promising architectural
seams, and an old idea should not regain authority merely because it appears in
a planning document. So every item here is one of three things:

```text
reserved extension
    the architecture has an intentional place for it
    evidence must still justify activating that seam

deferred hypothesis
    plausible and worth testing, but its representation is not decided

domain or product expansion
    valuable scope beyond the initial scale-focused implementation
```

The general admission rule:

> Preserve the architectural seam now. Add latent state or policy only when
> replayable real observations show that the simpler current representation has
> a repeatable, identifiable failure.

A new competency or prediction channel must additionally follow
[`research/extending-the-model.md`](research/extending-the-model.md).

## Reserved architectural extensions

### Transient session state

V1 does not model warm-up or fatigue. Its current `SessionState` contains only
the attempt count, recent-material history, and exact recovery context. This is
a deliberate scope boundary, not an architectural oversight.

Warm-up, fatigue, current readiness, and similar short-lived effects do not
belong in:

- persistent transferable competency;
- exact-material memory; or
- persistent material/context execution residuals.

They are candidate **transient latent state**: temporary changes in how well
held capability is expressed during a practice session.

The reserved decomposition is:

```text
persistent capability
    transferable competencies
    exact-material memory
    material/context residuals

transient readiness
    session-wide execution deviation
    eventually, distinguishable warm-up and fatigue components

task
    nominal exercise difficulty

observed performance
    persistent capability + transient readiness - difficulty + noise
```

The main value is attribution correctness. Without a transient explanation,
broad temporary underperformance can become negative evidence about persistent
competencies and material residuals.

#### 2.1.1 Start with one execution offset

The first useful model should not begin with separate sophisticated warm-up and
fatigue processes. It should test whether real histories identify one uncertain,
session-wide motor-performance offset:

```text
session_execution_offset
session_execution_uncertainty
```

The execution predictor would become:

```math
\eta_{\mathrm{exec}}(e,t) =
\sum_{k\in K_{\mathrm{motor}}}q^{(\mathrm{motor})}_{e,k}\widetilde\mu_k
+ \mu_{r,m,c}
+ s_u(t)
- D_{\mathrm{motor}}(e)
```

where `s_u(t)` is transient and session-local. The transient state must not
persist as ordinary long-term ability. Whether a future estimator resets it
between sessions, carries a decayed prior, or models recovery across measured
rest is an empirical design question.

The first estimand is not “fatigue” or “warm-up.” It is narrower:

> Current motor performance is temporarily better or worse than the persistent
> learner state predicts.

That is closer to what MIDI evidence can support and avoids medical or causal
claims the observations cannot establish.

#### 2.1.2 Require diverse cross-task evidence

One poor exercise must not create a session-state diagnosis. An F-sharp minor
failure could reflect material memory, the F-sharp residual, a crossing
competency, requested difficulty, or ordinary noise.

Evidence for a shared transient cause becomes more credible when unexpected
execution error appears across materially and structurally diverse tasks, for
example:

```text
F-sharp minor RH
C major LH
G major HT
D minor RH
```

The empirical question is:

> After conditioning on persistent competencies, material/context residuals,
> guidance, task difficulty, and known observation noise, do execution errors
> share a within-session component across unrelated exercises?

The estimator should require multiple diverse observations and retain broad
uncertainty. Repeated trouble on one material is evidence for a local residual,
not session-wide state.

#### 2.1.3 Warm-up and fatigue are interpretations of temporal shape

If a shared transient factor is identifiable, its within-session trajectory may
support more specific hypotheses.

Warm-up-like behavior:

```text
session start
    unexpectedly weak execution across varied tasks

initial activity
    rapid broad improvement toward persistent prediction

later
    stable performance
```

Fatigue-like behavior:

```text
session start or middle
    performance near persistent prediction

accumulated workload
    broad execution deterioration

continued workload
    persistent or worsening decrement
```

A later model might decompose the transient effect as:

```math
s_u(t)=W_u(t)-F_u(t)
```

with a short-lived warm-up deficit `W` that dissipates through activity and a
fatigue term `F` that accumulates through workload and recovers through rest.
This factorization is a deferred hypothesis. It should not be implemented until
the simpler shared offset is identifiable and the two temporal signatures are
separately supported.

#### 2.1.4 Session state must change evidence attribution

The complete extension is more than a scheduler heuristic. Session state should
participate in three places:

```text
session state
    -> modifies conditional execution prediction
    -> changes attribution of execution residuals
    -> informs scheduler challenge and safety decisions
```

Suppose persistent state predicts strong execution but several late-session,
unrelated attempts underperform. If a session adjustment explains that pattern,
the estimator should avoid attributing the full residual to long-term
competencies and material residuals.

Conceptually, poor execution creates competing explanations:

```text
observed execution error
    -> transferable competency evidence
    -> material/context residual evidence
    -> transient session-state evidence
```

Attribution must depend on structural exposure, material locality, cross-task
covariance, temporal position, workload, and uncertainty. A session factor must
not become a convenient sink that masks genuine persistent weakness.

#### 2.1.5 Keep the first session effect out of memory

The initial extension should affect only the motor execution channel. It should
not change:

```text
independent retrieval
current or retained durability
consolidation inference
factual retrieval history
```

Transient attention may affect retrieval in reality, but that distinction is
harder to identify and is not required to protect motor competency estimates.
The first semantic boundary should be:

> Session readiness changes how well currently held motor capability is
> expressed; it does not rewrite what the learner knows or how durable that
> knowledge is.

#### 2.1.6 Scheduler integration should mostly emerge from prediction

Once the session offset changes conditional execution, the existing prediction
pipeline naturally changes candidate admission:

```math
\widehat p_{\mathrm{exec}}(e,t)
\longrightarrow
\widehat p_{\mathrm{overall}}(e,t)
```

A negative transient offset can move harder candidates below the ordinary
challenge band and shift the set of candidates that fall within it. Recovery of
the offset can expand the challenge set again. This is cleaner than adding a
fatigue penalty to priority ranking or a special class of “warm-up exercises.”

A separate hard safety/workload policy may still suggest a break or stop after
an unusually long or demanding session. It must remain conservative and
non-diagnostic. Prediction adaptation and workload safety answer different
questions and should not be collapsed into one fatigue score.

#### 2.1.7 Preserve the evidence needed now

V1 should log enough local, replayable context to test the session hypothesis
later:

- practice session identifier;
- attempt-slot and selection ordinal within the session;
- exact timestamps and inter-attempt gaps;
- cumulative active practice time when reliably measurable;
- exercise difficulty dimensions;
- prediction components before the attempt;
- continuity, stability/evenness, achieved tempo, synchronization, and localized
  execution observations;
- material and competency structural exposures;
- guidance and recovery context; and
- reliable pause or app-backgrounding events, if available.

This supports questions such as:

```text
first few selections systematically underperform?
    possible warm-up-like shape

late selections systematically underperform?
    possible fatigue-like shape

effect weakens after a break?
    stronger transient-recovery evidence

effect spans unrelated motor structures?
    stronger session-wide evidence

effect remains confined to one material?
    prefer the material residual
```

#### 2.1.8 Characterization and admission gate

Synthetic characterization should contrast at least:

```text
stable learner
    no session effect

warm-up learner
    unchanged persistent skill; early transient execution deficit that fades

fatigue learner
    unchanged persistent skill; late broad execution deficit

material-weak learner
    local persistent deficit; no session effect

competency-weak learner
    related-task persistent deficit; no session effect

mixed learners
    warm-up plus genuinely weak competency
    fatigue plus genuinely weak material
```

The model must avoid:

- inferring fatigue from one noisy attempt;
- mistaking material-local weakness for session state;
- mistaking persistent competency weakness for warm-up;
- permanently changing competencies because of a transient truth;
- using session state to mask genuine long-term decline; and
- contaminating retrieval or durability estimates.

Real-data admission additionally requires:

- repeatable conditioned within-session residual structure;
- coverage across varied materials, execution contexts, workloads, gaps, and
  learner ability;
- held-out improvement in execution calibration;
- reduced corruption of persistent state under later observations;
- stable retrieval calibration;
- scheduler consequence characterization under the unchanged policy; and
- an observable pre-decision signal strong enough to affect prediction safely.

This is a post-V1 structural extension. It adds a fourth learner-state layer and
changes prediction/evidence attribution, so it must clear a higher bar than a
routine competency addition.

### New prediction and outcome channels

V1 separates retrieval, supported availability, conditional execution, bilateral
coordination, and topology. Rich observations such as expressive timing or
velocity control are not automatically latent state.

If a future capability answers a genuinely new question and should influence
prediction or challenge admission independently, it may require a new channel
with its own:

- latent state and uncertainty;
- prediction;
- observed outcome;
- prediction error;
- evidence weights;
- update path; and
- scheduler consequence analysis.

This is a structural change, not a competency-enum addition. The distinction and
admission workflow are defined in the competency extension guide.

### Execution evidence at the achieved motor difficulty

This extension is implemented. A learner who plays a requested 120 BPM exercise
perfectly evenly at 60 BPM still scores the performance that occurred for
continuity and stability, while execution surprise is evaluated at 60 BPM.

The fix is not to damp `motorScore`, which would conflate two separate
questions:

```text
how well did the motor execution go?
how difficult was the motor execution that actually occurred?
```

The execution channel evaluates its evidence at the difficulty of the
performance that happened:

```text
requested difficulty   difficulty(conditions at the requested tempo)
observed difficulty    difficulty(conditions at min(requestedTempo,
                                                     requestedTempo * achievedTempoRatio))

execution evidence attributed at the observed difficulty
every other channel evaluated normally
```

This adds no constant and no curve: the model already expresses how tempo
changes motor difficulty, and this reads that function at the tempo actually
sustained. Intermediate cases need no policy, since 93% of target is evidence at
93% of the tempo. Credit is capped at the requested tempo because the scheduler
chose that challenge; playing faster does not turn the attempt into an
unscheduled harder probe.

It must stay execution-specific. Slow, careful practice genuinely strengthens
factual scale memory, so achieved tempo may not touch retrieval, topology, or
causal memory formation.

An attempt with no measurable positive pace is attributed at the requested tempo
rather than at zero BPM, and records no performed tempo at all: a ratio of zero
says nothing was measured, so filing it as a pace would put the learner at the
bottom of the ladder. `LearnerModel.v1Prototype` retains the earlier attribution
semantics for historical replay; production models use demonstrated difficulty.

### Population and hierarchical calibration

The app should continue learning each individual locally. Optional, minimized,
longitudinal telemetry may later improve the shared model through:

- population-informed placement priors;
- calibration families for learning, diffusion, and evidence strength;
- estimated transfer relationships;
- fitted residual pooling;
- material and exercise difficulty effects;
- uncertainty calibration; and
- only after sufficient data, more sophisticated scheduling policies.

This preserves two separate learning systems:

```text
the app learns this pianist
    local history and immediate adaptation

the project learns how pianists learn
    optional aggregate evidence and versioned model refinement
```

Population fitting must not become a prerequisite for local operation.

## Learner-model extensions

### Performance envelopes

V1 maintains interpretable latent state and rich outcomes but does not model a
complete performance envelope. Future learner-facing or predictive summaries may
distinguish:

- reliable tempo under defined conditions;
- frontier tempo;
- variability around each tempo;
- first-attempt reliability;
- delayed retrieval reliability;
- hands-together synchronization range;
- robustness across direction, octave span, register, articulation, or rhythm;
  and
- recovery after error.

An envelope should not become a bag of independent mastery scores. Some values
may be derived from the existing predictor across task conditions; others may
need new state only if longitudinal evidence shows persistent, separately
identifiable variation. Derived envelopes must remain conditional on task
definition, including relevant material, hands, octave span, direction, and
guidance.

### Competency growth

The V1 state/update machinery is designed to admit future competencies without
rewriting memory or scheduler stages. Residual covariance may reveal missing
transferable structure across materials.

All proposals follow the competency extension guide: identifiability,
nonredundancy, transfer, observational replay, held-out calibration, unchanged-
policy scheduler characterization, and deterministic state migration.

### Richer performance-control dimensions

Possible future dimensions include:

- pulse stability;
- subdivision evenness;
- tempo tolerance;
- velocity consistency;
- dynamic balance;
- articulation control;
- repeated-note control; and
- expressive timing.

Many already belong in preserved observations. They should become competencies
or prediction channels only when data establish persistent, useful, and
identifiable learner differences after conditioning on current motor state,
material residuals, difficulty, and session effects.

## Scheduler and product extensions

### Explicit user goals and focus

The proposed contract now lives in
[`curriculum-and-focus.md`](system/curriculum.md). It separates the installed
domain catalog, provenance-backed curricula, durable learner goals, and
temporary focus. Scope controls candidate admission while `Goal(e)` expresses
soft emphasis among admitted candidates.

Future goals may include:

- exam or curriculum requirements;
- a selected scale-form or minor-scale focus;
- arpeggio preparation;
- target tempos or performance dates;
- temporary focus areas;
- free-practice requests; and
- explicit learner overrides.

Goal relevance belongs in the established goal term and product constraints. A
hard "only these" focus instead narrows the candidate scope. Neither mechanism
may redefine learner competence, evidence, prerequisites, or challenge
prediction, and changing either must preserve all learned state.

### Acquisition, development, and maintenance as practice regimes

V1 does not store acquisition/development/maintenance as discrete learner
states. The continuous probabilistic model already represents capability and
uncertainty more faithfully.

The deferred question is whether derived learner/material relationships should
change practice methodology:

```text
acquisition-like
    more guidance and supported repetition

development-like
    progressive cue fading, variable challenge, delayed tests

maintenance-like
    wider spacing and more interleaved independent retrieval
```

These should remain derived policy regimes, not authoritative latent labels.
Their value must be tested against the existing prediction and evidence model.

### Immediate repetition as an episode, not as several attempts

Repeating an exercise until it is right is pedagogically reasonable during
acquisition, and implementing it as "keep committing attempts until three
succeed" would be a mistake. Four immediate repetitions of one scale are not
four independent demonstrations of durable retrieval; they are one acquisition
episode with internal repetition, and feeding each into the memory clocks as an
ordinary scheduled attempt manufactures confidence quickly and quietly.

The distinction to preserve:

```text
rehearsal repetition    immediate repeats that establish the movement
retrieval observation   an attempt separated enough to be evidence of retention
```

If this is built, the unit should be an episode carrying its repetition history,
so what it means for the learner model is decided once and explicitly, rather
than emerging from how many records were appended.

V1 deliberately does not have it. The scheduler chooses one evidence-bearing
attempt at a time, and a deliberate "repeat this exercise" affordance is the
cheaper way to learn whether learners want immediate repetition at all, before
repetition is encoded into scheduler policy.

### Free practice, separate from scheduled practice

Playing before an attempt begins is warm-up: the keyboard shows it and nothing
records it. The transcript starts at Ready, which is what keeps exploratory
notes from making an attempt look started and from becoming insertions in an
alignment.

A real free-practice mode would be an explicit product mode rather than
something inferred from pre-start playing:

```text
scheduled practice   evidence-bearing, scheduler-controlled, attempt boundaries matter
free practice        learner-controlled, no progression, live feedback only
```

Measurement in free practice could eventually give descriptive feedback, and
even then it should not update the learner model unless that evidence path is
deliberately defined.

### Adaptive contextual-interference intensity

V1 implements a diversity term and repetition guard. A richer hypothesis is that
useful interleaving depends on current stability:

```text
early acquisition
    more blocked or narrowly varied practice

developing stability
    increasing variation among related tasks

established performance
    highly mixed retrieval and transfer practice
```

Contextual-interference effects are task- and learner-dependent. Any adaptive
policy must be characterized under unchanged learner semantics and clear
forward-learning outcomes, not justified by diversity for its own sake.

### Fatigue-aware workload and rest policy

A credible transient session estimate could inform challenge and safety. The
scheduler might avoid sustained highest-demand work, diversify overloaded
movement, or recommend a break.

Two related forms of state must remain distinct:

```text
workload facts
    elapsed active time, repetitions, breaks, task demand

transient performance estimate
    inferred deviation from persistent execution capability
```

Safety policy must not wait for a latent fatigue inference to become reliable.
Conservative workload constraints can remain direct, and neither path should
claim to diagnose injury or medical risk from MIDI behavior.

### Preserve the sessionless UX

Future scheduler intelligence remains constrained by a core product principle:

> Open the app, play what it gives you, and stop whenever you want.

There is no “behind” state. Lookahead is soft and revisable. New goals,
maintenance regimes, fatigue adaptation, or population-trained policies must not
turn practice into a rigid calendar or punish irregular use.

### Material admission by prerequisite, not by tier

The first material-admission policy is implemented, and
[`material-admission.md`](decisions/curriculum-and-progression.md) records it.
What remains reserved is the axis it approximates: the gate reads a
curriculum-derived band prior because nothing measures whether a hand pattern is
already established.

The gate should not encode a tier number or an ordering by how hard a fingering
looks. Novelty arrives on three independent axes, and a single sequence cannot
express them:

```text
material familiarity     pitch and topology knowledge of related material
motor familiarity        whether the fingering family is already established
notation complexity      if and when staff decoding participates
```

The distinction that makes this worth building is **new pitches with familiar
fingers** against **new fingers**. The current offer contains both: A, E, and D
natural minor reuse the C major fingering family entirely, so they are new
material over established motor structure, while B flat major introduces a
different entry and cycle. Those are different kinds of difficulty and a tier
list would rank them as one.

Sketched, not decided, and the part still unbuilt:

```text
A natural minor      requires the C-major-family hands
                     does not require prior minor material

B flat major         requires stronger single-hand execution, since it
                     introduces a new entry and cycle

C sharp harmonic     requires both stronger material familiarity and
minor                established black-key entry

```

The empirical inputs that would settle it come from practice rather than from
the fingering taxonomy: whether unfamiliar minors appear with enough support to
learn, whether the scheduler returns to new material soon enough after first
exposure, and whether the natural minors do transfer as cheaply as their shared
fingering suggests.

### The cold-start regime: placement priors against the challenge band

Measured, not conjectured. A census of all 6,912 generated candidates at slot
zero, with every material already seen so the unseen-material rule is not what
is being measured:

| Placement tier   | Fully eligible | Below band | In band | Best reachable `p` |
| ---------------- | -------------: | ---------: | ------: | -----------------: |
| `beginner`       |            240 |        240 |   **0** |          **0.283** |
| `someExperience` |          1,728 |      1,728 |   **0** |          **0.513** |
| `advanced`       |          6,912 |      5,088 |   1,824 |              0.730 |

The easiest exercise the catalog can produce is the same for all three: C major,
right hand, one octave, 60 bpm, continuously cued. Against `pMin = 0.60`, **two
of the three placement tiers cannot reach the challenge band at any exercise**,
and the third only just does.

`beginnerMean = -1.0`, `someExperienceMean = 0.0` and `pMin = 0.60` are each
defensible alone. Together they define a regime nobody chose: for the majority
of new learners the ordinary "not too easy, not too hard" path is inert, and
every attempt is admitted by a named bypass instead. A traced beginner sitting
confirms it — across sixteen consecutive attempts, `challengeBypass` was never
null.

That may be a coherent operating mode. A beginner genuinely is meeting
everything for the first time, and `pIntroductionMin = 0.15` exists to carry
exactly that. Two things about it are harder to defend.

**It applies to `someExperience`.** That tier describes somebody who can already
play a familiar scale one-handed, and it is what the app assumed for every
profile before placement was asked for. Introduction-only is a strange
description of them.

**The prerequisite gates lost their force under it, until they were made part of
admission.** Challenge admission is stage 3 and eligibility ranking is stage 4,
so the tier ordering could only sort what admission let through, and
`new_material` was admitting anything unseen. The introduction exception is now
stratified: it may bypass challenge difficulty, but while the slot holds an
introducible candidate in a higher eligibility tier, a lower one is not
reachable through it at all. For `someExperience` that removed provisional
selections from an early sitting entirely, and `advanced` was unaffected.

What it does not remove is the underlying scarcity. A beginner has five
foundation materials, and once all five have been met every remaining
introduction is provisional, so the deliberate fallback engages and
early-transfer material starts appearing around the thirteenth attempt. That is
the specified behavior rather than a leak — provisional means deferred while
something better exists, not forbidden — but it means the real question is
narrower than it looked:

> once a beginner has met the foundation, should the scheduler introduce less
> appropriate material, or stop introducing and consolidate what they have?

Answered by consolidating, and the answer was forced rather than chosen. A
census of the slot where it goes wrong found **no seen fully eligible candidate
surviving admission at all**: not in the ordinary band, no rung established so
the guidance probe could not climb, the bootstrap probe days away, and the
observation probe counting supported attempts that a previewed introduction
resets. Introducing was the only move the scheduler had, which is why
introducing is what it kept doing.

So consolidation is an admission exception rather than a ranking preference —
there was nothing to prefer. It offers a met and unretrieved scale at the
previewed rung when the slot has nothing appropriate left to introduce, and goes
quiet once that scale has been produced from memory. No refusal against the
introduction beside it is needed: the tier leads the ranking key, so fully
eligible consolidation outranks provisional novelty wherever both apply.

So the open question is not which floor to nudge. It is whether the intended
cold-start mode is introduction-driven, and if so, what should aim the
introductions once the appropriate material runs out. Candidate directions, none
yet argued for:

- a lower `pMin` for learners whose estimates are still near their placement
  prior, so ordinary admission can operate at all;
- placement priors set against the band rather than independently of it;
- an introduction envelope that respects the admission bands, so "new material"
  means the next appropriate material rather than any unseen material;
- accepting introduction-only as the intended cold start and making the bands
  the thing that orders introductions.

Resolved: the hands-together prerequisite was a floor on the two hand-execution
means, so whether a tier got hands-together work immediately was decided by the
equality semantics of two numbers set independently. It now asks for evidence
about the work in front of the learner - both hands having managed that scale at
that span - which is also what supplies the entry tempo.

### A sitting with nothing to offer

`_NothingToPlay` remains an error state in the app. Scheduler absence is no
longer ambiguous: `SchedulerPipeline.decide` returns `CandidateSelected` or
`SelectionBlocked`, with admission exhaustion named as a blocked reason.

A learner who fails most of what they are given has each material walked toward
support by recovery. Cued attempts never observe retrieval, so nothing
re-anchors, and when there is nothing left to introduce instead the slot admits
nothing at all. Over the seven-material catalog a true beginner reaches it by
slot eleven and in three quarters of runs within a hundred and twenty slots;
over the shipped forty-eight it never happens, at three times the length of a
sweep. So breadth is an escape rather than a delay.

It is a live path rather than a stress fixture, because a goal aimed at a
handful of scales recreates the narrow catalog exactly. Scoped goals now resolve
through stable curriculum requirements before a practice decision is made.

The scheduler now accepts family-declared `AcquisitionFloorEntry` realizations
from a caller that knows requirements remain unresolved. It consults them only
after ordinary admission blocks, keeps them inside the supplied candidate scope,
and runs them through ordinary safety, eligibility, ranking, guards, and pacing
under the named `acquisition_floor` bypass. No declared entry and a declared
entry rejected by those remaining stages are distinct blocked reasons.

The scale family supplies continuously cued, one-octave, ascending single-hand
entries. They prevent the seven-material true-beginner trajectory from running
dry in `keyrecall_simulation/test/sitting_ran_dry_test.dart`.

`PracticeScopeResolver` rejects unknown identities, family mismatches,
unrealizable constraints, dangling support, invalid focus, and unsupported
registered editions without returning a partial scope. Requirement evaluation
keeps coverage orthogonal to due and actionable work. `PracticeSession` can
therefore return selected, blocked, caught-up, or invalid-scope outcomes with
the correct layer ownership and opportunity accounting.

### Spend the slot after coordination is earned

**The prerequisite is settled.** It read the execution frontier, which moves
only on an attempt completed at or above `demonstratedMotorScore`; a weak hand
rarely clears that, so its frontier stayed empty and coordination work was never
offered. Readiness is now its own record, written on any completed attempt whose
pitch integrity clears its own bar, because a hand playing the right notes
unevenly knows the scale and a hand playing the wrong ones smoothly does not. An
uneven player went from qualifying in two simulated sittings of twenty to
eighteen.

The earlier scheduler let a fully eligible, admitted hands-together candidate
wait a median of seven to nineteen slots after its prerequisite was first
satisfied, and in some sittings never chose it.

Attributing every slot of that wait says the cause is not what it looked like:

```text
archetype             gap slots   other material   another realization of it
developing                  163             100%                          0%
intermediate                441             100%                          0%
advanced                    310             100%                          0%
uneven_hands                294             100%                          0%
```

Not one slot in any archetype went to a different realization of the scale that
was waiting. So the narrow same-material preference this was expected to need -
prefer the first hands-together realization of M over M's other realizations -
would produce a satisfying regression test and move the latency by nothing.

Production now derives a once-per-material coordination transition and ranks it
below eligibility but above retention. It remains owed until a hands-together
attempt produces execution evidence, then ordinary ranking resumes. The urgency
cannot accumulate or persist beyond that first observation.

Measured by `keyrecall_simulation/bin/hands_together.dart` and
`bin/ht_delay.dart`.

**Admission remains a separate question.** The delay above concerned a candidate
that was already admitted. Whether one should be admitted at all, relative to
factual retrieval and the band floor, is proposed in
[`coordination-transition-policy.md`](decisions/curriculum-and-progression.md).

### The remedial tempo range, and the coefficient that makes it inert

Three separate facts, kept apart because only the third is a decision.

**The range exists and is unreachable.** `metronomeLadder` runs from forty, and
the rungs below sixty were reserved for a learner who cannot manage the ordinary
floor. Candidate generation offers `[60, 80, 100, 120]`, and the only things
that materialize a tempo off that set are derived from frontier evidence, which
a struggling learner does not have. So nothing ever asks for forty to fifty
eight, in the app or in simulation - they share one generator.

**Under the current coefficient, reaching them would not help.** Motor
difficulty scales tempo as `beta_t log(b / b_0)` with `beta_t = 0.4` and a
reference of eighty. Descending the whole way from sixty to forty adds

```text
0.4 (ln(60/80) - ln(40/80)) = 0.4 ln(1.5) = 0.162
```

to the execution logit. A learner the challenge band has refused everything sits
near `p_exec = 0.30`, and reaching the floor of the band at 0.60 needs

```text
logit(0.60) - logit(0.30) = 0.847
```

which under that coefficient would take about **seven beats per minute**. The
sub-sixty ladder cannot move this learner into the band, and thirty one dry
sittings confirm it: none re-enters the band at any rung, and mean predicted
success rises from 0.298 to 0.333 across the entire descent.

For scale, an extra octave costs 0.3 and hands together costs 0.2 under the same
coefficients. Halving the tempo is currently worth about half of adding a second
octave.

**The coefficient has never been fitted.** `03-v1-math.md` §11.2 says the
difficulty betas are heuristic and should be replaceable by fitted values
without changing persisted observations, and §11.1 records that simulation has
used them unchanged since the prototype. So this is not a defensible theoretical
position that the evidence contradicts; it is a placeholder that has never been
tested, and simulation cannot fit it, because both synthetic generators invent
their own completion rules.

Which makes this a device question, and a small one. For a learner who knows the
notes, one octave of C major in one hand, fully cued, at forty, fifty and sixty,
several attempts each, scored against whatever `acceptable execution` is taken
to mean. Counterbalance the tempo order, or within-sitting learning will read as
a tempo effect.

That gives both quantities at once: whether predicted execution probability is
near right at each tempo, and whether the slope from sixty to forty resembles
the model's. Either can be wrong independently.

Until the slope is measured, generating sub-sixty candidates would ship a
difficulty axis the model has almost no reason to prefer. The candidate space
and the coefficient have to move together.

### Transcript capture cost

`PerformanceTranscript.appending` copies the whole note list per note, so
recording n notes copies O(n^2) elements, and each one publishes new Riverpod
state that repaints the staff.

Deliberately not addressed. A scale is tens of notes, the copying is of a small
list of immutable values, and the repaint per note is what makes the staff live.
Both costs are what an attempt is for.

The measurement that would change this is a profile of a real attempt, not the
shape of the loop. Worth taking if a longer form than a scale is ever recorded
as one transcript, or if the staff drops frames while somebody plays.

### A commit conceived before an erase

Store operations for one profile run one at a time, so no two interleave. That
is ordering, not agreement about which history an operation was conceived
against, and one gap follows from the difference:

```text
1. a session reads an empty journal and prepares attempt sequence 0
2. the roster erases that profile's history
3. the session's append runs
4. sequence 0 is contiguous against the journal the erase left
5. the erased history now holds that attempt
```

Every other stale write is already refused. A sequence above zero is not
contiguous against an emptied journal, and a checkpoint covering attempts the
journal no longer has is a cache miss rather than a seed. Only the first attempt
of a profile with no history lands silently.

The principled fix is a history generation: a token a session takes when it
opens and presents on every write, so a store can refuse work conceived against
a history it has since destroyed. It was not taken here because it is a change
to `PracticeStore` and to everything implementing it, which is more than the
size of the hole.

Reproduced by driving `PracticeLoopNotifier.finish` and
`ProfileRosterNotifier.eraseHistory` concurrently over one store.

### A rebuilt window reinterprets history under the current model

Reopening a sitting rebuilds the realization-family pacing window from the tail
of the journal, and each record's `productive` flag is recomputed by asking the
_current_ `LearnerModel.executionWasManaged` about a historical outcome. The
window is therefore derivable from the journal rather than separately persisted,
which is what keeps pacing state out of the schema, but its reconstruction is
interpreted by whatever learner version is running now.

If the managed-execution criterion moves, the same journal yields a different
window, so a sitting reopened after an upgrade can carry different pressure than
the one that was interrupted. Nothing is corrupted by this: the window is a
short rolling summary that the next dozen attempts replace, and the journal, the
learner state, and replay are untouched.

It belongs with the replay and versioning semantics rather than with pacing:
records carry the model versions they were decided under, and the question is
whether a derived session window should be reconstructed under the version that
observed each attempt or under the version reading it now. Worth settling when a
learner version actually changes that criterion, not before.

## Domain expansion

The long-term technical-practice domain may include:

- modes;
- arpeggios and inversions;
- contrary-motion exercises;
- scales in thirds, sixths, tenths, or other intervals;
- advanced regimen-derived or Russian-style patterns;
- symmetric, whole-tone, and diminished scales; and
- additional provenance-backed technical-material families.

These remain inside technical-practice scope. They are not a commitment to
general repertoire instruction.

Each new material family needs its own topology, canonical fingering research,
motor realization, structural opportunities, difficulty mapping, observations,
and extension characterization. An arpeggio is not a scale with a different
exercise pattern. Each family must also state explicitly which existing learner
states should transfer into it and which states are intentionally new.

Rhythmic and articulation variants and broken-chord patterns are not current
expansion targets. Arpeggios are the next architectural proof because they are
unlike scales in ways contrary motion is not. The cross-family contract and its
acceptance criteria are specified in
[`curriculum-and-focus.md`](system/curriculum.md).

### Alternative fingerings

V1 teaches one canonical fingering. Future legitimate alternatives should be
provenance-backed `FingeringPattern` records, not untracked overrides.

Alternative patterns may:

- map to an existing motor realization/family;
- introduce a distinct realization while sharing competencies;
- expose new structural opportunities; or
- eventually justify a new competency only after identifiability and transfer
  evidence.

The design must decide whether memory remains attached to musical material while
execution residuals or observations distinguish the chosen realization. It must
never infer the finger actually used from standard MIDI alone.

## Learner-facing product ideas

### Fluency Profile

Internal model state should not be shown raw. A future Fluency Profile may
translate it into useful descriptions of:

- recall and delayed reliability;
- accuracy and continuity;
- timing and tempo capability;
- right/left/combined coordination;
- consistency and robustness; and
- current readiness versus longer-term retention where evidence supports a
  useful distinction.

These are derived presentations, not one-to-one latent variables. Labels must
communicate uncertainty and avoid implying precision the model does not have.

### A hand shown rather than named

The task statement says which hand plays in words, and words are easy to read
past when the previous exercise used the other one. A small pair of hand figures
with the one in use marked would be read without being read, which is what a
person moving between the screen and the keyboard has attention for.

Not urgent, and deliberately not a replacement for the text: it is a second
channel for the same fact, which is the point.

### “Why this exercise?” explanations

Candidate and update traces can support concise explanations such as:

```text
This scale has not been tested independently for several days.
This tempo is challenging but currently achievable.
The notes are previewed because the previous retrieval attempt failed.
This key exercises a crossing pattern that transfers to related scales.
```

Explanations must be generated from facts the scheduler actually consumed. They
must not retrofit a plausible story after selection or expose raw latent values
as objective truths.

## Empirical and population learning

Future empirical work should prioritize questions that can change a named state,
prediction, evidence path, or decision:

- Is there a repeatable within-session execution curve after conditioning on
  persistent state and task difficulty?
- Which residual covariance patterns support new transferable competencies?
- Which performance-envelope summaries improve forward prediction or learner
  understanding?
- How should priors and calibration families vary across learner histories?
- Which transfer relationships reproduce across learners and material families?
- When does additional interleaving improve later performance rather than only
  change immediate difficulty?
- How do user goals affect adherence and learning without distorting inference?
- Do particular post-attempt feedback levels measurably affect subsequent
  observations? Feedback exposure is recorded separately today, and does not
  change evidence weight.

Use learner- and time-based holdouts, preserve repeated-measures structure,
report uncertainty and coverage, and retain immutable original histories for
replay. Policy learning should begin only after the action space, outcomes, and
counterfactual limitations are understood well enough to avoid optimizing noisy
short-term completion.

## Empirical Phase 1 questions

The first empirical work should test qualitative assumptions and data quality,
not optimize product satisfaction or fit every provisional coefficient.

### Retrieval calibration

Compare predicted retrieval probabilities with factual retrieval frequency.
Report calibration by:

```text
probability band
elapsed interval band
guidance level
material maturity
scheduler intent
learner and session
```

Completion must not substitute for factual retrieval. Unobserved retrieval must
not enter the success or failure denominator.

### Longitudinal posterior behavior

Examine whether consolidation posterior uncertainty contracts when informative
elapsed evidence arrives, remains broad under massed practice, and can reverse
after contradiction.

True half-life is not directly observable in real users. Posterior validation
must therefore use later held-out retrieval outcomes, posterior predictive
checks, and longitudinal coverage proxies rather than pretending the latent
truth is known.

### Recovery and probes

Measure:

- completion and episode length after recovery;
- time to the next factual observation;
- guidance-probe observability and success;
- realized state change after probes;
- marginal information yield by probe ordinal;
- whether the production recovery and probe assumptions remain qualitatively
  plausible.

The synthetic hybrid-recovery signal may be tracked as a future hypothesis, but
must not be activated opportunistically in production telemetry.

### Scheduler distributions

Measure real-session:

- material-selection concentration;
- revisit-gap distribution and tail;
- no-admission frequency;
- ordinary, recovery, guidance-probe, and bootstrap proportions;
- challenge-band placement and guidance fading.

These are guardrails and descriptive outcomes. They are not targets to optimize
in isolation.

## Statistical discipline

Early attempts from one learner are highly correlated. They are not independent
calibration samples.

Initial analysis must:

- report learner count, material count, factual observation count, and interval
  coverage separately;
- split evaluation by learner and by time, not randomly by attempt;
- preserve repeated-measures structure;
- distinguish exploratory from confirmatory analyses;
- avoid fitting a flexible model to a tiny beta cohort;
- retain original versioned traces when testing alternative parameters;
- evaluate calibration across varied latent timescales rather than one showcase
  fixture or learner.

Population fitting should begin only after the data span enough learners,
materials, guidance conditions, and elapsed intervals to identify the parameter
being changed.

## Gates for reopening the frozen systems

Everything above in this document is deferred by choice. **Inclusion here does
not lower the following gates.**

### Learner model

Reopen learner-state structure or transition semantics only when real,
replayable observations show a qualitative representational failure that cannot
be resolved by calibration.

Examples include:

- systematic prediction error after adequate elapsed material-local evidence;
- posterior uncertainty that cannot represent observed reversibility;
- a repeated conflict between retrieval evidence and causal learning
  attribution;
- state trajectories that violate the current consolidation envelope's intended
  meaning.

Numeric miscalibration alone should first trigger parameter estimation, not a
new state dimension.

Proposals to add a competency or prediction channel must also follow
[`research/extending-the-model.md`](research/extending-the-model.md):
demonstrate identifiability, held-out transfer, isolation from existing state,
and replayed value before reopening the ontology.

### Scheduler policy

Reopen scheduler structure only when real data identify a repeatable decision
failure with an observable pre-selection discriminator and a measurable cost.

The evidence must show that an alternative improves its intended local outcome
without unacceptable calibration, recovery, concentration, revisit-gap, or
no-admission regressions.

User preference or satisfaction may motivate product changes, but it does not by
itself validate a learner-model or scheduler-mechanism claim.

### Provisional coefficient calibration

Coefficient changes require:

- a named estimand and the events that identify it;
- a versioned baseline;
- held-out longitudinal evaluation;
- uncertainty or sensitivity reporting;
- replay against existing guardrails;
- an assumption-registry entry or update.

## Explicitly closed ideas

Closing a mechanism does not necessarily close the underlying problem it
attempted to solve.

The following are not open future proposals merely because they appear in older
documents. Synthetic work rejected them, left them unpromoted, or replaced them
with a clearer production mechanism:

- the old weighted scheduler utility equation;
- a generic scheduler “learning value” term;
- cross-material memory or durability seeding;
- post-success prediction bridges;
- reduced first-encounter support based on global placement confidence;
- generic guidance-probe cooldown or suppression;
- substitution of the factual-attempt clock for factual-success history;
- information-before-retention ranking exceptions;
- conditional stronger-support probe exceptions;
- motor-only recovery; and
- hybrid recovery as a production policy.

These results do not prove that no future empirical evidence could ever reopen a
related question. They mean the ideas are **closed by default**: do not place
them on a roadmap, implement them behind an unvalidated flag, or treat them as
aspirational V2 features.

The learner/scheduler experiment record in
[`../learner-model/04-v1-scheduler.md`](research/experiments/scheduler.md) and
the frozen-system gates in
[`../learner-model/05-production-implementation-plan.md`](system/history.md) are
authoritative for why and how a closed mechanism could be reconsidered.

## Planning summary

Among the currently preserved hypotheses, the transient session execution factor
is a particularly high-value early empirical question because it could prevent
systematic corruption of persistent competency estimates. It should still begin
as an identifiability question, not as a warm-up/fatigue feature commitment.

The broader principle is consistent across every section:

```text
preserve rich observations and architectural seams
    -> identify a repeatable failure of the simpler model
    -> isolate the proposed explanation
    -> compare through observational replay and held-out prediction
    -> characterize scheduler and product consequences
    -> promote only with versioned evidence and migration semantics
```

Until those gates are met, V1 remains the production contract and this document
remains planning context.
