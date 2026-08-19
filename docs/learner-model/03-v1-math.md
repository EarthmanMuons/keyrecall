# V1 Learner-Model Mathematics

## 1. Purpose

This document specifies the smallest mathematically coherent learner model
proposed for KeyRecall V1.

It is subordinate to:

- `01-research.md`, which preserves the research basis; and
- `02-v1-design.md`, which defines the conceptual architecture.

The purpose here is to make the V1 mathematics explicit enough to implement,
simulate, inspect, and later replace with empirically fitted models.

The model is intentionally provisional. It must work before KeyRecall has
population-scale longitudinal training data without disguising heuristic
parameters as established scientific constants.

## 2. Modeling goals

The V1 mathematical model must:

1.  represent uncertainty rather than only point mastery scores;
2.  separate transferable competency, exact-material memory, and
    material-specific execution effects;
3.  predict performance as a function of both learner state and task conditions;
4.  allow related practice to transfer through shared competencies;
5.  preserve material-specific deviations without creating isolated mastery
    scores for every exercise;
6.  account for retrieval support when interpreting memory evidence;
7.  permit learner state to evolve over time;
8.  remain interpretable and testable with synthetic learners;
9.  avoid requiring population-trained parameters at launch; and
10. provide a migration path toward fitted hierarchical or learner-model
    parameters once sufficient telemetry exists.

## 3. Notation

Let:

```text
u    learner
m    technical material
c    execution context, primarily RH/LH/HT
e    exercise
a    attempt (one specific performance of an exercise)
t    attempt time
k    transferable competency
```

Learner state contains:

\[ `\theta`{=tex}\_{u,k}(t) \]

for transferable competency `k`;

\[ M\_{u,m}(t) \]

for material retrievability; and

\[ r\_{u,m,c}(t) \]

for the material-specific execution residual.

The exercise supplies task features:

\[ x_e \]

and, for each competency `k`, a structural Q-matrix entry and a derived
predictor loading, both properties of the exercise itself, plus an
evidence-attribution weight that is a property of a specific _attempt_ rather
than of the exercise it was an attempt at (defined together in §9):

\[ Q\_{e,k} `\in \{0,1\}`{=tex}, `\quad `{=tex}q\_{e,k}, `\quad `{=tex}w\_{a,k}
\]

Observations from an attempt are denoted collectively by:

\[ O\_{u,e,t} \]

and derived evidence by:

\[ E\_{u,e,t} \]

## 4. Transferable competency state

Each transferable competency is represented by an uncertain latent state.

A convenient V1 representation is:

\[ `\theta`{=tex}_{u,k} `\sim`{=tex} `\mathcal{N}`{=tex}(`\mu`{=tex}_{u,k},
`\sigma`{=tex}\^2\_{u,k}) \]

Conceptually:

```yaml
CompetencyState:
  competency_id: RH_SCALE_EXECUTION
  mean: ...
  variance: ...
  last_evidence_at: ...
```

The mean represents the current estimate of transferable capability. The
variance represents epistemic uncertainty about that estimate.

V1 does not claim that actual human motor capability is normally distributed.
The Gaussian representation is an engineering approximation that provides simple
uncertainty propagation and online updating.

### 4.1 Initial competency priors

Before population data exists:

\[ `\mu`{=tex}_{u,k}(0) = `\mu`{=tex}_{0,k} \]

\[ `\sigma`{=tex}\^2\_{u,k}(0) = `\sigma`{=tex}\^2\_{0,k} \]

The initial means and variances are heuristic priors.

A placement process can rapidly update them. Later telemetry may provide
population-informed priors conditioned on relevant learner history.

## 5. Material memory state

`MaterialMemoryState` represents exact-material retrievability rather than
overall exercise success.

For V1, use an HLR-inspired forgetting curve:

\[ M\_{u,m}(t) = 2\^{-`\Delta `{=tex}t / h\_{u,m}} \]

where:

```text
Delta t    elapsed time since the relevant retrieval event
h          current material-specific memory half-life
M          predicted retrievability in [0, 1]
```

This curve shape is motivated by Half-Life Regression research. KeyRecall does
not initially adopt HLR's learned feature model or coefficients.

Conceptually:

```yaml
MaterialMemoryState:
  material_id: F_SHARP_HARMONIC_MINOR_SCALE
  log_half_life: ...
  half_life_uncertainty: ...
  logit_cold_start: ...
  cold_start_uncertainty: ...
  last_retrieval_at: ...
```

`log_half_life`/`half_life_uncertainty` and `logit_cold_start`/`cold_start_uncertainty`
are two separate mean/uncertainty pairs, not four independent fields: exactly
one pair is operative at a time, decided by whether `last_retrieval_at` has
ever been set (§5.3).

### 5.1 Memory is not exercise-success probability

A value such as:

\[ M\_{u,m}=0.6 \]

means the model estimates moderate independent availability of the technical
material under an appropriate retrieval context.

It does **not** mean there is a 60% probability that the learner can execute the
requested exercise successfully. Motor capability, execution context, tempo,
guidance, and other task conditions remain relevant.

### 5.2 Half-life update: log-space, surprise-driven

A multiplicative update (`h' = h·g` on success, `h' = h·s` on failure, `g > 1`,
`0 < s < 1`) was the original V1 proposal but is now **superseded**: simulation
(`analysis/learner-model/`) showed it has no lower equilibrium. Repeated
failure drives `h → 0` regardless of whether that failure was surprising,
because the update magnitude depends only on `g`/`s` and the evidence weight,
never on how well the current estimate already predicted the outcome.

The validated replacement reparameterizes in log-half-life space and makes the
update proportional to prediction error rather than a fixed ratio:

\[ `\ell `{=tex}= `\log `{=tex}h, `\qquad `{=tex} `\ell`{=tex}' = `\ell`{=tex} +
w_M `\left`{=tex}( `\alpha`{=tex}\_M `\delta`{=tex}\_M - `\lambda `{=tex}(
`\ell`{=tex}-`\ell`{=tex}\_0) `\right`{=tex}) \]

clipped to broad numerical bounds `[ℓ_min, ℓ_max]`, where:

```text
delta_M      y_retrieval - p_hat_independent_retrieval (surprise, not a fixed
             ratio: a failure against a confident prediction moves the
             estimate more than an already-expected failure)
alpha_M      evidence-scaling coefficient, heuristic V1
lambda       reversion strength toward the prior l_0, heuristic V1
l_0          log of the prior half-life
w_M          evidence weight (§6, §18); scales the WHOLE bracket, not just
             the evidence term - an unweighted reversion term let a single
             near-zero-weight attempt meaningfully erode an established
             estimate before this was caught in review
```

