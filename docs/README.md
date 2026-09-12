# KeyRecall Documentation

Three kinds of document, kept apart on purpose.

| Folder       | Answers                                         | Goes stale when       |
| ------------ | ----------------------------------------------- | --------------------- |
| `system/`    | How KeyRecall works today                       | the code changes      |
| `decisions/` | Why it works that way, and what we ruled out    | we change our minds   |
| `research/`  | What evidence we built on, and what we measured | never, it is a record |

## Start here

1. [`system/README.md`](system/README.md) is the architectural tour. It is the
   one document to read first.
2. [`GLOSSARY.md`](GLOSSARY.md) when a term is unfamiliar. Every entry opens in
   plain English.
3. [`system/`](system/) for the part you are working on.

Those three are meant to be enough. A newcomer should be able to understand the
whole architecture without opening `decisions/` or `research/`, which deepen
that understanding rather than being prerequisites for it.

## The rest

- [`decisions/`](decisions/) records why the system is shaped the way it is,
  grouped by subject rather than one file per choice. Each entry is Decision,
  Why, Evidence, Consequences. Read one when you are about to change the thing
  it describes.
- [`research/foundations/`](research/foundations/) is the outside evidence:
  learning science, motor learning, and piano pedagogy. What does the literature
  suggest?
- [`research/experiments/`](research/experiments/) is what we measured about
  KeyRecall itself, including the negative results. What did we learn?
- [`REFERENCES.md`](REFERENCES.md) is the research bibliography, one entry per
  source with a line on what we took from it.
- [`roadmap.md`](roadmap.md) is what is deliberately deferred, and what is
  closed.

## The editorial test

> If changing the implementation could make a statement false, it belongs in
> `system/`. If it explains why the implementation became that way, it belongs
> in `decisions/` or `research/`.

`system/` is written so it could be reconstructed from the code and its tests.
That is what keeps it honest: when the two disagree, the code is right and the
document is a bug.

Documents carry no `Written` or `Last revised` field. Git has those, and a
hand-typed date drifts. Three things do get stated:

- `Status:` only when it is not `current`. A `proposed` document describes
  something not built; a `superseded` one is kept for a finding that outlived
  it.
- `Research cutoff:` in `research/foundations/`, where the boundary of a
  literature review is real information.
- A commit, script, or experiment name in `research/experiments/`, because that
  is provenance rather than bookkeeping.

## Where else the answers live

```text
packages/                  operational semantics; the code is the authority
LearnerParams              the live learner constants
SchedulerConfig            the live scheduler constants
analysis/onset-grouping/   recorded playing behind the grouping constants
analysis/timing-calibration/  recorded playing behind the timing constants
analysis/scale-motor/      the motor realization corpus
CONTRIBUTING.md            how to build, test, and what will surprise you
```

Numeric calibration is versioned and provisional throughout. The architecture is
settled for initial production; the constants in it are starting points,
calibrated against recorded playing where that was possible and not yet against
a real learner population.
