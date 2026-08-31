# Production Learner and Scheduler Implementation Plan

**Status:** Implementation record. The app exists, and the contracts below were
implemented; read it for why the production shape is what it is, not for what to
build next.  
**Date:** August 20, 2026, with a status revision on August 26, 2026  
**Scope:** Production learner model, scheduler, local history, instrumentation,
offline replay, and optional research telemetry

## 1. Purpose

This document translated the validated learner-model and scheduler work into a
plan for implementing the real KeyRecall app, and the app was then built from
it. The sequencing is history; the contracts it defines, the attempt-event
shape, the update traces, and the deterministic replay requirement, are live and
implemented in `packages/keyrecall_journal` and `packages/keyrecall_practice`.

Where this document and the code disagree, the code is right and the difference
is worth recording here. Four things have moved since it was written: an attempt
now closes with a termination reason and a measurement rather than a bare
outcome, measurement comes from alignment rather than a self-report, material
admission gates candidates in the `REQUIRES` stage, and the Python prototype it
repeatedly refers to is frozen provenance rather than an authority.

The synthetic program is complete for mechanism discovery. It established a
coherent production learner-state architecture, justified one estimator-side
retained-durability inference mechanism, and rejected several attractive but
unsupported scheduler changes. The next implementation must preserve those
boundaries while making every real attempt reconstructable and suitable for
later empirical validation.

The immediate milestone is:

> **Empirical Phase 1: telemetry contract and offline replay validation**

This is not a plan to fit parameters from the first users. It is a plan to
ensure that real practice creates enough trustworthy local history to inspect,
replay, and eventually calibrate the model.

## 2. Authority and dependencies

This document is authoritative for:

- production implementation sequencing;
- the attempt-event and update-trace contracts;
- deterministic offline replay requirements;
- the boundary between complete local history and optional research telemetry;
- empirical validation gates for reopening the learner model or scheduler.

It does not redefine:

- learner-state architecture from `02-v1-design.md`;
- equations and transition semantics from `03-v1-math.md`;
- scheduler stages and information boundaries from `04-v1-scheduler.md`;
- privacy and consent principles from `design/product-vision.md`.

If implementation reveals a conflict with those documents, stop and resolve the
documentation conflict explicitly. Do not silently change semantics in code.

## 3. Decisions frozen before production implementation

### 3.1 Learner-model structure

The production material-memory representation has four distinct meanings:

```text
activation
    memory_anchor_at

current durability
    current_half_life_days
    current_half_life_uncertainty

retained consolidation
    consolidated_half_life_days
    consolidated_log_half_life_variance

factual retrieval history
    factual_last_retrieval_at
    last_retrieval_attempt_at
```

The implementation must preserve these distinctions:

- activation determines current retrievability;
- current durability governs decay from the activation anchor;
- consolidation is the retained upper envelope available for savings and
  restoration;
- factual retrieval history records what was actually observed and must not be
  replaced by a movable activation timestamp.

The estimator additionally performs retained-durability inference from factual,
elapsed retrieval evidence. Retrieval likelihood may revise what the estimator
believes already existed. Practice quality separately governs how much new
consolidation the event causally forms.

The diagnostic attribution must remain visible:

```text
consolidation_delta_from_retrieval_inference
consolidation_delta_from_causal_formation
```

Both deltas may update the same stored consolidation posterior, but they have
different meanings and must remain distinguishable in update traces.

### 3.2 Scheduler structure

The production scheduler retains its established pipeline and contracts:

```text
candidate generation
    -> eligibility tier
    -> safety suppression
    -> challenge admission or named bypass
    -> lexicographic priority ranking: R / I / V / G
```

The scheduler clocks remain separate:

```text
guidance probe  -> factual_last_retrieval_at
bootstrap probe -> last_retrieval_attempt_at
retention       -> predicted independent retrieval
information     -> operative estimator uncertainty
```

Consolidation alone does not directly enter scheduler prediction or ranking in
this version. It can affect future scheduling only through subsequent
learner-state transitions that change operative current memory.

### 3.3 Closed synthetic mechanism branches

Production implementation must not quietly introduce mechanisms rejected or left
unpromoted by the diagnostic passes:

- cross-material durability seeding;
- post-success prediction bridges;
- reduced first-encounter support based on global placement confidence;
- generic guidance-probe suppression or cooldown;
- attempt-clock substitution for factual-success history;
- information-first ranking exceptions;
- conditional stronger-support probe interleaves;
- motor-only recovery;
- hybrid recovery.

