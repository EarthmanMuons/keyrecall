# V1 Learner-Model Mathematics

## 1. Purpose

This document specifies the smallest mathematically coherent learner model
proposed for KeyRecall V1.

It is subordinate to:

- `learner-model-research.md`, which preserves the research basis; and
- `v1-learner-model-design.md`, which defines the conceptual architecture.

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

and competency loadings:

\[ q\_{e,k} \]

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
  half_life_seconds: ...
  last_retrieval_at: ...
  uncertainty: ...
```

### 5.1 Memory is not exercise-success probability

A value such as:

\[ M\_{u,m}=0.6 \]

means the model estimates moderate independent availability of the technical
material under an appropriate retrieval context.

It does **not** mean there is a 60% probability that the learner can execute the
requested exercise successfully. Motor capability, execution context, tempo,
guidance, and other task conditions remain relevant.

### 5.2 Provisional half-life update

Until enough data exists to fit an HLR-like feature model, V1 may use a
conservative multiplicative update:

\[ h' = h `\cdot `{=tex}g \]

after informative successful retrieval, and:

\[ h' = h `\cdot `{=tex}s \]

after informative retrieval failure, where:

\[ g \> 1 \]

and:

\[ 0 \< s \< 1 \]

The values of `g` and `s` are heuristic V1 parameters.

The effective update magnitude must depend on retrieval context. A continuously
prompted performance should not produce the same half-life update as an
independent retrieval.

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

## 9. Competency loadings

Each exercise has a set of relevant transferable competencies.

Let:

\[ q\_{e,k} `\ge 0`{=tex} \]

be the loading of exercise `e` on competency `k`.

For a simple V1 implementation, equal normalized loadings are preferable to
invented expert weights.

If an exercise meaningfully loads on `n` competencies:

\[ q\_{e,k} = `\frac{1}{n}`{=tex} \]

for each relevant competency, and zero otherwise.

Example:

```text
F# harmonic minor RH, two octaves

HARMONIC_MINOR_TOPOLOGY       0.25
DIATONIC_SCALE_MOTOR          0.25
RH_SCALE_EXECUTION            0.25
SCALAR_CROSSING               0.25
```

This is deliberately simpler than assigning unsupported values such as 0.7 or
0.4 to individual competencies.

The existing motor taxonomy and opportunity analysis determine which
competencies are relevant. Later data can estimate unequal loadings.

## 10. Performance model

Define an exercise performance logit:

\[ `\eta`{=tex}_{u,e,t} = b + `\sum`{=tex}*k q*{e,k}`\mu`{=tex}_{u,k}(t) +
`\gamma`{=tex}_M z(M_{u,m}(t)) + `\mu`{=tex}\_{r,u,m,c}(t) - D(e) \]

and:

\[ `\hat `{=tex}p\_{u,e,t} = `\sigma`{=tex}(`\eta`{=tex}\_{u,e,t}) =
`\frac{1}{1+e^{-\eta_{u,e,t}}}`{=tex} \]

where:

```text
b           intercept
q           competency loading
mu_k        transferable competency estimate
M           material retrievability
z(M)        transform used to place memory on model scale
gamma_M     memory contribution
r           material/context execution residual
D(e)        task difficulty
p_hat       predicted acceptable-performance probability
```

This is the proposed KeyRecall V1 synthesis. It is not copied from a single
published learner model.

### 10.1 Memory transform

Because `M` is a probability while the rest of the model operates on a logit
scale, V1 should not blindly add raw `M`.

A natural candidate is:

\[ z(M) =
`\operatorname{logit}`{=tex}(`\operatorname{clip}`{=tex}(M,`\epsilon`{=tex},1-`\epsilon`{=tex}))
\]

but this is not yet frozen.

Simulation should compare this with simpler bounded transforms before
implementation.

## 11. Task difficulty

Initially:

\[ D(e) = `\beta`{=tex}\_t g(`\mathrm{BPM}`{=tex}) + `\beta`{=tex}\_o O_e +
`\beta`{=tex}\_h H_e + `\beta`{=tex}\_d D_e + `\beta`{=tex}\_g G_e \]

where candidate terms include:

```text
BPM         tempo
O           octave-count effect
H           hand-configuration effect
D           direction effect
G           guidance/support effect where relevant to execution
```

Geometry, motor-event structure, and exercise pattern should be recorded even if
omitted from the first fitted/predictive equation.

### 11.1 Tempo transform

A candidate V1 transform is:

\[ g(`\mathrm{BPM}`{=tex}) =
`\log`{=tex}`\left`{=tex}(`\frac{\mathrm{BPM}}{\mathrm{BPM}_0}`{=tex}`\right`{=tex})
\]

because proportional tempo increases are more naturally represented than
absolute BPM differences.

This remains a modeling hypothesis to test in simulation and later telemetry.

### 11.2 Difficulty coefficients

Initial values for:

```text
beta_t
beta_o
beta_h
beta_d
beta_g
```

are heuristic.

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

### 15.1 Competency uncertainty update

A simple V1 rule can reduce variance after informative evidence:

\[ `\sigma`{=tex}'\^2\_{u,k} = `\max`{=tex}(
`\sigma`{=tex}\^2\_{`\min`{=tex},k},
`\sigma`{=tex}\^2\_{u,k}(1-`\lambda`{=tex}_k w_{e,k}) ) \]

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
attempt informative.

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

A conceptual update weight is:

\[ w_M = f( d_e, `\text{prior exposure}`{=tex},
`\text{attempt completion}`{=tex}, `\text{sequence evidence}`{=tex} ) \]

Then the half-life update can be expressed as:

\[ h' = h `\cdot `{=tex}g\^{w_M} \]

for successful retrieval evidence, or:

\[ h' = h `\cdot `{=tex}s\^{w_M} \]

for retrieval-failure evidence.

This formulation naturally attenuates updates when evidence is weak.

The exact definition of `w_M`, `g`, and `s` is a V1 heuristic to be tested.

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

Candidate generation should enforce domain constraints before scoring.

Examples:

```text
canonical fingering exists
requested octave count is supported
HT implementation is available
tempo lies within allowed product bounds
guidance configuration is valid
```

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
memory growth factor
memory shrink factor
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

A future implementation should maintain a versioned registry resembling:

```yaml
model_version: v1

