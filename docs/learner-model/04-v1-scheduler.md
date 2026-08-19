# V1 Scheduler Architecture

## 1. Purpose

This document specifies the V1 scheduler's pipeline and, specifically, the
information boundary between its stages: what each stage may read, what
decision it is allowed to make, and what it must leave to a different stage.

It is subordinate to `01-research.md`, `02-v1-design.md`, and `03-v1-math.md`
§20-23, which remain authoritative for the underlying math (the challenge-band
formula, the priority-utility form, review urgency). This document does not
re-derive that math or freeze numeric weights/bounds; those stay heuristic V1,
versioned, and open to simulation-driven revision, same as every constant in
`03-v1-math.md` §25-26. What this document adds is architectural: which stage
gets to look at which piece of state, stated precisely enough that violating
it is a visible design error, not just a code-review judgment call.

## 2. Why the boundary needs to be explicit

The learner-model experiments (`03-v1-math.md` §38, invariants 14-18) found
the same failure shape five separate times: a shared or blended signal let
one part of the model manufacture apparent learning it hadn't earned. A
single performance logit let memory contaminate motor competencies. A shared
execution channel let motor evidence contaminate topology. A shared
prediction/evidence pathway let a badly calibrated retrieval estimate look
like motor learning. A shared uncertainty field let pre-anchor evidence
manufacture confidence about a quantity it had never spoken to. Every fix was
the same shape: give the contaminated thing its own prediction, its own
evidence, and (where applicable) its own uncertainty - never a numerical
patch layered on top of the shared signal.

The scheduler is built from four stages that each answer a different
question about a candidate exercise. Nothing stops one stage's code from
reaching into state that belongs to another stage's question, and unlike the
learner model, that mistake would not _automatically_ show up as an
invariant failure - it would show up as a scheduler that behaves plausibly
while quietly answering the wrong question, unless the invariants are
written specifically to make that visible (§10). This document exists to
make that mistake visible before it's written, not to rediscover it through
simulation the way the learner model did.

The general rule, stated once so every section below can just apply it:

> A stage may use only the information appropriate to the question it
> answers. A decision that belongs to one stage must not be re-derived,
> second-guessed, weakened, or duplicated by a different stage.

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
things: hard domain/instrument constraints determine what candidate
generation is even capable of producing, so they belong inside stage 1 as
generation-time constraints, not a filter applied after generating invalid
candidates. The `REQUIRES` prerequisite gate is genuinely a separate,
learner-state-dependent stage, since it needs current competency state to
evaluate - that's stage 2. `GLOSSARY.md` §6's diagram is updated to match.

## 4. Stage 1: Candidate generation

**Question it answers:** what exercises could possibly be presented, given
the domain and this learner's instrument - independent of whether they'd be
any good to present right now.

**Allowed inputs:**

```text
TechnicalMaterial x ExercisePattern x ExecutionConditions x GuidanceContext
    x MotorRealization combinatorics (02-v1-design.md §4-8)
InstrumentProfile (key_count / playable_range, GLOSSARY.md §7)
```

**Forbidden inputs:** `LatentCompetencyState`, `MaterialMemoryState`,
`MaterialExecutionState`, `SessionState`. Nothing about this specific
learner's estimated ability, memory, or fatigue may influence what gets
generated - only what's structurally possible. This mirrors the Q-matrix's
own rule (`03-v1-math.md` §9.4): `Q` must never encode practice or transfer
that didn't happen. The same discipline applies here in the other direction -
candidate generation must never encode a readiness judgment that hasn't been
made yet by a later stage.

**Decision type:** set membership. A candidate is generated or it isn't;
there is no scoring at this stage. Generated iff:

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
`RH_SCALE_EXECUTION` + `LH_SCALE_EXECUTION` making
`HANDS_TOGETHER_COORDINATION` exercises more/fully eligible
(`v1-domain-model.md` §17, `03-v1-math.md` §20).

**Forbidden inputs:** `MaterialMemoryState`, `MaterialExecutionState`. This
gate answers "is the learner generally ready for this kind of exercise," not
"will this specific material go well" - that's challenge filtering's
question (§6), evaluated on the specific candidate, not a competency
prerequisite.

**Decision type:** soft, via an eligibility **tier**, not a numeric score fed
into priority ranking's utility. A candidate short of a prerequisite is a
worse candidate, not an invalid one - it remains available, but does not
compete on equal footing with a fully-eligible candidate; §7 defines exactly
how. Unlike stage 1, failing this doesn't remove the candidate from
consideration.

### 5.2 `SchedulerSafetyPolicy`

**Allowed inputs:** `SessionState` (workload/fatigue signal,
`GLOSSARY.md` §4) and direct session-history signals (recent repetition
count, sustained-intensity duration). **Not** competency, memory, or
execution state - this is a workload constraint, not a pedagogical one, and
explicitly not a medical/injury inference (`GLOSSARY.md` §8).

**Decision type:** closer to hard than `REQUIRES`. It can suppress a
candidate for this session regardless of how pedagogically appropriate it
is competency-wise - a session-load ceiling, not a ranking term.

