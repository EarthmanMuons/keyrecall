# Future Planning

- **Status:** Deliberately deferred design space
- **Last aligned:** August 21, 2026
- **Scope:** Post-V1 architectural seams, empirical hypotheses, domain growth,
  and product ideas worth preserving

## 1. Purpose and reopening discipline

This document records ideas KeyRecall has intentionally deferred. It is not a
roadmap commitment, release sequence, or alternative production specification.
The canonical initial-production system remains
[`../learner-model/v1-current-system.md`](../learner-model/v1-current-system.md).

V1 is deliberately simpler than the full design space. That simplicity should
not erase promising architectural seams, but neither should an old idea regain
authority merely because it appears in a planning document.

Every item here belongs to one of three categories:

```text
reserved extension
    the current architecture has an intentional place for it
    evidence must still justify activating that seam

deferred hypothesis
    plausible and worth testing, but its representation is not decided

domain or product expansion
    valuable scope beyond the initial scale-focused implementation
```

Structural changes remain subject to the reopening gates in
[`../learner-model/05-production-implementation-plan.md`](../learner-model/05-production-implementation-plan.md).
New competencies and prediction channels must additionally follow
[`../learner-model/competency-extension-guide.md`](../learner-model/competency-extension-guide.md).

The general admission rule is:

> Preserve the architectural seam now. Add latent state or policy only when
> replayable real observations show that the simpler V1 representation has a
> repeatable, identifiable failure.

## 2. Reserved architectural extensions

### 2.1 Transient session state

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

### 2.2 New prediction and outcome channels

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

### 2.3 Execution evidence at the achieved motor difficulty

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
rather than at zero BPM. `LearnerModel.v1Prototype` retains the earlier
attribution semantics for historical replay; production models use demonstrated
difficulty.

### 2.4 Population and hierarchical calibration

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

### 2.5 Feedback after an attempt is its own channel

`PerformanceFeedback` says what a learner sees of their own playing **during**
an attempt: nothing, a neutral echo, or an evaluative display. Showing them
afterwards what was measured is a different axis, and the practice screen
deliberately shows nothing.

It is not decoration. What a learner carries out of one attempt changes the next
one: told which notes were wrong, they will attend to those, which is useful
practice and also makes the following attempt a different observation from an
unaided one. So it belongs in `PresentationConditions` as its own value,
recorded per attempt, rather than arriving as UI polish.

The questions it raises are the ones the during-attempt axis already answered in
its own terms: whether it is neutral or evaluative, whether it is available at
every guidance rung, and whether an attempt that was reviewed afterwards is the
same evidence as one that was not.

A first version exists, built when practising on a real instrument showed that
an attempt ended without anything marking that it had. It answers the first
question deliberately and leaves the other two open. It says one true positive
thing about the attempt and names the next exercise, and it says why only when
the reason is one of the scheduler's named exceptions. It never invents: an
attempt that did not start gets no sentence.

Positive-only is presentation, not omission. Nothing is withheld, because the
evidence is written to the journal in full before anyone reads the screen, and a
complete account of a run, good and bad, is what a fluency profile is for.

What is still undesigned is the part that matters to evidence. The review is the
same at every rung and is not recorded in `PresentationConditions`, so an
attempt reviewed afterwards is not yet distinguishable from one that was not.
That is fine while the review says so little, and it is the first thing to fix
if it ever names individual notes.

## 3. Learner-model extensions

### 3.1 Performance envelopes

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

### 3.2 Competency growth

The V1 state/update machinery is designed to admit future competencies without
rewriting memory or scheduler stages. Residual covariance may reveal missing
transferable structure across materials.

All proposals follow the competency extension guide: identifiability,
nonredundancy, transfer, observational replay, held-out calibration, unchanged-
policy scheduler characterization, and deterministic state migration.

### 3.3 Richer performance-control dimensions

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

## 4. Scheduler and product extensions

### 4.1 Explicit user goals and focus

V1 reserves `Goal(e)` but sets it to zero because no goal model exists. Future
goals may include:

- exam or curriculum requirements;
- a selected scale-form or minor-scale focus;
- arpeggio preparation;
- target tempos or performance dates;
- temporary focus areas;
- free-practice requests; and
- explicit learner overrides.

Goal relevance belongs in the established goal term and product constraints. It
must not silently redefine learner competence, evidence, prerequisites, or
challenge prediction.

### 4.2 Acquisition, development, and maintenance as practice regimes

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

### 4.3 Immediate repetition as an episode, not as several attempts

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

### 4.4 Free practice, separate from scheduled practice

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

### 4.5 Adaptive contextual-interference intensity

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

### 4.6 Fatigue-aware workload and rest policy

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

### 4.7 Preserve the sessionless UX

Future scheduler intelligence remains constrained by a core product principle:

> Open the app, play what it gives you, and stop whenever you want.

There is no “behind” state. Lookahead is soft and revisable. New goals,
maintenance regimes, fatigue adaptation, or population-trained policies must not
turn practice into a rigid calendar or punish irregular use.

### 4.8 Material admission by prerequisite, not by tier

The first material-admission policy is implemented, and
[`material-admission.md`](../domain-model/material-admission.md) records it.
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

### 4.8 The cold-start regime: placement priors against the challenge band

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
the specified behaviour rather than a leak — provisional means deferred while
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

## 4.9 A sitting with nothing to offer

`_NothingToPlay` is an error state, and simulation established that catalog
breadth is the only thing that keeps it off the screen. `PracticeSession.open`
refuses a scoped goal for that reason.

