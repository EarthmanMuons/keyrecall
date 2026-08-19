# V1 Canonical Vocabulary and Conventions

**Status:** Living reference, updated as design decisions land\
**Date:** August 18, 2026\
**Purpose:** Settle, in one place, every term where the document set has
accumulated more than one name or more than one shape for the same concept. See
`README.md` for how this fits into the overall consolidation.

Nothing here is mathematically novel: it's a naming and authority decision, not
new design work. Substantive open questions are listed in §14 as deferred, not
resolved here.

---

## 1. Competency (canonical)

`Competency` replaces `KnowledgeComponent`, `KC`, and `Component`:
`product-vision.md` §7, `v1-domain-model.md` §6.5, and `02-v1-design.md` §9.1
each independently named the same concept, a persistent transferable latent
capability that exercises provide evidence about. `02-v1-design.md` §9.1 has the
canonical ten-Competency ontology; the older `Component` material in
`v1-domain-model.md` is marked superseded there.

## 2. Fingering/motor vocabulary

`FingeringGroup` (`v1-domain-model.md` §6.2) is retired, not renamed: mechanical
analysis found all 96 canonical fingering records collapse into one
`MotorFamily`, a different kind of result than the multi-family classification
`FingeringGroup` was designed to hold. Canonical triad:

```text
FingeringPattern    concrete canonical fingering, authoritative data
MotorRealization     mechanically derived realization of a pattern
MotorFamily          higher-level equivalence class over realizations
```

Runtime field naming follows `fingering-taxonomy.md` §15 (`fingering_pattern`,
not `fingering_group`); already applied.

## 3. `Exercise`: the compositional definition is canonical

Two shapes exist:

- `v1-domain-model.md` §6.3, flat:
  `scale_definition, hand_mode, octaves, direction, motion, tempo, rhythm, articulation, register, pattern_variant`
- `02-v1-design.md`, compositional:
  `TechnicalMaterial + ExercisePattern + ExecutionConditions + GuidanceContext + MotorRealization + Opportunities`

**Decision:** the compositional definition is canonical. It's what makes
`GuidanceContext` a first-class part of the evidence model rather than UI state,
which is load-bearing for the whole memory/execution split in `02-v1-design.md`
§9. The flat definition in `v1-domain-model.md` §6.3 is superseded.

## 4. `LearnerState` vs. `SessionState`

`02-v1-design.md` and `03-v1-math.md` only model persistent state
(`LatentCompetencyState`, `MaterialMemoryState`, `MaterialExecutionState`). The
transient, within-session layer from `product-vision.md` §12 (warm-up, fatigue,
temporary performance variation) was dropped somewhere along the way, not
deliberately retired.

**Decision:** restore it as a distinct layer:

```text
LearnerState
    persistent across sessions
    LatentCompetencyState + MaterialMemoryState + MaterialExecutionState

SessionState
    transient, within a single practice session
    warm-up signal, fatigue signal, temporary performance deviation
```

Without it, a bad last ten minutes of a session can get interpreted as
persistent competency loss rather than transient state: an inference correctness
issue, not just a UX gap. Exact math is not decided here (§14). `SessionState`
may feed `SchedulerSafetyPolicy` (§8) alongside direct workload signals, but
isn't the only input a safety rule can use.

## 5. Acquisition / Development / Maintenance

`product-vision.md` §13 treats ADM as an explicit state each competency
occupies, governing practice methodology. Neither `02-v1-design.md` nor
`03-v1-math.md` has an ADM variable.

**Decision:** that's the right evolution, stated explicitly rather than left
looking like an oversight. The continuous probabilistic state already does what
ADM was for. ADM survives only as a derived, user-facing description, never as
stored model state:

```text
ACQUISITION   ~ low/uncertain capability; substantial instructional support
DEVELOPMENT   ~ improving capability; progressively independent performance
MAINTENANCE   ~ established capability; periodic evidence/review
```

The scheduler doesn't need to know which bucket a competency is "in" to operate.
`02-v1-design.md` should get a short note saying this, so nobody re-adds a
discrete stage field believing it was never considered.

