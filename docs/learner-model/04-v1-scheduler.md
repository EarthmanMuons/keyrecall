# V1 Scheduler Architecture

> **Reader note:** This document is authoritative for stage information
> boundaries and preserves the scheduler experiment record. Start with
> [`v1-current-system.md`](v1-current-system.md) §8 for the adopted production
> policy without the experiment chronology.

## 1. Purpose

This document specifies the V1 scheduler's pipeline and, specifically, the
information boundary between its stages: what each stage may read, what decision
it is allowed to make, and what it must leave to a different stage.

It is subordinate to `01-research.md`, `02-v1-design.md`, and `03-v1-math.md`
§20-23, which remain authoritative for the underlying math (the challenge-band
formula, the priority-utility form, review urgency). This document does not
re-derive that math or freeze numeric weights/bounds; those stay heuristic V1,
versioned, and open to simulation-driven revision, same as every constant in
`03-v1-math.md` §25-26. What this document adds is architectural: which stage
gets to look at which piece of state, stated precisely enough that violating it
is a visible design error, not just a code-review judgment call.

## 2. Why the boundary needs to be explicit

The learner-model experiments (`03-v1-math.md` §38, invariants 14-18) found the
same failure shape five separate times: a shared or blended signal let one part
of the model manufacture apparent learning it hadn't earned. A single
performance logit let memory contaminate motor competencies. A shared execution
channel let motor evidence contaminate topology. A shared prediction/evidence
pathway let a badly calibrated retrieval estimate look like motor learning. A
shared uncertainty field let pre-anchor evidence manufacture confidence about a
quantity it had never spoken to. Every fix was the same shape: give the
contaminated thing its own prediction, its own evidence, and (where applicable)
its own uncertainty - never a numerical patch layered on top of the shared
signal.

The scheduler is built from four stages that each answer a different question
about a candidate exercise. Nothing stops one stage's code from reaching into
state that belongs to another stage's question, and unlike the learner model,
that mistake would not _automatically_ show up as an invariant failure - it
would show up as a scheduler that behaves plausibly while quietly answering the
wrong question, unless the invariants are written specifically to make that
visible (§10). This document exists to make that mistake visible before it's
written, not to rediscover it through simulation the way the learner model did.

The general rule, stated once so every section below can just apply it:

> A stage may use only the information appropriate to the question it answers. A
> decision that belongs to one stage must not be re-derived, second-guessed,
> weakened, or duplicated by a different stage.

## 3. The four-stage pipeline

```text
candidate generation
        |
        v
eligibility (REQUIRES prerequisite gate + SchedulerSafetyPolicy)
        |
        v
challenge filtering
        |
        v
priority ranking
        |
        v
next exercise
```

This reconciles two slightly different framings already in the doc set.
`03-v1-math.md` §20 describes hard domain constraints as two layers _within_
candidate generation; the integrated current-system guide shows domain
constraints and prerequisite eligibility as steps before it. Both are right
about different things: hard domain/instrument constraints determine what
candidate generation is even capable of producing, so they belong inside stage 1
as generation-time constraints, not a filter applied after generating invalid
candidates. The `REQUIRES` prerequisite gate is genuinely a separate,
learner-state-dependent stage, since it needs current competency state to
evaluate - that's stage 2. `v1-current-system.md` §8 shows the resulting current
pipeline.

## 4. Stage 1: Candidate generation

**Question it answers:** what exercises could possibly be presented, given the
domain and this learner's instrument - independent of whether they'd be any good
to present right now.

**Allowed inputs:**

```text
TechnicalMaterial x ExercisePattern x ExecutionConditions x GuidanceContext
    x MotorRealization combinatorics (02-v1-design.md §4-8)
InstrumentProfile (key_count / playable_range, `GLOSSARY.md`)
```

**Forbidden inputs:** `LatentCompetencyState`, `MaterialMemoryState`,
`MaterialExecutionState`, `SessionState`. Nothing about this specific learner's
estimated ability, memory, or fatigue may influence what gets generated - only
what's structurally possible. This mirrors the Q-matrix's own rule
(`03-v1-math.md` §9.4): `Q` must never encode practice or transfer that didn't
happen. The same discipline applies here in the other direction - candidate
generation must never encode a readiness judgment that hasn't been made yet by a
later stage.

**Decision type:** set membership. A candidate is generated or it isn't; there
is no scoring at this stage. Generated iff:

```text
canonical fingering exists
requested octave count is supported
HT implementation is available (if hands == TOGETHER)
tempo lies within allowed product bounds
guidance configuration is valid
InstrumentProfile register/capability fits (do not generate an exercise
    the connected instrument cannot physically present)
```

## 5. Stage 2: Eligibility

**Question it answers:** given everything that could be presented, which
candidates are pedagogically or physically appropriate right now.

Two sub-questions share this pipeline position but must stay distinct data
sources, because they answer genuinely different questions and one is not a
substitute evidence source for the other:

### 5.1 `REQUIRES` prerequisite gate

**Allowed inputs:** `LatentCompetencyState` (mean and uncertainty) for the
specific competencies a prerequisite relationship names, e.g. adequate
`RH_SCALE_EXECUTION` + `LH_SCALE_EXECUTION` making `HANDS_TOGETHER_COORDINATION`
exercises more/fully eligible (`v1-domain-model.md` §17, `03-v1-math.md` §20).

**Forbidden inputs:** `MaterialMemoryState`, `MaterialExecutionState`. This gate
answers "is the learner generally ready for this kind of exercise," not "will
this specific material go well" - that's challenge filtering's question (§6),
evaluated on the specific candidate, not a competency prerequisite.

**Decision type:** soft, via an eligibility **tier**, not a numeric score fed
into priority ranking's utility. A candidate short of a prerequisite is a worse
candidate, not an invalid one - it remains available, but does not compete on
equal footing with a fully-eligible candidate; §7 defines exactly how. Unlike
stage 1, failing this doesn't remove the candidate from consideration.

### 5.2 `SchedulerSafetyPolicy`

**Allowed inputs:** `SessionState` (workload/fatigue signal, `GLOSSARY.md` §4)
and direct session-history signals (recent repetition count, sustained-intensity
duration). **Not** competency, memory, or execution state - this is a workload
constraint, not a pedagogical one, and explicitly not a medical/injury inference
(`GLOSSARY.md` §8).

**Decision type:** closer to hard than `REQUIRES`. It can suppress a candidate
for this session regardless of how pedagogically appropriate it is
competency-wise - a session-load ceiling, not a ranking term.

## 6. Stage 3: Challenge filtering

**Question it answers:** is the predicted difficulty of this _specific_
candidate - material, execution conditions, and guidance level all fixed in the
candidate generated by stage 1 and admitted by stage 2 - in a productive zone
for this learner. Stage 2 doesn't choose those fields; it only evaluates
eligibility and safety on the candidate stage 1 already produced.

**Allowed inputs:** `Prediction.overall_p` from `predicted_success()`
(`03-v1-math.md` §10.1: `material_available_p * execution_p`), computed for this
candidate's exact `TechnicalMaterial` / `ExecutionConditions` /
`GuidanceContext`.

`overall_p`, not `independent_retrieval_p` or `execution_p` alone, is the right
quantity: guidance level is a property of _this candidate_, chosen by stage 1,
not a fixed backdrop the learner shows up to. A fully-cued version of hard
material legitimately predicts as easier than an unguided version of the same
material, and challenge filtering should reflect that - it's answering "will
presenting this exact candidate go well," which cueing genuinely changes. This
is the `03-v1-math.md` §13 principle (`p_hat_acceptable` may be a composite
scheduler-facing scalar even though state updates must not be) applied to a
concrete quantity.

`predicted_topology_p` is deliberately excluded. Topology is a parallel
inference target (`03-v1-math.md` §10.1), not part of "will this attempt's
execution look acceptable" - folding it into the challenge signal would make
this stage re-decide something the evidence model already keeps separate.
Whether topology warrants its own probe-selection signal is open, not resolved
here (§9).

**Forbidden inputs:** retention need, information value, diversity, goals (stage
4's questions); `REQUIRES`/safety eligibility (stage 2's question, already
applied - a candidate that reaches this stage is already known to be eligible).

**Decision type:** a true filter, not a filter-or-score. Priority ranking (§7)
has no term that consumes a challenge score - its rank key is eligibility tier
plus R/I/V/G, nothing else - so a "strongly deprioritize" option here would be
exactly the dangling-score problem `REQUIRES` had before §7.1: a distinction
with nowhere to go. The decision is therefore binary, reached through one of
four paths:

```text
override                                 -> survives, unconditional (wins
                                             regardless of an active recovery
                                             context)
active recovery context (§6.3)           -> exclusive: only the exact
                                             recovery target survives; every
                                             other candidate is filtered out
                                             for this decision
otherwise, per candidate:
  p_min <= overall_p <= p_max              -> survives, normal band
  new material, overall_p >= p_intro_min   -> survives, introduction
                                               envelope (§6.1)
  guidance-probe eligible (anchored)       -> survives, guidance probe (§6.2)
  bootstrap-probe eligible (unanchored)    -> survives, bootstrap probe (§6.4)
  otherwise                                -> filtered out
```

Simulation (`analysis/scheduler/`, §10) validated these paths as genuine
admission gates, not uniformly unconditional bypasses. Diagnostic probe and
explicit learner request (`override`) remain true, unconditional bypasses: they
skip band evaluation outright, on grounds challenge filtering has no basis to
second-guess. New-material introduction and the two probes turned out to need
their own conditional gates instead (§6.1, §6.2, §6.4). Recovery turned out to
need something stronger than an ordinary bypass - not just "this one candidate
may also be admitted," but "only this one candidate may be admitted" (§6.3), a
distinction simulation only surfaced after an earlier, looser recovery design
produced two further failures (§10).

### 6.1 New-material introduction: a conditional envelope, not a blanket bypass