## 6. Stage 3: Challenge filtering

**Question it answers:** is the predicted difficulty of this _specific_
candidate - material, execution conditions, and guidance level all fixed in
the candidate generated by stage 1 and admitted by stage 2 - in a productive
zone for this learner. Stage 2 doesn't choose those fields; it only
evaluates eligibility and safety on the candidate stage 1 already produced.

**Allowed inputs:** `Prediction.overall_p` from `predicted_success()`
(`03-v1-math.md` §10.1: `material_available_p * execution_p`), computed for
this candidate's exact `TechnicalMaterial` / `ExecutionConditions` /
`GuidanceContext`.

`overall_p`, not `independent_retrieval_p` or `execution_p` alone, is the
right quantity: guidance level is a property of _this candidate_, chosen by
stage 1, not a fixed backdrop the learner shows up to. A fully-cued version
of hard material legitimately predicts as easier than an unguided version of
the same material, and challenge filtering should reflect that - it's
answering "will presenting this exact candidate go well," which cueing
genuinely changes. This is the `03-v1-math.md` §13 principle
(`p_hat_acceptable` may be a composite scheduler-facing scalar even though
state updates must not be) applied to a concrete quantity.

`predicted_topology_p` is deliberately excluded. Topology is a parallel
inference target (`03-v1-math.md` §10.1), not part of "will this attempt's
execution look acceptable" - folding it into the challenge signal would make
this stage re-decide something the evidence model already keeps separate.
Whether topology warrants its own probe-selection signal is open, not
resolved here (§9).

**Forbidden inputs:** retention need, information value, diversity, goals
(stage 4's questions); `REQUIRES`/safety eligibility (stage 2's question,
already applied - a candidate that reaches this stage is already known to
be eligible).

**Decision type:** a true filter, not a filter-or-score. Priority ranking
(§7) has no term that consumes a challenge score - its rank key is
eligibility tier plus R/I/V/G, nothing else - so a "strongly deprioritize"
option here would be exactly the dangling-score problem `REQUIRES` had
before §7.1: a distinction with nowhere to go. The decision is therefore
binary:

```text
p_min <= overall_p <= p_max    -> survives, ranked normally in stage 4
outside the band                -> filtered out
named exception                 -> bypasses this stage, survives explicitly
```

Named exceptions (diagnostic probe, new-material introduction, recovery
after retrieval failure, explicit learner request, `03-v1-math.md` §21) skip
challenge filtering entirely rather than widening the band or softening the
reject into a penalty. If simulation later shows a genuine need for a softer
challenge concept, that becomes its own named architectural mechanism with a
defined consumer, not an implicit score threaded through a stage that
doesn't read it.

## 7. Stage 4: Priority ranking

**Question it answers:** among everything that survived stages 1-3, what
should be presented next.

### 7.1 Eligibility tier is the primary key, not a fifth utility term

§5.1's `REQUIRES` evaluation has to affect the outcome somehow, but the existing
architectural decision (`GLOSSARY.md` §6) is specifically that it must not
become a weighted term competing with retention/information/diversity/goals,
since that would let a soft pedagogical judgment get outvoted by, say, a
strong diversity score - the same kind of boundary violation §2 warns
about. The resolution is a discrete, ordered **eligibility tier**, computed
once from `REQUIRES` (e.g. `FULLY_ELIGIBLE` / `PROVISIONALLY_ELIGIBLE` - the
exact count and labels are open, §9), that ranks lexicographically ahead of
the R/I/V/G utility rather than inside it:

```text
rank_key(e) = (eligibility_tier(e), U(e))
```

Candidates are ordered by tier first, then by `U(e)` (or the lexicographic
R>I>V>G ordering, §7.3) within a tier. A `PROVISIONALLY_ELIGIBLE` candidate
never outranks a `FULLY_ELIGIBLE` one no matter how strong its retention or
diversity score is; it remains reachable - for diagnostic probes,
material introduction, a fallback when no fully-eligible candidate survives
stages 1-3, or other explicitly allowed progression scenarios - without
competing numerically against readiness.

Taken literally, "never outranks" and "remains reachable for diagnostic
probes" are in tension whenever a fully-eligible candidate also survives:
under the strict lexicographic rule, the provisional candidate is reachable
only when no fully-eligible one does. If a diagnostic probe should sometimes
be deliberately chosen despite fully-eligible alternatives existing, that
needs a named tier bypass, the same shape as challenge filtering's named
exceptions (§6) - not decided here (§9).

This preserves both standing decisions: `REQUIRES` isn't a hard
`if not requires: reject()` (stage 1's
kind of decision), and it isn't `w_P P(e)` buried inside pedagogical utility
either.

### 7.2 Within a tier: R/I/V/G

Each term reads a different slice of state (`03-v1-math.md` §22):

