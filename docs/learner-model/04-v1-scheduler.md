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
p_min <= overall_p <= p_max              -> survives, normal band
new material, overall_p >= p_intro_min   -> survives, introduction envelope (§6.1)
guidance-probe eligible                  -> survives, guidance probe (§6.2)
recovery / override                      -> survives, named exception
otherwise                                -> filtered out
```

Simulation (`analysis/scheduler/`, §10) validated two of these paths as genuine
admission gates rather than unconditional bypasses - not every named exception
"skips the check entirely." Diagnostic probe, recovery after retrieval failure,
and explicit learner request remain true bypasses (`override`/`recovery`): they
skip band evaluation outright, on grounds challenge filtering has no basis to
second-guess. New-material introduction and guidance fading turned out to need
their own conditional gates instead, below.

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

### 6.2 Guidance probe: a bounded step back toward independence

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

checked after the `recovery` exception, so a failed probe doesn't immediately
trigger another probe (`SessionState.last_outcome_failed` routes the next
attempt to `recovery` instead). A successful probe is a genuine retrieval test,
so it can re-anchor the clock itself; if it does, normal band admission - not a
further bypass - is what lets less-guided realizations compete from there. One
step, not a jump straight to unguided: the probe only needs to restore a genuine
test, not solve the whole difficulty gap at once.

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
| Challenge     | `Prediction.overall_p` (this candidate); `MaterialMemoryState` existence/timing and `SessionState.last_outcome_failed` (named exceptions §6.1-§6.2)                                                         | Retention, information, diversity, goals; topology | Reject / keep, via the band or a named exception              |
| Priority      | Eligibility tier (primary key); retention (memory + this candidate's `retrieval_opportunity`, §7.2); information (uncertainty + this candidate's evidence potential); diversity (history); goals (external) | Challenge/difficulty (already decided)             | Rank within tier, then select via the repetition guard (§7.3) |

## 9. Deliberately left open

Matching `03-v1-math.md` §25's provenance discipline, none of the following are
resolved by this document - they are heuristic V1 choices, currently versioned
in `analysis/scheduler/config.py`/`config.toml`, same status as the learner
model's `alpha`/`lambda` constants before Experiments B/C. Simulation (§10)
validated the _mechanisms_ these constants parameterize; the specific values
remain exactly as heuristic and revisable as before:

```text
challenge-band bounds (p_min, p_max) and their named-exception conditions
p_introduction_min, the separate lower band for new-material introduction
    (§6.1) - validated as a mechanism, not as a value
guidance probe's elapsed-time threshold (§6.2) - heuristic value; the
    currently one-step probe scope is validated behaviorally but remains
    revisable if later scenarios justify a broader progression policy
repetition guard's consecutive-selection cap (§7.3) - likewise
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
diversity/interleaving's exact data model and decay
goals data model
whether topology gets its own probe-selection signal (§6)
```

## 10. Scheduler simulation tests

This list is no longer purely aspirational. `analysis/scheduler/` implements the
boundary contract itself as `pipeline.py`, and verifies it in two complementary
passes, mirroring the split `03-v1-math.md` §38 established for the learner
model: `invariants.py` (10 checks) proves the boundary holds mechanically - a
forbidden input can't move a stage's decision, regardless of whether the
resulting behavior is any good; `scenarios.py` (7 checks) runs the pipeline
longitudinally, driving `analysis/learner-model/simulate.py`'s own `run()` loop
through `SchedulerAgent` (`agent_pick`/`agent_on_outcome` hooks) rather than a
second update simulator, and asks whether the resulting behavior is actually
good. Both suites pass alongside the learner model's own 26 invariants.

`03-v1-math.md` §30's pathology list motivated the scenarios below; three of
them found real problems, which drove the revisions described in §6.1, §6.2,
§7.2, and §7.3:

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

guidance is not removed before independent retrieval is plausible (§30,
    the paired failure mode). Structurally supported by the guidance
    probe's own design (one step at a time, gated on a prior confirmed
    success plus elapsed time, §6.2) but not covered by a dedicated
    scenario - still open.

failure can increase support without destroying motor challenge. Not
    covered by a dedicated scenario - still open. check_failure_recovery_
    is_temporary (analysis/scheduler/scenarios.py) verifies the recovery
    exception itself clears correctly after a subsequent success, not
    this specific claim about ExecutionConditions.

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
```

Two further scenarios validate existing architecture rather than resolving a §30
pathology: eligibility progression (§5.1 - `PROVISIONALLY_ELIGIBLE` to
`FULLY_ELIGIBLE` as RH/LH competency crosses the `REQUIRES` threshold) and the
recovery exception's temporariness (§6, checked above). The repetition guard has
its own dedicated scenario beyond the longitudinal one above, directly proving
both its properties (excludes an over-repeated material when an alternative
exists; never forces zero admission when none does) against directly-constructed
candidates rather than relying on a real run to produce the right conditions
incidentally.

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
GLOSSARY.md §6            scheduler structure decision; diagram updated to
                          match §3 above
GLOSSARY.md §7/§8         InstrumentProfile, SchedulerSafetyPolicy
v1-domain-model.md §17     REQUIRES
analysis/scheduler/        executable counterpart to this document: pipeline.py
                            implements stages 2-4 and the boundary contract,
                            invariants.py verifies it mechanically (10 checks),
                            scenarios.py verifies it behaviorally (7 checks,
                            §10), longitudinal.py adapts it into
                            analysis/learner-model/simulate.py's run() loop
```