`h = e^ℓ` is automatically positive; the clip bounds exist as numerical
guards, not as the model's primary stabilizer. A dedicated invariant
(`analysis/learner-model/invariants.py`, "repeated expected failures reach a
stable equilibrium, not collapse") checks that repeated _expected_ failure
settles at an interior equilibrium rather than running to the clip floor -
the property the multiplicative rule lacked. Diagnostic runs (10 successful
retrievals at 1-minute/hour/day/week spacing) show this surprise-driven
update already carries meaningful elapsed-time information through
`p_hat_independent_retrieval`'s own decay formula, without an explicit
separate time-weighting term; see §35 for that open question.

The effective update magnitude must depend on retrieval context, and does so
through `w_M`. That dependency needed to be a hard gate, not just
attenuation: §18 covers why.

### 5.3 Before the clock anchors: cold-start belief gets the same treatment

`ℓ`/`w_M` above is only operative once `last_retrieval_at` has been set at
least once. Before that, `retrievability_or_prior()` returns
`cold_start_estimate` directly rather than computing anything from `ℓ`, and
this section's fix applied to `ℓ` originally left that earlier estimate on
the old multiplicative-shrink form V1 first proposed: every pre-anchor
failure shrank it by the same fixed fraction regardless of whether the
failure was surprising, with no lower equilibrium other than a hard floor.

The same reparameterization resolves it, in logit space instead of
log-half-life space since `cold_start_estimate` is a probability rather than
a positive duration:

```text
c            logit(cold_start_estimate)
c' = c + w_M ( alpha_c delta_c - lambda_c (c - c_0) )
delta_c      y_retrieval - cold_start_estimate
c_0          logit(prior_retrievability)
```

clipped to broad probability bounds, same role as `[ℓ_min, ℓ_max]` above.
`alpha_c`/`lambda_c` are separate heuristic parameters from `alpha_M`/`lambda`:
different scale, different underlying quantity, no principled reason to
share a value.

Two further issues surfaced while fixing this, both instances of one rule:
evidence about one state representation must not silently become evidence
about another.

**`ℓ` must not move pre-anchor.** The original implementation updated `ℓ`
during the pre-anchor phase too, using `delta_M` computed against
`cold_start_estimate` - evidence about a quantity `ℓ` doesn't represent yet.
`update()` now branches on whether `last_retrieval_at` has ever been set:
pre-anchor evidence moves only `c`; post-anchor evidence moves only `ℓ`. The
first successful retrieval anchors the clock but updates neither - it
confirms cold-start availability, not a retention interval, since retrieval
immediately after any retrieval trivially reads as `M ≈ 1` regardless of `h`.

**Uncertainty needed the same split.** A single shared `uncertainty` field
meant pre-anchor failures could shrink confidence in `ℓ` even though no
observation had been about it, and that artificially low uncertainty would
carry across silently the moment the clock anchored. `half_life_uncertainty`
and `cold_start_uncertainty` are now separate fields, each updated only
alongside its own mean.

Invariants (`analysis/learner-model/invariants.py`) mirror §5.2's for this
layer: `cold_start_estimate` stays finite/bounded and reaches an interior
equilibrium under repeated expected failure, and uncertainty is
phase-separated - repeated pre-anchor failure shrinks
`cold_start_uncertainty` but leaves `half_life_uncertainty` untouched, the
first successful retrieval doesn't either, and only a genuinely spaced
post-anchor observation does.

## 6. Retrieval demand

Let:

\[ d_e `\in [0,1]`{=tex}\]

represent a derived retrieval-demand measure for exercise `e`.

Interpretation:

```text
0    required material is effectively supplied
1    independent production is required
```

The value should be derived from preserved raw guidance information rather than
stored as the sole source of truth.

Relevant inputs may include:

```text
notes previewed before attempt
fingering previewed
target keys displayed
note names displayed
next-note cues
time since prior material exposure
```

No V1 numerical mapping from these fields to `d_e` should be presented as a
research-established coefficient.

### 6.1 Memory evidence

A simple conceptual memory-evidence quantity is:

\[ y_M = I\_{`\mathrm{sequence}`{=tex}} `\cdot `{=tex}d_e \]

where:

\[ I\_{`\mathrm{sequence}`{=tex}} `\in [0,1]`{=tex}\]

summarizes sequence/pitch integrity.

This equation is illustrative rather than frozen. In particular, failure under
high retrieval demand may be more diagnostically informative than the simple
product form captures.

The required invariant is:

> Material-memory updates are strongly conditioned on how much of the material
> had to be independently retrieved.

Simulation surfaced a sharper version of that invariant than a continuous
attenuation weight can express. Representing continuous cueing as "retrieval
failure at low confidence" (`w_M` near zero but nonzero) is still
distinguishable from "retrieval was never tested": repeated low-confidence
observations of the same guidance level accumulate under ordinary evidence
weighting, so 50 fully-cued attempts could erode an established memory
estimate through legitimate-looking accumulation, not a calculation error.
The fix was semantic, not numerical: whether an attempt is a retrieval
observation at all is a property of the attempt distinct from its outcome.
`retrieval_succeeded` is `True`/`False` when independent retrieval was
genuinely tested, and `None` when it wasn't (continuous pitch cues) - `None`
attempts carry `w_M = 0` categorically, not merely a small `w_M`, and don't
accumulate under repetition. See §18.

## 7. Material execution residual

The V1 execution state is:

\[ r\_{u,m,c}(t) \]

a dynamic learner x material x execution-context residual.

At cold start:

\[ r\_{u,m,c}(0) `\sim`{=tex} `\mathcal{N}`{=tex}(0,`\sigma`{=tex}\^2\_{r,0}) \]

The zero-centered prior implements partial pooling: without material-specific
evidence, prediction falls back toward shared competencies and general task
effects.

Conceptually:

```yaml
MaterialExecutionState:
  material_id: F_SHARP_HARMONIC_MINOR_SCALE
  execution_context: RIGHT
  residual_mean: 0.0
  residual_variance: ...
  last_evidence_at: ...
```

### 7.1 Residual dynamics

A provisional V1 transition is:

\[ `\mu`{=tex}\_r(t+`\Delta `{=tex}t) =
`\rho`{=tex}(`\Delta `{=tex}t)`\mu`{=tex}\_r(t) \]

where:

\[ 0 `\le `{=tex}`\rho`{=tex}(`\Delta `{=tex}t) `\le 1`{=tex} \]

and `rho` decreases slowly with elapsed nonuse.

The residual therefore tends toward the shared prediction rather than toward
zero performance.

Uncertainty should increase with elapsed time:

\[ `\sigma`{=tex}\_r\^2(t+`\Delta `{=tex}t) = `\sigma`{=tex}\_r\^2(t) +
`\omega`{=tex}\_r f(`\Delta `{=tex}t) \]

where `omega_r` is a heuristic diffusion parameter.

The exact functions for `rho` and `f` are not established by the current
research and must be treated as provisional.

## 8. Competency dynamics during nonuse

For transferable competency state, V1 should initially avoid asserting a
specific performance-decay rate without data.

A conservative transition is:

\[ `\mu`{=tex}_{u,k}(t+`\Delta `{=tex}t) = `\mu`{=tex}_{u,k}(t) \]

while uncertainty grows:

\[ `\sigma`{=tex}\^2\_{u,k}(t+`\Delta `{=tex}t) = `\sigma`{=tex}\^2\_{u,k}(t) +
`\omega`{=tex}\_k f(`\Delta `{=tex}t) \]

Thus absence of evidence makes the model less certain rather than automatically
declaring that broad transferable capability has declined.

Relevant practice on any material can refresh and update the competency.

Later longitudinal data may justify explicit competency-specific forgetting
terms.

## 9. The Q-matrix: structural opportunity, derived loading, and evidence attribution

V1 resolves two previously competing ideas: a qualitative
`PRIMARY`/`SECONDARY`/`NONE` Q-matrix (`../domain-model/v1-domain-model.md`
§6.6, now superseded) and an equal-normalized-loading rule that ignored that
distinction entirely. Both were trying to answer different questions with one
symbol. V1 uses three:

```text
Q[e,k]   structural opportunity     "Can exercise e provide evidence
                                      about competency k at all?"

q[e,k]   derived predictor loading  "How much weight does k get in the
                                      provisional performance predictor?"

w[a,k]   evidence attribution       "How informative was what actually
                                      happened in attempt a, for
                                      competency k?"
```

`Q` and `q` are indexed by exercise `e`: they describe the exercise's design and
don't change between two attempts at it. `w` is indexed by attempt `a`, not
exercise `e`, precisely because it's computed from what actually happened: two
attempts at the identical exercise can produce different `w`.

Only `Q` is domain truth. `q` is a provisional mathematical convenience built
from `Q`. `w` is computed per attempt, after the fact, from the actual
observation.

### 9.1 Structural Q-matrix

\[ Q\_{e,k} `\in \{0,1\}`{=tex} \]

> Does exercise `e` create an opportunity to observe competency `k`?

This is binary, not qualitative, and it is **generated from exercise
composition**, not authored as a per-scale table:

```text
MAJOR_SCALE_TOPOLOGY / NATURAL_MINOR_TOPOLOGY /
HARMONIC_MINOR_TOPOLOGY / MELODIC_MINOR_TOPOLOGY
    1 iff material.form matches

RH_SCALE_EXECUTION
    1 iff hands ∈ {RIGHT, TOGETHER}

LH_SCALE_EXECUTION
    1 iff hands ∈ {LEFT, TOGETHER}

SCALAR_CROSSING
    1 iff the generated event stream contains a crossing opportunity

MULTI_OCTAVE_CONTINUATION
    1 iff the generated exercise contains an internal octave continuation

DIRECTION_REVERSAL
    1 iff the exercise contains a turnaround/reversal

HANDS_TOGETHER_COORDINATION
    1 iff hands == TOGETHER
```

Tonic barely matters to `Q` membership: exact material identity already lives in
`MaterialMemoryState`, and hand/material idiosyncrasy already lives in
`MaterialExecutionState`. `Q` only needs to know which transferable competencies
this exercise's composition (material form, hand configuration, and generated
event stream) can provide evidence about at all.

