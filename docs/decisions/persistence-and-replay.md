# Persistence and replay

Why the journal is the only authority, what a checkpoint may be trusted to do,
and where invalid values are rejected.

The mechanics are in [`../system/history.md`](../system/history.md). This file
is why they are that way.

## Learner state is not stored

**Decision.** The attempt journal is authoritative and append-only. What the
system believes about a player is whatever replaying that journal produces.

**Why.** Two things fall out of it. A stored belief can drift away from the
evidence that produced it, and nothing would detect that; there is no stored
belief here to drift. And a change to how the model learns becomes honest about
its own blast radius, because it changes what the whole history means rather
than only what happens next.

**Consequences.** `LearnerParams.modelVersion` has to move whenever the model
learns differently, or old attempts get reinterpreted under constants that were
never used to produce them. Startup costs a replay, which is what checkpoints
exist to reduce.

## Four things are stored that replay could recompute

**Decision.** The presented exercise, the prediction, the evidence weights, and
the memory attribution are persisted. Replay recomputes each and **compares**.

**Why.** They are an audit trace, not a cache. Reapplying the stored numbers
would reproduce any past mistake perfectly and prove nothing. Recomputing and
comparing is how a change that would silently reinterpret history gets caught
instead of absorbed.

**Consequences.** Full state snapshots are not duplicated per attempt. Each
record carries the hash of the state its decision was made from and the state
its update produced, which proves replay rebuilt the right state at every step
without paying to store it.

## Recorded exercises are not regenerated

**Decision.** `Exercise.recorded` rebuilds what was presented, including its
stored motor opportunities. It is not how new exercises are built.

**Why.** Replaying an old decision through a newer generator would silently
rewrite historical evidence: the same nominal exercise could resolve to
different notes or expose different opportunities.

## Canonical state advances only on a committed attempt

**Decision.** Every look-ahead, preview, and non-selecting decision runs against
a scratch copy. Canonical state advances only when the attempt is durably in the
journal, and at most once for it.

**Why.** Time propagation is mathematically path-independent but **not**
path-independent in floating point: advancing through three intervals and
advancing through their sum land on different bits, and a state hash is exact.
Replay propagates from one recorded attempt to the next, so the writer must do
the same.

**Consequences.** Propagating canonical state at a moment the journal does not
record makes that state unreachable by replay, which costs the journal its
authority. This is the one rule the persistence boundary imposes on the app.

## Idempotency is not first-write-wins

**Decision.** An attempt id returning with identical content is a retry and a
no-op. An attempt id returning with **different** content is a collision and
throws.

**Why.** In an authoritative log, silently keeping one of two conflicting
records is worse than refusing both: it produces a history that looks clean and
is wrong.

**Consequences.** The attempt is frozen when a close begins rather than
recomputed, because the app reads its clock again on every call and may hand
over a fresh transcript. A rebuilt record would offer the same id carrying
different content, which this rule then refuses. A retry finishes the
transaction that was started.

An append whose answer was lost is settled by reading durable history back.
Three answers and no others: the attempt is there and the append committed;
nothing with that id is there and the record may be written again; or that id
holds different content, which is a collision rather than something to resolve
by picking one.

## Sequence numbers are contiguous

**Decision.** `journalSequence` counts attempts in append order with no gaps,
and is distinct from `indexInSession`.

**Why.** A lost line has to be detectable rather than silently absorbed. And a
within-session index cannot say what a checkpoint already includes: a history
spans many sessions, so resuming from a session-relative position would silently
reapply every attempt from every other session.

## A checkpoint binds the history it skips

**Decision.** A checkpoint carries a chained digest over the canonical content
of every record it stands in for, and validation recomputes it.

**Why.** A per-record hash says the state at that position was reached. It says
nothing about whether the records _before_ it still say what they said.

```text
h(genesis)  = H(header, hash of the state replay starts from)
h(n)        = H(h(n-1), content hash of attempt n)
```

**Consequences.** Changing an earlier outcome, or opening the same journal under
a different placement, makes the digest disagree and costs a full replay. The
digest is over canonical content rather than over the file, built from decoded
records re-encoded canonically, so whitespace and key order are outside what it
binds: two files differing only in those ways hold the same history.

This is the trade a checkpoint is. The digest establishes the history is
**unchanged**, not that it was ever **verified**. Discard every checkpoint to
get the stronger claim back, which costs only time.

## A checkpoint from another model version is unusable in every mode

**Decision.** Including counterfactual replay.

**Why.** It already contains one model's reading of everything before it, so
seeding a different model from it produces a hybrid: earlier history estimated
one way, later history another. That answers no question anyone asked.

## Rejecting a checkpoint is not rejecting a journal

**Decision.** The production open path falls back to a full replay. But
`replayJournal` throws when handed a bad one.