Hybrid recovery was directionally valid and calibration-safe, but its 1.46 to
1.80 percentage-point completion gain did not shorten recovery or factual
return. It remains an empirical hypothesis, not a production branch.

### 3.4 What remains provisional

The semantic architecture and transition boundaries are frozen pending empirical
evidence. Numeric calibration is not.

Provisional quantities include:

- initial priors and uncertainty;
- support and retrieval-success learning factors;
- current-durability and consolidation rates;
- retained-inference prior variance and likelihood weighting;
- posterior grid or approximation details;
- guidance, difficulty, challenge-band, and ranking coefficients;
- safety and probe thresholds.

Implement these values through versioned configuration. Do not scatter them as
unversioned constants through UI or persistence code.

## 4. Production architecture boundary

The production app should separate six responsibilities:

```text
domain catalog
    versioned materials, exercises, motor realizations, and guidance contexts

learner state
    current local estimates and uncertainty

scheduler
    candidate traces and one selected action

observation pipeline
    raw input -> derived outcome and quality summaries

attempt journal
    append-only local reconstruction record

research export
    optional, minimized projection of the local journal
```

The local learner model and scheduler must work fully without research
telemetry, an account, or a network connection.

## 5. Canonical attempt transaction

Every presented attempt is one ordered transaction:

```text
1. establish decision time
2. propagate learner state to that time
3. construct and evaluate candidates
4. select an exercise and persist the decision record
5. present the exercise
6. derive an outcome from local observations
7. classify factual retrieval observability and evidence weights
8. apply estimator evidence transitions
9. apply causal learner-state transitions
10. update scheduler session state
11. persist the outcome, update trace, and state-after reference
```

The state and parameters used at step 3 must be the same state and parameters
identified by the decision record. An app crash after presentation must not
silently manufacture an outcome. An app crash after outcome derivation must be
recoverable without applying the update twice.

### 5.1 Stable identifiers

Each transaction needs locally unique identifiers:

```text
practice_session_id
attempt_id
decision_id
exercise_definition_id
material_id
learner_state_before_id
learner_state_after_id
outcome_id
```

`attempt_id` is the idempotency key for outcome and state-update persistence.
Reprocessing the same attempt must return the already committed result or fail
loudly; it must never update learner state twice.

### 5.2 Time semantics

Persist timestamps with an unambiguous UTC representation and enough precision
to reproduce interval calculations. Also record the monotonic ordering within a
session so wall-clock corrections cannot reorder attempts.

Replay must use the recorded decision and outcome times, not the machine's
current time.

Derived elapsed quantities should be stored in the update trace for diagnosis,
but canonical replay recomputes them from the recorded state and timestamps and
asserts that they match.

### 5.3 Learner-update ordering

The production update must preserve the established event ordering. For a
factual retrieval observation with a pre-attempt activation anchor:

```text
1. capture the pre-attempt anchor and current durability
2. record last_retrieval_attempt_at when retrieval was factually observed
3. apply retained-consolidation likelihood inference
4. apply ordinary current-durability evidence correction
5. apply the event's causal learning transition
6. project and validate the current <= consolidation envelope
```

The inferred consolidation update runs before the current-durability evidence
update so newly inferred retained headroom is available to the ordinary
estimator transition. Causal consolidation formation runs afterward and remains
separately execution-quality-sensitive.

The event boundaries remain:

```text
first factual success without a prior anchor
    no elapsed half-life evidence
    + causal establishment and possible strengthening of memory

later factual success
    positive retrieval evidence
    + retained-consolidation inference when the interval is informative
    + activation refresh
    + current-durability strengthening
    + causal consolidation formation

factual retrieval failure on a productive attempt
    negative retrieval evidence
    + retained-consolidation inference when the interval is informative
    + productive-nonsuccess learning

retrieval unobserved
    no retrieval-likelihood evidence
    + any causal supported-practice transition allowed by the attempt outcome
```

A success transition cannot leave estimated current durability below its
pre-attempt value. A failure may reduce inferred retained consolidation, but
consolidation cannot be projected below current durability. Projection error
must remain represented in consolidation posterior variance rather than
appearing as additional certainty.

## 6. Local attempt-journal contract

The complete journal is local-first and more detailed than optional research
telemetry. A logical attempt record contains the following sections.

### 6.1 Provenance

```text
attempt_schema_version
domain_model_version
observation_model_version
performance_model_version
learner_model_version
scheduler_version
parameter_set_version
app_build_version
```

Version identifiers must resolve to immutable model definitions or archived
configuration. A version string that cannot recover its parameters is not
sufficient for replay.