`Q` does **not** depend on guidance level. Guidance changes how much a given
outcome tells us (§6, §18), not which musical material or motor opportunities
the exercise contains. A fully-cued harmonic-minor exercise still has
`Q[HARMONIC_MINOR_TOPOLOGY] = 1`; the evidence model just assigns it a near-zero
`w`.

Example, two-octave F major RH, ascending and descending:

| Competency                    |   Q |
| ----------------------------- | --: |
| `MAJOR_SCALE_TOPOLOGY`        |   1 |
| `RH_SCALE_EXECUTION`          |   1 |
| `SCALAR_CROSSING`             |   1 |
| `MULTI_OCTAVE_CONTINUATION`   |   1 |
| `DIRECTION_REVERSAL`          |   1 |
| `HANDS_TOGETHER_COORDINATION` |   0 |

(`LH_SCALE_EXECUTION` and the other three `SCALE_TOPOLOGY` competencies are 0
and omitted from the table.)

### 9.2 Derived predictor loading

For the provisional performance predictor (§10), normalize `Q` into a loading:

\[ q\_{e,k} = `\frac{Q_{e,k}}{\sum_j Q_{e,j}}`{=tex} \]

This keeps the original reasoning for equal normalized loadings (avoiding
invented per-competency weights such as 0.7 or 0.4) while making explicit that
`q` is _derived from_ `Q`, not an independently authored quantity. For the
F-major example above (5 relevant competencies), each gets `q = 0.2`.

Later data can estimate unequal loadings; that remains a heuristic V1 choice to
revisit. It does not require reintroducing `PRIMARY`/`SECONDARY` into `Q`
itself.

#### 9.2.1 Loadings are renormalized within a prediction channel, not just over all of `Q`

§10 splits the single performance logit into separate motor, topology, and
retrieval-availability predictions. Each of those channels needs its own
loading, renormalized within its own competency subset, not the single `q`
above restricted post hoc: dividing the full-`Q` loading down to only the
motor-relevant terms would systematically understate the motor channel's
competency term whenever topology is also relevant to the same exercise
(true for nearly every exercise, since a form's topology competency is
almost always in `Q` alongside its motor competencies). Concretely:

```text
q_motor[e,k]      Q[e,k] / sum(Q[e,j] for j in MOTOR_COMPETENCIES) if k motor, else 0
q_topology[e,k]   Q[e,k] / sum(Q[e,j] for j in TOPOLOGY_COMPETENCIES) if k topology, else 0
```

