# KeyRecall Glossary

- **Status:** Canonical V1 terminology
- **Last aligned:** August 29, 2026

This file is a concise lookup reference for current terms. It does not record
design history, supersessions, open questions, or mathematical derivations. See
[`README.md`](README.md) for document authority and history, and
[`learner-model/v1-current-system.md`](learner-model/v1-current-system.md) for
the integrated V1 explanation.

## Terms

### Activation

The operative recency of exact-material memory, represented by
`MaterialMemoryState.memory_anchor_at`. A factual retrieval success sets the
anchor to the attempt time. Productive supported practice may move an existing
anchor partway toward the present without recording a retrieval success.

Activation is distinct from current durability and retained consolidation.

### Attempt

One presentation and performance of an `Exercise`, including the decision
context, observations, derived outcome, evidence weights, state transitions, and
state references needed for deterministic replay.

### Assumption Registry

A record of conceptual claims about the world or design, including their basis,
confidence, and falsifier. It is distinct from the Parameter Registry, which
records numeric configuration.

### Bootstrap probe

A challenge-band exception that offers notes previewed and then hidden for a
material that has been tested but never successfully retrieved. Its clock uses
`last_retrieval_attempt_at`. It prevents never-successful material from becoming
permanently trapped under continuous cueing.

### Consolidation exception

A challenge-band exception that offers a scale already met and not yet produced
from memory, at the previewed rung, when the slot has nothing appropriate left
to introduce. Not to be confused with retained consolidation, which is a memory
state.

### Candidate

A domain-valid `Exercise` considered by the scheduler. Candidate generation uses
domain and instrument constraints but no learner state.

### Cold-start estimate

The estimated probability of independently retrieving exact material before the
first successful retrieval establishes a memory anchor. It is stored in logit
form and has uncertainty separate from current-durability uncertainty.

### Competency

A persistent, transferable latent learner capability estimated from relevant
practice across materials. `Competency` is the canonical term; older documents
may use `KnowledgeComponent`, `KC`, or `Component`.

V1 estimates ten competencies: four scale-topology competencies, right- and
left-hand scale execution, scalar crossing, multi-octave continuation, direction
reversal, and hands-together coordination.

### CompetencyCategory

An organizational label over competencies with no estimated learner state of its
own. `SCALE_TOPOLOGY` and `SCALE_EXECUTION` are categories, not latent
variables.

### Consolidation

See **Retained consolidation**.

### Current durability

The half-life currently governing decay from `memory_anchor_at`. It is positive,
may be corrected by factual elapsed retrieval evidence, and never exceeds
retained consolidation.

### Derived evidence

The interpretation of raw and summarized observations used to update a
particular state channel. It includes factual retrieval status and
channel-specific evidence weights.

### Eligibility tier

An ordered scheduler classification derived from pedagogical prerequisites. The
current tiers are `FULLY_ELIGIBLE` and `PROVISIONALLY_ELIGIBLE`. Tier is the
first ranking key, not a weighted utility term.

### Evidence weight

An attempt-specific measure of how informative an observation is about one state
channel. Competencies use `w[a,k]`; material memory and execution use distinct
`w_M` and `w_r` values. There is no universal attempt confidence scalar.

### Exercise

A requested task composed from `TechnicalMaterial`, `ExercisePattern`,
`ExecutionConditions`, `GuidanceContext`, `MotorRealization`, and observable
`Opportunities`. The older flat exercise shape in `v1-domain-model.md` is
superseded.

### ExercisePattern

The ordering or transformation applied to technical material. V1 implements
`LINEAR`.

### ExecutionConditions

The requested hand configuration, direction, octave count, tempo, and related
physical conditions of an exercise. These parameterize task difficulty rather
than material identity.

### Factual retrieval

A retrieval observation that actually occurred. Its three values are:

```text
true    factual retrieval was tested and succeeded
false   factual retrieval was tested and failed
null    retrieval was not factually tested
```

“Factual” means retrieval was tested without concurrent answer-supplying cues.
Continuous pitch cues produce `null`, not a weak failure. Notes previewed and
then hidden remain a lower-demand factual test.

### FingeringPattern

The concrete canonical fingering for one scale, form, hand, and direction. It is
authoritative domain data. The retired `FingeringGroup` term should not be used
as a synonym.