Material this hand has not played (no `MaterialExecutionState` entry for
`(materialId, hands)`) is admitted only if `overall_p >= p_introduction_min`, a
separate, lower threshold than the steady-state band (§9: heuristic, currently
0.15 vs. `p_min`'s 0.60) - still `overall_p`, still stage 3's own signal, just a
different band for a first-contact candidate.

Per hand, not per material. `MaterialMemoryState` is keyed by material, because
knowing the notes of a scale is a fact about the scale; execution residuals are
keyed by material and hand, because a fingering is not. Reading introduction off
memory alone left the second hand with no admission path at all - introduction
silent because the scale was known, consolidation silent because it had been
retrieved, and execution progression with no frontier to step from - and a
device sitting kept every scale on the hand that met it first for thirty
attempts.

Hands-together is excluded. Playing both hands at once is not a third hand
meeting the material; it is a transition off two frontiers that already exist,
with its own prerequisite and its own conservative entry tempo, which is
execution progression's step to offer.

This replaced an earlier, unconditional form (any never-practiced material
bypassed challenge filtering outright, regardless of realization difficulty).
Simulation (§10) found that version couldn't produce learner-sensitive
introductions: `I(e)` reads only competency _variance_, which starts identical
across learner tiers (§12), and an unconditional bypass meant `overall_p` -
which the competency _mean_ does drive - never gated admission either, so mean
had no channel into which realization got introduced at all. Gating on
`overall_p` against a lower threshold fixes this without touching priority
ranking: the same `overall_p` every profile already produces determines which
realizations (tempo, octaves, hands, guidance) clear the bar, so a beginner is
naturally left with easier realizations and a stronger learner with a broader
range - no explicit tier branching, and stage 4 still never reconsiders
difficulty (§7).

### 6.2 Guidance probe: a bounded step back toward independence, once anchored

§10 documents a failure mode this mechanism exists to close: once a candidate's
memory looks poor enough that only a cued realization clears the band, a cued
attempt never tests retrieval at all (`retrieval_succeeded` stays `None`,
`03-v1-math.md` §18.2 - correctly, not a bug) - so `MaterialMemoryState`'s clock
can never re-anchor, and the same cued realization keeps winning admission
indefinitely. Nothing in stages 3-4 as originally specified could recover from
that: it isn't a ranking problem (§7.2), it's that the only genuinely-tested
alternative is structurally unable to reach the band on its own.

The guidance probe is a narrow, named exception admitting exactly one step less
guidance than full cueing (§9: currently `notes_previewed`, not straight to
unguided), gated on:

```text
material has a prior confirmed successful retrieval (MaterialMemoryState
    exists and factual_last_retrieval_at is set - never probes a material that
    was never genuinely retrieved at all)
enough elapsed time since that success (§9: heuristic threshold) - not
    re-probed on literally the next attempt
```

Anchored on `factual_last_retrieval_at` specifically: this is the probe for a
material that HAS succeeded before and might now support less guidance. §6.4
covers the paired, unanchored case - a material that has never succeeded needs a
different mechanism, not a weakened version of this precondition.

Suppressed entirely whenever a recovery context is active (§6.3), not merely
checked after it: a failed probe sets `SessionState.last_failed_exercise`, which
routes the next attempt to recovery's exact one-step-more-guidance sibling of
the probe itself, so a failed probe can only ever be followed by MORE support,
never less (§10's guidance-probe-cascade finding). A successful probe is a
genuine retrieval test, so it can re-anchor the clock itself; if it does, normal
band admission - not a further bypass - is what lets less-guided realizations
compete from there. One step, not a jump straight to unguided: the probe only
needs to restore a genuine test, not solve the whole difficulty gap at once.

### 6.3 Recovery: exact, reactive, exclusive admission

Recovery answers a different question from the two probes: not "should we test
whether less guidance now works," but "the learner just failed at exactly what
we asked - what should happen right now." `SessionState` tracks this as
`last_failed_exercise: Exercise | None` - the failed exercise itself, not a bare
boolean - set whenever `retrieval_succeeded is False` and cleared on any other
outcome, including an untested (cued) one.

When `last_failed_exercise` is set, `recovery_target()` computes the exact
sibling: same `TechnicalMaterial` and `ExecutionConditions` (hands, octaves,
direction, tempo), exactly one step MORE guidance than what just failed
(unguided -> `notes_previewed` -> `concurrent_pitch_cues`; a cued attempt is
never itself a recovery source, since a cued failure is impossible -
`retrieval_succeeded` stays `None` under continuous cueing, never `False`,
§18.2). "Preserve motor challenge" is defined by this construction, not by a
separate check: everything about the task except guidance stays fixed.

Recovery is exclusive, not merely preferred: while a recovery context is active,
ONLY the exact recovery target may survive challenge filtering (§6) - every
other candidate is filtered out for this decision, even one that would otherwise
fall within the normal band or qualify for `new_material`/`guidance_probe`. This
was not the original design. An earlier version made `last_outcome_failed` a
bare boolean bypass admitting any candidate after a failure, and simulation
(§10) found this let priority ranking, not recovery's own intent, pick the
winner two different ways: `R(e)`'s retrieval-opportunity scaling favors LESS
guidance, so a failed guidance-probe attempt was routed toward MORE independence
instead of more support; and a failure on a demanding realization (long, fast,
direction-reversed) was routed to the easiest realization overall, not a
guidance-adjusted sibling of what actually failed. Both are the same underlying
defect: a bare bool tells the scheduler recovery is needed but not what it is
recovering FROM. Naming the failed exercise itself, and making its
one-step-more-guided sibling the only admissible answer, closes both failure
modes at once (§10).

`override` still wins regardless of an active recovery context: it is an
explicit caller instruction (diagnostic probe, explicit learner request), not an
inferred policy, and this document's own boundary rule (§2) treats an explicit
instruction as outside any stage's discretion to second-guess.

### 6.4 Bootstrap probe: the unanchored counterpart to the guidance probe

Making recovery exact and exclusive (§6.3) exposed a sharper version of §6.2's
original problem. Two genuine failures in a row correctly escalate recovery all
the way to maximum cueing (`concurrent_pitch_cues`) - before the material has
EVER had a successful retrieval, i.e.
`MaterialMemoryState.factual_last_retrieval_at` is still unset. The guidance
probe's own precondition is exactly that anchor (§6.2), so it structurally
cannot fire for a material in this state: nothing in §6.1-§6.3 offers a path
back to testing retrieval at all, and the material would stay fully cued for the
rest of the simulation (§10).

This is not the same situation the guidance probe already covers, and is not
fixed by weakening the guidance probe's own precondition to pretend it is.
`factual_last_retrieval_at`'s meaning - confirmed successful retrieval - stays
exactly as strong as before; a material that has never succeeded is not the same
epistemic case as one that succeeded a while ago and might now support less
support, and conflating them would let the probe fire on evidence it doesn't
actually have.

Instead, the two cases get separate mechanisms sharing one shape. The bootstrap
probe is the guidance probe's unanchored counterpart, gated on:

```text
material has never had a confirmed successful retrieval
    (factual_last_retrieval_at is None)
material has genuinely been tested at least once
    (MaterialMemoryState.last_retrieval_attempt_at is not None,
    03-v1-math.md §5.4)
enough elapsed time since that attempt (§9: currently reuses the
    guidance probe's own threshold, §6.2, as a starting simplification)
```

offering exactly the `notes_previewed` realization, same scope as the guidance
probe, never straight to unguided. `last_retrieval_attempt_at` (`03-v1-math.md`
§5.4) is what makes this possible: a genuine learner-state field, distinct from
`factual_last_retrieval_at`, that records any tested retrieval attempt - win or
lose - so the scheduler can tell "never successfully retrieved" apart from
"never even tested" without overloading or weakening the success-only anchor.

The bootstrap probe's job is to guarantee the scheduler keeps OFFERING a genuine
retrieval-observing opportunity at roughly the configured interval - not to
guarantee that opportunity eventually succeeds, which is stochastic and
learner-dependent and not something a scheduling policy can promise.
`check_never_successful_material_is_not_permanently_trapped` (§10) verifies
exactly this: no unbroken cued-only run spans the rest of the simulation, not
that retrieval is eventually retrieved successfully.

Checked after the guidance probe in `challenge_bypass()`'s precedence: the two
preconditions (`factual_last_retrieval_at is not None` vs. `is None`) are
mutually exclusive for any given candidate, so the check order does not change
which candidates qualify, only which check runs first.

## 7. Stage 4: Priority ranking

**Question it answers:** among everything that survived stages 1-3, what should
be presented next.

### 7.1 Eligibility tier is the primary key, not a fifth utility term

§5.1's `REQUIRES` evaluation has to affect the outcome somehow, but the existing
architectural decision (`GLOSSARY.md` §6) is specifically that it must not
become a weighted term competing with retention/information/diversity/goals,
since that would let a soft pedagogical judgment get outvoted by, say, a strong
diversity score - the same kind of boundary violation §2 warns about. The
resolution is a discrete, ordered **eligibility tier**, computed once from
`REQUIRES` (e.g. `FULLY_ELIGIBLE` / `PROVISIONALLY_ELIGIBLE` - the exact count
and labels are open, §9), that ranks lexicographically ahead of the R/I/V/G
utility rather than inside it:

```text
rank_key(e) = (eligibility_tier(e), U(e))
```

Candidates are ordered by tier first, then by `U(e)` (or the lexicographic
R>I>V>G ordering, §7.4) within a tier. A `PROVISIONALLY_ELIGIBLE` candidate
never outranks a `FULLY_ELIGIBLE` one no matter how strong its retention or
diversity score is; it remains reachable - for diagnostic probes, material
introduction, a fallback when no fully-eligible candidate survives stages 1-3,
or other explicitly allowed progression scenarios - without competing
numerically against readiness.

Taken literally, "never outranks" and "remains reachable for diagnostic probes"
are in tension whenever a fully-eligible candidate also survives: under the
strict lexicographic rule, the provisional candidate is reachable only when no
fully-eligible one does. If a diagnostic probe should sometimes be deliberately
chosen despite fully-eligible alternatives existing, that needs a named tier
bypass, the same shape as challenge filtering's named exceptions (§6) - not
decided here (§9).

This preserves both standing decisions: `REQUIRES` isn't a hard
`if not requires: reject()` (stage 1's kind of decision), and it isn't
`w_P P(e)` buried inside pedagogical utility either.

### 7.2 Within a tier: R/I/V/G

Each term reads a different slice of state (`03-v1-math.md` §22):

```text
R  retention/review need     retention_need(material) x retrieval_opportunity(e)
                              (§23's f(1-M, U_M), now scaled by whether THIS
                              candidate can act on that need). Simulation
                              (§10) found the unscaled form let a
                              continuously-cued candidate win on an
                              ever-rising retention score even though every
                              attempt it wins leaves that need exactly as
                              unresolved as before (retrieval_succeeded stays
                              None, §18.2, so the memory clock never
                              re-anchors) - the same contamination shape §2
                              warns about, a material-level need copied
                              unscaled onto a candidate that cannot remediate
                              it. retrieval_opportunity(e) reads
                              GuidanceContext (retrieval_demand/
                              retrieval_observed), 0 under continuous cueing;
                              still MaterialMemoryState plus this candidate's
                              own evidence-generating properties, the same
                              category of read I(e) below already allows.

I  information value          Expected uncertainty REDUCTION from presenting
                              THIS candidate, not merely a lookup of current
                              state uncertainty. Two guidance variants of the
                              same material carry the same state uncertainty
                              but different evidence potential (§18.2: a
                              retrieval_observed=false candidate has w_M=0,
                              structurally incapable of reducing memory
                              uncertainty) - I(e) has to be able to tell them
                              apart, so its inputs are current uncertainty
                              (competency variance, both memory-uncertainty
                              phases §5.3, execution residual variance)
                              PLUS the candidate's own evidence-generating
                              properties (Q/competency opportunities,
                              GuidanceContext/retrieval_observed, the
                              evidence weights those imply). Reading candidate
                              properties here doesn't cross the boundary in
                              §2's sense: they're consumed to answer I's own
                              question, "which candidate is likely to reduce
                              uncertainty," never to re-decide eligibility or
                              challenge.

V  diversity/interleaving     Session/practice HISTORY (recently-presented
                              materials). Not a learner-state estimate at all.

G  learner-goal priority      Externally supplied goals/preferences. Not a
                              learner-state estimate.
```

**Rejected:** a capability-weighted `I(e)` (each term above multiplied by a
matching prediction component - `execution_p` for motor/topology,
`independent_retrieval_p` for memory) was tried in simulation (§10) to give
competency mean a channel into new-material ranking. It failed on both counts
that matter: `execution_p` is a direct transform of the same task-difficulty
signal challenge filtering already consumes
(`sigmoid(competency - difficulty)`), so reading it in `I(e)` let stage 4
reconstruct a difficulty-sensitive preference after stage 3 had already made the
challenge decision - exactly the boundary violation this document exists to
prevent, caught by the invariant built to catch it - and it didn't even change
the ranking outcome it was meant to fix, since the component scales
same-material candidates roughly uniformly. The actual fix belongs to stage 3
(§6.1), not `I(e)`: `I(e)` stays as originally specified above.

**Forbidden:** re-deriving challenge or difficulty - already decided in stage 3.
This stage ranks; it does not reject, and no term here may overturn stage 3's
admission decision or stage 2's eligibility tier (§7.1).

### 7.3 Selection: repetition guard, then rank

Computing `rank_key(e)` for every admitted candidate (§7.1-§7.2) is not the same
act as choosing among them. A narrow, named **repetition guard** sits between
the two: a material selected more than a configured number of consecutive times
(§9: heuristic, currently 5) is excluded from winning, unless excluding it would
leave no admitted candidate at all - never the only viable material, which would
force no selection whatsoever.

Simulation (§10) found this belongs here, not inside `V(e)`: under the
lexicographic form (§7.1), `V` only ever breaks _exact_ ties in `R` and `I`,
which continuous-valued state rarely produces, so no numerical diversity
penalty - however large - could stop a material whose `R`/`I` legitimately
outrank the alternatives every single time. The guard is therefore a
selection-time policy, applied after ranking, not another ranking term:

```text
candidates with rank_key            (§7.1-§7.2, unchanged)
        |
        v
repetition guard                    exclude an over-repeated material's
                                     candidates from winning, unless doing
                                     so would leave none admitted
        |
        v
highest rank_key among the rest     the selected exercise
```

This two-step selection is the scheduler's one canonical choice function,
implemented as `select_scheduler_choice()` (`analysis/scheduler/pipeline.py`) so
every real caller goes through both steps together; composing the raw rank
comparison alone (`select_next(run_pipeline(...))`, skipping the guard) is a
real gap this document flags explicitly, not a valid shortcut - it silently
reproduces the perseveration failure the guard exists to prevent.

### 7.4 Initial-production decision

Scheduler simulation adopted the lexicographic R>I>V>G ordering. Together with
eligibility tier as the primary key, it is the frozen initial-production policy
recorded in `05-production-implementation-plan.md` §3.2. V1 uses no weighted-sum
scheduler weights.

## 8. Information boundary summary

| Stage         | Reads                                                                                                                                                                                                           | Must not read                                                                                          | Decision                                                      |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| Generation    | Domain combinatorics, `InstrumentProfile`                                                                                                                                                                       | Any learner state                                                                                      | Generated / not                                               |
| `REQUIRES`    | `LatentCompetencyState`                                                                                                                                                                                         | `MaterialMemoryState`, `MaterialExecutionState`                                                        | Eligibility tier (§7.1)                                       |
| Safety policy | `SessionState`, session history                                                                                                                                                                                 | Competency, memory, execution state                                                                    | Suppress / not (per session)                                  |
| Challenge     | `Prediction.overall_p` (this candidate); `MaterialMemoryState` existence/timing (`factual_last_retrieval_at`, `last_retrieval_attempt_at`) and `SessionState.last_failed_exercise` (named exceptions §6.1-§6.4) | Retention, information, diversity, goals; topology; `memory_anchor_at` for probe timing; consolidation | Reject / keep, via the band or a named exception              |
| Priority      | Eligibility tier (primary key); retention (memory + this candidate's `retrieval_opportunity`, §7.2); information (uncertainty + this candidate's evidence potential); diversity (history); goals (external)     | Challenge/difficulty (already decided)                                                                 | Rank within tier, then select via the repetition guard (§7.3) |

The memory-field dependencies are intentionally exact:

```text
guidance probe  -> factual_last_retrieval_at
bootstrap probe -> last_retrieval_attempt_at
retention       -> Prediction.independent_retrieval_p
information     -> operative cold-start/current-durability uncertainty
```

`memory_anchor_at` affects scheduling only through the derived retrieval
prediction, never probe-history timing. Retained consolidation and its
uncertainty have no immediate scheduler input in V1: changing consolidation
alone with activation/current state fixed leaves predictions, admission, and
ranking unchanged. It can affect later scheduling only after a learner-state
transition restores current durability or activation.

## 9. Deliberately left open

Matching `03-v1-math.md` §25's provenance discipline, none of the following are
resolved by this document - they are heuristic V1 choices, currently versioned
in `analysis/scheduler/config.py`/`config.toml`, same status as the learner
model's `alpha`/`lambda` constants before Experiments B/C. Simulation (§10)
validated the _mechanisms_ these constants parameterize; the specific values
remain exactly as heuristic and revisable as before:

```text
challenge-band bounds (p_min, p_max) and their named-exception conditions -
    Pass 3 (§10.1) found p_min sampled-robust over [0.60, 0.70] and p_max
    robust over the full sampled [0.75, 0.98] range; characterization, not
    a recommended retuning
p_introduction_min, the separate lower band for new-material introduction
    (§6.1) - validated as a mechanism, not as a value; Pass 3 (§10.1) found
    it sampled-robust over [0.15, 0.25]
guidance probe's elapsed-time threshold (§6.2) - heuristic value; the
    currently one-step probe scope is validated behaviorally but remains
    revisable if later scenarios justify a broader progression policy.
    The bootstrap probe (§6.4) currently reuses this same threshold value
    as a starting simplification; whether the two intervals should
    diverge is open, not decided by sharing a config value. Pass 3 (§10.1)
    found the shared interval sampled-robust over [1, 5] days, failing
    above 10 by recreating §30's original absorbing-cueing pathology
repetition guard's consecutive-selection cap (§7.3) - likewise; Pass 3
    (§10.1) found it sampled-robust over [2, 8], and confirmed the
    documented cap-below-window dependency with recent_window (config.toml)
priority ordering - simulation used and validated lexicographic R>I>V>G (§10),
    now frozen for initial production; the untried weighted-sum alternative is
    not a V1 production path
eligibility-tier count/labels and exactly what promotes/demotes a candidate
    between tiers (§7.1)
whether/how a provisionally-eligible candidate can be deliberately chosen
    over a fully-eligible one for a diagnostic probe or material
    introduction - a named tier bypass, the same shape as challenge
    filtering's named exceptions (§6), rather than silently reachable only
    when no fully-eligible candidate exists (§7.1)
I(e)'s exact form for combining current uncertainty with a candidate's
    evidence potential (§7.2) - not just that both belong in it. A
    capability-weighted variant was tried and rejected (§7.2); the form
    stated in §7.2 remains the open baseline
SchedulerSafetyPolicy thresholds ("sustained high-demand" numerically)
REQUIRES relationships beyond the RH/LH -> HT example
diversity/interleaving's exact data model and decay - Pass 3 (§10.1) found
    recent_window sampled-robust over [10, 25]
goals data model
whether topology gets its own probe-selection signal (§6)
```

## 10. Scheduler simulation tests

This list is no longer purely aspirational. `analysis/scheduler/` implements the
boundary contract itself as `pipeline.py`, and verifies it in two complementary
passes, mirroring the split `03-v1-math.md` §38 established for the learner
model: `invariants.py` (13 checks) proves the boundary holds mechanically - a
forbidden input can't move a stage's decision, regardless of whether the
resulting behavior is any good; `scenarios.py` (10 checks) runs the pipeline
longitudinally, driving `analysis/learner-model/simulate.py`'s own `run()` loop
through `SchedulerAgent` (`agent_pick`/`agent_on_outcome` hooks) rather than a
second update simulator, and asks whether the resulting behavior is actually
good. Both suites pass alongside the learner model's own 32 invariants.

`03-v1-math.md` §30's pathology list motivated the scenarios below; most of them
found real problems, which drove the revisions described in §6.1-§6.4, §7.2, and
§7.3. Two rounds of findings, not one: the first round produced R(e), the
guidance probe, and the introduction envelope; fixing the recovery exception
properly (§6.3) - itself a response to two findings from the second round - then
exposed a third-round finding the first two rounds' architecture could not have
surfaced on its own, resolved by the bootstrap probe (§6.4):

```text
no endless repetition of one material (§30). Originally failed: a lucky
    early unguided success anchors MaterialMemoryState's clock, the
    scheduler then locks onto a fully-cued realization of the same
    material, and a cued attempt never tests retrieval (retrieval_
    succeeded stays None, §18.2) - so the clock never re-anchors,
    R(e)'s old unscaled form keeps rising without bound, and the same
    material keeps winning. Not a V-term gap: V only breaks exact ties
    under lexicographic ranking, which continuous state rarely produces.
    Resolved by candidate-actionable R(e) plus the repetition guard
    (§7.2, §7.3), not by strengthening V(e).

old material eventually resurfaces (§30). Passed under the original
    architecture; unaffected by the R(e)/guard revisions.

guidance can fade after successful retrieval (§30: "guidance that never
    fades"). Originally failed, and not for the reason this document
    first guessed. The original theory - that a lower-guidance variant
    passively enters the band once memory improves - assumed memory CAN
    improve while the scheduler leans on cueing. It can't: a cued
    attempt never tests retrieval at all, so nothing updates
    MaterialMemoryState while the scheduler stays cued, and it stays
    cued permanently once it arrives there. Resolved by the guidance
    probe (§6.2), a narrow admission exception that periodically forces
    a genuinely-tested, one-step-less-guided attempt; I(e) was never the
    right lever, as this document originally guessed.

new-material selection reflects transferable competency and uncertainty,
    not a fixed novice default (§24). Originally failed, also not for
    the reason this document first guessed: I(e) reads only competency
    variance, not mean, and variance starts identical across learner
    tiers (§12) - so "uncertainty affects selection primarily through
    I(e)," as this document originally claimed, gave mean no channel in
    at all under the old unconditional new-material bypass. Resolved by
    the conditional introduction envelope (§6.1): the same overall_p
    every profile already produces (competency mean included) decides
    which realizations are admitted, not I(e).

guidance is not removed before independent retrieval is plausible (§30,
    the paired failure mode to §6.2's own probe). Originally failed once
    a dedicated scenario was written: a failed probe
    (challenge_bypass="guidance_probe", retrieval_succeeded=False) routed
    the next attempt to the OLD bare-boolean recovery exception, which
    admitted every guidance level - and R(e)'s retrieval_opportunity term
    rewards LESS guidance, so nothing in ranking favored restoring
    support, and both traced probe failures jumped straight to fully
    unguided. Resolved by exclusive recovery (§6.3): a failed probe's
    recovery target is exactly its own one-step-more-guidance sibling, so
    the next attempt can only step toward more support, never less.

failure can increase support without destroying motor challenge.
    Originally failed once a dedicated scenario was written: the OLD
    SessionState.last_outcome_failed was a bare bool with no memory of
    WHICH realization failed, so recovery admitted every
    ExecutionConditions combination, not just guidance variants of the
    failed one - the winner collapsed to the easiest realization overall
    (1 octave, 60bpm, UP), not a guidance-adjusted sibling of what
    actually failed. Resolved by last_failed_exercise (the exercise
    itself, §6.3) plus exclusive recovery admission: only the exact
    one-step-more-guidance sibling may survive this decision.

never-successful material is not permanently trapped at full cueing. Not
    one of §30's original items - a new failure mode this round of
    fixes exposed, not present before recovery became exact and
    exclusive: recovery can correctly escalate a material straight to
    maximum cueing after two genuine failures, before any success ever
    anchors `memory_anchor_at`/`factual_last_retrieval_at`, and anchored
    guidance_probe's own
    precondition means it can never fire for a material in that state -
    no path back to testing retrieval at all. Resolved by the bootstrap
    probe (§6.4): not by guaranteeing eventual success, which is
    stochastic and learner-dependent, but by guaranteeing the scheduler
    keeps offering a genuine retrieval-observing candidate at roughly
    the configured interval.
```

Three further scenarios validate existing architecture rather than resolving a
§30 pathology: eligibility progression (§5.1 - `PROVISIONALLY_ELIGIBLE` to
`FULLY_ELIGIBLE` as RH/LH competency crosses the `REQUIRES` threshold), the
recovery exception's temporariness (§6 - `SchedulerAgent.on_outcome` sets
`last_failed_exercise` on a genuine failure and clears it on any other outcome),
and the repetition guard's own dedicated scenario, directly proving both its
properties (excludes an over-repeated material when an alternative exists; never
forces zero admission when none does) against directly-constructed candidates
rather than relying on a real run to produce the right conditions incidentally.

### 10.1 Pass 3: sampled parameter robustness

Pass 1 mechanically validated the scheduler's boundary contract, and Pass 2
behaviorally validated the implemented mechanisms in §6-§7; every numeric
threshold they use (§9's list) stayed an untuned heuristic placeholder
throughout. Pass 3 (`analysis/scheduler/sensitivity.py`) characterizes how
robust those placeholders are - not which values are best - by reusing Pass 2's
own 10 behavioral checks as a pass/fail oracle across a sampled grid of each
parameter's value, one parameter at a time (Phase A) and across 4 hand-picked,
architecturally-motivated parameter pairs together (Phase B), looking for two
individually-safe values that combine to break something neither breaks alone.

The results are **sampled robustness findings, not estimated true boundaries**:
a 5-point grid can report "0.60 passed, 0.50 failed," never that the true
boundary sits at exactly 0.53. Every endpoint below is a grid observation, not a
fitted value.

```text
p_min                  sampled passing: 0.40-0.70
p_max                  robust over the sampled 0.75-0.98 range
p_introduction_min     sampled passing: 0.15-0.25
shared probe interval  sampled passing: 1-5 days (§6.4: also governs
                       bootstrap_probe, not independently tunable yet, §9)
repetition cap         sampled passing: 2-5
recency window         sampled passing: 10-25
```

All 6 defaults pass, and every bounded default has at least one neighboring
sampled value that also passes. Pass 3 does not establish that any default is
preferable to its neighbors or locate the true boundary of its passing region;
`config.toml` is unchanged by this pass, matching Pass 1/Pass 2's own discipline
of characterizing before retuning.

A minority of seeds don't reproduce a check's own scripted precondition at all
(scenarios.py's own "test setup error:" convention, e.g. no guidance-probe
failure occurring in a given run) - inconclusive, not evidence either way, and
excluded from every classification. `sensitivity.py` tracks this as a third
state per `(value, check)`/`(cell, check)` group (fails / holds / insufficient
coverage) rather than folding an absence of evidence into "holds," and reports a
coverage count so a silent evidence gap can't masquerade as a clean result. 5
individual runs were inconclusive; 1 `(value, check)` group and 1
`(cell, check)` group lacked any conclusive run entirely. In both cases, the
same value or cell had at least one other, independently conclusive check that
had already failed there, so none of the classifications reported above rest on
missing evidence.

None of the 4 tested parameter pairs (band width; introduction envelope vs.
steady-state band; probe interval vs. repetition cap; repetition cap vs. recency
window) produced a brittle interaction - every combined-cell failure was already
predictable from an individually-unsafe input in Phase A alone. Two deliberate
out-of-contract cells (`p_introduction_min >= p_min`) and three
(`repetition cap >= recency window`, `config.toml`'s own documented assumption)
were executed and recorded, not conflated with an ordinary interaction finding:
the three repetition-cap/recency-window out-of-contract cells failed as
predicted, a pre-registered positive control on the sweep's own plumbing.

**Structural finding, not a value-tuning one:** the sweep's aggressive grid
exposed a genuine crash in `SchedulerAgent.pick()` (`longitudinal.py`) -
`repetition_guard()`'s own documented fallback (returning the raw, unfiltered
trace list when nothing reaches priority ranking) left `NOT_REACHED` candidates
with `rank_key=None` in the `runners_up` sort, which cannot compare
`None < None`. Never reached by Pass 1/Pass 2's own configurations; reached the
moment Pass 3 pushed `p_min`/`p_introduction_min` far enough to genuinely admit
nothing. Fixed by excluding `rank_key is None` entries from that sort -
diagnostic-only, touches neither `winner` selection nor `repetition_guard()` nor
admission itself. This is the kind of finding this document's own
frozen-unless-structural-failure scope (§2, §9) exists to allow: a state no
scripted scenario had reached before, not a policy disagreement.

### 10.2 Pass 4: production-memory redesign characterization

`analysis/scheduler/stress.py` now records calibration metrics as well as
scheduler behavior: overall prediction bias/MAE, observed retrieval frequency,
and independent-retrieval prediction bias/MAE/Brier score. Retrieval metrics
include only attempts where retrieval was actually observed.

The same 250-trial matrix was run at the immediate pre-redesign baseline
(`2a6b5ce`) and at the production-memory redesign (`db35709`). Every trial
completed and neither run produced a hard-property violation.

Scheduler behavior moved in the expected direction as the synthetic learner
became more durable:

```text
metric                                      baseline   redesigned   change
recovery fraction                             0.378       0.317     -16.3%
guidance-probe fraction                       0.432       0.376     -13.0%
continuous-cue fraction                       0.381       0.313     -17.9%
maximum material-selection fraction           0.713       0.591     -17.1%
mean revisit interval                         1.622d      1.910d    +17.7%
mean of each trial's maximum revisit gap      12.153d     26.565d  +118.6%
no-admission rate                             0.138       0.141      +2.5%
```

The longer tail is a characterization flag, not by itself a regression. It
coincides with less concentration, less recovery/cueing, and better observed
retrieval performance rather than with a scheduler contract failure.

Weighted over every observed retrieval, calibration changed as follows:

```text
metric                            baseline   redesigned
observed retrieval count           38,537      43,328
retrieval success fraction          0.322       0.503
retrieval prediction bias          -0.038      -0.050
retrieval prediction MAE            0.143       0.124
retrieval prediction Brier          0.081       0.077
overall prediction MAE              0.210       0.187
```

The redesign is slightly more conservative on average, not over-optimistic,
while reducing both retrieval and overall prediction error. That does not
support lowering global durability-growth rates merely to reproduce the old
scheduler trajectory. One intentionally misspecified fixture,
`memory_strong_technique_weak`, remains the main localized calibration problem:
its core-sweep retrieval bias moved from `-0.367` to `-0.576` because true
initial memory is much stronger than the estimator's cold-start information.
That is a placement/observability target for later calibration, not evidence
against the four-axis transition semantics.

Pass 4 is parallelized across independent trials while preserving input order.
`--workers` defaults to at most 8 local processes and `--workers 1` retains the
serial path. Static candidate pools are generated once per agent, and
guidance-independent retrieval/execution/topology prediction components are
computed once per realization per pipeline call. The exhaustive repetition-cap
property stores the complete set of admitted material IDs rather than every full
`CandidateTrace`, so compact diagnostic runner-up logs remain bounded.

The optimization was checked at three levels:

```text
cached pipeline predictions == direct learner-model predictions
8 large trials: serial result objects == parallel result objects
full 250-trial CSV outputs == pre-optimization CSV outputs byte for byte
```

On the characterization machine, one representative 7-material trial fell from
about 4.25 seconds and 136 MB peak RSS to 2.66 seconds and 27 MB. Eight large
trials ran 5.82 times faster with 8 workers than serially. The complete
250-trial sweep finished in about 45 seconds with no crashes or hard-property
violations.

### 10.3 Pass 5: cold-start identifiability and retrieval observability

`analysis/learner-model/cold_start_identifiability.py` holds estimator
initialization constant while varying latent truth along two axes: technique
strength and initial memory strength. Each fixture uses the same broad
competency prior, the same 0.4 cold-start retrieval estimate, the same 3-day
current and consolidated half-lives, and the same uncertainties. Only the
synthetic learner differs. The production scheduler then makes 60 selections or
admission decisions at half-day intervals from the same seven-material pool.

The four fixtures are beginner, technique-strong/memory-weak,
memory-strong/technique-weak, and broadly strong. Results below are means over
30 deterministic seeds. A calibrated retrieval band means five consecutive
selected attempts with absolute independent-retrieval prediction error at most
0.10. Early metrics cover the first 20 actual selections; no-admission
opportunities are recorded separately.

```text
profile                         initial   first observed   calibrated   unnecessary   final
                                  bias       retrieval        by       early cueing    bias
beginner                         0.000          1.00         1.00          0.00       -0.025
technique strong, memory weak    0.250          1.00        27.43          0.00        0.009
memory strong, technique weak   -0.450          1.00          n/a         13.00       -0.570
broadly strong                  -0.450          1.00          n/a         13.00       -0.308
```

Starting too high is visible in the technique-strong/memory-weak fixture: it
averages 7.0 early unguided attempts while true retrievability is at most 0.30,
57.5% of its early selections use recovery, and its first successful retrieval
does not arrive until attempt 8.17 on average. Starting too low is visible in
both memory-strong fixtures: 13 of their first 20 selections use guidance
despite true retrievability of at least 0.70. They nevertheless receive much
less recovery than the beginner or memory-weak fixtures.

Retrieval observation itself is not globally scarce for the problematic
memory-strong fixtures:

```text
profile                         selections 1-5   6-10    11-15   16-20
beginner                              87.3%      84.0%    75.3%    60.7%
technique strong, memory weak         82.0%      68.7%    72.7%    62.7%
memory strong, technique weak         98.7%      95.3%    86.7%    85.3%
broadly strong                        97.3%      96.7%    86.7%    84.7%
```

The detailed observability artifact splits these counts by five-selection
window, guidance level, challenge bypass, and probe type. Its executable
contract also checks the categorical boundary: continuous pitch cues yield no
factual retrieval observation, while notes-previewed and unguided attempts do.
Serial and parallel runs produce identical CSV files.

The estimator trajectories separate from the beginner trajectory only slowly.
Using a difference of at least 0.15 for five consecutive aggregate selections,
the broadly strong fixture diverges at selection 19 and the
memory-strong/technique-weak fixture at selection 29. The
technique-strong/memory-weak fixture never meets that separation criterion. No
fixture produces five consecutive selected attempts inside the ordinary
challenge band during the 60-attempt horizon. The two memory-strong fixtures
also average 4.67 and 8.70 no-admission decisions, respectively.

These results do not support global probing as the first intervention. The
strong-memory learner already produces abundant observed successes. The more
specific limitation is that memory evidence and durability state are local to
each material. A first success establishes memory but cannot identify a
forgetting interval, so each newly demonstrated material still begins its
post-success durability near the ordinary prior. Evidence from one material does
not establish an "often memory-strong" placement state for another.

The next localized experiment should therefore target cold-start initialization
or uncertainty, potentially with an explicit placement-only state that pools
early retrieval evidence without granting immediate ordinary scheduler credit.
Bootstrap-probe selection is a secondary option for profiles or configurations
whose observation matrix is actually sparse. Ordinary post-placement transitions
and production coefficients remain frozen until such a mechanism is
characterized. Pass 4 aggregate MAE/Brier, recovery, concentration, maximum-gap
tails, and the 13 scheduler invariants remain the guardrails.

Pass 5 writes four artifacts:

```text
cold_start_profile_summary.csv
cold_start_seed_summary.csv
cold_start_trajectories.csv
cold_start_observability.csv
```

### 10.4 Pass 6: cross-material placement-memory characterization

`analysis/learner-model/cross_material_placement.py` tests whether first factual
retrieval observations should inform the cold-start prediction for other,
still-unestablished materials. The experimental state is learner-level and
epistemic only:

```text
placement_memory_estimate
placement_memory_uncertainty
placement_memory_evidence_count
```

It is not synthetic learner truth and it does not represent a transferable
half-life. Only the first factual retrieval observation for each material enters
the state. Success and failure both contribute, weighted by the existing
material-memory evidence weight. Repeated practice on one material contributes
no further placement evidence.

The provisional diagnostic uses a prior evidence strength of 2.0:

```text
estimate = (2 * 0.4 + weighted successes) / (2 + evidence mass)
uncertainty = 2 / (2 + evidence mass)
effective prior = 0.4 + (1 - uncertainty) * (estimate - 0.4)
```

The uncertainty term conservatively shrinks the estimate back toward the
ordinary 0.4 prior. These equations are experimental values, not production
calibration.

Three mechanisms use otherwise identical production behavior:

```text
control                     no cross-material state
pooled_prior                effective prior initializes unestablished material
pooled_prior_uncertainty    same prior plus narrowed cold-start uncertainty
```

The intervention may change only `logit_cold_start` and, in the third variant,
`cold_start_uncertainty` while a material has no factual retrieval observation.
It does not change current durability, consolidation, competencies, scheduler
policy, or any established material. The script checks this boundary directly.

The four Pass 5 profiles were rerun over 30 deterministic seeds. A fifth mixed
fixture assigns three randomly chosen materials strong prior memory and four
weak prior memory for each seed. The main placement costs changed as follows:

```text
profile                         control                 pooled prior
                         unnecessary  low-memory  unnecessary  low-memory
                              cueing    unguided       cueing    unguided
beginner                        0.00       0.00          0.00       0.00
technique strong, memory weak   0.00       7.00          0.00       5.80
memory strong, technique weak  13.00       0.00         13.00       0.00
broadly strong                 13.00       0.00         13.00       0.00
mixed prior knowledge           2.40       4.00          2.47       4.00
```

The pooled estimate learns the intended cross-material signal. Its final
effective prior averages 0.596 for memory-strong/technique-weak learners, 0.675
for broadly strong learners, and 0.290 for technique-strong/memory-weak
learners. This helps the memory-weak fixture reach retrieval calibration sooner,
moving the mean from selection 27.43 to 19.70, and reduces its early low-memory
unguided selections by 1.20.

It does not address the primary strong-memory failure. Both strong profiles
still receive 13 unnecessary guided selections in their first 20 selections,
neither reaches retrieval calibration, and their divergence from the beginner
trajectory remains at selections 29 and 19. Final retrieval bias is effectively
unchanged at -0.570 and about -0.31.

The reason is now mechanical. Strong learners usually succeed on their first
new-material retrieval. That success immediately establishes an ordinary
material-memory state, after which the placement prior is no longer operative.
The later cueing cost comes from the established material's ordinary-prior
durability, not its pre-observation cold-start probability. The diagnostic
therefore learns a real placement signal but stops consuming it before the
dominant error occurs.

Aggregate metrics across the five controlled fixtures improve modestly, but the
mixed fixture exposes the tradeoff:

```text
metric                          control   pooled prior   pooled + uncertainty
retrieval prediction MAE         0.287       0.277              0.277
retrieval prediction Brier       0.245       0.237              0.238
recovery fraction                0.355       0.354              0.354
mean maximum concentration       0.406       0.403              0.403
mean maximum revisit gap        10.71d      10.74d             10.74d
```

Mixed-knowledge retrieval MAE worsens from 0.202 to 0.214, strong-material
cueing rises slightly from 2.40 to 2.47, and weak-material unguided exposure
does not improve. Narrowing cold-start uncertainty produces no material benefit
over changing the prior alone.

The explicit late-contradiction sequence shows conservative reversibility. After
three successes the effective prior is 0.616. Consecutive failures move it to
0.556, 0.502, then 0.456, so three contradictory observations are required to
move it below 0.5. That behavior is bounded and reversible, but the full mixed
fixture shows that reversibility alone does not justify production use.

Pass 6 therefore does not support promoting either experimental mechanism. It
does support the narrower inference that early cross-material retrieval results
contain learner-level placement information. The next experiment must decide
whether that evidence may remain operative after first success until a material
has supplied an informative elapsed interval. That could be tested as an
epistemic prediction bridge without changing stored current or consolidated
half-life. Seeding durability directly would be a stronger claim and remains
unsupported by Pass 6.

Pass 6 writes four artifacts:

```text
placement_profile_summary.csv
placement_variant_summary.csv
placement_trajectories.csv
placement_reversibility.csv
```

### 10.5 Pass 7: post-success interval-identifiability bridge

`analysis/learner-model/interval_prediction_bridge.py` extends the Pass 6
placement sidecar through the period after first factual success but before
material-local durability is identifiable. The representation distinguishes:

```text
before_first_factual_success
post_success_interval_unidentified
interval_identified
```

The bridge exists only at prediction time. Scheduler selection sees the bridged
retrieval probability, while the ordinary estimator update receives its own
unbridged prediction. Stored current durability, consolidation, transition
rates, synthetic truth, and scheduler policy are unchanged.

Interval information is not defined by attempt count. For an ordinary retrieval
prediction `p`, elapsed time `delta`, and estimated half-life `h`, the
diagnostic uses a bounded Bernoulli information proxy for log half-life:

```text
x = ln(2) * delta / h
interval information = min(1, p * x^2 / (1 - p))
```

Zero elapsed time contributes zero information. Evidence is multiplied by the
existing material-memory evidence weight and accumulated over factual retrieval
observations after first success. The primary information threshold is 0.25.

The bridged probability is a 0.5 interpolation in logit space between ordinary
material retrievability and the uncertainty-limited Pass 6 placement prior. This
keeps the result between its two inputs. Four variants were compared:

```text
control                     ordinary material prediction immediately
bridge_until_second         bridge until one later factual observation
bridge_until_informative    bridge until information reaches 0.25
decaying_bridge             exponentially decay weight as information accrues
```

All values are diagnostic probes, not fitted production coefficients.

The bridge changes prediction in the intended phase. Across 30 seeds, the
information-threshold variant changes mean retrieval bias as follows:

```text
profile                       phase                     control   bridged
memory strong, technique weak interval-unidentified     -0.545    -0.394
memory strong, technique weak interval-identified       -0.567    -0.568
broadly strong                interval-unidentified     -0.535    -0.345
broadly strong                interval-identified       -0.372    -0.373
```

Thus cross-material placement evidence remains useful after first success. It
also moves divergence from the beginner trajectory from selection 29 to 21 for
the memory-strong/technique-weak fixture and from 19 to 18 for the broadly
strong fixture.

The mechanism nevertheless fails the primary behavioral acceptance criteria:

```text
metric                              control   until informative
strong-profile unnecessary cueing    13/20          13/20
memory-strong final bias              -0.570         -0.573
broadly-strong final bias             -0.308         -0.319
memory-strong no-admission count       8.70           8.50
stable challenge-band fraction         0.00           0.00
mixed-knowledge retrieval MAE          0.202          0.212
mixed weak-material unguided count     4.00           4.00
```

Mixed strong-material cueing improves slightly from 2.40 to 2.27, but that does
not offset the MAE regression. The pooled-prior effect from Pass 6 still reduces
the memory-weak fixture's early unguided count from 7.0 to 5.8; extending the
bridge is not responsible for that benefit.

Aggregate metrics across the five fixtures improve because the bridge corrects
the targeted middle phase:

```text
metric                       control   second   informative   decaying
retrieval prediction MAE       0.287    0.264       0.260       0.262
retrieval prediction Brier     0.245    0.226       0.222       0.224
recovery fraction              0.345    0.344       0.345       0.344
mean maximum revisit gap      10.71d   10.70d      10.75d      10.79d
```

A post hoc threshold decomposition at 0.10, 0.25, 0.50, and 1.00 rules out the
specific 0.25 cutoff as the whole problem. For the memory-strong/technique-weak
fixture, observations classified as identified at the much stricter 1.00
threshold still have -0.581 ordinary retrieval bias. Increasing bridge lifetime
would cover more error, but it would not produce a locally calibrated state to
which prediction could safely hand off.

The durability trace exposes that handoff problem. At the end of the control
run, estimated current and consolidated half-lives average:

```text
profile                         current   consolidated   latent initial truth
memory strong, technique weak     2.90d       3.03d             20d
broadly strong                    6.35d      11.33d             20d
```

Positive interval evidence updates current durability, but current durability is
capped by estimated consolidation. Estimated consolidation begins at the
ordinary 3-day prior and is raised mainly by the quality-weighted causal success
transition. In the memory-strong/technique-weak fixture, weak execution quality
therefore keeps the consolidation envelope near 3 days even though retrieval
successes provide evidence of strong pre-existing memory.

Pass 7 does not support promoting a prediction bridge. It supports two narrower
findings: the post-success underidentified phase is real and bridgeable, but the
material estimator does not absorb enough evidence to become a viable handoff
target afterward. The next diagnostic should isolate estimator-side
consolidation inference from causal consolidation formation. In particular, it
should test whether spaced retrieval evidence can revise the estimate of
pre-existing retained durability without changing synthetic truth or the
learner-side consolidation transition.

Pass 7 writes five artifacts:

```text
bridge_profile_summary.csv
bridge_variant_summary.csv
bridge_phase_summary.csv
bridge_threshold_summary.csv
bridge_trajectories.csv
```

### 10.6 Pass 8: retained-durability inference

`analysis/learner-model/retained_durability_inference.py` tests whether factual
retrieval intervals can revise estimated retained consolidation independently of
the quality-weighted causal consolidation transition. Synthetic learner truth,
scheduler policy, prediction bridging, and production transition rates remain
unchanged.

The diagnostic distinguishes two sources of movement in the same experimental
consolidation field:

```text
retrieval inference   evidence about durable memory that existed before practice
causal formation      durable memory created by the current practice event
```

Retrieval inference runs only when factual retrieval is observed and an anchor
already existed before the attempt. A first success therefore establishes memory
through the existing causal transition but supplies no elapsed-interval
evidence. The inference step runs before the ordinary estimator update so that
current-durability evidence can use any newly inferred consolidation headroom.
The existing causal equation then runs without coefficient changes. The two
consolidation deltas are recorded separately.

For elapsed interval `delta` and candidate half-life `h`, all experimental
variants use the factual Bernoulli retrieval model:

```text
p = 2^(-delta / h)
```

Four estimator variants are compared:

```text
control             no retained-durability inference
success-only score  bounded likelihood score for successes only
signed score        bounded likelihood score for successes and failures
Bayesian posterior  grid posterior over log half-life using the Bernoulli likelihood
```

The score variants use the derivative with respect to log half-life. With
`x = ln(2) * delta / h`, the success score is `x`, the failure score is
`-p*x/(1-p)`, and the information proxy is `p*x^2/(1-p)`. The Bayesian variant
uses the current log-consolidation estimate and uncertainty as its Gaussian
prior, weights the likelihood by the existing factual memory-evidence weight,
then projects posterior mean and variance back into the existing consolidation
state. All score gains, bounds, grid resolution, and posterior details remain
diagnostic rather than calibrated production choices.

Controlled trajectories establish the intended qualitative behavior:

```text
trajectory                 control final   signed final   Bayesian final
massed successes              25.87d          25.87d          25.86d
daily successes               18.10d          19.48d          21.56d
weekly successes              13.57d          20.12d          23.78d
biweekly successes            13.57d          25.58d          29.94d
20-day successes              11.13d          26.28d          29.05d
weak-execution 14-day         4.69d          16.35d          19.65d
strong-execution 14-day      11.13d          21.65d          25.08d
```

The massed trajectory receives less than 0.02 days of net inferred consolidation
in either two-sided variant. Increasing elapsed intervals produce increasing
retained-durability inference. On the first 14-day success, weak and strong
execution receive exactly the same inference delta, while strong execution
receives the larger causal-formation delta. This mechanically separates
retrieval evidence from practice quality.

The adversarial sequence of two 14-day successes followed by two 14-day failures
rejects the one-sided mechanism. Its consolidation remains at 17.00 days after
both failures. The signed score returns to 12.97 days and the Bayesian posterior
returns to 13.26 days. Four long-interval failures from the initial state also
lower consolidation to the current-durability envelope. Retained-durability
inference is therefore reversible rather than a success ratchet.

A scheduler-free profile run uses identical unguided attempts at progressively
longer intervals for every estimator variant. Across 30 seeds, the primary
memory-strong/technique-weak fixture changes as follows:

```text
metric                         control   signed   Bayesian
final current durability        2.97d     6.40d      6.40d
final consolidation             3.01d     8.49d      9.92d
post-interval retrieval bias   -0.374    -0.346     -0.346
```

The mixed fixture's weak materials have identical prediction error across all
three variants. Their final consolidation falls rather than rises because
failures provide negative retained-durability evidence. Mixed strong materials
gain consolidation without transferring that belief to weak materials.

The final comparison lets the unchanged scheduler react to each experimental
estimator. The Bayesian variant produces the clearest result:

```text
profile/material class            control bias   Bayesian bias   control/Bayesian consolidation
memory strong, technique weak        -0.570          -0.424                 3.03d / 6.51d
broadly strong                       -0.308          -0.302                11.33d / 14.54d
technique strong, memory weak          0.009           0.007                 4.51d / 2.38d
mixed strong                         -0.521          -0.522                 6.06d / 7.04d
mixed weak                            0.014           0.010                 4.58d / 2.28d
```

The primary fixture's final absolute bias improves by about 26 percent, and its
consolidation is no longer trapped near the 3-day prior. Weak-memory calibration
does not regress. Early unnecessary cueing remains 13 of 20 for the globally
strong fixtures because no informative interval exists during that phase. Mixed
strong materials show little prediction benefit because the scheduler selects
them too rarely to collect enough local interval evidence. Those are limits of
evidence availability, not evidence that the estimator-side pathway is
misdirected.

Pass 8 supports a reversible likelihood-based retained-durability update and
rules out success-only inference. The Bayesian posterior is the strongest
structural candidate because it uses the full factual likelihood and carries
uncertainty explicitly. It is not promoted by this pass: its prior shape, grid,
and update strength remain provisional, and the experiment intentionally does
not alter production estimator code. The next implementation boundary is to
design the production estimator update around this likelihood semantics, then
rerun the full characterization and calibration stack. It is not a reason to
change synthetic truth, causal consolidation formation, or scheduler policy.

Pass 8 writes six artifacts:

```text
retained_inference_trajectories.csv
retained_inference_summary.csv
retained_inference_profiles.csv
retained_inference_profile_summary.csv
retained_inference_scheduler.csv
retained_inference_scheduler_summary.csv
```

### 10.7 Pass 9: production inference and posterior-state validation

Pass 9 promotes the structural result from Pass 8 into the production estimator.
A factual retrieval observation with a pre-existing anchor now runs these
transitions in order:

```text
retained-consolidation posterior inference
current-durability evidence correction
causal consolidation formation or productive-nonsuccess learning
```

The first transition uses the factual Bernoulli interval likelihood and the
posterior state defined in `03-v1-math.md` §5.3.1. It cannot run on first
retrieval, unobserved retrieval, zero-weight evidence, or intervals shorter than
one provisional hour. Its likelihood grid uses the broad memory half-life
bounds, then projects the posterior mean upward if needed to preserve the
current-durability envelope. Success and failure are both likelihood
observations. Execution quality remains absent from inference and continues to
affect only causal consolidation formation.

The state field formerly named `consolidated_half_life_uncertainty` is now
`consolidated_log_half_life_variance`. This is a semantic rename rather than a
compatibility alias: the new field is specifically the variance of the
approximate posterior over log consolidated half-life. New material and the pure
V1 state upgrade initialize it from `consolidation_prior_log_variance`; no
historical estimator observation is pretended to contain this posterior
information.

`update()` returns event-local diagnostics for:

```text
consolidation_delta_from_retrieval_inference
consolidation_delta_from_causal_formation
```

Simulation traces retain both values. They are attribution data, not persistent
learner state. Pass 8 explicitly disables the production inference path and pins
its original prior variance, so its control and candidate results remain a
reproducible historical experiment.

The structural gate adds direct checks for all production boundaries. The
learner suite now verifies that first and unobserved retrieval do not update the
posterior, near-zero successes and failures are inference-inert, long failures
can lower consolidation, bounds are preserved, inference is identical across
execution qualities, and causal formation remains quality-sensitive. All 32
learner invariants, 13 scheduler invariants, and 10 scheduler scenarios pass.

`analysis/learner-model/posterior_state_validation.py` isolates the posterior
from causal learning and scheduler selection. It generates paired Bernoulli
retrieval evidence over intervals from 0.25 to 90 days for latent half-lives of
1, 3, 7, 14, 30, and 90 days. One-at-a-time variants characterize prior
variance, posterior variance floor, likelihood weight, and grid resolution.

The first provisional settings used prior log variance 1.0 and minimum log
variance 0.05. Across 100 seeds and all six latent half-lives, broadening the
prior to 2.0 and conservatively flooring posterior variance at 0.20 changes:

```text
metric                                      initial provisional   Pass 9 provisional
mean absolute log error                            0.332                 0.288
root mean squared log error                        0.416                 0.361
nominal 90% interval coverage                      77.3%                 96.2%
```

The final controlled posterior remains ordered by latent durability:

```text
latent half-life   median estimate   mean log bias   90% coverage
1d                       1.06d            0.084           99%
3d                       2.99d            0.008           98%
7d                       6.74d           -0.045           99%
14d                     12.71d           -0.090           92%
30d                     28.33d           -0.101           96%
90d                     70.15d           -0.251           93%
```

The remaining high-end underestimation and low-end overestimation are
quantitative calibration limits. A prior variance of 4.0 improves aggregate log
error only marginally, from 0.288 to 0.285, so the production value remains 2.0
rather than selecting the widest tested prior from one Monte Carlo suite. The
301-point production grid agrees with a 1001-point grid within the 1% mechanical
tolerance at every latent half-life.

The unchanged scheduler was then run through the complete 250-trial stress
matrix against a matched control that disables only retained inference:

```text
metric                                  disabled control   production
observed retrieval count                    43,328           43,360
retrieval prediction bias                   -0.050           -0.039
retrieval prediction MAE                     0.124            0.120
retrieval prediction Brier                   0.077            0.067
overall prediction MAE                       0.187            0.187
recovery fraction                            0.317            0.318
guidance-probe fraction                      0.376            0.376
maximum material-selection fraction          0.591            0.620
mean maximum revisit gap                     26.57d           27.29d
no-admission rate                            0.141            0.140
```

Both sweeps complete without crashes or hard-property violations. The production
pathway improves calibration with essentially unchanged recovery, guidance,
overall prediction error, and no-admission behavior. Mean material concentration
rises by 4.9% and the mean maximum-gap tail rises by 2.7%. Both remain well
below the pre-redesign concentration baseline, but they remain secondary
regression metrics for later calibration. Half and double likelihood weights do
not remove the concentration shift and are worse on the controlled posterior
metric, so Pass 9 does not tune the estimator around scheduler shape.

The primary localized fixture also behaves as predicted by Pass 8:

```text
profile                         final retrieval bias   early unnecessary cueing
memory strong, technique weak          -0.42                     13/20
broadly strong                          -0.29                     13/20
technique strong, memory weak            0.01                      0/20
beginner                                -0.02                      0/20
```

Pass 9 therefore closes the structural and initial calibration gates for
production retained-durability inference. Its numerical posterior settings
remain provisional, especially at the 1-day and 90-day extremes. The unchanged
13/20 early cueing result remains a separate cold-start limitation because no
elapsed interval evidence exists during those selections.

Pass 9 writes three posterior-validation artifacts:

```text
posterior_validation_trajectories.csv
posterior_validation_summary.csv
posterior_validation_variant_summary.csv
```

### 10.8 Pass 10: prior-knowledge placement policy

Pass 10 returns to the remaining 13 of 20 early supported selections for the
globally memory-strong fixtures. It tests the narrower scheduler-side claim that
cross-material placement evidence can grant permission for a less-supported
first encounter without granting memory credit for an unseen material.

The experiment freezes the Pass 9 learner model, estimator parameters, candidate
set, eligibility stages, ranking, and synthetic truth. It reuses Pass 6's
epistemic placement belief only after the scheduler has selected a material.
Three sidecar policies can reduce the selected exercise's support on its first
encounter:

```text
notes permission      after 2 observations and effective prior >= 0.55
unguided permission   after 2 observations and effective prior >= 0.55
tiered permission     notes at the threshold above, then unguided after
                      3 observations and effective prior >= 0.60
```

These thresholds are diagnostic values, not production calibration. An override
is allowed only when it removes support, and prediction, outcome sampling,
learner update, and recovery tracking all consume the resulting exercise. The
trace retains both proposed and presented guidance. Placement evidence never
changes a material prediction, stored half-life, uncertainty, transition rate,
candidate admission, or rank.

The fixture set adds two adversarial profiles to the Pass 6 set. `sparse_expert`
knows a seed-randomized 2 of 7 materials, while `common_keys_expert` knows the
fixed C major, G major, and F major cluster. Both are otherwise memory-weak. The
diagnostic records first-encounter support and factual success, false-high and
false-low placement, threshold and reversal timing, and strong/weak material
splits. Retrieval calibration, recovery, concentration, maximum gap, and
no-admission behavior remain guardrails.

The result falsifies the proposed intervention under the current scheduler. In
30 matched seeds, every one of the 1,470 first encounters across seven profiles
and the control was already unguided. The sidecar confidence became permissive
on many later attempts, but all three policies made zero overrides. Their
trajectories and aggregate metrics are therefore identical to control.

```text
profile                           first-encounter success   early supported selections
memory strong, technique weak             85.2%                      13.0/20
broadly strong                             84.3%                      13.0/20
beginner                                   44.3%                       0.0/20
technique strong, memory weak              17.1%                       0.0/20
mixed prior knowledge                      49.0%                       2.4/20
sparse expert                              34.3%                       1.4/20
common-keys expert                         47.1%                       2.1/20
```

The heterogeneous guardrail also reveals that first encounters are already
maximally diagnostic: all 4 weak materials in the mixed and common-key fixtures,
all 5 weak materials in the sparse fixture, and all 7 materials in the globally
memory-weak fixture are initially tested unguided. Pass 10 adds no risky
encounters, but it also has no remaining first-encounter support to remove.

The globally strong 13 of 20 count is instead a post-first-observation effect.
Across 30 seeds for each strong fixture, its 390 supported early selections
decompose as follows:

```text
profile                           guidance probes   recovery   bootstrap probes
memory strong, technique weak          303             82              5
broadly strong                          301             85              4
```

This changes the diagnosis. The production scheduler already uses unguided
bootstrap encounters to test unseen material. Cross-material confidence that
only grants permission for the same test is redundant. Reducing the 13 of 20
count would require a separate experiment on post-observation guidance-probe and
recovery decisions, including whether the current "unnecessary cueing" metric is
counting intentional supported probes as a cost. Pass 10 does not broaden its
intervention to that later phase and promotes no scheduler policy.

Pass 10 writes six artifacts:

```text
prior_knowledge_trajectories.csv
prior_knowledge_first_encounters.csv
prior_knowledge_seed_summary.csv
prior_knowledge_profile_summary.csv
prior_knowledge_variant_summary.csv
prior_knowledge_reversals.csv
```

### 10.9 Pass 11: supported-selection intent and cost

Pass 11 decomposes supported selections before considering any scheduler-policy
change. It replaces the interpretive shortcut:

```text
true retrieval >= 0.70 and guidance != unguided
    -> unnecessary cueing
```

with separate intent classes:

```text
ordinary supported selection
recovery support
guidance probe
bootstrap probe
```

The old count remains reproducible in Passes 5, 6, and 10, but it is no longer
treated as a behavioral defect by itself. High latent retrievability says
nothing about the selected support's diagnostic value, the estimator's current
belief, or execution and topology risk.

`analysis/learner-model/supported_selection_intent.py` reruns the seven Pass 10
fixtures across 30 matched seeds without changing learner or scheduler state
semantics. For each supported winner it records the selected intent, expected
information, factual evidence availability, event-local prediction and
uncertainty changes, and whether guidance later fades. It also evaluates the
exact unguided sibling against the same pre-attempt learner and session state.
The counterfactual is never presented and never updates state.

Expected information and realized uncertainty changes remain separate metrics.
Competency variance, material-execution variance, operative memory uncertainty,
and consolidation log variance have different meanings and are not summed into a
synthetic "information gained" scalar.

The 13 of 20 early supported selections for each globally strong fixture retain
the Pass 10 intent decomposition:

```text
profile                           guidance probes   recovery   bootstrap probes
memory strong, technique weak          303             82              5
broadly strong                          301             85              4
```

#### 10.9.1 Guidance probes

Every guidance probe uses notes preview and yields a factual retrieval
observation. The probes are not low-yield support:

```text
metric                                      memory strong,       broadly
                                            technique weak        strong
all probe selections                              1,083            1,079
early probe selections                              303              301
retrieval success                                  80.4%            80.2%
mean expected-information score                    1.997            1.349
mean operative-memory uncertainty reduction        0.094            0.124
mean consolidation log-variance reduction          0.269            0.269
mean competency-variance reduction                  0.179            0.146
mean execution-variance reduction                   0.066            0.144
mean absolute retrieval-prediction change           0.542            0.497
same candidate changed admission after probe       80.4%            69.9%
```

No unguided sibling is challenge-admitted. All are below the challenge band
under the estimator's current state. The predicted limiting component is memory
for 868 of 1,083 probes in the memory-strong/technique-weak fixture and 835 of
1,079 probes in the broadly strong fixture. Execution limits another 215 and 194
respectively; topology limits 50 broadly strong probes.

This is an epistemic distinction: latent truth says memory is strong, but the
scheduler must act on the estimated state. Under that state, the probes generate
substantial evidence and usually produce the intended immediate admission
change. Counting every one as unnecessary support was misleading.

The remaining question is cadence and termination. Later unguided presentation
occurs after none of the memory-strong/technique-weak probes and after only
11.7% of broadly strong probes within the 60-attempt horizon. For the latter
group it takes a mean 18.8 further selections. The probes are informative, but
the diagnostic does not yet establish that their repeated frequency is optimal.

#### 10.9.2 Recovery support

Recovery has different semantics and should not share the probe cost metric. It
is temporary in the strong profiles:

```text
metric                                      memory strong,       broadly
                                            technique weak        strong
all recovery selections                             240              246
notes-preview recovery                               31               35
continuous-cue recovery                             209              211
factual retrieval observed                         12.9%            14.2%
later guidance faded                               84.6%            85.4%
mean selections until fading                        1.35             1.77
```

Continuous-cue recovery provides no factual memory evidence, which explains the
small or negative phase-sensitive memory-uncertainty movement. It does still
reduce competency and execution uncertainty. An unguided sibling is never
ordinarily admitted because recovery is intentionally exclusive after a factual
failure.

The more important result is the predicted limiting component of the triggering
failed selection. This is a diagnostic attribution to the lowest component
probability; the production challenge stage still filters only `overall_p` and
does not make a dimension-specific rejection:

```text
trigger limiting component                 memory strong,       broadly
                                            technique weak        strong
memory                                             38               31
execution                                         164              156
topology                                           38               59
```

Execution is the limiting component for 68.3% and 63.4% of recovery triggers.
The current recovery action can only add notes preview or continuous pitch cues,
which changes material availability rather than execution capability. This is
evidence for a possible support-modality mismatch, not evidence that recovery
itself is excessive. Testing a motor-targeted recovery action requires a new
policy experiment and is outside Pass 11.

Pass 11 therefore closes the original 13 of 20 metric as a cold-start defect.
Most of the count is purposeful, high-yield diagnostic probing. The two
remaining scheduler questions are narrower: whether guidance-probe cadence can
terminate sooner after sufficient evidence, and whether recovery should target
the predicted failing dimension. No production scheduler policy changes in this
pass.

Pass 11 writes five artifacts:

```text
supported_selection_events.csv
supported_selection_profile_summary.csv
guidance_probe_summary.csv
recovery_support_summary.csv
supported_counterfactual_summary.csv
```

### 10.10 Pass 12: recovery modality

Pass 12 tests the possible support-modality mismatch isolated by Pass 11. It
does not modify production policy. Three diagnostic variants run the seven Pass
10 fixtures across 30 matched seeds:

```text
control
    all failures use existing one-step memory guidance

dimension targeted
    memory/topology limited -> existing recovery
    execution limited       -> one-step motor simplification

motor floor diagnostic
    memory/topology limited -> existing recovery
    execution limited       -> easiest same-hands motor realization
```

The motor actions use existing candidate dimensions. They preserve material,
hands, and the failed attempt's guidance while lowering tempo, octave span, or
direction complexity. The one-step variant chooses the single available change
with the highest predicted execution probability. The floor uses 60 BPM, one
octave, and upward-only motion. Direct checks ensure that a motor intervention
never adds memory guidance, never lowers predicted execution probability
relative to control recovery, and never raises predicted material availability.

The trigger dimension is a diagnostic attribution to the lowest predicted
component probability, not a new production decision boundary. Memory- and
topology-limited failures remain controls under the existing recovery policy.

The intervention mechanically works on the dimension it changes. Depending on
profile and dose, targeted actions raise predicted execution probability by
about 0.05 to 0.10 while reducing material availability by about 0.28 to 0.50
relative to cue-escalating control. That tradeoff, however, does not produce a
robust recovery improvement.

For the primary memory-strong/technique-weak fixture:

```text
metric                              control   one-step motor   motor floor
recovery selections per seed          8.00          7.77           7.57
recovery episodes per seed             7.80          6.70           6.80
mean episode length                    1.02          1.17           1.11
execution-recovery completion          0.0%          0.4%           2.4%
retrieval observation                  0.0%         81.1%          79.3%
retrieval success when observed         n/a         85.8%          88.3%
same-dimension episode recurrence      0.0%          9.7%           3.8%
retrieval prediction MAE              0.475         0.463          0.462
retrieval prediction Brier            0.375         0.358          0.360
```

Motor targeting preserves useful retrieval evidence and slightly reduces the
number of recovery episodes, but it does not make the exercise completable for
this technique-weak learner. Control's zero recurrence is not a clean success:
most control recoveries escalate to continuous cues, which censor retrieval and
clear the factual-failure recovery trigger after one attempt.

The broadly strong fixture also provides no clear reason to promote the
mechanism. Recovery count is essentially unchanged at 8.20, 8.17, and 8.13. The
floor nearly preserves execution-recovery completion (94.5% control versus
93.6%), while one-step targeting lowers it to 88.9%. Observation increases from
7.7% to 75-78%, but ordinary challenge-band admission still takes about 18-20
later selections where it occurs.

The weak and heterogeneous controls reject a global execution-argmin policy more
strongly:

```text
profile / metric                       control   one-step motor   motor floor
technique strong, memory weak
  recovery selections                   31.2          35.1           35.2
  mean episode length                    1.18          1.54           1.56
  execution-recovery completion         78.7%         45.6%          43.3%
  retrieval Brier                       0.084         0.089          0.086

beginner
  recovery selections                   27.0          33.3           33.9
  mean episode length                    1.09          1.66           1.79
  execution-recovery completion          0.0%          0.0%           0.0%

mixed prior knowledge
  recovery selections                   27.2          31.1           30.7
  execution-recovery completion         78.4%         51.1%          53.8%
```

The minimum predicted component is therefore insufficient to choose one support
modality. A multiplicative outcome can remain jointly memory- and
execution-limited even when execution is the smallest component. Removing the
memory support exposes that second weakness. More retrieval observations improve
aggregate MAE and Brier and reduce concentration, but those downstream gains do
not compensate for longer and less successful recovery in the protective
fixtures.

Pass 12 rejects both motor-only recovery candidates. It promotes no scheduler
change. If recovery is revisited, the narrower next experiment should be
factorial: independently vary motor simplification and memory guidance to test a
hybrid action and estimate each contribution. That is separate from the next
planned guidance-probe marginal-yield characterization.

Pass 12 writes six artifacts:

```text
recovery_modality_trajectories.csv
recovery_modality_events.csv
recovery_modality_episodes.csv
recovery_modality_seed_summary.csv
recovery_modality_profile_summary.csv
recovery_modality_variant_summary.csv
```

### 10.11 Pass 13: guidance-probe marginal yield

Pass 13 separates control characterization from diagnostic suppression. The
production scheduler and learner model remain unchanged.

The control stage records each material's probe ordinal, time since the prior
probe, predicted retrieval, expected information, four separate uncertainty
states, factual outcome, evidence weight, and event-local state movement. It
also evaluates the exact unguided sibling on later attempts to measure actual
challenge admission rather than presentation alone. Results are grouped by exact
ordinal, ordinal band, operative-memory uncertainty band, and
consolidation-variance band. No combined realized-information score is created.

Across 30 seeds and seven profiles, marginal yield declines strongly:

```text
probe ordinal   probes   success   expected I   |delta retrieval p|   memory U reduction   consolidation V reduction   next probe
1-2              1,741    54.2%       1.939            0.405                 0.160                    0.474               4.24d
3-5              1,849    52.5%       1.533            0.331                 0.099                    0.147               3.37d
6-8                680    24.4%       1.184            0.160                 0.053                    0.074               1.51d
9+               1,306     1.1%       0.729            0.010                 0.011                    0.026               1.24d
```

The decline is real but not uniform. The globally strong fixtures have only four
ordinal-9+ probes each. Their late probes still succeed 75-100% and produce
large retrieval-prediction movement. Nearly all ordinal-9+ volume comes from
beginner, memory-weak, sparse, mixed, and clustered-knowledge materials. The
last four of those groups have zero successes at ordinal 9+; beginner success is
3.8%.

The uncertainty view tells the same story without ordinal confounding:

```text
operative memory U   probes   success   expected I   |delta retrieval p|   memory U reduction
high                  2,677    57.2%       1.850            0.406                 0.142
medium                1,333    40.0%       1.352            0.245                 0.081
low                   1,566     2.0%       0.774            0.015                 0.016
```

Low consolidation variance is rarer, but its 188 probes similarly yield 3.2%
success, 0.021 absolute retrieval movement, 0.001 memory-uncertainty reduction,
and 0.011 consolidation-variance reduction. Repeated probes can still reduce
competency and execution variance, so low memory yield does not imply zero total
learner-state evidence.

The scheduler's expected-information term is directionally calibrated to the
state dimensions it emphasizes. Across control probes, its correlation with
realized reduction is 0.641 for operative memory uncertainty, 0.600 for
consolidation log variance, and 0.470 for competency variance. Correlation with
execution-variance reduction is only 0.109. The heuristic recognizes much of the
declining memory yield; the probe bypass itself has no termination threshold
based on that value.

The short late-probe interval exposes a clock boundary. Successful probes move
`factual_last_retrieval_at`, naturally delaying the next probe. Failed probes
leave that success clock old, so the material remains probe-eligible after
recovery. Pass 13 therefore includes a targeted five-day failed-probe cooldown
in addition to the initially planned sidecars:

```text
variant                 probes/seed   suppressed winners   retrieval MAE   Brier   no admission
control                    26.55              0.00              0.228       0.191       1.96
10-day minimum spacing     14.14             28.46              0.285       0.259      12.05
15-day success cooldown    21.30              7.50              0.246       0.218       7.35
5-day failure cooldown     22.40             21.38              0.256       0.223       2.58
memory-U threshold         24.68             11.09              0.259       0.220       2.09
low-yield history          26.30              2.49              0.237       0.198       1.96
```

Every suppression policy worsens aggregate retrieval calibration. Broad spacing
and success cooldown frequently remove the only admitted candidate. Failed-probe
cooldown limits that no-admission increase and improves calibration in both
globally strong fixtures, but it materially worsens the memory-weak fixture and
is not robust. The uncertainty rule suppresses many winning probes but often
substitutes another material's probe, so total probe count falls only 7.1% while
MAE and Brier worsen. The deliberately strict low-yield history rule barely
changes probe volume and still regresses calibration and the revisit-gap tail.

Control probes lead to later unguided admission only 2.3% of the time within the
horizon. Suppression does not improve that outcome consistently. Some variants
end with lower average uncertainty because they alter material coverage and
concentration, but their prediction calibration is worse; lower uncertainty is
not evidence that the omitted observations were unnecessary.

Pass 13 therefore establishes diminishing marginal memory yield, especially
after repeated failures, but rejects all tested termination policies. Late
failed probes continue to supply negative retrieval evidence and some motor
evidence. Simply suppressing them either removes the only admitted action or
redirects selection without resolving the material's challenge-band state. A
future probe-policy intervention would need an explicit alternative action or a
different admission pathway, not only a cooldown. No production policy is
promoted.

Pass 13 writes nine artifacts:

```text
guidance_probe_events.csv
guidance_probe_exact_ordinal_summary.csv
guidance_probe_ordinal_summary.csv
guidance_probe_uncertainty_summary.csv
guidance_probe_consolidation_variance_summary.csv
guidance_probe_information_calibration.csv
guidance_probe_policy_seed_summary.csv
guidance_probe_policy_profile_summary.csv
guidance_probe_policy_variant_summary.csv
```

### 10.12 Pass 14: low-yield probe alternative actions

Pass 14 preserves the production scheduler and characterizes the exact state
immediately before each probe that can be identified as low-yield without using
its future outcome. The diagnostic trigger is probe ordinal 9 or later, or two
consecutive prior probes below all Pass 13 low-yield thresholds. In this matrix,
the ordinal rule accounts for the trigger set.

The diagnostic reruns the unchanged candidate pipeline on the preserved state
and session, then records the best candidate in each alternative class:

```text
admitted non-probe       any admitted action other than a guidance probe
ordinary band            bypass-free candidate inside the challenge band
provisional              admitted provisional-tier non-probe
recovery-like            exact same motor realization with continuous cues
easier motor             same material and guidance with lower motor demand
memory support           best same-material continuous-cue candidate
other near band          other material closest to the band among rejected candidates
end session              present nothing else in the current 20-attempt session
```

Every candidate row retains its rejection reason, predicted retrieval and
overall probabilities, eligibility tier, bypass, R/I/V/G terms, and actual rank
key. The sidecar does not turn any diagnostic alternative into a production
admission route.

Across 30 seeds and seven profiles, 1,306 control probes meet the trigger:

```text
alternative             available   admitted   mean overall p   principal boundary
admitted non-probe         98.2%       98.2%        0.288        99.7% are other-material bootstrap probes
ordinary band              69.1%       69.1%        0.608        61.1% are on the probed material
provisional                12.6%       12.6%        0.266        beginner-only bootstrap probes
exact recovery-like       100.0%       12.3%        0.508        87.7% remain too hard
easier motor               53.1%       53.1%        0.244        all still use the guidance-probe bypass
memory support            100.0%       69.0%        0.591        31.0% remain too hard
other near band           100.0%        0.0%        0.573        all remain below the challenge band
```

This is not general candidate scarcity. An admitted non-probe exists in 98.2% of
trigger states, and a bypass-free in-band candidate exists in 69.1%. However,
the apparent alternatives have specific costs. The best non-probe is almost
always a bootstrap probe on another unresolved material. The best bypass-free
action is often stronger memory support on the same material. Easier-motor
candidates remain guidance probes rather than escaping the probe policy.

The selected probe wins primarily through retention urgency, not an inflated
information score. Against the best admitted non-probe, the probe has higher
retention in every comparable event, averaging 0.596 versus 0.421. The
alternative has much higher expected information, averaging 1.978 versus 0.718,
and much less negative diversity. Since V1 ranking is lexicographic in R/I/V/G
within a tier, retention decides first. The same pattern holds against
ordinary-band alternatives: probe retention is higher in every comparable event.
Pass 14 therefore does not identify a broken information heuristic or a missing
candidate generator. It identifies a choice among unresolved-material testing,
stronger support, and current-material retention urgency.

The trigger distribution reinforces the Pass 13 localization:

```text
profile                         trigger events
beginner                              184
technique strong, memory weak         252
memory strong, technique weak           4
broadly strong                           4
mixed prior knowledge                 283
sparse expert                         269
common-keys expert                    310
```

The intentional no-selection comparator ends the remainder of the current
session at a trigger without advancing probe history. It is deliberately a
strong version of shortening the session:

```text
metric                              control   end session
selected attempts per seed           58.04       42.93
attempt slots ended per seed           0.00       15.11
retrieval prediction MAE              0.228       0.263
retrieval prediction Brier            0.191       0.218
recovery selections                   22.56       15.38
no-selection count                     1.96       17.07
maximum material fraction              0.466       0.386
maximum revisit gap                   11.03d       9.38d
```

The shorter revisit gap is mechanical because the sidecar removes session slots.
It does not offset the lost evidence or worse calibration. Nearly all of the
intervention falls on weak and heterogeneous profiles; the two globally strong
profiles almost never reach the trigger. Ending the session is therefore not a
generally preferable substitute for the late probe.

Pass 14 also isolates four pre-probe clocks on factual failures. Across all
failed probes, time since the last factual attempt correlates positively with
memory-uncertainty reduction (0.614) and consolidation-variance reduction
(0.583), while time since the last factual success correlates negatively (-0.720
and -0.618). This aggregate contrast reflects the accumulation of failures after
an old success.

Within the low-yield failed tail, attempt and previous-probe elapsed time still
correlate with absolute retrieval-prediction movement (0.361), but carry almost
no relationship to memory-uncertainty or consolidation-variance reduction
(0.048/-0.011). Consecutive prior probe failures are much more diagnostic of low
uncertainty yield (-0.839/-0.845). An attempt-based eligibility clock might
space the probes, but elapsed attempt time alone does not identify when their
posterior yield has recovered. The factual-success clock must remain distinct
from factual-attempt and probe history regardless of any later policy.

Pass 14 promotes no scheduler change. A next intervention should compare
explicit alternatives rather than suppress probes in isolation. The most direct
candidates are another material's bootstrap test and stronger same-material
support, with the production ranking and challenge contracts held visible. A
generic cooldown, an attempt-clock substitution, and unconditional session
termination are not supported by this characterization.

Pass 14 writes eight artifacts:

```text
probe_alternative_events.csv
probe_alternative_availability.csv
probe_alternative_kinds.csv
probe_alternative_rejections.csv
probe_alternative_clock_summary.csv
probe_alternative_policy_seed_summary.csv
probe_alternative_policy_summary.csv
probe_alternative_policy_profile_summary.csv
```

### 10.13 Pass 15: retention-vs-information tradeoff

Pass 15 tests diagnostic ranking exceptions only when the unchanged Pass 14
trigger fires. Production admission, ranking, learner transitions, and clocks
remain unchanged. The policy sidecars are:

```text
control                    retain lexicographic R/I/V/G
bootstrap alternative      choose the best admitted non-probe only when it is
                           another material's bootstrap probe
stronger support repeated  after at least two consecutive probe failures,
                           choose admitted same-material continuous cues
stronger support once      insert that support at most once before the next
                           factual probe on the material
information before R       preserve eligibility tier, but compare I before R
                           at the Pass 14 trigger only
```

The two-failure threshold is diagnostic, not production calibration. The
repeated and one-shot support variants are separate because continuous cues do
not create a factual retrieval result. Without an explicit one-shot boundary,
the failure streak remains unchanged and the same exception can select support
again indefinitely.

Each policy trajectory records full-run calibration, recovery, concentration,
revisit gaps, no-admission, probe counts, and final uncertainty. Every trigger
also receives a ten-selection consequence window. Because policy trajectories
diverge after the first intervention, Pass 15 additionally forks the exact
control trigger state. Each available action starts with an identical estimator,
synthetic truth, session, time, and random-generator state, then returns to the
production scheduler for ten selections. These paired rollouts isolate the
action's short-horizon consequence from later policy drift.

The paired control-state comparison explains why stronger support is tempting:

```text
metric change vs. retention-first probe      bootstrap   stronger support   I before R
immediate completion                           +0.067          +0.528          +0.085
immediate retrieval observation                 0.000          -1.000           0.000
next-10 retrieval observations                 +0.068          +0.533          +0.064
next-10 retrieval successes                    -0.060          +0.041          -0.064
memory-U reduction                             -0.009          +0.016          -0.012
consolidation-V reduction                      -0.037          +0.021          -0.046
recovery selections                            -0.068          -0.533          -0.064
material coverage                              +0.675          +0.100          +0.626
selections until original-material return      +0.797          +0.407          +0.748
selections until factual return                -0.583          -0.942          -0.625
```

The same-material intervention makes the trigger action completable, then
returns to a factual test sooner than control because control usually enters a
recovery action after another failed probe. Its next ten selections slightly
improve memory and consolidation uncertainty reduction while reducing recovery.
The immediate action itself remains fully censored for retrieval. Bootstrap and
information-first choices broaden coverage but postpone the urgent material and
slightly reduce memory-state evidence over the paired horizon.

Repeated-policy results reject all four ranking exceptions:

```text
variant                    applied/seed   probes   recovery   retrieval MAE   Brier   max fraction   max gap
control                         0.00       26.55     22.56         0.228       0.191      0.466       11.03d
bootstrap alternative           3.80       23.06     22.29         0.235       0.200      0.380       14.11d
stronger support repeated       7.88       22.67     18.53         0.254       0.209      0.457       11.43d
stronger support once           3.01       25.08     21.00         0.236       0.196      0.465       11.00d
information before R            8.82       24.14     21.47         0.257       0.219      0.272       14.61d
```

Bootstrap substitution reduces concentration, but increases the maximum-gap tail
by 3.09 days and worsens calibration. The aggressive information-first
comparator lowers final estimated uncertainty and concentration, but has the
largest MAE/Brier regression and a 3.58-day gap increase. Lower uncertainty is
not a benefit when prediction calibration worsens.

Repeated stronger support confirms the factual-history trap. It raises trigger
count from 6.22 to 9.77 per seed, and only 18.5% of its later trigger horizons
return to a factual test within ten selections. Retrieval MAE rises by 0.025 and
Brier by 0.018.

The one-shot boundary is substantially safer. It reduces guidance probes by 1.48
and recovery by 1.55 selections per seed while leaving no-admission,
concentration, and the revisit-gap tail effectively unchanged. It nevertheless
raises aggregate MAE by 0.008 and Brier by 0.005. The regression is localized in
the protective weak and heterogeneous fixtures:

```text
profile                         delta MAE   delta Brier   delta recovery
technique strong, memory weak      +0.008       +0.005          -2.50
mixed prior knowledge              +0.018       +0.015          -2.80
sparse expert                      +0.013       +0.008          -2.60
common-keys expert                 +0.017       +0.007          -2.97
```

Beginner and both globally strong fixtures are essentially unaffected because a
qualifying stronger-support action is absent or the late trigger is rare. The
one-shot rule therefore trades fewer recovery actions for worse retrieval
calibration precisely where late failures are common. It does not clear the
acceptance gate.

Pass 15 promotes no scheduler change and does not justify changing the global
R/I/V/G ordering. Retention-first late probes remain the least harmful complete
policy among those tested. The paired result does identify a narrower future
question: whether a stronger-support interleave can be conditioned on a
measurable completion need without systematically censoring memory evidence.
That would require a new discriminator, not merely the existing low-yield
trigger or failure count.

Pass 15 writes ten artifacts:

```text
probe_ranking_trajectories.csv
probe_ranking_events.csv
probe_ranking_choice_summary.csv
probe_ranking_horizon_summary.csv
probe_ranking_paired_horizons.csv
probe_ranking_paired_summary.csv
probe_ranking_paired_profile_summary.csv
probe_ranking_seed_summary.csv
probe_ranking_profile_summary.csv
probe_ranking_variant_summary.csv
```

### 10.14 Pass 16: probe-failure completion need

Pass 16 applies the stopping rule proposed after Pass 15. It fits no classifier
and changes no scheduler policy. Instead, it uses the paired control-state
rollouts as outcome labels and asks whether fixed, pre-selection observable
strata identify where one stronger-support interleave is safe.

The analysis includes only Pass 15 trigger states where same-material stronger
support is admitted after at least two consecutive factual probe failures. For
each state, the retention-first probe and stronger-support action begin with the
same estimator, synthetic truth, session, time, and random-generator state. The
event records only predictors available before presentation:

```text
prediction components and their gaps
probe ordinal and prior factual-probe outcomes
recent completion and factual-failure histories
current and consolidated durability
memory uncertainty and consolidation variance
competency and execution variance
stronger-support predicted overall gain
```

Future paired outcomes label the rows for analysis only. Two labels are
retained:

```text
completion-recovery benefit
    immediate completion improves and next-10 recovery decreases

strict oracle benefit
    completion-recovery benefit
    + factual return is not later
    + retrieval MAE does not increase
    + retrieval Brier does not increase
```

The production discriminator is never allowed to read either label or any future
outcome.

Across 30 seeds, 900 trigger states have the qualifying stronger-support
candidate. The aggregate treatment effect reproduces Pass 15:

```text
metric                                        stronger support minus probe
immediate completion                                      +0.528
immediate retrieval observation                           -1.000
next-10 retrieval observations                            +0.533
next-10 retrieval successes                               +0.041
memory-U reduction                                        +0.016
consolidation-V reduction                                 +0.021
recovery selections                                       -0.533
days until factual return                                 -0.471
retrieval MAE                                             +0.0036
retrieval Brier                                           +0.0004
```

Only 28.1% of individual states improve both immediate completion and recovery.
Only 42/900, or 4.7%, also satisfy the strict future-outcome oracle label. That
small oracle-positive subset exists, but the tested production observables do
not isolate it coherently.

Several candidate predictors are nearly constant after the Pass 14 trigger and
stronger-support admission have already filtered the state:

```text
observable                                      dominant stratum
predicted retrieval p                           below 0.20 in 899/900
memory uncertainty                              low in 900/900
stronger-support overall-p gain                 0.30-0.45 in 897/900
execution residual variance                     low in 898/900
recent factual failures                         2-3 in 900/900
```

Completion history provides less separation than the hypothesis requires. The
previous probe failed both retrieval and completion in 505 states and retrieval
alone in 395. Their completion-recovery benefit rates are similar, 27.7% and
28.6%. Mean MAE still rises by 0.0037 and 0.0036, respectively. Retrieval-only
failures improve Brier slightly, but not MAE.

The most favorable supported one-factor strata still fail the strict group gate:

```text
stratum                         n   delta completion   delta recovery   delta factual days   delta MAE   delta Brier
control overall p < 0.20       94        +0.553           -0.479            -0.426            +0.0043      -0.0090
control execution p 0.40-0.60 640        +0.525           -0.530            -0.472            +0.0026      -0.0001
recent completion failures 2-3 398        +0.550           -0.515            -0.470            +0.0032      +0.0013
```

The first two satisfy every mean criterion except nonincreasing MAE. The third
regresses both calibration measures. Fixed two-factor intersections do not
resolve the tradeoff. No region with at least 50 examples simultaneously has:

```text
completion gain >= 0.25
recovery reduction >= 0.10
no later factual return
nonincreasing retrieval MAE
nonincreasing retrieval Brier
```

The highest strict-oracle fraction among supported single-factor strata is 8.5%,
and the highest among tested two-factor regions is 8.8%. This is at most a weak
enrichment of a rare future-outcome label, not an operational completion-need
boundary.

The technique-strong/memory-weak fixture is the closest profile-level result:
completion rises by 0.542, recovery falls by 0.611, MAE changes by only +0.0001,
and Brier improves by 0.0007. Fixture identity and latent truth are not
available to production, however, and the observable strata do not recover that
result without including heterogeneous states that regress calibration.

Pass 16 therefore promotes no classifier and no further scheduler experiment.
The current synthetic analysis cannot identify completion need strongly enough
from pre-selection state to justify censoring a factual probe. Per the stopping
rule, scheduler exception search is frozen. Further gains should come from
empirical calibration and richer real-learner observations rather than more
conditional synthetic policy branches.

Pass 16 writes five artifacts:

```text
probe_completion_need_labeled_events.csv
probe_completion_need_summary.csv
probe_completion_need_profile_summary.csv
probe_completion_need_strata.csv
probe_completion_need_regions.csv
```

### 10.15 Pass 17: factorial recovery support

Pass 17 returns to the recovery-modality question left open by Pass 12. It does
not reopen the probe or ranking exception search frozen by Pass 16. The
diagnostic changes an action only after production has already entered recovery
following a factual retrieval failure.

The experiment crosses memory guidance with three motor doses:

```text
                              motor none        motor one step       motor floor
memory guidance off          repeat failed     Pass 12 motor-only   motor-only floor
memory guidance on           production        hybrid one-step      hybrid floor
```

"Memory guidance off" preserves the failed attempt's guidance. "Memory guidance
on" uses production's one-step-more-guidance recovery target. Motor
simplification then changes only tempo, octave span, or direction within that
guidance condition. The production control is therefore exactly memory-on,
motor-none. All six cells apply unconditionally at every recovery trigger;
predicted limiting dimension is recorded only for post hoc stratification.

The full matrix contains 1,260 trajectories: six cells, seven fixtures, 30
seeds, and 600 attempts per trajectory. Factorial contrasts are paired by
fixture and seed. Motor simplification was actually available on 85.1% of
memory-on one-step recoveries and 78.3% of memory-on floor recoveries.

The no-memory-guidance cells reproduce Pass 12's protective result. Relative to
motor-none with guidance off, retaining production memory guidance raises
recovery completion from 0.304 to 0.623 and reduces mean episode length from
5.597 to 1.097. Retrieval is observed on every guidance-off recovery but on only
0.145 of production recoveries. This is the expected completion-protection and
factual-observability tradeoff, not evidence for removing memory support.

Both hybrid cells improve immediate completion without a meaningful calibration
regression:

```text
metric                              production     hybrid step     hybrid floor
recovery completion                    0.623           0.637            0.641
mean recovery episode length           1.097           1.098            1.098
completed one-selection exit           0.584           0.596            0.600
recovery retrieval observation         0.145           0.146            0.147
selections until factual return        3.598           3.612            3.619
retrieval MAE                          0.2284          0.2280           0.2278
retrieval Brier                        0.1913          0.1913           0.1910
maximum selection fraction             0.466           0.466            0.464
mean maximum revisit gap, days         11.026          11.014           10.943
no-admission count                      1.957           1.957            1.981
```

The paired completion effects are +0.0146 with standard error 0.0024 for one
step and +0.0180 with standard error 0.0026 for the floor. Their completed
one-selection-exit effects are +0.0129 and +0.0168. Mean episode length changes
by less than 0.001 selection for either hybrid. The memory-by-motor interaction
is positive but small: +0.0066 for one-step completion and +0.0096 for floor
completion.

No protective fixture has a material calibration regression. The largest hybrid
changes are +0.0003 MAE and +0.0008 Brier for one step, and +0.0003 Brier for
the floor. Factual return is delayed by only 0.014 and 0.021 selections in the
aggregate. Concentration, revisit-gap, and no-admission guardrails remain
effectively unchanged.

The limiting-dimension strata remain descriptive because the six policies
produce different downstream trigger populations. They show that recovery is not
confined to execution-limited states and reinforce the reason for the
unconditional factorial design. Under production recovery, 2,635 selections are
memory-limited, 1,825 execution-limited, and 277 topology-limited. Applying a
post hoc argmin rule to those changing populations would not identify the
factorial treatment effect.

Pass 17 therefore promotes no production recovery change. The hybrid completion
effect is repeatable and calibration-safe in these fixtures, but it is only
1.5-1.8 percentage points and does not shorten recovery episodes or accelerate
factual return. It does not clear the predeclared requirement for a material
localized recovery improvement. Recovery policy is now frozen alongside the
probe and ranking policy. Further recovery calibration should use real learner
outcomes rather than additional synthetic mechanism branches.

Pass 17 writes eight artifacts:

```text
recovery_factorial_trajectories.csv
recovery_factorial_events.csv
recovery_factorial_episodes.csv
recovery_factorial_seed_summary.csv
recovery_factorial_profile_summary.csv
recovery_factorial_variant_summary.csv
recovery_factorial_dimension_strata.csv
recovery_factorial_effects.csv
```

## 11. Relationship to existing documents

This document adds a boundary-contract layer on top of already-established
material; it does not replace it.

```text
03-v1-math.md §20-22    underlying math: hard/soft eligibility split,
                          challenge-band formula, priority-utility form -
                          still authoritative for the numbers
03-v1-math.md §23        review urgency (R term)
03-v1-math.md §13        scheduler score vs. state evidence - the principle
                          this document's §6 applies to overall_p specifically
03-v1-math.md §5.5        last_retrieval_attempt_at - a genuine
                          MaterialMemoryState field this document's §6.4
                          consumes but does not own; §5.5 is authoritative
                          for what it means
v1-current-system.md §8   integrated current scheduler explanation
GLOSSARY.md               InstrumentProfile, SchedulerSafetyPolicy, and terms
v1-domain-model.md §17     REQUIRES
analysis/scheduler/        executable counterpart to this document: pipeline.py
                            implements stages 2-4 and the boundary contract,
                            invariants.py verifies it mechanically (13 checks),
                            scenarios.py verifies it behaviorally (10 checks,
                            §10), longitudinal.py adapts it into
                            analysis/learner-model/simulate.py's run() loop,
                            sensitivity.py sweeps the remaining heuristic
                            values against that same behavioral suite (§10.1),
                            stress.py performs Pass 4 characterization (§10.2),
                            and cold_start_identifiability.py performs the
                            controlled Pass 5 characterization (§10.3), while
                            cross_material_placement.py performs the Pass 6
                            placement-memory diagnostic (§10.4) and
                            interval_prediction_bridge.py performs the Pass 7
                            prediction-bridge diagnostic (§10.5), while
                            retained_durability_inference.py performs the Pass 8
                            estimator-inference diagnostic (§10.6), and
                            posterior_state_validation.py performs the Pass 9
                            posterior calibration diagnostic (§10.7), while
                            prior_knowledge_placement.py performs the Pass 10
                            first-encounter placement-policy diagnostic (§10.8),
                            and supported_selection_intent.py performs the Pass
                            11 intent, yield, and counterfactual characterization
                            (§10.9), while recovery_modality.py performs the Pass
                            12 dimension-targeted recovery diagnostic (§10.10),
                            and guidance_probe_yield.py performs the Pass 13
                            marginal-yield and termination diagnostic (§10.11),
                            while probe_alternative_actions.py performs the Pass
                            14 alternative-action and clock diagnostic (§10.12),
                            and probe_ranking_tradeoff.py performs the Pass 15
                            ranking-alternative and paired-horizon diagnostic
                            (§10.13), while probe_completion_need.py performs the
                            Pass 16 completion-need discriminator
                            characterization (§10.14), and
                            recovery_factorial.py performs the Pass 17
                            recovery-support factorial characterization (§10.15)
```