`q_{e,k}` from this section remains the general-purpose derived loading (used
in traces/diagnostics for the exercise's full evidence footprint); the
subset-renormalized variants are what the performance model and competency
update actually use per channel.

### 9.3 Evidence attribution

\[ w\_{a,k} `\in [0,1]`{=tex} \]

> Given what actually happened in attempt `a`, how informative is the
> observation about competency `k`?

This is where the old Q-matrix's `PRIMARY`/`SECONDARY` reasoning actually
belongs. Consider a two-octave HT exercise where both hands are individually
strong but the attempt falls apart during HT performance:

```text
Q[RH_SCALE_EXECUTION]          = 1        w  low
Q[LH_SCALE_EXECUTION]          = 1        w  low
Q[HANDS_TOGETHER_COORDINATION] = 1        w  high
```

`Q` doesn't change between attempts; `w` does. An HT hesitation is ambiguous
with respect to either individual hand (RH weakness, LH weakness, or a
coordination failure), so the evidence model should update
`HANDS_TOGETHER_COORDINATION` strongly while updating
`RH_SCALE_EXECUTION`/`LH_SCALE_EXECUTION` cautiously. A clean HT success can
still provide some positive evidence for all three. This is the same principle
the domain model already noted (`../domain-model/v1-domain-model.md` §8-11), now
living as a number instead of a qualitative table label.

`w_{a,k}` is specific to `LatentCompetencyState` evidence attribution. Other
state layers use analogous evidence-informativeness terms: the `w` in §15.1's
uncertainty update, `w_r` in §16 (material-execution evidence), and `w_M` in §18
(material-memory evidence), but these are not instances of the same mathematical
quantity. `MaterialMemoryState` and `MaterialExecutionState` are not
competencies, so `w_r` and `w_M` answer "how informative was this attempt about
this material/context," not "...about this competency." They share the general
principle of evidence-weighted updating, not a common formula, and should stay
distinct symbols with distinct meanings rather than letting `w` become a
universal scalar attached to an attempt; that distinction will matter once the
Evidence Model is formalized.

### 9.4 Cross-competency transfer is not a Q-matrix entry

If strong `RH_SCALE_EXECUTION` evidence improves the _prior_ for under-observed
`LH_SCALE_EXECUTION` (`02-v1-design.md` §9.1.5), that transfer happens in the
prior/correlation structure of the competency state, not by setting
`Q[e, LH_SCALE_EXECUTION] = 1` on an RH-only exercise. If no LH opportunity
occurred, `Q[e, LH_SCALE_EXECUTION] = 0`, full stop. The same applies to
transfer between scale-topology competencies (e.g. harmonic-minor practice
informing a melodic-minor prior): it's a relationship between competency states,
never a fictitious `Q` entry recording practice that didn't happen. This
preserves the invariant already stated in `02-v1-design.md` §14: related
practice transfers through shared/correlated state, not by recording it as if it
were direct practice of untested material or context.

## 10. Performance model

### 10.0 Superseded: single shared logit

The originally proposed single logit,

\[ `\eta`{=tex}_{u,e,t} = b + `\sum`{=tex}*k q*{e,k}`\mu`{=tex}_{u,k}(t) +
`\gamma`{=tex}_M z(M_{u,m}(t)) + `\mu`{=tex}\_{r,u,m,c}(t) - D(e) \]

with `p_hat = sigma(eta)`, is **superseded**. Simulation (`analysis/learner-model/`,
documented at length in commit history as "Experiment B") found a specific
failure mode: when `M` collapses toward 0 (as the §5.2-superseded half-life
rule made it, but the problem is structural, not limited to that one bug),
`gamma_M z(M)` dominates `eta` and pins `p_hat` near 0 regardless of the
competency term. Every attempt that then happens to start reads as a large,
spurious positive prediction error, and that error gets attributed to
whichever competencies the exercise touches - a badly calibrated memory
estimate manufacturing apparent motor learning it didn't cause. Rerunning
the same synthetic beginner profile under the split model below reversed
competency-error correction from -18% (diverging) to +6% (converging), with
the memory half-life dynamics left deliberately unchanged, isolating the
single shared logit itself as the defect, not the memory rule that first
exposed it. See §29.2 and §34 for the resulting invariants.

### 10.1 Two-stage retrieval/execution model, with topology as a separate channel

The validated replacement factors "was an acceptable attempt produced" into
two questions that ask genuinely different things about the learner, plus a
third channel for pitch/form knowledge that is neither:

\[ `\hat `{=tex}p\_{`\mathrm{overall}`{=tex}} = `\hat `{=tex}p\_{`\mathrm{available}`{=tex}} `\cdot `{=tex}
`\hat `{=tex}p\_{`\mathrm{exec}`{=tex}} \]

```text
p_hat_retrieval    P(independent retrieval): M(t) itself, no transform
p_hat_available    P(material available): 1 - d_e(1 - M(t)); guidance can
                    supply material the learner wouldn't independently
                    retrieve, mirrored structurally in the synthetic
                    generator's own outcome-sampling formula
p_hat_exec         P(acceptable execution | material available):
                    sigma(eta_exec)
p_hat_topology     P(topology/pitch-form correctly known): sigma(eta_topology)
p_hat_overall      p_hat_available * p_hat_exec
```

\[ `\eta`{=tex}\_{`\mathrm{exec}`{=tex}} = `\sum`{=tex}\_{k
`\in `{=tex}`\mathrm{Motor}`{=tex}} q\_{`\mathrm{motor}`{=tex}}[e,k]
`\tilde `{=tex}`\mu`{=tex}_{u,k}(t) + `\mu`{=tex}\_{r,u,m,c}(t) -
D\_{`\mathrm{motor}`{=tex}}(e) \]

\[ `\eta`{=tex}\_{`\mathrm{topology}`{=tex}} = `\sum`{=tex}\_{k
`\in `{=tex}`\mathrm{Topology}`{=tex}} q\_{`\mathrm{topology}`{=tex}}[e,k]
`\tilde `{=tex}`\mu`{=tex}_{u,k}(t) \]

where `\tilde\mu_{u,k}` is the correlated-prior-adjusted competency mean
(`02-v1-design.md` §9.1.5), `q_motor`/`q_topology` are the subset-renormalized
loadings (§9.2.1), and `Motor`/`Topology` partition the ten Competencies
(§9.1.2) exactly along the `CompetencyCategory` boundary already established
there.

`p_hat_topology` deliberately does **not** enter `p_hat_overall`: it answers
a different question than "would this attempt succeed" -
`p_hat_available`/`p_hat_exec` are about _this attempt_, while
`p_hat_topology` is a standing belief about latent pitch-form knowledge.
Folding it into the same product would make it a fourth hurdle factor rather
than what it actually is, a parallel inference target with its own evidence
channel (§12, §15). Keep this distinction explicit in any future revision;
it is easy to look at three predicted probabilities and "correct" the
equation into a three-factor product.

`gamma_M z(M)` (the old memory-transform term) is retired along with the
single shared logit it belonged to (§10.0). Memory no longer enters the
execution-latent scale, so no memory transform is required by the V1
performance model.

`D_motor(e)` drops the guidance term `G_e` that the original `D(e)` (§11)
carried: guidance affects whether material is _available_
(`p_hat_available`), not how hard it is to _execute_ once available. A
guidance term inside execution difficulty double-counts cueing's effect once
the hurdle split separates the two questions. §11 restates this.

Two invariants lock the separation in directly (`analysis/learner-model/invariants.py`):
guidance changes `p_hat_available` but leaves `p_hat_retrieval` and
`p_hat_exec` exactly unchanged; and varying motor evidence
(continuity/temporal-stability) never moves a topology competency's mean,
nor does varying topology evidence move a motor competency's.

## 11. Task difficulty

Initially:

\[ D\_{`\mathrm{motor}`{=tex}}(e) = `\beta`{=tex}\_t g(`\mathrm{BPM}`{=tex}) +
`\beta`{=tex}\_o O_e + `\beta`{=tex}\_h H_e + `\beta`{=tex}\_d D_e \]

where candidate terms include:

```text
BPM         tempo
O           octave-count effect
H           hand-configuration effect
D           direction effect
```

No guidance term: §10.1's hurdle split puts guidance's effect on
`p_hat_available` (via `d_e`, §6), not on execution difficulty. A `beta_g G_e`
term inside `D(e)` was part of the original single-logit proposal
(superseded, §10.0); once retrieval availability and execution are separate
predictions, keeping a guidance term here as well would double-count cueing.
Simulation's synthetic ground-truth generator carried the same conflation
(guidance affecting true motor quality, not just true retrievability) and
needed the equivalent fix once the estimator's split exposed the mismatch
between them - a reminder that this is a structural claim about which factors
belong on which side of the hurdle, not just an estimator implementation
detail.

Geometry, motor-event structure, and exercise pattern should be recorded even if
omitted from the first fitted/predictive equation.

### 11.1 Tempo transform

A candidate V1 transform is:

\[ g(`\mathrm{BPM}`{=tex}) =
`\log`{=tex}`\left`{=tex}(`\frac{\mathrm{BPM}}{\mathrm{BPM}_0}`{=tex}`\right`{=tex})
\]

because proportional tempo increases are more naturally represented than
absolute BPM differences.

This remains a modeling hypothesis to test in simulation and later telemetry;
simulation has used it unchanged since the prototype's first version.

### 11.2 Difficulty coefficients

Initial values for:

```text
beta_t
beta_o
beta_h
beta_d
```

are heuristic. `beta_g` is retired along with the guidance term above.

The model architecture should make them explicit and versioned so they can be
replaced by fitted coefficients without changing persisted observations.

## 12. Rich performance outcomes

The learner-state model is parsimonious; the evidence representation is not.

An attempt should retain multiple outcome channels, for example:

\[ y\_{`\mathrm{pitch}`{=tex}} `\in [0,1]`{=tex}\]

\[ y\_{`\mathrm{continuity}`{=tex}} `\in [0,1]`{=tex}\]

\[ y\_{`\mathrm{stability}`{=tex}} `\in [0,1]`{=tex}\]

and, for HT:

\[ y\_{`\mathrm{coordination}`{=tex}} `\in [0,1]`{=tex}\]

Additional event-local observations should remain available rather than being
discarded after computing these summaries.

The exact scoring functions that map MIDI observations to these bounded outcomes
belong to the observation/evidence specification, not to the latent state
definition.

§10.1's topology channel needs its own outcome, independent of the channels
above:

\[ y\_{`\mathrm{topology}`{=tex}} `\in [0,1]`{=tex}\]

`y_pitch` (pitch/sequence integrity, `y_sequence`/`I_sequence` elsewhere in
this document) is not a substitute: simulation's synthetic generator blends
it from both material-retrieval quality and motor quality, so using it as
`y_topology`'s target would let retrieval noise back into topology
competency evidence through the observation side even after §10.1 removed it
from the prediction side. `y_topology` should instead measure pitch/form
correctness on its own, independent of whether the material was
independently retrieved or how cleanly it was executed - "poor topology,
good execution" and "good topology, poor execution" need to be
representable as distinct cases, in both the synthetic generator and real
evidence extraction. §15 covers the corresponding update.

## 13. Scheduler success score versus state evidence

The scheduler may require a scalar:

\[ y\_{`\mathrm{scheduler}`{=tex}} \]

or predicted probability:

\[ `\hat `{=tex}p\_{`\mathrm{acceptable}`{=tex}} \]

to compare candidate exercises.

State updates should **not** therefore be forced through the same scalar.

For example:

```text
MaterialMemoryState
    primarily informed by independent pitch/sequence retrieval

topology competencies
    primarily informed by pitch/sequence evidence

motor competencies
    informed by continuity, timing, and event-local behavior

MaterialExecutionState
    informed by persistent deviation from the shared prediction
```

This separation prevents a single composite score from destroying diagnostic
information.

## 14. Prediction error

For a bounded outcome:

\[ y `\in [0,1]`{=tex}\]

and prediction:

\[ `\hat `{=tex}p `\in [0,1]`{=tex}\]

define prediction error:

\[ `\delta `{=tex}= y-`\hat `{=tex}p \]

This provides a simple online learning signal.

A learner who performs better than expected yields positive evidence; worse than
expected yields negative evidence.

There is one `delta` per prediction channel (§10.1), not one universal
`delta` shared across state layers:

```text
delta_exec       y_motor - p_hat_exec           (motor competencies, §15;
                                                  execution residual, §16)
                 y_motor = (y_continuity + y_stability) / 2 - not y_pitch,
                 which blends in retrieval quality (§12)
delta_topology   y_topology - p_hat_topology     (topology competencies, §15)
delta_M          y_retrieval - p_hat_retrieval   (material memory, §18)
```

This followed directly from §10.0's finding: a shared `delta` computed
against a blended prediction lets a badly calibrated layer manufacture
apparent evidence for another layer's state. The general rule (§13) is that
a state layer should be updated only from a residual whose prediction was
actually generated by that layer.

## 15. Provisional competency update

For relevant competency `k`:

\[ `\mu`{=tex}'_{u,k} = `\mu`{=tex}_{u,k} + `\alpha`{=tex}_k
q_{e,k}`\delta`{=tex}\_k \]

where:

```text
alpha_k    V1 learning-rate parameter
q_e,k      exercise loading
delta_k    evidence-channel prediction error relevant to competency k
```

The update should be applied only when the attempt contains meaningful evidence
for that competency.

For example, failure to retrieve a scale and therefore never beginning the
physical execution should not strongly reduce motor competencies.

`q_{e,k}` and `delta_k` are channel-specific (§9.2.1, §14): a motor
competency `k` uses `q_motor[e,k]` and `delta_exec`; a topology competency
uses `q_topology[e,k]` and `delta_topology`. Both still share one `alpha_k`
learning-rate parameter and the same update form; only the loading and the
prediction error driving it differ by channel. Before this split, topology
competencies were updated from `delta_exec` (continuity/temporal-stability
evidence, which carries no information about pitch/form knowledge in the
synthetic generator) purely because they shared a Q-matrix entry with motor
competencies on the same exercise - diluting rather than informing their
estimates. `w_{a,k}` (§9.3) still attenuates topology's update under heavy
cueing exactly as before; only the target it's attenuating changed.

### 15.1 Competency uncertainty update

A simple V1 rule can reduce variance after informative evidence:

\[ `\sigma`{=tex}'\^2\_{u,k} = `\max`{=tex}(
`\sigma`{=tex}\^2\_{`\min`{=tex},k},
`\sigma`{=tex}\^2\_{u,k}(1-`\lambda`{=tex}_k w_{a,k}) ) \]

