# Extending the Competency Model

- **Status:** Future ontology and calibration guide
- **Scope:** Criteria and workflow for proposing, testing, and promoting new
  competencies or prediction channels after V1

## 1. Purpose

This document preserves the extension path built into KeyRecall's V1 learner
model. It is not part of the current production ontology and does not authorize
adding any specific competency. The canonical initial-production behavior
remains [`v1-current-system.md`](v1-current-system.md).

The main future challenge is unlikely to be plumbing a new competency into the
model. The generic state and `Q`/`q`/`w` machinery already support that. The
hard question is whether a proposed capability is empirically distinct,
transferable, and identifiable enough to deserve persistent state rather than
remaining domain structure, an observed outcome, or a material residual.

## 2. The existing extension seam

Adding a competency within an existing prediction channel follows the same
generic path as every V1 competency:

```text
add persistent competency state with mean and variance
    -> define structural exposure with Q[e,k]
    -> define predictor loading with q[e,k]
    -> define attempt evidence with w[a,k]
    -> connect it to the appropriate prediction error and update
    -> add isolating invariants and synthetic fixtures
```

This path does not require redesigning exact-material memory, material-specific
execution residuals, or scheduler stages. Candidate examples might include:

```text
THUMB_UNDER_TRANSITION
CHROMATIC_FINGERING
ARPEGGIO_THUMB_TRANSITION
ARPEGGIO_HAND_SHAPE
REPEATED_NOTE_TECHNIQUE
```

These names are illustrative proposals, not accepted ontology entries.

## 3. Ontology expansion versus a new prediction channel

The first design decision is whether the proposed ability fits an existing
channel.

### 3.1 Routine ontology expansion

A new motor factor joins the motor structural map, contributes to `eta_exec`,
receives motor evidence weights, and updates from `delta_exec`. Examples include
octave displacement, thumb transitions, repeated-note technique, or arpeggio
hand shape.

A new pitch/form factor joins the topology structural map, contributes to
`eta_topology`, receives topology evidence weights, and updates from
`delta_topology`.

These are ontology extensions. Their prediction and observation semantics
already exist.

Routine ontology expansion may change predictions within an existing channel,
but it does not by itself authorize new scheduler stages, exception types,
ranking terms, or challenge semantics. Scheduler structure remains frozen and
must be evaluated unchanged when characterizing the consequences of the new
predictions.

### 3.2 Structural model expansion

An ability that does not fit retrieval, conditional execution, or topology may
need its own prediction, outcome, uncertainty, and error channel. Sight-reading
fluency or expressive timing could fall into this category if KeyRecall later
treats either as an independent target that influences challenge admission.

That is not “one more competency.” It changes the state/prediction contract and
is a structural post-V1 decision. It must clear the learner-model reopening gate
in
[`05-production-implementation-plan.md`](05-production-implementation-plan.md)
before implementation.

The rule is:

> Extend an existing channel when the proposed competency answers an existing
> prediction question. Add a channel only when the system must ask and observe a
> genuinely new question.

## 4. Identifiability comes before tuning

Do not begin by choosing a learning rate. First show that observations can
distinguish the proposed competency from its neighbors.

For a hypothetical `ARPEGGIO_THUMB_TRANSITION`, construct controlled synthetic
truth profiles such as:

```text
learner A    strong general RH execution, weak thumb transition
learner B    strong general RH execution, strong thumb transition
learner C    weak general RH execution, strong thumb transition
learner D    weak general RH execution, weak thumb transition
```

Exercise contrasts should vary structural exposure while holding other causes as
stable as possible:

```text
high thumb-transition opportunity
low or no thumb-transition opportunity
same material under different motor demands
different materials sharing the proposed competency
```

This is a factorial identifiability test, not a realistic learner taxonomy or a
product-facing label.

## 5. Minimum synthetic claims

Before tuning coefficients, the extension must demonstrate all of these:

1. Exercises with `Q[e,k] = 0` do not update the new competency.
2. Under controlled exposure, trajectories generated from weak and strong latent
   competency truth become distinguishable in the estimated competency state and
   relevant held-out predictions.
3. Learning on one material improves prediction for another material that shares
   the competency.
4. The material execution residual does not absorb all transferable signal
   before the competency can learn it.
5. The new state does not contaminate unrelated competencies or prediction
   channels.
