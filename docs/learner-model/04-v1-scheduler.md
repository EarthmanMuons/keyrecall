# V1 Scheduler Architecture

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
candidate generation; `GLOSSARY.md` §6's diagram shows domain constraints and
prerequisite eligibility as steps before it. Both are right about different
things: hard domain/instrument constraints determine what candidate generation
is even capable of producing, so they belong inside stage 1 as generation-time
constraints, not a filter applied after generating invalid candidates. The
`REQUIRES` prerequisite gate is genuinely a separate, learner-state-dependent
stage, since it needs current competency state to evaluate - that's stage 2.
`GLOSSARY.md` §6's diagram is updated to match.

## 4. Stage 1: Candidate generation

**Question it answers:** what exercises could possibly be presented, given the
domain and this learner's instrument - independent of whether they'd be any good
to present right now.

**Allowed inputs:**

```text
TechnicalMaterial x ExercisePattern x ExecutionConditions x GuidanceContext
    x MotorRealization combinatorics (02-v1-design.md §4-8)
InstrumentProfile (key_count / playable_range, GLOSSARY.md §7)
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

An unseen `TechnicalMaterial` (no `MaterialMemoryState` entry yet) is admitted
only if `overall_p >= p_introduction_min`, a separate, lower threshold than the
steady-state band (§9: heuristic, currently 0.15 vs. `p_min`'s 0.60) - still
`overall_p`, still stage 3's own signal, just a different band for a
first-contact candidate.

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
    exists and last_retrieval_at is set - never probes a material that
    was never genuinely retrieved at all)
enough elapsed time since that success (§9: heuristic threshold) - not
    re-probed on literally the next attempt
```

Anchored on `last_retrieval_at` specifically: this is the probe for a material
that HAS succeeded before and might now support less guidance. §6.4 covers the
paired, unanchored case - a material that has never succeeded needs a different
mechanism, not a weakened version of this precondition.

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
EVER had a successful retrieval, i.e. `MaterialMemoryState.last_retrieval_at` is
still unset. The guidance probe's own precondition is exactly that anchor
(§6.2), so it structurally cannot fire for a material in this state: nothing in
§6.1-§6.3 offers a path back to testing retrieval at all, and the material would
stay fully cued for the rest of the simulation (§10).

This is not the same situation the guidance probe already covers, and is not
fixed by weakening the guidance probe's own precondition to pretend it is.
`last_retrieval_at`'s meaning - confirmed successful retrieval - stays exactly
as strong as before; a material that has never succeeded is not the same
epistemic case as one that succeeded a while ago and might now support less
support, and conflating them would let the probe fire on evidence it doesn't
actually have.

Instead, the two cases get separate mechanisms sharing one shape. The bootstrap
probe is the guidance probe's unanchored counterpart, gated on:

```text
material has never had a confirmed successful retrieval
    (last_retrieval_at is None)
material has genuinely been tested at least once
    (MaterialMemoryState.last_retrieval_attempt_at is not None,
    03-v1-math.md §5.4)
enough elapsed time since that attempt (§9: currently reuses the
    guidance probe's own threshold, §6.2, as a starting simplification)
```

offering exactly the `notes_previewed` realization, same scope as the guidance
probe, never straight to unguided. `last_retrieval_attempt_at` (`03-v1-math.md`
§5.4) is what makes this possible: a genuine learner-state field, distinct from
`last_retrieval_at`, that records any tested retrieval attempt - win or lose -
so the scheduler can tell "never successfully retrieved" apart from "never even
tested" without overloading or weakening the success-only anchor.

The bootstrap probe's job is to guarantee the scheduler keeps OFFERING a genuine
retrieval-observing opportunity at roughly the configured interval - not to
guarantee that opportunity eventually succeeds, which is stochastic and
learner-dependent and not something a scheduling policy can promise.
`check_never_successful_material_is_not_permanently_trapped` (§10) verifies
exactly this: no unbroken cued-only run spans the rest of the simulation, not
that retrieval is eventually retrieved successfully.