where `w` represents evidence informativeness.

This is an engineering approximation, not exact Bayesian posterior inference.

The important behavior is:

```text
informative evidence -> uncertainty decreases
time without evidence -> uncertainty increases
```

## 16. Provisional execution-residual update

First compute the performance expected from shared state and task features.

The execution residual should absorb only the remaining persistent deviation.

A simple update is:

\[ `\mu`{=tex}'\_r = `\mu`{=tex}\_r + `\alpha`{=tex}_r
w_r`\delta`{=tex}_{`\mathrm{execution}`{=tex}} \]

where `w_r` reflects whether enough actual execution occurred to make the
attempt informative, and `delta_execution` is `delta_exec` (§14) - the
same motor-only prediction error the execution competencies use (§15), not
a shared/blended one. The residual and the competencies it's meant to be a
residual _against_ need to agree on what they're both being corrected
relative to.

Examples:

```text
cannot begin because material is forgotten
    w_r approximately 0

plays complete exercise but consistently underperforms expectation
    w_r high
```

The residual should remain strongly regularized near zero when evidence is
sparse.

## 17. Partial pooling in a local V1 model

Without a population-level hierarchical fit, V1 can approximate partial pooling
through:

1.  a zero-centered residual prior;
2.  high initial residual uncertainty;
3.  conservative residual learning rates;
4.  mean reversion toward zero with nonuse; and
5.  requiring repeated material-specific evidence before allowing a large
    residual magnitude.

This is not equivalent to fitting a full hierarchical Bayesian mixed model, but
it preserves the intended behavior until enough data exists to estimate
population distributions.

## 18. Material-memory update and guidance

Memory updating should distinguish at least:

```text
independent success
supported success
independent failure
supported failure
```

The half-life update itself is specified in §5.2 (log-half-life,
surprise-driven via `delta_M`); this section covers `w_M` and, more
fundamentally, what counts as a retrieval observation at all.

### 18.1 `w_M`

\[ w_M = f( d_e, `\text{prior exposure}`{=tex},
`\text{attempt completion}`{=tex}, `\text{sequence evidence}`{=tex} ) \]

remains the right shape: an evidence weight scaling how much a given attempt
should move the memory estimate. §5.2's update multiplies `w_M` against the
whole bracket (evidence term and reversion term together) - a bug found in
review had `w_M` scaling only the evidence term, so a single attempt with
`w_M` near zero could still meaningfully move an established estimate
through an unweighted reversion pull. The exact definition of `w_M` is a V1
heuristic to be tested.

### 18.2 Retrieval-not-tested is a distinct observation from retrieval-tested-and-failed

The distinction that turned out to matter is not continuous attenuation of
`w_M` but a categorical one underneath it. Continuous cueing (concurrent
pitch/note-name display) supplies the material outright: the learner never
had to demonstrate independent retrieval, so there is no retrieval
observation to weight, weakly or otherwise. Representing that attempt as "a
low-confidence retrieval failure" (small but nonzero `w_M`) is different
from representing it as "not a retrieval observation" (`w_M = 0`
categorically): under repetition, many small-but-nonzero observations of the
same guidance level accumulate under ordinary evidence weighting - simulation
found 50 consecutive fully-cued attempts could erode an established
100-day half-life by roughly 80% this way, which is the evidence-weighting
machinery working correctly on data that didn't actually exist.

The retrieval outcome is therefore three-valued, not two:

```text
retrieval_succeeded = True   independent retrieval was tested and succeeded
retrieval_succeeded = False  independent retrieval was tested and failed
retrieval_succeeded = None   this attempt was not an independent-retrieval
                              observation (continuous cueing supplied the
                              material); w_M = 0 unconditionally, regardless
                              of task completion or any other signal
```