### Fluency Profile

The user-facing interpretation of internal learner state, such as “recall
strong; right-hand execution developing.” It is derived presentation, not an
additional latent state.

### GuidanceContext

The instructional and cueing conditions surrounding an attempt, including prior
instruction, notes previewed before performance, continuous cues during
performance, and feedback policy. Guidance changes retrieval demand and evidence
interpretation.

### Guidance probe

A challenge-band exception that presents an anchored material with one step less
guidance after the configured interval since its last factual retrieval success.
It tests whether support can fade.

### Half-life

The elapsed time over which predicted independent retrievability falls by half
under the V1 forgetting curve:

```math
M(t)=2^{-\Delta t/h}
```

### InstrumentProfile

The connected instrument's relevant physical capabilities. V1 requires enough
range information to prevent generation of exercises that do not fit the
instrument. Other hardware metadata remains descriptive unless validated as a
model input.

### LearnerState

Persistent state across practice sessions:

```text
LatentCompetencyState
MaterialMemoryState
MaterialExecutionState
```

It excludes short-lived scheduling context in `SessionState`.

### MaterialExecutionState

A dynamic, partially pooled learner-by-material-by-execution-context residual.
It captures persistent material-specific procedural readiness not already
explained by transferable competencies or task difficulty.

It also carries the execution frontier for that material and hand configuration.

### Execution frontier

The fastest tempo a learner has managed at each octave span, for one material
and one hand configuration, held on `MaterialExecutionState`. A tempo per span
rather than a widest span and a fastest tempo, since those are two maxima and
the pair of them need never have been played together.

It advances only on an attempt that completed with a motor score at or above
`demonstratedMotorScore`, and it is the baseline execution progression steps
from.

### Paced tempo

The fastest tempo a learner has actually played a material cleanly, whatever
they were asked for, held beside the execution frontier on
`MaterialExecutionState`.

A separate question from the frontier, and deliberately not folded into it. The
frontier records what was asked for and managed, which is the only thing a step
goes on from; this records how fast somebody plays when nobody is holding them
back. Keeping them apart preserves the rule that evidence at a tempo is earned
by being asked for that tempo, while letting an unseen scale arrive near the
speed the learner actually plays. It is what `transferableTempoFor` reads.

### Execution progression

A challenge-band exception that offers one adjacent execution step on material
already produced from memory: the next tempo rung, one octave wider, or the same
work with both hands. Exactly one axis moves per candidate; see
`ExecutionAdvance`.

Distinct from consolidation, which offers material that has been met and not yet
produced. The two partition what is known about a material, alongside
introduction for material never met.

### ExecutionAdvance

Which execution axis a candidate advances against the frontier: none, tempo,
span, hands together, or multiple. Only a single adjacent step is admissible;
`multiple` exists so that going wider and faster at once is structurally
excluded rather than merely outranked.

### MaterialMemoryState

The exact-material state containing activation, current durability, retained
consolidation, cold-start belief, uncertainty, and factual retrieval history. It
is keyed by learner and `TechnicalMaterial`, not by hand or exercise variant.

### MotorFamily

A higher-level equivalence class over mechanically derived motor realizations.
`DIATONIC_3_4_CYCLE` is domain structure, not learner state.

### MotorRealization

The mechanically derived realization of a `FingeringPattern`, including phases,
crossings, continuations, reversals, and other technical events.

### Observation

A raw or derived fact about an attempt, such as MIDI events, pitch integrity,
continuity, temporal stability, tempo, or local behavior near an expected motor
event. Observations remain richer than the persistent latent state.

### Opportunity

A location or condition in an exercise where a competency could be observed,
such as a scalar crossing, octave continuation, reversal, or hands-together
coordination event. Opportunity does not claim that the expected fingering was
actually used.

### Parameter Registry

The versioned numeric configuration for learner and scheduler behavior. Current
registries are `analysis/learner-model/params.toml` and
`analysis/scheduler/config.toml`. Their V1 values are heuristic unless
explicitly documented otherwise.

### Partial pooling

The behavior by which sparse material-specific evidence remains close to a
shared learner prediction, while repeated direct evidence permits a larger
personalized residual. V1 approximates this locally with zero-centered priors,
conservative updates, and mean reversion.

### Q-matrix

The structural mapping from exercises to transferable competencies:

```math
Q_{e,k}\in\{0,1\}
```

`Q[e,k] = 1` means exercise `e` creates an opportunity to observe competency
`k`. It does not state how strong the predictor loading or actual evidence is.

### Metronome ladder

The Maelzel tempo progression, from 40 to 208, used as an adjacency relation
rather than a candidate set: it defines what the next and previous tempo are.
Its steps grow with the tempo, which is the right shape for a quantity where a
fixed count of beats per minute does not mean a fixed amount at both ends.

### Recovery

An exclusive challenge-band exception immediately after a factual retrieval
failure. The recovery target is the same material and motor task with exactly
one step more guidance.

### Repetition guard

A selection-time policy that prevents an over-repeated material from winning
when another admitted material exists. It never removes the only admitted
option.

### Retained consolidation

The slower durability envelope retained from prior learning. It supports savings
and restoration of current durability but does not directly enter V1 prediction
or scheduling.

### Retrieval demand

A number in `[0,1]` describing how much independent production a guidance
configuration requires. In the current prototype, continuous cues use `0.05`,
notes previewed use `0.6`, and unguided practice uses `1.0`. Continuous cues
still have zero retrieval opportunity because retrieval is not observed.

### Retrieval opportunity

The ability of a candidate to produce genuine retrieval evidence. It is zero
when retrieval is not observed and otherwise equals retrieval demand. Retention
and information scores use it so a candidate cannot benefit from evidence it is
structurally unable to collect.

### Savings

Faster reacquisition after apparent forgetting because retained consolidation
survives below current readiness. A learner with prior durable practice need not
behave like a true beginner even when current performance is similar.

### SchedulerSafetyPolicy

Conservative workload constraints applied before challenge admission. V1
implements a session-attempt cap, unset in production, and makes no medical or
injury diagnosis from performance data.

### SessionState

Transient scheduler context within a practice session, currently including the
attempt count, recent-material history, and the last failed exercise. It is
separate from persistent `LearnerState`.

### Structural opportunity

See **Q-matrix**.

### TechnicalMaterial

The underlying musical object being practiced. For V1 scales, identity is
primarily tonic plus scale form. Hand, tempo, octave count, direction, pattern,
and guidance are not part of material identity.

## Mathematical symbols

| Symbol                                                            | Meaning                                       |
| ----------------------------------------------------------------- | --------------------------------------------- |
| $u$                                                               | learner                                       |
| $m$                                                               | technical material                            |
| $c$                                                               | execution context, primarily RH/LH/HT         |
| $e$                                                               | exercise                                      |
| $a$                                                               | attempt                                       |
| $k$                                                               | transferable competency                       |
| $\theta_{u,k}$                                                    | latent competency state                       |
| $\mu_{u,k}$, $\sigma^2_{u,k}$                                     | competency mean and variance                  |
| $M_m(t)$                                                          | predicted independent material retrievability |
| $h_{\mathrm{current},m}$, $h_{\mathrm{consolidated},m}$           | current and retained half-lives               |
| $r_{u,m,c}$                                                       | material-specific execution residual          |
| $Q_{e,k}$                                                         | binary structural opportunity                 |
| $q^{(C)}_{e,k}$                                                   | derived predictor loading for channel $C$     |
| $w_{a,k}$, $w_M$, $w_r$                                           | channel-specific evidence weights             |
| $d_e$                                                             | retrieval demand                              |
| $D_{\mathrm{motor}}(e)$                                           | conditional motor-task difficulty             |
| $R(e)$, $\mathrm{Info}(e)$, $\mathrm{Div}(e)$, $\mathrm{Goal}(e)$ | scheduler priority terms                      |

## Retired terms

| Retired                                            | Use instead                                                                    |
| -------------------------------------------------- | ------------------------------------------------------------------------------ |
| `KnowledgeComponent`, `KC`, `Component`            | `Competency`                                                                   |
| `FingeringGroup`                                   | `FingeringPattern`, `MotorRealization`, or `MotorFamily`, according to meaning |
| flat `Exercise` record                             | compositional `Exercise`                                                       |
| discrete acquisition/development/maintenance state | derived Fluency Profile language                                               |
| `PRIMARY`/`SECONDARY` Q entries                    | `Q`, predictor loading `q`, and attempt evidence `w`                           |