```text
R  retention/review need     MaterialMemoryState only (§23: f(1-M, U_M)).
                              Not competency, not execution state.

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

**Forbidden:** re-deriving challenge or difficulty - already decided in
stage 3. This stage ranks; it does not reject, and no term here may overturn
stage 3's admission decision or stage 2's eligibility tier (§7.1).

### 7.3 Open

Whether `U(e)` is a weighted sum or the lexicographic R>I>V>G ordering
`03-v1-math.md` §22 sketches, the exact weights, and the eligibility-tier
count/labels are scheduler-simulation work (§9), not decided here.

## 8. Information boundary summary

| Stage         | Reads                                                                                                                                                      | Must not read                                      | Decision                     |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ---------------------------- |
| Generation    | Domain combinatorics, `InstrumentProfile`                                                                                                                  | Any learner state                                  | Generated / not              |
| `REQUIRES`    | `LatentCompetencyState`                                                                                                                                    | `MaterialMemoryState`, `MaterialExecutionState`    | Eligibility tier (§7.1)      |
| Safety policy | `SessionState`, session history                                                                                                                            | Competency, memory, execution state                | Suppress / not (per session) |
| Challenge     | `Prediction.overall_p` (this candidate)                                                                                                                    | Retention, information, diversity, goals; topology | Reject / keep                |
| Priority      | Eligibility tier (primary key); retention (memory); information (uncertainty + this candidate's evidence potential); diversity (history); goals (external) | Challenge/difficulty (already decided)             | Rank within tier             |

## 9. Deliberately left open

Matching `03-v1-math.md` §25's provenance discipline, none of the following
are resolved by this document - they are heuristic V1 choices for scheduler
simulation to narrow, same status as the learner model's `alpha`/`lambda`
constants before Experiments B/C:

```text
challenge-band bounds (p_min, p_max) and their named-exception conditions
priority weights (w_R, w_I, w_D, w_G) vs. the lexicographic alternative
eligibility-tier count/labels and exactly what promotes/demotes a candidate
    between tiers (§7.1)
whether/how a provisionally-eligible candidate can be deliberately chosen
    over a fully-eligible one for a diagnostic probe or material
    introduction - a named tier bypass, the same shape as challenge
    filtering's named exceptions (§6), rather than silently reachable only
    when no fully-eligible candidate exists (§7.1)
I(e)'s exact form for combining current uncertainty with a candidate's
    evidence potential (§7.2) - not just that both belong in it
SchedulerSafetyPolicy thresholds ("sustained high-demand" numerically)
REQUIRES relationships beyond the RH/LH -> HT example
diversity/interleaving's exact data model and decay
goals data model
whether topology gets its own probe-selection signal (§6)
```

## 10. Scheduler simulation tests

Only after the learner-state model behaves sensibly should the scheduler be
introduced - it now has (`03-v1-math.md` §38: 26 invariants, four rounds of
adversarial review). `03-v1-math.md` §30 already lists the pathologies to
test for; this section adds the specific properties this document's
boundary contract implies, without duplicating that list:

```text
no endless repetition of one material (§30: "repeating the same material
    indefinitely" - a V-term failure if diversity has no effect)
no permanent preference for easiest exercises (§30: "always choosing the
    easiest exercise" - a challenge-band failure if the band's lower bound
    isn't enforced, or an I-term failure if information value never competes
    with retention)
old material eventually resurfaces (§30: "never revisiting older material"
    - an R-term failure)
guidance can fade after successful retrieval (§30: "guidance that never
    fades"). The primary mechanism is stage 3, not I(e): candidate
    generation must offer lower-guidance variants; while memory is weak,
    those variants' material_available_p (and so overall_p) sits below
    p_min and challenge filtering rejects them outright, not merely
    deprioritizes them. As MaterialMemoryState improves, material_available_p
    rises and the lower-guidance variant enters the challenge band - only
    then does it exist for priority ranking to choose among at all. I(e)'s
    role is downstream of that: once both guidance variants are admitted,
    it can help decide between them by their remaining evidence potential
    (§7.2), but it is not what causes guidance to fade as memory improves -
    that's the challenge band doing its job. If simulation shows the
    lower-guidance variant never gets admitted despite strong memory,
    investigate stage 3 (band bounds, overall_p computation) before R/I/V/G
guidance is not removed before independent retrieval is plausible (§30:
    the paired failure mode - challenge filtering using overall_p, not
    execution_p alone, is specifically what should prevent this)
failure can increase support without destroying motor challenge (a stage-2
    vs. stage-3 separation test: a retrieval failure should be able to move
    the next candidate's GuidanceContext without collapsing ExecutionConditions
    difficulty to trivial - if it does, guidance and motor difficulty are
    contaminating each other the way §10.0's single logit once did)
new-material selection reflects transferable competency and uncertainty,
    not a fixed novice default (§24: an experienced learner should be able
    to receive a demanding initial probe on unseen material - competency
    priors drive the challenge prediction itself (§6); uncertainty affects
    selection primarily through I(e) (§7.2), not through the prediction)
```

Each of these should become a scripted scenario against the existing
synthetic learner profiles (`03-v1-math.md` §28) and a pass/fail check,
mirroring `analysis/learner-model/invariants.py`'s style rather than
introducing a new verification approach.

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
```