competency:
  prior_mean:
    value: ...
    provenance: heuristic
  prior_variance:
    value: ...
    provenance: heuristic
  learning_rate:
    value: ...
    provenance: heuristic
  uncertainty_diffusion:
    value: ...
    provenance: heuristic

material_memory:
  initial_half_life:
    value: ...
    provenance: heuristic
  success_growth:
    value: ...
    provenance: heuristic
  failure_shrink:
    value: ...
    provenance: heuristic
  curve:
    value: half_life
    provenance: literature_inspired

material_execution:
  prior_mean:
    value: 0
    provenance: model_design
  prior_variance:
    value: ...
    provenance: heuristic
  learning_rate:
    value: ...
    provenance: heuristic
  mean_reversion:
    value: ...
    provenance: heuristic
  uncertainty_diffusion:
    value: ...
    provenance: heuristic

scheduler:
  challenge_min:
    value: ...
    provenance: heuristic
  challenge_max:
    value: ...
    provenance: heuristic
```

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
full cueing produces weak independent-memory evidence
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

## 35. Open mathematical decisions

Simulation should resolve or narrow the following before production
implementation:

```text
exact competency prior scale
exact residual prior variance
exact uncertainty update approximation
exact material-memory prior
memory success/failure update factors
retrieval-demand mapping
memory transform inside performance logit
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
  `learner-model-research.md`.

Those sources support the architecture and several qualitative relationships.

They do **not** provide ready-made KeyRecall coefficients for piano technique.
The combination of these components, the mapping from MIDI evidence, and the
initial V1 constants are KeyRecall design choices that must be validated through
simulation and longitudinal use.

## 38. Immediate next artifact

The next useful artifact is an executable simulation specification or prototype
that turns the equations in this document into deterministic code and tests the
synthetic learner profiles described above.

The purpose of that prototype is not to optimize parameter values. It is to
falsify bad assumptions early and verify that the state architecture produces
the intended qualitative behavior before scheduler policy is layered on top.