**Why.** Passing a checkpoint to `replayJournal` is an explicit claim about that
journal, and a false claim should be heard. Opening the app is not making that
claim.

**Consequences.** A malformed record, an ownership violation, or an
unrecoverable file is a different thing entirely and fails the load.

## Ownership is checked before content is read

**Decision.** The header's profile is compared to the profile that asked, at the
store and again when a session opens.

**Why.** A whole file copied into another profile's directory is internally
consistent at every record, and its creation time and placement can match. No
amount of replay establishes whose it is.

## Time runs forward

**Decision.** `occurredAt` never goes backward, and appending a backward step is
refused. Clock correction is resolved at the observation boundary, before the
attempt is recorded.

**Why.** Every memory transition is driven by elapsed time, and propagating
backward is illegal in the model, so a journal recording a backward step would
be impossible to replay.

**Consequences.** The raw reading may be kept in `observedWallTime` for
diagnostics, and nothing computes decay from it. The journal tail bounds the
correction whether or not the last attempt was measured, since an unmeasured
attempt moved no state but is still recorded history.

### Timestamps have one grammar

```text
YYYY-MM-DDThh:mm:ss[.f{1,6}](Z|(+|-)hh:mm)
```

Four-digit years, mandatory seconds, at most six fractional digits, an offset
within 14 hours. **Every bound is there because the platform parser does
something quietly wrong past it**: `2026-02-31` becomes March 3, `+00:99`
becomes the previous day, a seventh fractional digit is truncated into a
different instant, and a timestamp with no offset means whatever the machine
reading it decides.

## Persisted data is untrusted input

**Decision.** Reading persisted data either produces one unambiguous domain
object or throws a located `JournalFormatException`.

**Why.** An unrecognized enum id, a numeric key that is not a number, a failed
cast, and a domain rule the data breaks all mean the same thing at this
boundary, so they should all be said the same way rather than escaping as
`ArgumentError`, `FormatException`, or `TypeError`.

**Consequences.** The promise belongs to every public reader of persisted data:
records, headers, profiles, checkpoints, sitting exports, and the storage
layer's own single-slot files. Domain constructors go on throwing
`ArgumentError` on their own terms, because that is useful inside the model, and
the boundary translates on the way out. Storage wraps a whole decode rather than
each nested field, so adding domain validation later cannot quietly reopen the
leak.

A serialized map key is checked against the identity inside its value. The two
are statements of the same fact, and trusting one lets a disagreement reassign
one material's memory to another, or collapse two execution contexts into
whichever decoded last.

## Runtime rejection, not assertions, at a trust boundary

**Decision.** Values crossing a trust boundary are rejected at runtime. Values
that are calibrated constants use assertions.

**Why.** Assertions are compiled out of release builds and are off by default
under `dart run`, which is exactly where a corrupt journal or a hand-edited file
is read. A calibrated constant, by contrast, comes from the source tree and a
bad one is a programming error that should fail loudly in development.

The class is decided by **where the value comes from**, not by how numerical the
type is. See
[`../system/validation-boundaries.md`](../system/validation-boundaries.md).

## Storage is deliberately absent from the journal package

**Decision.** The journal holds records in memory and encodes to JSON lines. An
adapter wraps it.

**Why.** Keeping the contract above any storage engine is what stops the engine
from deciding the schema. One record per line also means an adapter can append
without rewriting what came before, and a person can read a journal with
ordinary tools.

## Schema versions move independently

**Decision.** `attemptSchemaVersion` and `checkpointSchemaVersion` are separate,
and a reader meeting a version it does not understand fails rather than
guessing.

**Why.** This is the historical source of truth, and a misread record rewrites
the past.

**Consequences.** A schema change means a pure, versioned upgrade function, with
upgrade tests covering existing persisted state, historical golden journals, and
genuinely new material separately. A field copied because old history lacks a
better estimate is an **upgrade expedient** and must be documented as one,
rather than as evidence that the old estimator measured both meanings.

## The counterfactual boundary

**Decision.** An alternative estimator may be applied only to the exercise that
was actually presented.

**Why.** The journal holds no outcome for an action never taken. A scheduler
replay showing a different choice says nothing about what that choice would have
achieved.

**Consequences.** It is not policy evaluation and must not be reported as such.

Relatedly, `isFaithful` does not prove the scheduler would select the same
exercise again. Exact learner replay is not exact scheduler replay: that would
need the candidate set the slot considered and a decision trace hash over it,
and the journal records neither. That part of the production contract is
unfinished, and nothing should read `isFaithful` as a stronger invariant than
the journal can support.

## Erasing is the one destructive operation

**Decision.** Deliberately not part of the practice loop.

**Why.** Everything else in this file exists to make history unrewritable.
Erasure is the single exception, and keeping it out of the ordinary path is what
stops it from becoming an ordinary outcome.