A learner who fails most of what they are given has each material walked toward
support by recovery. Cued attempts never observe retrieval, so nothing
re-anchors, and when there is nothing left to introduce instead the slot admits
nothing at all. Over the seven-material catalog a true beginner reaches it by
slot eleven and in three quarters of runs within a hundred and twenty slots;
over the shipped forty-eight it never happens, at three times the length of a
sweep. So breadth is an escape rather than a delay.

It is a live path rather than a stress fixture, because `PracticeGoal.scopeOf`
narrows the catalog to `targetMaterialIds` and a goal aimed at a handful of
scales recreates the narrow catalog exactly. Goals are therefore expressible but
not runnable: `PracticeSession.open` throws for a scoped goal.

Shipping goals means lifting that refusal, which needs a principled floor first:
something a learner in that state can always be offered, which today's eight
admission mechanisms between them do not guarantee.

Pinned in `keyrecall_simulation/test/sitting_ran_dry_test.dart`, and the true
beginner's invariant stays skipped in `trajectory_invariants_test.dart` until
the floor exists.

## 4.10 Spend the slot after coordination is earned

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
[`coordination-transition-policy.md`](coordination-transition-policy.md).

## 4.11 Scheduler evaluation cost

Profiling the simulation sweep measured the app as a side effect. One decision
is about forty milliseconds on a development machine, and ninety-six per cent of
it is `SchedulerPipeline.evaluate` over roughly eight thousand candidates, of
which prediction and information are more than half:

```text
per candidate
  predict              1.062 us
  information          1.069 us
  eligibilityFor       0.212 us
  structuralQ          0.194 us
  realizationRankFor   0.168 us
```

A phone is slower than the machine that produced those numbers, and the learner
waits for this between exercises.

The obvious saving is that `information` is computed for every candidate and
consumed only by the ones that reach ranking, which is a small fraction. It was
deliberately not taken: a lazy term would capture a `LearnerState` that mutates
after the slot, and `CandidateTrace` deliberately populates stage values for
candidates an earlier stage excluded, so that "why not that one?" is answerable
from the trace alone.

So the question is architectural rather than a matter of shaving a hot loop:

> Can expensive state-dependent work be skipped for candidates that cannot reach
> ranking, without weakening the explainability of rejected ones?

A two-phase trace would answer it - admission-stage facts always present,
ranking-stage facts explicitly absent with a reason - and that is a change to
the trace contract, not an optimization. Worth doing on its own, away from
correctness work.

`keyrecall_simulation/bin/profile_evaluate.dart` reproduces the numbers above.
Not a timing assertion, which would be flaky; a command to run when evaluation
feels slow, against the figures recorded here.

### What the caching pass took, and what it did not

Contrary motion took the candidate set from 6,912 to 9,216, and a decision then
varied by learner rather than sitting near one number: 47ms for `developing`
against 90ms for `uneven_hands`, on the same candidates. The difference was
`eligibilityFor` asking questions of learner state alone once per candidate,
where the repertoire question walks the whole catalog. Answering those once per
decision brought `uneven_hands` to about 47ms and left `developing` unchanged,
which is the shape a fix for a state-dependent pathology should have.

Two caches paid and two did not, and the reason is the same in both directions:

> Redundancy is not sufficient reason for a cache. The key has to be cheaper
> than the work it avoids.

`information` is computed for four and a half times more candidates than it has
distinct answers, and caching it alone saved almost nothing, because deriving
the key rebuilt the competency set. Deriving that set once per exercise instead
made both the key and the term cheaper, and then the cache paid.

The realization terms look like better candidates still: they ignore guidance,
so a third of the candidate set shares an answer, and `evaluate` already holds
the guidance-normalized realization to key them by. Caching them measured
**slower**, 47.0-47.5ms against 46.4-46.6ms, because hashing an `Exercise` costs
more than the two terms it avoids. Not taken.

The remaining structural question is the two-phase trace above, which is worth
more than any further memoization.

## 4.12 The remedial tempo range, and the coefficient that makes it inert

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

## 5. Domain expansion

The long-term technical-practice domain may include:

- modes;
- arpeggios and inversions;
- contrary-motion exercises;
- rhythmic and articulation variants;
- scales in thirds, sixths, tenths, or other intervals;
- broken-chord patterns;
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

### 5.1 Alternative fingerings

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

## 6. Learner-facing product ideas

### 6.1 Fluency Profile

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

### 6.2 A hand shown rather than named

The task statement says which hand plays in words, and words are easy to read
past when the previous exercise used the other one. A small pair of hand figures
with the one in use marked would be read without being read, which is what a
person moving between the screen and the keyboard has attention for.

Not urgent, and deliberately not a replacement for the text: it is a second
channel for the same fact, which is the point.

### 6.3 “Why this exercise?” explanations

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

## 7. Empirical and population learning

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

Use learner- and time-based holdouts, preserve repeated-measures structure,
report uncertainty and coverage, and retain immutable original histories for
replay. Policy learning should begin only after the action space, outcomes, and
counterfactual limitations are understood well enough to avoid optimizing noisy
short-term completion.

## 8. Explicitly closed ideas

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
[`../learner-model/04-v1-scheduler.md`](../learner-model/04-v1-scheduler.md) and
the frozen-system gates in
[`../learner-model/05-production-implementation-plan.md`](../learner-model/05-production-implementation-plan.md)
are authoritative for why and how a closed mechanism could be reconsidered.

## 9. Planning summary

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
