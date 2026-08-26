# KeyRecall Documentation Map

- **Status:** Current navigation and authority map
- **Last aligned:** August 21, 2026

## Start here

Readers should not need to reconstruct the current system from the research
chronology.

1. Read
   [`learner-model/v1-current-system.md`](learner-model/v1-current-system.md)
   for the complete, present-tense V1 learner model and scheduler.
2. Use [`GLOSSARY.md`](GLOSSARY.md) when a term or symbol is unfamiliar.
3. Follow links from the current-system guide only when you need detailed
   provenance, experiment reports, or implementation contracts.

The older documents are intentionally retained. They explain why the current
design exists and preserve negative results that should not be rediscovered, but
they are not the shortest path to understanding V1.

## Document structure

```text
docs/
├── README.md
├── GLOSSARY.md
│
├── design/
│   ├── product-vision.md
│   └── future-planning.md           deferred seams, hypotheses, and closed ideas
│
├── domain-model/
│   ├── alignment-contract.md        single-hand aligner exists; grouping does
│                                    not (evidence: analysis/onset-grouping/)
│   ├── attempt-termination.md       closures exist; non-learner paths do not
│   ├── material-admission.md        what may be introduced now, and why
│   ├── fingering-taxonomy.md
│   ├── motor-taxonomy.md
│   └── v1-domain-model.md
│
└── learner-model/
    ├── v1-current-system.md          integrated current view; start here
    ├── competency-extension-guide.md future ontology admission and tuning
    ├── 01-research.md                literature and evidentiary basis
    ├── 02-v1-design.md               architectural reasoning
    ├── 03-v1-math.md                 detailed math and learner experiments
    ├── 04-v1-scheduler.md            boundary contract and scheduler experiments
    └── 05-production-implementation-plan.md
                                      journal, replay, telemetry, and rollout
```

Executable analysis lives outside `docs/`:

```text
analysis/learner-model/    frozen: the Python prototype's model and experiments
analysis/scheduler/        frozen: the Python prototype's pipeline diagnostics
analysis/onset-grouping/   live: instrument takes behind the grouping decision
analysis/timing-calibration/ live: instrument takes behind the timing constants
```

The Python prototype is research provenance rather than a second implementation;
see `analysis/README.md` for what that means and what is canonical instead.

The current verification baseline is 32 learner-model invariants, 13 scheduler
information-boundary invariants, and 10 longitudinal scheduler scenarios.

## Authority

| Need                                                              | Authority                                               |
| ----------------------------------------------------------------- | ------------------------------------------------------- |
| Integrated initial-production behavior                            | `learner-model/v1-current-system.md`                    |
| Future competency admission, validation, and calibration workflow | `learner-model/competency-extension-guide.md`           |
| Canonical terminology and symbols                                 | `GLOSSARY.md`                                           |
| Product thesis, UX, privacy principles                            | `design/product-vision.md`                              |
| Deferred architectural, product, and domain hypotheses            | `design/future-planning.md`                             |
| Canonical scale fingering                                         | `domain-model/fingering-taxonomy.md`                    |
| Derived motor family, phase, crossing, and continuation structure | `domain-model/motor-taxonomy.md`                        |
| Domain entities not superseded below                              | `domain-model/v1-domain-model.md`                       |
| Research claims, citations, and limitations                       | `learner-model/01-research.md`                          |
| Learner-state architecture and ten-Competency ontology            | `learner-model/02-v1-design.md`                         |
| Detailed equations, derivations, and learner experiment record    | `learner-model/03-v1-math.md`                           |
| Scheduler stage information boundaries and experiment record      | `learner-model/04-v1-scheduler.md`                      |
| Attempt journal, replay, telemetry, and implementation gates      | `learner-model/05-production-implementation-plan.md`    |
| Operational semantics                                             | the Dart packages under `packages/`                     |
| Current provisional numeric values                                | `LearnerParams` and `SchedulerConfig` in those packages |
| How the V1 model was derived, and its equivalence evidence        | `analysis/README.md`                                    |

The current-system guide integrates these authorities; it does not erase their
more detailed contracts. If it conflicts with executable semantics or a
specialized authority, treat that as a documentation bug and resolve it
explicitly.

## Current view versus history

The documents have different jobs:

```text
v1-current-system.md     what V1 does and why, without chronology
competency-extension-guide.md
                         how a future competency earns promotion
future-planning.md       what is deliberately deferred or closed by default
01-05                    how the design was justified, tested, and prepared
git history              exact sequence of individual revisions
```

Historical sections may contain formulas clearly marked illustrative,
superseded, provisional, or open at the time they were written. A later
production decision wins over an earlier proposal. In particular:

1. The flat `Exercise`, `FingeringGroup`, `Component` ontology, and qualitative
   Q-matrix in `v1-domain-model.md` are superseded by the compositional
   exercise, ten-Competency ontology, and `Q`/`q`/`w` mapping.
2. Crossed-effects and single-logit equations in the research and early math
   sections are motivating precedents, not the production predictor. V1 uses
   separate retrieval availability, execution, and topology channels.
3. Early scheduler utility sketches are superseded by the staged pipeline and
   the production lexicographic key: eligibility tier, retention, information,
   diversity, goals.
4. Multiplicative memory updates are superseded by surprise-driven log-space
   current-durability and logit-space cold-start updates.
5. Binary or attenuated treatment of fully cued retrieval is superseded by the
   three-valued factual outcome; untested retrieval has exactly zero memory
   evidence.

These records remain in place because knowing what failed is valuable. They are
not prerequisites for implementing the current system.

## Production status

The synthetic mechanism-discovery phase is complete. The architecture,
transition ordering, and scheduler policy are frozen for initial production
pending empirical evidence. Numeric calibration remains provisional and
versioned.

The next milestone is the telemetry contract and deterministic offline replay
described in `learner-model/05-production-implementation-plan.md`, followed by
developer and small-pilot validation. Optional research telemetry must refine
the local-first system, never be required for it to function.
