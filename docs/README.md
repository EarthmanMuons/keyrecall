# KeyRecall Documentation Map

**Status:** Living map, updated as the doc set evolves\
**Date:** August 18, 2026\
**Purpose:** Orient new readers, and record the current document authority and
lineage so later documents stop re-deriving vocabulary that earlier documents
already settled.

---

## 1. Why this file exists

KeyRecall's design work has gone through several passes, and earlier documents
weren't always updated to reflect what later passes concluded: independently
drafted vocabularies for the same concepts, a Q-matrix that predated the
analysis that made it stale, no explicit statement of which document wins when
two disagree. This file, together with `GLOSSARY.md`, establishes the vocabulary
and authority so that kind of drift gets caught rather than accumulating. See §4
for known supersessions and `GLOSSARY.md` §14 for the resolution ledger.

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
│   └── v1-domain-model.md           domain entities; Q-matrix superseded inline (§4)
│
└── learner-model/                what KeyRecall BELIEVES about the pianist
    ├── 01-research.md               learning-science research basis
    ├── 02-v1-design.md              learner-state architecture
    ├── 03-v1-math.md                V1 equations, scheduler math, simulation plan
    └── 04-v1-scheduler.md           scheduler pipeline + information-boundary contract
```

`analysis/learner-model/` (repo root, not under `docs/`) is the executable
counterpart to `01-03`: a simulation prototype with a 30-check invariant suite
and behavioral diagnostics, referenced throughout `03-v1-math.md` §5, §10, §18,
§29, §38 as the source of several findings that revised those documents after
simulation, not before it.

The numeric prefixes in `learner-model/` are load-bearing, not cosmetic:
`03-v1-math.md` states explicitly that it is subordinate to `02-v1-design.md`,
which is subordinate to `01-research.md`. That's a real, agreed dependency
chain, so the filenames encode it directly instead of requiring a reader to
infer it from prose or commit history.

`domain-model/` is **not** numbered the same way yet, though the condition for
doing so is now met: the Q-matrix reconciliation (§4, item 1) is done, and
`v1-domain-model.md` now consistently builds on `fingering-taxonomy.md` and
`motor-taxonomy.md` rather than partially predating them. Numbering this folder
(`01-fingering-taxonomy.md` → `02-motor-taxonomy.md` → `03-v1-domain-model.md`)
is a reasonable next small step, not yet applied here.

## 3. What each document is authoritative for

| Document                             | Authoritative for                                                                                                        | Not authoritative for                                                                                                                |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `design/product-vision.md`           | Product thesis, UX principles, competitive landscape, one-sentence vision                                                | Any specific data model, math, or current competency vocabulary                                                                      |
| `domain-model/fingering-taxonomy.md` | Canonical fingering per scale/hand (source of truth)                                                                     | Motor-family classification, learner state                                                                                           |
| `domain-model/motor-taxonomy.md`     | Motor-family/phase/crossing structure, mechanically verified                                                             | Latent competency ontology (explicitly out of scope, see its §15)                                                                    |
| `domain-model/v1-domain-model.md`    | Domain entities not explicitly superseded below (`ScaleDefinition`, `ExpectedEvent`, relationships, prerequisites, etc.) | `Exercise` (flat form), `FingeringGroup`, `Component` ontology, and its own Q-matrix tables (§6.2-§11), all superseded, see §4 below |
| `learner-model/01-research.md`       | Research grounding, citations, KeyRecall-synthesis vs. research-supported distinction                                    | Frozen equations (several formulas here are illustrative precedent, not adopted; see §4 below, items 3-4)                            |
| `learner-model/02-v1-design.md`      | Learner-state architecture; reconciled ten-Competency ontology (§9.1); compositional `Exercise` model                    | Numerical parameters, scheduler equations                                                                                            |
| `learner-model/03-v1-math.md`        | V1 equations, scheduler math (challenge-band formula, priority-utility form, §20-23), simulation/calibration plan        | Scheduler stage information-boundary contract (see `04-v1-scheduler.md`)                                                             |
| `learner-model/04-v1-scheduler.md`   | Scheduler pipeline structure; which stage may read which state and make which decision                                   | Numeric bounds/weights (still heuristic V1, unresolved), scheduler math itself (`03-v1-math.md` §20-23)                              |

When a conflict between documents isn't listed in §4 below, don't infer
authority from filename date or commit order: treat it as an unresolved
documentation issue and raise it, rather than silently picking a side. This
project deliberately preserves research and design history instead of
continuously rewriting it as though the current design had existed from the
start, so an undocumented conflict is a gap to flag, not a puzzle to resolve by
inference.

## 4. Known supersessions and resolution status

This section records known document supersessions, both completed and
still-pending migrations, so historical material in the older documents is never
mistaken for current design.

1. **`v1-domain-model.md` §6.2, §6.5-§11**: resolved. Superseded by the
   ten-Competency ontology (`02-v1-design.md` §9.1) and the `Q`/`q`/`w` Q-matrix
   (`03-v1-math.md` §9); inline notes point to both. `GLOSSARY.md` §14 has the
   resolution record.
2. **`v1-domain-model.md` §6.3 (flat `Exercise`)**: superseded by the
   compositional `Exercise` in `02-v1-design.md`.
3. **`01-research.md` §21.1's crossed-effects sketch** is motivating precedent,
   not the adopted model; `03-v1-math.md` §10's actual equation has no separate
   `b_u`/`c_m` terms, that role is played by the competency/memory/residual
   state directly.
4. **`product-vision.md` §14 and `01-research.md` §22's scheduler utility sums**
   are superseded by `03-v1-math.md` §20-§22's eligibility → challenge-filter →
   priority-ranking structure.

## 5. What this consolidation pass does _not_ cover yet

Deliberately out of scope for this pass; see `GLOSSARY.md` §14 for the full list
with rationale:

- Exact `SessionState` mathematics (decay, fatigue signal definition).
- Exact `InstrumentProfile` field set beyond the V1-required subset.
- Exact safety-policy thresholds.
- Exact placement-prior numeric values.

These become real design work once the vocabulary below is agreed.