6. Held-out prediction improves relative to the simpler ontology.
7. Uncertainty contracts from direct relevant evidence and diffuses under nonuse
   without becoming spuriously confident.
8. The candidate provides incremental held-out predictive value beyond the most
   closely related existing competencies; adding it does not merely split one
   identifiable latent factor into two unstable states.

The minimum redundancy comparison includes:

```text
candidate competency versus covariance with existing competencies
candidate model containing both the new and closest existing competency
ablation with the candidate removed
ablation with the closest existing competency removed
```

A candidate that works in isolation but adds no stable value once the accepted
ontology is present is redundant, not an extension.

Failure of one of these claims should first trigger a review of structural
exposure, observations, and identifiability. It is not a reason to compensate
with a larger learning rate.

## 6. Use residual structure to discover missing competencies

The material-specific execution residual is both a safety valve and a discovery
signal.

If learners consistently struggle with one material for an unmodeled reason, a
negative material/context residual can protect prediction quality. That is the
correct fallback while evidence is sparse. But if the same unexplained error
recurs across several materials sharing a structural feature, separate residuals
may be hiding one transferable competency.

Raw correlation among learned residual means is not sufficient: exposure and
scheduler policy can make those states move together. The useful production
question is:

> After conditioning on existing competencies, task difficulty, guidance, and
> known material/context effects, do the remaining errors covary with a shared
> structural feature?

A natural discovery path is:

```text
conditioned residual covariance
        |
        v
candidate shared structural feature
        |
        v
candidate competency and Q mapping
        |
        v
offline replay and held-out comparison
        |
        v
promotion only if predictive transfer improves
```

This must be assessed across learners and held-out materials. Better fit on the
same material is evidence for a residual, not necessarily a transferable
competency.

## 7. Validate with replay

The production journal is designed to replay the same learner histories through
alternative model versions without changing what the learners experienced.

Compare:

```text
accepted V1 ontology
versus
V1 plus one candidate competency
```

Keep two evaluation modes distinct:

```text
observational replay
    preserves historical presented exercises and outcomes
    compares alternative learner models on the same factual evidence

policy counterfactual simulation
    allows the alternative model to make different future choices
    requires a synthetic or fitted outcome model
    is not empirical replay, even when initialized from historical state
```

Observational comparison must preserve the original presented exercise,
outcomes, decision context, domain/catalog version, parameters, and factual
evidence. The candidate model may reinterpret the recorded observations, but it
must not rewrite the historical policy trajectory and then mistake that
counterfactual experience for observed data.

Policy counterfactual simulation answers a separate question about downstream
scheduler consequences. Its generated outcomes must remain labeled as modeled
rather than observed.

Prefer forward or held-out evaluation. At minimum, require:

- retrieval calibration remains stable unless the feature genuinely affects
  retrieval;
- execution MAE/Brier improves on structurally relevant exercises;
- unrelated exercise predictions remain stable;
- material residual magnitudes shrink where the shared feature now explains
  their covariance;
- uncertainty converges sensibly rather than collapsing;
- cross-material generalization improves; and
- gains reproduce across learners, materials, and time splits.

Improved in-sample fit is insufficient. The new state adds flexibility by
construction; its value is transfer and forward prediction.

## 8. Calibrate competency families before individual keys

The generic update remains:

```math
\mu'_k = \mu_k + \alpha_k q_{e,k}w_{a,k}\delta_{channel}
```

A new competency does not initially need an independently hand-tuned learning
rate, diffusion rate, evidence shrinkage, prior mean, and prior variance. Group
competencies into calibration families such as:

```text
topology
broad motor
localized motor
coordination
```

Share parameters within a family unless longitudinal data support a split. This
reduces the number of weakly identified coefficients and makes comparisons
between the simpler and extended ontology more stable.

Share a calibration family only where the parameters have the same semantic
meaning. Initialization may still depend on explicitly modeled placement or
relationships to existing broad competency state; family membership does not
require every competency to begin from an identical prior.

With enough learners and repeated material coverage, these families can acquire
population-level or hierarchical priors. At that point, the V1 residual's
zero-centered shrinkage approximation can also become a fitted partial-pooling
model.

Parameter calibration is downstream of structural admission:

```text
prove observability and transfer
    -> establish held-out value
    -> assign a shared parameter family
    -> tune family parameters
    -> split competency-specific parameters only with evidence
```

