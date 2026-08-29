# The four data products

- **Status:** Current. The authority for what each store is for, what may be
  lost from it, and where aggregation is allowed.
- **Written:** August 29, 2026

KeyRecall keeps several things about a learner, and they are easy to confuse
because they overlap in content. They differ in the only way that matters:
**what happens when you lose one.**

```text
AUTHORITATIVE
AttemptJournal ────────► lose it and the history is gone
   │
   ├──► Checkpoint ─────► lose it and the next open is slower
   │
   ├──► Fluency history ► lose it and a chart is rebuilt
   │
   └──► Telemetry ──────► never held locally; a projection at an export boundary
```

One rule follows from that shape and does most of the work here: **aggregation
is allowed in the projections and forbidden in the journal.**

## Journal size is not a problem, and this is the measurement

`storage_footprint_test.dart` runs real sittings and measures what they write.
As of this writing, over 350 committed attempts:

| Quantity                           |                          Bytes |
| ---------------------------------- | -----------------------------: |
| Attempt record, mean               |                      **1,933** |
| Attempt record, min / median / max |          1,791 / 1,948 / 2,040 |
| Checkpoint                         |                          5,676 |
| Journal after gzip                 | **8.6% of raw** (~166/attempt) |

Which projects to:

| Practice volume | Attempts/year | 1 year | 5 years | 10 years | 10 years gzipped |
| --------------- | ------------: | -----: | ------: | -------: | ---------------: |
| 20 a day        |         7,300 |  14 MB |   71 MB |   141 MB |            12 MB |
| 40 a day        |        14,600 |  28 MB |  141 MB |   282 MB |            24 MB |
| 100 a day       |        36,500 |  71 MB |  353 MB |   706 MB |            61 MB |

A dedicated learner practising forty attempts every single day for a decade
costs a few hundred megabytes, and an eighth of that if the file is ever
compressed. **So the journal is retained in full, indefinitely, and no
compaction scheme is warranted.**

Two things earned that answer, and both were decisions made earlier for other
reasons. The transcript and the alignment edit script are deliberately not
persisted, so the largest artifact of an attempt never reaches disk. And the
wire format repeats its keys on every line, which is why ordinary compression
finds an eleven-fold reduction sitting there unclaimed: if size ever does become
a problem, transparent compression is the whole answer and costs nothing
semantically.

The characterization test exists so that stops being a belief. Its bound is
loose on purpose: it is a tripwire for a record that quietly grew by an order of
magnitude, not a budget to optimize against.

## Why time-series compaction is the wrong shape for the journal

A time-series database can replace ten-second samples with hourly averages
because the samples stop mattering once the average exists. The journal's claim
is not of that kind. It says:

> this exact sequence of observations produced this exact learner trajectory.

Exact replay and state-hash agreement are production invariants;
`PracticeSession.open` refuses to run a history it cannot reproduce.
Downsampling old attempts into summaries would end that guarantee, and would end
it silently, because the summarized attempts are exactly the evidence needed to
notice.

There is a coherent scheme that would preserve it, if the numbers above ever
changed by two orders of magnitude:

```text
placement ─► epoch 1 ─► verified checkpoint ─► epoch 2 ─► verified checkpoint ─► …
```

where a checkpoint that replay has verified becomes a new genesis and the epoch
behind it is archived. That is a new persistence contract with consequences for
model migration, debugging, export, and historical reinterpretation. It is not
worth entertaining until a measurement demands it, and the measurement says the
opposite.

## The four products

### 1. Attempt journal — authoritative

Append-only, lossless, retained indefinitely. Learner state is reproducible by
replaying it in order. It holds what replay needs and what a later model must be
able to reinterpret, and nothing it can safely recompute.

Its genesis is small and immutable: the profile, its creation instant, and its
[placement tier](../domain-model/progression-graph.md). Placement belongs there
because every posterior in the journal is a function of it; a history that does
not record the prior it was computed against cannot reproduce itself.

Nothing may be aggregated, summarized, or dropped.

### 2. Checkpoint — disposable acceleration

A snapshot of learner state at a journal position, verified against the journal
before it is trusted and discarded when it does not match. Losing one costs
replay time and nothing else. It is not historical evidence and must never be
read as such.

### 3. Fluency history — a rebuildable projection

Does not exist yet. This is where the time-series thinking belongs.

A learner-facing chart over years of practice should not scan the whole journal
per frame, so it wants derived storage: per-session and per-day summaries,
competency posteriors and uncertainties over time, tempo and quality
distributions. Those are genuine time series, they index well, and they may be
downsampled with age — per attempt recently, daily in the medium term, weekly or
monthly for old history.

All of that is safe **because the projection is disposable**. Delete it and
rebuild it from the journal. That property is what keeps the aggregation honest,
and it buys something else: when a later learner model changes what fluency
means, the projection is regenerated under the new model rather than being
discovered to have destructively summarized the only evidence there was.

### 4. Telemetry — a projection at an export boundary

Opt-in, minimized, versioned, and **not a journal upload**. Its schema is
defined by the analyses it supports, field by field, in
[`05-production-implementation-plan.md` §10](../learner-model/05-production-implementation-plan.md).
A field belongs in it because a research question needs it, never because the
journal happens to carry it.

The governing distinction:

> **Local persistence is optimized for faithful reconstruction. Telemetry is
> optimized for answering specified questions with the minimum necessary data.**

Those goals should produce different schemas, and the fact that they do is the
design working.

## Where privacy techniques apply, and where they do not

Privacy risk changes at every boundary, and the technique appropriate to one is
wrong at the others:

```text
the learner's device        exact journal, in the app sandbox
        │ explicit, opt-in, minimized projection
central collection          pseudonymous events
        │ aggregation, differential privacy
research dataset            statistics, or synthetic data for sharing
```

The literature on synthetic learning-analytics data and on differential privacy
for learning analytics is about the lower two boundaries: many learners' records
pooled somewhere they did not put them.[^1][^2] It is not an argument for
degrading a single learner's own history on their own device.

Data minimization still applies locally — the transcript and edit script are
discarded rather than kept because they might be useful, which is minimization
doing its job. But **semantic downsampling for privacy happens at the export
boundary, not by damaging the canonical local evidence.**

## The reinterpretability boundary

Worth stating plainly, because it is a consequence of a decision made for
storage reasons and it constrains future research:

```text
performance ──► measurement v1 ──► Outcome ──► learner v1 ──► state
               (not persisted)   (persisted)
```

A future **learner model** can be run over historical outcomes; that is what
replay is. A future **measurement model** cannot be run over historical
performances, because those performances are gone.

That is probably the right trade — keeping every MIDI event forever would change
both the storage and the privacy calculation substantially — but it is a
boundary rather than an oversight. Its practical consequence: if a research
question needs something the `Outcome` does not represent, such as a timing
distribution rather than a stability score, that statistic has to be added to
the journal deliberately and in advance. It cannot be recovered later.

[^1]:
    Liu et al., _Scaling While Privacy Preserving: A Comprehensive Synthetic
    Tabular Data Generation and Evaluation in Learning Analytics_ (2024),
    <https://arxiv.org/abs/2401.06883>.

[^2]:
    Liu et al., _Advancing privacy in learning analytics using differential
    privacy_ (2025), <https://arxiv.org/abs/2501.01786>.