## 6. Scheduler structure

`product-vision.md` §14 and `01-research.md` §22 each sketched a weighted-sum
scheduler utility; `03-v1-math.md` §20-§22 instead uses candidate generation →
challenge-band filter → priority ranking. Treating difficulty as a filter rather
than a penalty term fighting a challenge-seeking term in the same sum is a real
structural improvement; the two earlier formulas are retired.

```text
candidate generation         (domain constraints - canonical fingering exists,
                               tempo in bounds, ... - decide what gets
                               generated at all, not a filter applied after)
        ↓
eligibility                  (REQUIRES prerequisite gate + SchedulerSafetyPolicy)
        ↓
challenge filtering          (p_min ≤ p̂ ≤ p_max, with named exceptions)
        ↓
priority ranking             (retention, information, diversity, goals)
```

`REQUIRES` (`v1-domain-model.md` §17) belongs in the eligibility stage, not as a
weighted term competing with retention/information/diversity/ goals. Applied in
`03-v1-math.md` §20. Full stage-by-stage information-boundary contract - what
each stage may read, what it must leave to another stage -
`learner-model/04-v1-scheduler.md`.

## 7. `InstrumentProfile` (new)

Not previously modeled anywhere. The learner model interprets timing and
velocity as evidence of motor competency; instrument differences are a real
confound, and a generated exercise can request a register the connected
controller doesn't have.

**Decision:** add `InstrumentProfile` to the domain model, with an explicit
V1-required/deferred split rather than speculative completeness:

```text
InstrumentProfile
    key_count / playable_range      REQUIRED in V1: hard constraint on
                                     candidate generation; do not schedule an
                                     exercise whose register doesn't fit
    measured_latency?               deferred; only matters if timing is ever
                                     interpreted against generated sound or an
                                     external clock; raw inter-onset MIDI
                                     timing is largely unaffected
    action_type?                    deferred metadata; record it, but do not
                                     normalize scores against it without
                                     evidence
    velocity_available
    velocity_curve/calibration?     deferred metadata, same reasoning
    capabilities
```

## 8. `SchedulerSafetyPolicy` (new): practice-load constraints, not fatigue diagnosis

Not previously modeled. An autonomous scheduler built around Challenge Point
theory is, by design, going to keep pushing tempo/difficulty toward the
learner's frontier repeatedly, across many keys, with no session-length concept.
That has real overuse/RSI implications for a physical motor-skill domain, and
nothing in the document set addressed it.

**Decision:** add a policy layer that may consume `SessionState` alongside
direct workload/session-history signals, but does **not** perform medical/injury
inference (KeyRecall should be cautious about claiming MIDI behavior indicates
physical risk). Conservative, non-diagnostic workload guardrails, not contingent
on successfully detecting fatigue:

```text
SchedulerSafetyPolicy
    limits sustained high-demand repetition
    encourages variation over long high-intensity runs
    can surface rest recommendations
    avoids escalating difficulty further under a fatigue-consistent SessionState signal
```

This sits in the eligibility/filtering part of the pipeline in §6: it constrains
what the scheduler will choose, not another ranking term.

## 9. `Fluency Profile`: restored as the explicit user-facing abstraction

`product-vision.md` §32.2 proposed this as the learner-facing surface over the
internal state. It doesn't appear anywhere in `02-v1-design.md` or
`03-v1-math.md`, which only got more detailed about the internal state during
the same period. Given how far that internal state now goes
(`LatentCompetencyState`, `MaterialMemoryState`, `MaterialExecutionState`, and
now `SessionState`), a translation layer to something a user can actually read
matters more, not less.

**Decision:** restore it explicitly. `02-v1-design.md` should state the boundary
directly:

```text
Internal (never shown raw):
    LatentCompetencyState, MaterialMemoryState,
    MaterialExecutionState, SessionState

User-facing (derived):
    Fluency Profile
        e.g. "C# minor: recall strong, RH execution developing,
              LH execution strong"
```