`None` gives `w_M = 0` categorically rather than merely a small value, so it
cannot accumulate into meaningful evidence no matter how many times it
recurs. `notes_previewed` (preview before the attempt, then hidden) remains
a genuine, weaker-than-cold retrieval observation - `retrieval_succeeded` is
a real `True`/`False` there, and repetition legitimately accumulates
evidence, same as an unguided attempt just with lower per-observation
weight. Two invariants hold both sides of this: many fully-cued attempts
with `retrieval_succeeded = None` leave the half-life estimate exactly
unchanged (not merely close), on an estimate established both above and
below the prior; and repeated genuinely-observed low-demand failures do
still lower the estimate.

This has the same shape as the `Q`-matrix reasoning in §9.4: an event that
didn't happen (here, a retrieval that was never tested) must not be recorded
as if it had, however weakly.

## 19. Savings and reacquisition

The current model must not assume that low present readiness means the learner
is equivalent to a novice.

At minimum, persistence should retain historical information such as:

```text
lifetime meaningful attempts
prior successful retrieval history
prior execution evidence
previous posterior/state snapshots where useful
```

The initial V1 equations do not yet specify a distinct savings term.

Simulation should test whether the combination of transferable competency,
historical material memory, and residual dynamics already produces reasonable
reacquisition behavior.

If not, savings becomes an explicit extension rather than being hidden inside an
arbitrary constant.

## 20. Candidate generation

The scheduler should generate exercises from valid combinations of:

```text
TechnicalMaterial
ExercisePattern
ExecutionConditions
GuidanceContext
MotorRealization
```

Candidate generation should enforce domain constraints before scoring, in two
layers with different semantics.

**Hard eligibility**: engineering/domain validity. A candidate that fails one of
these should never be generated at all:

```text
canonical fingering exists
requested octave count is supported
HT implementation is available
tempo lies within allowed product bounds
guidance configuration is valid
```

**Prerequisite gate (`REQUIRES`)**: pedagogical appropriateness given current
learner state, e.g.:

```text
adequate RH_SCALE_EXECUTION + LH_SCALE_EXECUTION
    -> HANDS_TOGETHER_COORDINATION exercises become more/fully eligible
```

Unlike hard eligibility, this gate is normally **soft**: a candidate that falls
short of a prerequisite is a worse candidate, not necessarily an invalid one.
Implementations should treat it as a scoring input rather than an
`if not requires: reject()` check; "eligibility" and "gate" are deliberately
different words from "hard eligibility" above because the two fail differently.
`REQUIRES` (`../domain-model/v1-domain-model.md` §17) belongs in this gate,
ahead of challenge filtering and priority ranking (§22): it answers "how
eligible is this exercise given the current prerequisites," rather than "how
should it rank for retention, information, diversity, or goals."

## 21. Challenge filtering

For each candidate exercise, compute:

\[ `\hat `{=tex}p_e =
P(`\text{acceptable performance}`{=tex}`\mid`{=tex}`\text{current state}`{=tex})
\]

V1 can discard or strongly deprioritize candidates outside a broad challenge
band:

\[ p\_{`\min`{=tex}} `\le`{=tex} `\hat `{=tex}p_e `\le`{=tex} p\_{`\max`{=tex}}
\]

A provisional engineering range such as:

```text
0.60 <= p_hat <= 0.90
```

may be useful for simulation, but is **not** asserted to be a
research-established optimal success range.

The bounds must therefore be configurable and versioned.

Exceptions may deliberately leave the band, for example:

```text
diagnostic probe
new-material introduction
recovery after retrieval failure
explicit learner request
```

## 22. Candidate priority

Among viable candidates, V1 should use an interpretable priority function.

Conceptually:

\[ U(e) = w_R R(e) + w_I I(e) + w_D V(e) + w_G G(e) \]

where candidate terms might represent:

```text
R    retention/review need
I    information value / uncertainty reduction
V    diversity or interleaving value
G    learner-goal priority
```

The exact utility equation is not frozen.

A simpler lexicographic V1 is also acceptable:

```text
1. satisfy challenge constraints
2. prioritize retention need
3. prioritize uncertainty/information value
4. encourage repertoire diversity
5. respect learner goals
```

Simulation should compare the two approaches before implementation.

## 23. Review urgency

A simple material-memory urgency measure is:

\[ R_m = 1-M\_{u,m} \]

A more useful form may incorporate uncertainty:

\[ R_m = f(1-M\_{u,m}, U\_{u,m}) \]

where `U` is uncertainty about the material-memory estimate.

This creates continuous priority rather than a binary due/not-due boundary.

## 24. New-material behavior

For an unseen material:

```text
MaterialMemoryState
    broad prior

MaterialExecutionState
    residual mean = 0
    high uncertainty
```

Prediction is therefore dominated by:

```text
transferable competencies
general task difficulty
material-family/topology priors
```

An experienced learner can consequently receive a more demanding initial probe
than a beginner without requiring an entirely separate placement architecture.

## 25. Parameter provenance

Every numerical parameter should carry an explicit provenance category.

### 25.1 Research-structured

The literature supports the model family or qualitative relationship, but not
necessarily KeyRecall's numerical value.

Examples:

```text
logistic response modeling
hierarchical/partially pooled item effects
time-dependent material retrievability
dynamic latent state
guidance-sensitive retrieval evidence
```

### 25.2 Literature-inspired

The form is borrowed or adapted from prior research, but its use in KeyRecall
requires validation.

Examples:

```text
HLR-style half-life forgetting curve
multi-skill logistic structure
```

### 25.3 Heuristic V1

The value or rule is selected for engineering reasons before sufficient
KeyRecall data exists.

Examples:

```text
initial half-life
memory evidence coefficient (alpha_M)
memory reversion strength (lambda)
competency prior variance
residual prior variance
learning rates
uncertainty diffusion
tempo coefficient
octave penalty
HT penalty
guidance mapping
challenge band
scheduler weights
```

### 25.4 Empirically fitted

Later versions may estimate parameters from KeyRecall longitudinal data.

No parameter should silently move between these categories.

## 26. Initial parameter registry

This registry exists now, not just as a future intention:
`analysis/learner-model/params.toml`, loaded by `params.py` into typed,
frozen dataclasses. Every section below has a `model_version` field
(currently `v1-prototype-0`) but does not yet carry the per-value
`provenance` annotation this section originally sketched; every value in it
is `heuristic` in the §25.3 sense unless noted otherwise. The shape
resembles:

```yaml
model_version: v1-prototype-0

competency:
  prior_mean: ...
  prior_variance: ...
  min_variance: ...
  learning_rate: ...
  uncertainty_diffusion: ...
  evidence_shrinkage: ...

material_memory:
  initial_half_life_days: ...
  alpha_memory: ... # evidence coefficient on log-half-life, §5.2
  reversion_lambda: ... # reversion strength toward the prior, §5.2
  min_half_life_days: ... # numerical guard, not the primary stabilizer
  max_half_life_days: ...
  prior_retrievability: ...
  prior_uncertainty: ...
  min_uncertainty: ...
  evidence_shrinkage: ...
  alpha_cold_start: ... # evidence coefficient on logit(cold_start), §5.3
  reversion_lambda_cold_start: ... # reversion strength toward the prior, §5.3
  min_cold_start_probability: ... # numerical guard
  max_cold_start_probability: ...

material_execution:
  prior_variance: ...
  min_variance: ...
  learning_rate: ...
  mean_reversion_tau_days: ...
  uncertainty_diffusion: ...
  evidence_shrinkage: ...

hand_transfer:
  rho_hand: ... # correlated-prior strength, 02-v1-design.md §9.1.5
  shrinkage_tau: ...

difficulty:
  tempo_beta: ...
  octave_beta: ...
  hand_beta: ...
  direction_beta: ...
  reference_tempo_bpm: ...
  # no guidance_beta: retired with D(e) -> D_motor(e), §11

placement:
  beginner_mean: ...
  some_experience_mean: ...
  advanced_mean: ...
  prior_variance_broad: ...
```

