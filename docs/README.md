# KeyRecall Documentation Map

**Status:** Proposed structure — pending confirmation before Phase 2 content
edits begin\
**Date:** August 18, 2026\
**Purpose:** Orient new readers, and record the current document authority and
lineage so later documents stop re-deriving vocabulary that earlier documents
already settled.

---

## 1. Why this file exists

KeyRecall's design work has gone through several passes. Each pass got more
precise than the last, but earlier documents were never fully updated to reflect
what later passes concluded. The result was three independently drafted
vocabularies for the same concepts, a Q-matrix that predates the analysis that
made it stale, and no explicit statement of which document wins when two
disagree.

This file — together with `GLOSSARY.md` — is the first deliverable of a
deliberate consolidation pass, done **before** writing the V1 prototype. It does
not yet rewrite the affected sections of the seven documents below; it
establishes the vocabulary and authority those edits will use, so the edits
happen once, coherently, instead of piecemeal. See §4 below for the specific
list of pending content edits per document, and `GLOSSARY.md` §14 for what this
pass deliberately leaves undecided.

## 2. Reading order

There are three document threads. Read top to bottom within a thread; the
threads themselves can be read in any order, though **Product Vision** gives the
most useful framing for the other two.

```text
docs/
├── README.md                    you are here
├── GLOSSARY.md                  canonical vocabulary + conventions
│
├── design/
│   └── product-vision.md        why KeyRecall exists, product/UX principles
│
├── domain-model/                what a scale exercise IS and REQUIRES
│   ├── fingering-taxonomy.md        canonical fingering research (source of truth)
│   ├── motor-taxonomy.md            mechanically derived motor structure
│   └── v1-domain-model.md           Q-matrix / domain entities (partial — see §4)
│
└── learner-model/                what KeyRecall BELIEVES about the pianist
    ├── 01-research.md               learning-science research basis
    ├── 02-v1-design.md              learner-state architecture
    └── 03-v1-math.md                V1 equations, scheduler structure, simulation plan
```

The numeric prefixes in `learner-model/` are load-bearing, not cosmetic:
`03-v1-math.md` states explicitly that it is subordinate to `02-v1-design.md`,
which is subordinate to `01-research.md`. That's a real, agreed dependency
chain, so the filenames encode it directly instead of requiring a reader to
infer it from prose or commit history.

`domain-model/` is **not** numbered the same way yet. Chronologically,
`v1-domain-model.md` was written first and `fingering-taxonomy.md` /
`motor-taxonomy.md` came later and superseded parts of it (see §4). Numbering
the files to match the chronology would misrepresent that as a settled, agreed
order the way `learner-model/` is. Once the Q-matrix reconciliation (§4, item 2)
is done, this folder should get the same numbering treatment.

## 3. What each document is authoritative for

| Document                             | Authoritative for                                                                                                                                          | Not authoritative for                                                                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `design/product-vision.md`           | Product thesis, UX principles, competitive landscape, one-sentence vision                                                                                  | Any specific data model, math, or current competency vocabulary                                                                       |
| `domain-model/fingering-taxonomy.md` | Canonical fingering per scale/hand (source of truth)                                                                                                       | Motor-family classification, learner state                                                                                            |
| `domain-model/motor-taxonomy.md`     | Motor-family/phase/crossing structure, mechanically verified                                                                                               | Latent competency ontology (explicitly out of scope — see its §15)                                                                    |
| `domain-model/v1-domain-model.md`    | Domain entities not explicitly superseded below (`ScaleDefinition`, `ExpectedEvent`, relationships, prerequisites, etc.)                                   | `Exercise` (flat form), `FingeringGroup`, `Component` ontology, and its own Q-matrix tables (§6.2-§11) — all superseded, see §4 below |
| `learner-model/01-research.md`       | Research grounding, citations, KeyRecall-synthesis vs. research-supported distinction                                                                      | Frozen equations (several formulas here are illustrative precedent, not adopted — see §4 below, items 4-5)                            |
| `learner-model/02-v1-design.md`      | Learner-state architecture; current _provisional_ competency ontology (subject to revision by the Q-matrix reconciliation); compositional `Exercise` model | Numerical parameters, scheduler equations                                                                                             |
| `learner-model/03-v1-math.md`        | V1 equations, scheduler structure (eligibility → challenge filter → priority ranking), simulation/calibration plan                                         | —                                                                                                                                     |

When a conflict between documents isn't listed in §4 below, don't infer
authority from filename date or commit order — treat it as an unresolved
documentation issue and raise it, rather than silently picking a side. This
project deliberately preserves research and design history instead of
continuously rewriting it as though the current design had existed from the
start, so an undocumented conflict is a gap to flag, not a puzzle to resolve by
inference.

## 4. Known supersessions (not yet applied to the documents themselves)

These are agreed but not yet written into the affected files. Listed here so the
map is honest about the current state of the docs, not just the target state.

1. **`v1-domain-model.md` §6.5-§7 (`Component` categories) and §8-§11 (Q-matrix
   tables)** are superseded in spirit by `motor-taxonomy.md` and by the
   `Competency` ontology in `02-v1-design.md` §9.1, but the tables themselves
   haven't been rewritten yet. Treat the Q-matrix as **known stale**, not
   current, until this reconciliation happens. This is the substantive next
   design task after this consolidation — see `GLOSSARY.md` §1 and §14.
2. **`v1-domain-model.md` §6.2 (`FingeringGroup`)** is superseded by the
   `FingeringPattern` → `MotorRealization` → `MotorFamily` decomposition in
   `motor-taxonomy.md`. See `GLOSSARY.md` §2 for why this isn't a simple rename.
3. **`v1-domain-model.md` §6.3 (flat `Exercise`)** is superseded by the
   compositional `Exercise` in `02-v1-design.md`
   (`TechnicalMaterial + ExercisePattern + ExecutionConditions + GuidanceContext + MotorRealization + Opportunities`).
4. **`01-research.md` §21.1's crossed-effects sketch**
   (`logit P(Y) = xβ + b_u + c_m + r_{u,m}`) is motivating precedent, not the
   adopted model. `03-v1-math.md` §10's actual equation has no separate
   `b_u`/`c_m` terms — that role is played by the competency/memory/residual
   state directly.
5. **`design/product-vision.md` §14 and `01-research.md` §22's scheduler utility
   sums** are superseded by `03-v1-math.md` §20-§22's eligibility →
   challenge-filter → priority-ranking structure.

## 5. What this consolidation pass does _not_ cover yet

Deliberately out of scope for this pass — see `GLOSSARY.md` §14 for the full
list with rationale:

- Resolving whether the Q-matrix's `PRIMARY`/`SECONDARY`/`NONE` distinction
  survives as anything more than relevant/not-relevant.
- Exact `SessionState` mathematics (decay, fatigue signal definition).
- Exact `InstrumentProfile` field set beyond the V1-required subset.
- Exact safety-policy thresholds.
- Exact placement-prior numeric values.

These become real design work once the vocabulary below is agreed.