## 9. Keep competency identity out of generic learner mechanics

The competency list must not become the model architecture. Production
competencies should be primarily data-driven descriptors, for example:

```text
id
prediction_channel
prior_family
diffusion_family
structural feature or opportunity mapping
```

Domain extraction may require competency-specific code, especially when a new
technical event must be derived from a score or fingering realization. The
generic learner prediction and update loops should nevertheless operate on
descriptors and mappings, not accumulate branches such as:

```python
if competency == SCALAR_CROSSING:
    ...
elif competency == DIRECTION_REVERSAL:
    ...
```

This separation is what lets ontology growth remain a data/evidence change
rather than an algorithm rewrite.

Adding a competency changes the dimensionality of persisted learner state.
Existing state must upgrade deterministically and without manufacturing
historical evidence. The new competency begins from its versioned prior unless
an explicit historical observational replay reconstructs it from recorded
attempts. A schema upgrade alone must never pretend those attempts were already
processed under the new ontology.

## 10. Evolve the synthetic harness in two layers

Do not turn the permanent V1 fixture matrix into an exhaustive combination of
every future domain and competency.

Maintain two layers:

```text
Core regression suite
    small, fast, permanently stable
    protects V1 semantics and previously observed failures

Extension characterization suite
    scoped to one proposed competency or technical-material family
    may be larger while the mechanism is under investigation
```

When an extension is accepted, graduate only its essential invariants and
regression fixtures into the core suite. Preserve the larger characterization
and its conclusion as an audit artifact; it need not run on every change.

An arpeggio extension, for example, should have a focused characterization suite
for arpeggio transfer, structural exposure, residual confounding, and separation
from scale competencies. Only stable semantic protections belong in the common
regression matrix.

## 11. Promotion gate

A candidate competency should clear a high bar:

- repeated conditioned error covariance across exercises sharing a structural
  feature;
- enough observations to distinguish it from existing competencies;
- incremental predictive value beyond the most closely related existing
  competencies;
- meaningful held-out or forward prediction improvement;
- transfer across materials that the existing model cannot explain;
- stable results across learners, cohorts, materials, and time splits;
- stable or improved calibration outside the affected exercises;
- sensible uncertainty and parameter estimates;
- stable scheduler consequences: no unacceptable concentration, revisit-gap,
  no-admission, recovery, or guidance regression under the unchanged policy; and
- successful replay against all current invariants and scheduler guardrails.

Evaluate admission and downstream compatibility in that order:

```text
learner-model admission
    identifiability
    nonredundancy
    transfer
    held-out calibration

then scheduler compatibility
    unchanged policy
    changed predictions
    guardrail characterization
```

Scheduler characterization tests the consequences of the candidate learner
model. It must not retune the scheduler to make the ontology extension pass.

Interpret the result according to where it generalizes:

```text
improves the same material only
    -> retain or refine the material residual

improves several structurally related materials
    -> evidence for a transferable competency

requires a new predicted and observed outcome
    -> candidate structural channel change, not routine ontology expansion
```

No candidate should be promoted solely because its feature has a plausible
musical name or because a more flexible model fits training data better.

## 12. Extension workflow

Use this sequence for every proposal:

1. Name the proposed capability and its prediction channel.
2. State why existing competencies and residuals cannot explain it.
3. Define observable structural opportunities and generate `Q`.
4. Define predictor loading `q` without inventing unsupported precision.
5. Define attempt evidence `w`, including zero-evidence cases.
6. Build controlled weak/strong truth contrasts and exposure/no-exposure
   exercises.
7. Prove isolation, identifiability, nonredundancy, transfer, and uncertainty
   behavior.
8. Analyze conditioned real errors and data coverage.
9. Run observational replay through baseline and candidate models.
10. Compare held-out calibration, transfer, residual structure, and unrelated
    predictions.
11. Characterize admission, ranking, concentration, revisit, recovery, guidance,
    and no-admission behavior under the unchanged scheduler.
12. Assign shared family parameters before considering competency-specific
    tuning.
13. Promote only after the learner-model reopening gate is satisfied.
14. Version the ontology, mappings, parameters, and replay semantics together.
15. Graduate the smallest durable regression set into the core suite.

The stopping rule is as important as the workflow: when evidence cannot separate
the candidate from existing state, preserve the simpler ontology and collect
better observations rather than tuning around nonidentifiability.