`success_growth`/`failure_shrink` (multiplicative half-life factors) and
`gamma_memory` (the single-logit memory-transform coefficient) from earlier
versions of this registry are retired along with the equations they
belonged to (§5.2, §10.0); they are not renamed fields, they no longer
exist. A `scheduler` section does not exist yet: challenge-band and
priority-ranking parameters (§21-22) remain unimplemented.

Persisting `model_version` with derived learner state and attempts allows later
replay and comparison.

## 27. Simulation before scheduler implementation

The first executable model should be a simulation harness, not the production
scheduler.

It should contain:

```text
LearnerState
PerformanceModel
EvidenceModel
StateUpdater
SyntheticLearner
```

The harness should permit deterministic random seeds and complete state traces.

## 28. Synthetic learner profiles

At minimum, simulate:

```text
BEGINNER
    weak broad competencies
    high uncertainty

INTERMEDIATE
    moderate shared competencies

ADVANCED
    strong shared competencies

RH_STRONG_LH_WEAK
    asymmetric hand competencies

TECHNIQUE_STRONG_MEMORY_WEAK
    strong motor state
    weak material retrieval

MEMORY_STRONG_TECHNIQUE_WEAK
    strong topology/material knowledge
    weak execution

RETURNING
    historically strong
    long nonuse interval

MATERIAL_SPECIFIC_DIFFICULTY
    strong general skill
    persistent negative residual on one material
```

These are test fixtures, not learner labels intended for the product UI.

## 29. State-model simulation tests

Before adding scheduling, verify:

This list is no longer purely aspirational: `analysis/learner-model/invariants.py`
implements it as 23 passing checks against the code in
`analysis/learner-model/{state,model,synthetic}.py`, run via
`mise run analysis:learner-model`. §29.1-§29.8 below are covered; three
categories weren't anticipated when this list was first written and were
added once simulation exposed the need for them:

```text
motor and topology competency updates are independent (§10.1, §15)
guidance affects material availability, not independent retrieval or
    execution (§10.1, §18.2)
log-half-life stays finite/bounded, and repeated *expected* failure
    reaches a stable equilibrium rather than collapsing (§5.2)
unobserved retrieval (continuous cueing) never moves memory state,
    however many times repeated; genuinely observed low-demand failures
    still accumulate evidence (§18.2)
```

`analysis/learner-model/analyze.py` runs a complementary behavioral-diagnostics
pass (calibration, competency convergence, memory tracking, a memory-spacing
sensitivity probe, residual localization, and a parameter-sensitivity sweep)
that answers a different question than these invariants: not "does the model
violate an architectural rule" but "does it behave plausibly over months of
synthetic practice, and which heuristic parameters actually matter." §10.0's
finding (single-logit contamination) and the log-half-life equilibrium
property (§5.2) were both first identified there, then reduced to the
invariants above.

### 29.1 Priors

```text
new learner has broad uncertainty
new material residual is near zero
shared state dominates cold-start prediction
```

### 29.2 Learning

```text
consistent success raises relevant competency estimates
consistent failure lowers them
irrelevant competencies do not move
uncertainty contracts with informative evidence
```

### 29.3 Transfer

```text
practicing one scale improves predictions for related unpracticed scales
without creating fictitious direct attempts
```

### 29.4 Material-specific residual

```text
one persistently awkward scale develops a negative residual
other scales remain governed by shared state
sparse evidence does not create extreme residuals
```

### 29.5 Memory

```text
retrievability decreases with elapsed time
independent retrieval strengthens memory more than prompted execution
retrieval failure changes memory state appropriately
```

### 29.6 Guidance

```text
full cueing produces zero independent-memory evidence, not merely weak
    evidence (categorical, §18.2, not a continuous attenuation)
unguided success produces strong memory evidence
failed unguided retrieval does not strongly penalize motor execution
```

### 29.7 Nonuse

```text
competency uncertainty increases
execution residual becomes less influential
material retrievability decreases
```

### 29.8 Reacquisition

```text
returning learner does not behave identically to a true novice
```

If this fails, investigate whether an explicit savings mechanism is required.

## 30. Scheduler simulation tests

Only after the learner-state model behaves sensibly should the scheduler be
introduced.

Test for pathological policies including:

```text
repeating the same material indefinitely
always choosing the easiest exercise
always choosing the hardest viable exercise
never revisiting older material
over-testing unknown material
rapid tempo oscillation
excessive RH/LH alternation or neglect
guidance that never fades
guidance removed before independent retrieval is plausible
```

The scheduler should instead demonstrate:

```text
appropriate revisitation
gradual challenge adjustment
meaningful interleaving
guidance fading
recovery after failure
transfer-sensitive introduction of new material
```

## 31. Calibration strategy

V1 calibration should proceed in stages.

### Stage 1: structural simulation

Choose broad heuristic values only to test qualitative behavior.

Question:

> Does the model behave coherently?

### Stage 2: developer/pilot use

Collect longitudinal traces and inspect:

```text
prediction calibration
state trajectories
failure modes
scheduler choices
reacquisition
guidance transitions
```

Question:

> Are predictions and state transitions plausible on real piano practice?

### Stage 3: empirical parameter fitting

With sufficient data, estimate:

```text
difficulty coefficients
tempo transform
memory parameters
competency learning rates
residual variance
residual dynamics
guidance effects
scheduler calibration
```

Question:

> Which heuristic assumptions can now be replaced by measured relationships?

### Stage 4: model comparison

Compare the V1 model against alternatives using held-out longitudinal data.

Potential alternatives include:

```text
DAS3H-style temporal features
full hierarchical Bayesian logistic models
multidimensional residuals
factorization models
contextual-bandit scheduling
```

Complexity should be added only when predictive or scheduling benefit justifies
it.

## 32. Required diagnostics

The implementation should make the model inspectable.

For any scheduled exercise, developer diagnostics should be able to explain:

```text
predicted success
relevant competencies and their estimates
material retrievability
material execution residual
task-difficulty contributions
guidance/retrieval demand
uncertainty
review urgency
scheduler priority components
```

A scheduler whose decisions cannot be inspected will be much harder to validate
during the period when most parameters are heuristic.

## 33. Persistence requirements

To permit replay and future model fitting, preserve:

```text
attempt timestamp
technical material
exercise pattern
execution conditions
guidance context
retrieval context
model version
raw or sufficiently lossless MIDI-derived observations
event-local observations
derived evidence with evidence-model version
state before update where practical
state after update or reproducible state snapshot
```

Historical source observations are more valuable than any particular V1 state
estimate because future models can recompute the latter.

## 34. V1 mathematical invariants

The following are the current mathematical invariants:

1.  Performance is predicted from both learner state and task context.
2.  Transferable competencies carry uncertainty.
3.  Material retrievability is distinct from whole-exercise success.
4.  Material memory is time-sensitive.
5.  Material-execution residuals are zero-centered and partially pooled.
6.  Material-execution residuals are dynamic.
7.  Task conditions such as tempo do not create independent remembered items.
8.  Guidance affects evidence interpretation.
9.  Rich outcome channels are retained independently of scheduler scoring.
10. A failed retrieval is not automatically evidence of failed motor capability.
11. Related practice updates shared competencies rather than fictitious
    material-specific attempts.