### 6.2 Decision context

```text
practice_session_id
attempt_index_in_session
decision_at

learner_state_before_id
learner_state_before_hash
session_state_before

candidate_catalog_version
candidate_set_hash
tie_break_seed_or_token
```

Persist the scheduler's selected candidate trace:

```text
eligibility_tier
safety_status and suppression reason
challenge_status
challenge_bypass or scheduler_intent
predicted retrieval, execution, topology, and overall probabilities
challenge-band bounds
R / I / V / G priority terms
final rank key
```

The production path does not need to store the full candidate set for every
attempt. It must store enough canonical inputs to regenerate it and a hash that
detects divergence. A local developer-diagnostics mode may additionally retain
the top rejected candidates and their rejection reasons.

### 6.3 Presented exercise

Record the exercise actually shown, not only the scheduler's intended candidate:

```text
exercise_definition_id
material_id and material family
hands
tempo
octave span
direction
hand motion
pattern, rhythm, and articulation when applicable
guidance level and guidance features
motor realization and competency opportunities
```

If UI availability, user choice, or another product layer substitutes an
exercise after scheduling, persist both the selected and presented definitions
and a typed substitution reason.

`hand_motion` is required on the wire rather than defaulted from absence. No
released history exists to preserve, so a journal without it is a journal this
build did not write, and failing loudly is better than a decode path that has to
be carried forever. This is the exception a pre-release schema gets once; the
versioned upgrade discipline in section 9 governs every change after it.

### 6.4 Outcome and factual observation

The outcome contract must keep completion and retrieval separate:

```text
started
completed
retrieval_succeeded: true | false | null
```

`null` means retrieval was not observed. It must never be serialized, queried,
or analyzed as failure.

Record the derived performance summaries consumed by the evidence model:

```text
pitch accuracy or error summary
continuity summary
timing quality and variance
tempo achieved
crossing delay where observable
hand synchronization where observable
topology evidence where observable
user interruption or technical-failure reason
```

The exact observation vocabulary remains versioned. Raw timestamped MIDI should
stay local only as long as needed to derive these summaries and should not be
included in research telemetry by default.

### 6.5 Evidence and transition trace

Persist the evidence classification used by the update:

```text
retrieval_observed
retrieval_evidence_weight
competency evidence weights
material-execution evidence weight
elapsed interval used for retained inference
```

Persist event-local state deltas at minimum for:

```text
current durability from retrieval evidence
consolidation from retained-durability inference
current durability from causal learning
consolidation from causal formation
activation-anchor movement
cold-start estimate and uncertainty
competency mean and variance
material-execution mean and variance
```

Each delta should identify the transition name and its pre-transition and
post-transition value. This is an audit trace, not a second source of truth;
replay recomputes it and compares the result.

### 6.6 State references

The attempt journal must identify:

```text
state_before
    exact input to prediction and scheduling

state_after
    committed output after learner and session updates
```

Full state snapshots need not be duplicated for every attempt. A practical
design is an initial snapshot plus an append-only event stream and periodic
checkpoints. Every checkpoint must include a canonical serialization and hash.

## 7. Material-memory serialization

The production serializer must preserve the exact current semantics:

```text
material_id
log_current_half_life
current_half_life_uncertainty
log_consolidated_half_life
consolidated_log_half_life_variance
logit_cold_start
cold_start_uncertainty
memory_anchor_at
factual_last_retrieval_at
last_retrieval_attempt_at
```

The consolidation uncertainty field is specifically posterior variance in
log-half-life space. It is not a generic confidence score.

### 7.1 New-material defaults

A genuinely new material starts with:

```text
current durability              configured current-durability prior
consolidation                   same initial durability value
current uncertainty             configured current prior uncertainty
consolidation variance          independent log-half-life prior variance
cold-start estimate             configured retrieval prior
cold-start uncertainty          configured cold-start prior uncertainty
memory anchor                   unset
factual last retrieval          unset
last retrieval attempt          unset
```

Anchor existence determines whether cold-start or anchored retrievability is
operative. Factual-success existence does not replace that check.

### 7.2 Schema upgrades

The first production schema should use the split fields directly, without
compatibility aliases for an overloaded `last_retrieval_at` or `half_life`.

Future schema changes must be implemented as pure, versioned semantic upgrade
functions. Upgrade tests must cover existing persisted state, historical golden
journals, and genuinely new material separately. A field copy made because old
history lacks a better estimate must be documented as an upgrade expedient, not
as evidence that the old estimator measured both meanings.

### 7.3 State validation

Persisted state validation must enforce:

```text
0 < current_half_life_days
current_half_life_days <= consolidated_half_life_days
consolidated_half_life_days <= configured consolidation bound

uncertainties are positive and finite
timestamps are finite and not later than the transition time

factual_last_retrieval_at set
    => memory_anchor_at set

when both timestamps exist:
    factual_last_retrieval_at <= memory_anchor_at
```

Supported practice may move an existing activation anchor but cannot create the
first anchor in the current transition policy. That is a policy rule, not a
representational biconditional.

## 8. Offline replay

### 8.1 Replay modes

The implementation needs three distinct replay modes.

**Exact learner replay**

```text
recorded initial state
+ recorded presented exercises and outcomes
+ original model and parameter versions
-> original state transitions and final state
```

This mode must be deterministic within documented floating-point tolerance.

**Exact scheduler replay**

```text
recorded state and session context
+ domain catalog and scheduler configuration
+ tie-break token
-> regenerated candidates, decision trace, and selected exercise
```

Candidate-set and selected-trace hashes must match the journal.

**Counterfactual estimator replay**

```text
same recorded exercises and observed outcomes
+ alternative learner-model or parameter version
-> alternative predictions and state trajectory
```

This supports calibration and model comparison. It does not establish what the
learner would have done under a different scheduled exercise.

### 8.2 Counterfactual boundary

Historical outcomes are valid evidence for alternative estimators only for the
exercise that was actually presented. A scheduler replay may show that another
candidate would have been chosen, but the journal contains no factual outcome
for that unpresented action.

Do not treat offline scheduler replay as causal policy evaluation without an
appropriate randomized or otherwise justified evaluation design.

### 8.3 Replay acceptance tests

Before beta use, the production implementation must prove:

- replay from an initial snapshot reproduces every state checkpoint;
- replay is identical after process restart;
- event retries are idempotent;
- `retrieval_succeeded = null` remains unobserved through serialization;
- schema upgrades preserve historical meaning;
- candidate regeneration matches its stored hash;
- the selected decision trace matches its stored hash;
- state corruption or missing model versions fail loudly;
- counterfactual replay never mutates canonical local history.

A small set of anonymized, hand-inspected golden journals should live with the
production test suite.

## 9. Developer diagnostics

For any attempt, the app's diagnostics should be able to show:

```text
state before
candidate selected and why
best rejected alternatives and why they lost
prediction components
presented guidance and motor challenge
factual observation classification
evidence weights
ordered state transitions and attribution deltas
state after
```

This view is essential for debugging real disagreements. Aggregate dashboards
cannot reveal whether an error came from observation derivation, prediction,
state update, candidate admission, or ranking.

Diagnostic exports must follow the same privacy controls as other local history.

## 10. Optional research-telemetry projection

Research telemetry is an opt-in, data-minimized projection of the local journal.
It is not the canonical learner history and must not be required for local
adaptation.

### 10.1 High-value fields

The initial research projection should prioritize:

```text
pseudonymous installation identifier
coarse learner/session sequence identifiers
all model, parameter, schema, and app versions

exercise and material identifiers
hands, tempo, octave span, direction, and guidance
scheduler intent and named bypass

pre-attempt predicted retrieval and overall probability
pre-attempt current and consolidated durability summaries
pre-attempt operative uncertainties

factual retrieval observation and success/failure
completion
derived pitch, continuity, and timing quality

elapsed factual retrieval interval
retained-inference consolidation delta
causal-formation consolidation delta
```

Whether complete state snapshots or detailed candidate traces should leave the
device requires a separate privacy and data-volume review. They are required
locally for replay, not automatically required in research uploads.

### 10.2 Privacy and integrity

The production implementation must follow `design/product-vision.md`:

- explicit opt-in and clear disclosure;
- no loss of app functionality when disabled;
- no account identity attached to research events;
- no raw MIDI by default;
- encrypted transport and storage;
- schema validation, bounded values, deduplication, and rate limits;
- explicit reset, retention, and deletion semantics;
- rotation of the pseudonymous identifier after a local history reset.

Telemetry enabled or disabled must not change scheduling, predictions, learner
updates, or local history fidelity.

## 11. Empirical Phase 1 questions

The first empirical work should test qualitative assumptions and data quality,
not optimize product satisfaction or fit every provisional coefficient.

### 11.1 Retrieval calibration

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

### 11.2 Longitudinal posterior behavior

Examine whether consolidation posterior uncertainty contracts when informative
elapsed evidence arrives, remains broad under massed practice, and can reverse
after contradiction.