The Fluency Profile's labels (`strong`/`developing`/etc.) are derived
presentations, not claims of a one-to-one correspondence with specific latent
variables, same spirit as the ADM labels in §5.

## 10. Two registries, kept distinct

`product-vision.md` §27 proposed an **Assumption Registry** for
conceptual/design uncertainty. `03-v1-math.md` §25-§26 independently built a
**Parameter Registry** for numerical model configuration. These look similar but
answer different questions.

**Decision:** keep both; state the boundary so nobody merges them:

```text
Assumption Registry
    claims about the world or the design
    e.g. "standard MIDI cannot directly observe fingering"
         "HT transfer from RH+LH is only partial"
    fields: ID, title, assumption, basis, evidence strength,
            confidence, observable/falsifier, status

Parameter Registry
    numerical model configuration
    e.g. residual.prior_variance = ..., provenance: heuristic
    fields: value, provenance category, model version
```

A Parameter Registry entry may cite an Assumption Registry ID as its basis (e.g.
a heuristic memory half-life citing the HLR-precedent assumption), but they are
not interchangeable, and an assumption is not automatically a parameter.

Neither registry currently exists as an actual file; both are still prose ("open
questions" / "explicit non-decisions" lists and the §25-26 provenance scheme).
Standing them up as real, structured, greppable files is listed as pending work
in §14.

## 11. Notation: `03-v1-math.md` symbol cleanup

The math document is close enough to implementation that readability should beat
compact single-letter typography, and it currently reuses letters for unrelated
quantities within itself:

| Current              | Meaning                                            | Collides with                                            | Rename to                      |
| -------------------- | -------------------------------------------------- | -------------------------------------------------------- | ------------------------------ |
| `D_motor(e)`         | motor/execution task difficulty (§10-11)           | its own component below                                  | `Diff_motor(e)`                |
| `D_e`                | direction effect, a term inside `D_motor(e)` (§11) | `D_motor(e)` itself                                      | `Dir_e`                        |
| `G(e)`               | goal-relevance, scheduler ranking (§22)            | none currently; historically `G_e` (see below)           | `Goal(e)`                      |
| `I(e)`               | information value, scheduler ranking (§22)         | `I_sequence` below                                       | `Info(e)`                      |
| `I_sequence`         | sequence/pitch integrity, memory evidence (§6.1)   | `I(e)` above                                             | `Seq` (or `Seq_e`)             |
| `V(e)`               | diversity/interleaving value (§22)                 | none, renamed for consistency                            | `Div(e)`                       |
| `R(e)`               | retention/review need, scheduler ranking (§22)     | none, renamed for consistency                            | `Ret(e)`                       |
| `d_e`                | retrieval demand ∈ [0,1] (§6)                      | none, but easy to misread next to `Dir_e`                | keep `d_e`, flag as distinct   |
| `w_R, w_I, w_D, w_G` | scheduler ranking weights (§22)                    | case-collide with `w_r` (execution residual weight, §16) | `w_ret, w_info, w_div, w_goal` |

`O_e` (octave effect) and `H_e` (hand-configuration effect), both in §11, don't
collide with anything and can stay as-is.

`D(e)` (the pre-hurdle-split "total task difficulty") and `G_e`
(guidance/support difficulty effect, formerly a term inside it) are retired,
not renamed: simulation (`analysis/learner-model/`) split retrieval
availability from execution difficulty, and guidance now affects the former,
not the latter (`03-v1-math.md` §10-11, §18). `D(e)` became `D_motor(e)`
above; `G_e` has no successor symbol because it no longer corresponds to
anything the model computes.

## 12. Placement priors: self-report maps primarily to the mean, not the variance

`product-vision.md` §5 describes collecting a rough self-report ("new to scales"
/ "some experience" / "advanced") before practice begins. `03-v1-math.md` §4.1
defines `μ_{0,k}` and `σ²_{0,k}` as "heuristic priors" without saying how
self-report maps to them, a real gap since synthetic cold-start behavior in the
simulation harness (§28-29) depends on it.

**Decision:** self-report shifts the **prior mean**, while **uncertainty stays
broad regardless of tier**:

```text
beginner        lower μ0,   broad σ0
some experience moderate μ0, broad σ0
advanced        higher μ0,  still meaningfully broad σ0
```

Uncertainty staying broad (rather than shrinking with a more confident
self-report tier) is what lets the first few diagnostic exercises dominate
quickly instead of the self-report anchoring the estimate too strongly. The
exact numeric mapping from tier to `μ0` is a heuristic V1 parameter (Parameter
Registry, `provenance: heuristic`), not decided here.

## 13. Citation hygiene

`01-research.md`'s citation for the 2026 VR piano-training paper (currently
"_Adaptive Visual Hand Guidance for Piano Training_ (2026)", arXiv:2603.06253)
should be corrected to its actual title and authors: _"Skill-Adaptive Ghost
Instructors: Enhancing Retention and Reducing Over-Reliance in VR Piano
Learning"_ (Hsieh, Visser, Eisemann, Marroquim). Small, mechanical fix, bundled
into the pending-edits list in `README.md` §4 rather than applied here since it
touches document content.