12. Heuristic constants are explicitly identified and versioned.
13. Historical observations remain available for future refitting.
14. A state layer is updated only from a prediction error its own layer
    generated (§14): motor, topology, and material-memory each predict and
    update from their own channel, never a shared/blended one.
15. Guidance affects material availability, never independent retrievability
    or execution difficulty (§10.1, §11, §18.2).
16. An observation that never happened (retrieval never tested, under
    continuous cueing) is a distinct state from an observation that happened
    and failed, and must not be recorded as weak evidence of failure (§18.2).
17. Repeated _expected_ evidence (predictions already matching outcomes)
    settles at a stable equilibrium; it does not compound into unbounded
    drift merely because attempts keep happening (§5.2).
18. Within one state layer, a representation (and its uncertainty) that
    isn't yet the operative prediction must not move from evidence about a
    different representation: cold-start belief and half-life are both
    `MaterialMemoryState`, but evidence about one must not silently become
    confidence about the other (§5.3).

## 35. Open mathematical decisions

Simulation should resolve or narrow the following before production
implementation:

```text
exact competency prior scale
exact residual prior variance
exact uncertainty update approximation
exact material-memory prior
retrieval-demand mapping
tempo transform
initial difficulty coefficients
residual mean-reversion function
uncertainty diffusion function
composite acceptable-performance definition
challenge-band bounds
candidate utility versus lexicographic ranking
minimum evidence required for residual personalization
explicit savings term, if necessary
```

Resolved by simulation, not merely narrowed:

- ~~**memory success/failure update factors**~~: resolved architecturally
  (§5.2, log-half-life, surprise-driven `delta_M`). The specific `alpha_M`
  and `lambda` values remain heuristic and unfitted.
- ~~**memory transform inside performance logit**~~: resolved by removal.
  `gamma_M z(M)` no longer exists; memory doesn't enter the execution logit
  at all (§10.0-§10.1).
- ~~**retrieval observability**~~: resolved (§18.2). Whether an attempt is a
  retrieval observation at all is categorical and distinct from retrieval
  _demand_ (§6, how much of the material had to be independently produced).
  `retrieval-demand mapping` itself - the numeric demand values, e.g. the
  0.05 floor under continuous cueing - remains open, listed above.
- ~~**cold-start retrievability update**~~: resolved (§5.3), same
  reparameterization as §5.2 in logit space, with its own uncertainty state
  properly separated from `half_life_uncertainty`. `alpha_c`/`lambda_c`
  remain heuristic and unfitted, same status as `alpha_M`/`lambda`.
- ~~**synthetic ground-truth memory clock under continuous cueing**~~:
  resolved. `TrueMaterialMemory` models learning from retrieval practice: the
  clock now resets only when retrieval was both genuinely demanded and
  actually performed, not on a hidden counterfactual success sampled during
  continuous cueing. The latent retrievability draw itself is unchanged and
  still feeds `material_retrieval`; only the clock-reset condition gained the
  `retrieval_observed` guard.

Opened by simulation:

```text
whether the log-half-life update needs an explicit elapsed-time term of its
    own, beyond what leaks through p_hat_retrieval's own decay formula - a
    spacing diagnostic (10 successes at 1 minute/hour/day/week spacing)
    showed meaningfully different inferred half-lives across spacing
    without one, but this hasn't been validated against a known true
    half-life, only checked for the absence of a specific failure mode
    (short spacing implying "extraordinary retention"). Left open: no
    diagnostic has yet demonstrated a problem this would fix.
```

These are deliberately not hidden behind apparently precise constants.

## 36. Proposed implementation sequence

The next implementation work should proceed in this order:

```text
1. Define versioned parameter/config structures.

2. Implement pure state objects:
       CompetencyState
       MaterialMemoryState
       MaterialExecutionState

3. Implement deterministic time propagation.

4. Implement PerformanceModel.

5. Implement EvidenceModel from synthetic outcome channels.

6. Implement StateUpdater.

7. Build synthetic learner generator.

8. Write invariant/property tests.

9. Run longitudinal state simulations.

10. Inspect and revise equations/heuristics.

11. Add candidate generation.

12. Add scheduler challenge filtering.

13. Add candidate prioritization.

14. Run scheduler simulations.

15. Only then connect the model to real MIDI-derived evidence.
```

This sequence isolates learner-model errors from MIDI-analysis errors and
scheduler-policy errors.

## 37. Research basis and boundary

The mathematical architecture is informed by established families including:

- logistic and item-response learner modeling;
- Performance Factors Analysis and DAS3H-style multi-skill temporal models;
- Half-Life Regression;
- hierarchical/mixed-effects models with learner/item effects;
- dynamic/longitudinal latent-state models; and
- motor-learning and procedural-retention research summarized in
  `01-research.md`.

Those sources support the architecture and several qualitative relationships.

They do **not** provide ready-made KeyRecall coefficients for piano technique.
The combination of these components, the mapping from MIDI evidence, and the
initial V1 constants are KeyRecall design choices that must be validated through
simulation and longitudinal use.

## 38. Prototype status and next steps

The prototype this section originally called for now exists
(`analysis/learner-model/`) and has done its job: falsifying bad assumptions
early, before scheduler policy was layered on top. Several rounds of
simulation-driven revision are folded into this document rather than
narrated here in full (git history has the detailed account):

```text
first pass    implemented this document's original equations as code;
              invariant/behavioral testing caught several implementation-
              level bugs (retrieval/exposure conflation, a missing memory-
              scaling factor, a guidance-sign error) without requiring
              architectural change

Experiment B  found and fixed the single-shared-logit cross-layer
              contamination described in §10.0, by splitting retrieval/
              availability from execution

Experiment    found and fixed the same contamination pattern one level down:
B.1           motor and topology competencies sharing one execution channel;
              splitting them further improved every synthetic profile's
              correction (§15)

Experiment C  replaced the multiplicative half-life rule with the log-half-
              life, surprise-driven update (§5.2); review caught two more
              instances of the same underlying pattern (an unweighted
              reversion term, and retrieval-not-tested conflated with
              retrieval-tested-and-failed) before it was safe to commit

Cold-start    applied the same reparameterization to the pre-anchor belief
follow-up     (§5.3); review found the pattern twice more inside this one
              fix (log_half_life moving from evidence that wasn't about it,
              and a shared uncertainty field carrying confidence across to a
              representation no observation had spoken to). Separately,
              resolved the synthetic ground-truth memory clock resetting on
              an untested hidden counterfactual under continuous cueing
```

The consistent shape across every round: a shared/blended prediction,
evidence signal, or state field let one representation manufacture apparent
learning it didn't earn, and the fix was always to give the contaminated
representation its own prediction, its own evidence, and its own
uncertainty, never a numerical containment measure (a cap, a smaller floor,
a threshold) layered on top of the shared signal. §34's invariants 14-18
generalize this.

What remains open is listed in §35: only the question of whether the memory
update needs an explicit elapsed-time term beyond what already leaks through
`p_hat_retrieval`'s decay formula, deliberately left open until a diagnostic
demonstrates a problem it would fix.

The learner-model prototype is now a stable V1 simulation baseline. The
remaining §35 question about explicit elapsed-time weighting is deliberately
deferred until a diagnostic demonstrates a problem that requires it; it does
not block scheduler work.

The next artifact is therefore the scheduler-policy prototype: candidate
generation, eligibility and prerequisite filtering, challenge filtering, and
priority ranking (§20-22), tested against the established synthetic learner
profiles and invariant suite before any production integration.