True half-life is not directly observable in real users. Posterior validation
must therefore use later held-out retrieval outcomes, posterior predictive
checks, and longitudinal coverage proxies rather than pretending the latent
truth is known.

### 11.3 Recovery and probes

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

### 11.4 Scheduler distributions

Measure real-session:

- material-selection concentration;
- revisit-gap distribution and tail;
- no-admission frequency;
- ordinary, recovery, guidance-probe, and bootstrap proportions;
- challenge-band placement and guidance fading.

These are guardrails and descriptive outcomes. They are not targets to optimize
in isolation.

## 12. Statistical discipline

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

## 13. Gates for reopening the frozen systems

[`../design/future-planning.md`](../design/future-planning.md) inventories
reserved seams, deferred hypotheses, and closed ideas. Their inclusion there
does not lower the following gates.

### 13.1 Learner model

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
[`competency-extension-guide.md`](competency-extension-guide.md): demonstrate
identifiability, held-out transfer, isolation from existing state, and replayed
value before reopening the ontology.

### 13.2 Scheduler policy

Reopen scheduler structure only when real data identify a repeatable decision
failure with an observable pre-selection discriminator and a measurable cost.

The evidence must show that an alternative improves its intended local outcome
without unacceptable calibration, recovery, concentration, revisit-gap, or
no-admission regressions.

User preference or satisfaction may motivate product changes, but it does not by
itself validate a learner-model or scheduler-mechanism claim.

### 13.3 Provisional coefficient calibration

Coefficient changes require:

- a named estimand and the events that identify it;
- a versioned baseline;
- held-out longitudinal evaluation;
- uncertainty or sensitivity reporting;
- replay against existing guardrails;
- an assumption-registry entry or update.

## 14. Implementation sequence

### Stage A: canonical production types

Implement and test:

- versioned domain identifiers;
- learner and session state;
- immutable exercise and outcome records;
- nullable factual retrieval semantics;
- canonical serialization and hashing;
- parameter registry and version resolution.

### Stage B: learner model and scheduler

Port the validated semantics from the analysis prototype. Preserve transition
ordering and scheduler information boundaries. Use shared fixtures or generated
golden cases to compare production behavior against the prototype.

### Stage C: transactional local journal

Implement attempt lifecycle, idempotent outcome commits, periodic checkpoints,
crash recovery, and local reset semantics.

### Stage D: deterministic replay

Build replay as a library or command-line tool usable in tests and developer
diagnostics. Exact learner replay is required before optional telemetry work.

### Stage E: diagnostic inspection

Add attempt-level explanations, state-transition attribution, candidate
rejection reasons, and privacy-safe export.

### Stage F: optional telemetry projection

After privacy review, implement explicit consent, minimization, batching,
integrity validation, deletion/reset behavior, and a local preview of what will
be uploaded.

### Stage G: pilot validation

Run developer and small-pilot sessions to validate event completeness,
replayability, qualitative calibration, and model assumptions. Do not treat this
stage as population coefficient fitting.

## 15. Production acceptance checklist

Before the real app relies on adaptive scheduling:

- [ ] Every presented attempt has one idempotent journal transaction.
- [ ] The selected and presented exercise cannot diverge silently.
- [ ] Factual retrieval `true`, `false`, and `null` survive persistence exactly.
- [ ] Learner update ordering matches the authoritative math.
- [ ] Scheduler stage inputs match the authoritative boundary contract.
- [ ] Consolidation inference and causal formation deltas are separately
      visible.
- [ ] Exact learner replay reproduces all state checkpoints.
- [ ] Exact scheduler replay reproduces candidate and selection hashes.
- [ ] Historical model and parameter versions remain resolvable.
- [ ] Counterfactual replay cannot mutate canonical history.
- [ ] The app works fully with research telemetry disabled.
- [ ] Raw MIDI is excluded from research telemetry by default.
- [ ] Reset, consent, retention, and deletion behavior is tested.
- [ ] Golden traces cover acquisition, reacquisition, savings, supported
      practice, long gaps, probes, recovery, and first success.
- [ ] Existing learner and scheduler invariants have production counterparts.

## 16. Explicit stopping point

At the start of production implementation:

```text
production learner-model semantics
    frozen pending empirical evidence

production scheduler policy
    frozen pending empirical evidence

synthetic mechanism search
    complete

numeric calibration
    provisional and versioned

next milestone
    telemetry contract and offline replay validation
```

The goal is no longer to invent another synthetic mechanism. It is to build a
faithful, inspectable implementation that can show exactly where the current
model agrees or disagrees with real learners.