Checked after the guidance probe in `challenge_bypass()`'s precedence: the two
preconditions (`last_retrieval_at is not None` vs. `is None`) are mutually
exclusive for any given candidate, so the check order does not change which
candidates qualify, only which check runs first.

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

### 7.4 Open

Whether `U(e)` is a weighted sum or the lexicographic R>I>V>G ordering
`03-v1-math.md` §22 sketches, the exact weights, and the eligibility-tier
count/labels are scheduler-simulation work (§9), not decided here.

## 8. Information boundary summary

| Stage         | Reads                                                                                                                                                                                                       | Must not read                                      | Decision                                                      |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------- |
| Generation    | Domain combinatorics, `InstrumentProfile`                                                                                                                                                                   | Any learner state                                  | Generated / not                                               |
| `REQUIRES`    | `LatentCompetencyState`                                                                                                                                                                                     | `MaterialMemoryState`, `MaterialExecutionState`    | Eligibility tier (§7.1)                                       |
| Safety policy | `SessionState`, session history                                                                                                                                                                             | Competency, memory, execution state                | Suppress / not (per session)                                  |
| Challenge     | `Prediction.overall_p` (this candidate); `MaterialMemoryState` existence/timing (`last_retrieval_at`, `last_retrieval_attempt_at`) and `SessionState.last_failed_exercise` (named exceptions §6.1-§6.4)     | Retention, information, diversity, goals; topology | Reject / keep, via the band or a named exception              |
| Priority      | Eligibility tier (primary key); retention (memory + this candidate's `retrieval_opportunity`, §7.2); information (uncertainty + this candidate's evidence potential); diversity (history); goals (external) | Challenge/difficulty (already decided)             | Rank within tier, then select via the repetition guard (§7.3) |

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
priority weights (w_R, w_I, w_D, w_G) vs. the lexicographic alternative -
    simulation used and validated lexicographic (§10); the weighted-sum
    alternative remains untried, not ruled out
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
model: `invariants.py` (10 checks) proves the boundary holds mechanically - a
forbidden input can't move a stage's decision, regardless of whether the
resulting behavior is any good; `scenarios.py` (10 checks) runs the pipeline
longitudinally, driving `analysis/learner-model/simulate.py`'s own `run()` loop
through `SchedulerAgent` (`agent_pick`/`agent_on_outcome` hooks) rather than a
second update simulator, and asks whether the resulting behavior is actually
good. Both suites pass alongside the learner model's own 26 invariants.

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
    anchors last_retrieval_at, and anchored guidance_probe's own
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
p_min                  sampled passing: 0.60-0.70
p_max                  robust over the sampled 0.75-0.98 range
p_introduction_min     sampled passing: 0.15-0.25
shared probe interval  sampled passing: 1-5 days (§6.4: also governs
                       bootstrap_probe, not independently tunable yet, §9)
repetition cap         sampled passing: 2-8
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
coverage count so a silent evidence gap can't masquerade as a clean result. 85
individual runs were inconclusive; 3 `(value, check)` groups and 5
`(cell, check)` groups lacked any conclusive run entirely. In every one of those
8 cases, the same value or cell had at least one other, independently conclusive
check that had already failed there, so none of the classifications reported
above rest on missing evidence.

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
03-v1-math.md §5.4        last_retrieval_attempt_at - a genuine
                          MaterialMemoryState field this document's §6.4
                          consumes but does not own; §5.4 is authoritative
                          for what it means
GLOSSARY.md §6            scheduler structure decision; diagram updated to
                          match §3 above
GLOSSARY.md §7/§8         InstrumentProfile, SchedulerSafetyPolicy
v1-domain-model.md §17     REQUIRES
analysis/scheduler/        executable counterpart to this document: pipeline.py
                            implements stages 2-4 and the boundary contract,
                            invariants.py verifies it mechanically (10 checks),
                            scenarios.py verifies it behaviorally (10 checks,
                            §10), longitudinal.py adapts it into
                            analysis/learner-model/simulate.py's run() loop,
                            sensitivity.py sweeps the remaining heuristic
                            values against that same behavioral suite (§10.1)
```