## 14. Resolution ledger: deferred and resolved items

Tracks the items this document originally flagged as explicitly not decided
here, so the vocabulary/authority pass didn't quietly expand into resolving open
design questions it wasn't meant to settle, and records resolutions as they land
in later passes so a reader isn't left thinking an item is still open once it
isn't. Deferred still means what it says for everything below that isn't marked
resolved.

- ~~**Q-matrix reconciliation itself**~~: **resolved**, see `03-v1-math.md` §9.
  `PRIMARY`/`SECONDARY`/`NONE` is retired from the Q-matrix entirely: a binary
  structural `Q_{e,k}`, a derived predictor loading `q_{e,k}`, and a per-attempt
  evidence weight `w_{a,k}`. The ten-Competency ontology (§1) and
  `FingeringPattern` field rename (§2) are both applied.
- **`SessionState` mathematics**: decay function, what counts as an informative
  fatigue signal (§4).
- **`InstrumentProfile` field boundary** beyond the V1-required
  `key_count`/`playable_range` (§7).
- **`SchedulerSafetyPolicy` thresholds**: what "sustained high-demand
  repetition" means numerically (§8).
- **Placement-prior numeric values**: the mapping philosophy is decided (§12),
  the actual `μ0`/`σ0` numbers per self-report tier are not.
- **Standing up the two registries as real files** rather than prose
  open-questions lists (§10).

---

## 15. Summary table

| Old term(s)                                           | Canonical                                                            | Status                       |
| ----------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------- |
| `KnowledgeComponent`, `KC`, `Component`               | `Competency`                                                         | rename                       |
| `FingeringGroup`                                      | _(retired)_, see `FingeringPattern`/`MotorRealization`/`MotorFamily` | retire, not rename           |
| flat `Exercise` (`v1-domain-model.md` §6.3)           | compositional `Exercise` (`02-v1-design.md`)                         | supersede                    |
| _(missing)_                                           | `LearnerState` / `SessionState` split                                | restore                      |
| ADM as persistent state                               | ADM as derived label only                                            | retire as state              |
| 3 scheduler utility formulas                          | eligibility → challenge filter → priority ranking                    | supersede 2, keep 1          |
| _(missing)_                                           | `InstrumentProfile`                                                  | add                          |
| _(missing)_                                           | `SchedulerSafetyPolicy`                                              | add                          |
| _(dropped)_                                           | `Fluency Profile`                                                    | restore                      |
| Assumption Registry vs. Parameter Registry            | both, distinct responsibilities                                      | clarify, don't merge         |
| `D(e)`/`D_e`/`G(e)`/`I(e)`/`I_sequence`/`V(e)`/`R(e)` | see §11 table                                                        | rename for collision-freedom |
| `G_e`                                                 | _(retired)_, see §11                                                 | retire, not rename           |
| _(missing)_                                           | self-report → `μ0` mapping philosophy                                | decide                       |
