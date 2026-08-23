# keyrecall_journal

The durable boundary under [KeyRecall](https://github.com/EarthmanMuons/keyrecall):
what history is, and how learner state is recovered from it. Pure Dart, no
Flutter dependencies, and no storage engine.

## The profile owns the history

A shared instrument means a shared install, so an install has no single learner.
It has one independent history per `Profile`: its own journal, its own state,
its own session.

```text
KeyRecall install
├── Alice   journal, learner state, current session
├── Bob     journal, learner state, current session
└── Child   journal, learner state, current session
```

A profile id is opaque and stable, never derived from a display name. Names
change and repeat, so a history keyed on one would be lost by a rename and
merged by a coincidence. `newProfileId()` generates a version 4 UUID, which is
also the namespace a future sync would merge on.

Every persisted artifact is scoped by it. `AttemptRecord` carries the profile id
on the record itself rather than only on the journal, so a record stays
self-describing once exported or merged, and a journal refuses an attempt from
another profile outright.

`LearnerState` deliberately does not know about profiles. It stays the pure
learner-model object, and this layer associates one with a profile:

```text
Profile -> AttemptJournal -> LearnerState / checkpoints
```

That keeps `keyrecall_learner` free of app-account concepts.

## What is authoritative

The **attempt journal is the source of truth.** It is append-only, and learner
state is whatever replaying it produces. Nothing rewrites a record.

A **checkpoint is disposable acceleration.** It saves a replay from starting at
the beginning, and nothing more. Deleting every checkpoint must cost time and
nothing else, which is why one carries the hash of its own content, the point in
history it covers, and the model version that produced it.

Its position is a journal sequence, not a position within a sitting. A history
spans many sessions, and a within-session index cannot say what a checkpoint
already includes: resuming from one would silently reapply every attempt from
every other session. It also names the attempt at that sequence, so a resume is
checked rather than trusted, and it captures a deep copy, since learner state is
mutable and an aliased checkpoint would drift away from the hash it claims.

A checkpoint from another model version is unusable as a shortcut in *every*
mode, counterfactual included. It already contains one model's reading of
everything before it, so seeding a different model from it would produce a
hybrid: earlier history estimated one way, later history another. That answers
no question anyone asked. Replay from the beginning instead.

**Model and scheduler versions are recorded on every attempt**, not once per
journal, because a journal outlives any single model version and a record must
stay interpretable on its own.

## What is stored, and why

Four things are persisted even though replay recomputes them: the presented
exercise, the prediction, the evidence weights, and the memory attribution.
They are the audit trace. Replay recomputes each and compares, which is how a
change that would silently reinterpret history gets caught instead of absorbed.
Reapplying the stored numbers would reproduce any past mistake perfectly and
prove nothing.

Full state snapshots are not duplicated per attempt. Each record carries the
hash of the state its decision was made from and the state its update produced,
so replay proves it rebuilt the right state at every step without paying to
store it.

`retrieval_succeeded` is `true`, `false`, or `null`, and `null` means retrieval
was never tested. It must never be read, queried, or analyzed as failure.

## Time runs forward

`occurredAt` is the model timeline, and it never goes backward. Every memory
transition is driven by elapsed time, and propagating backward is illegal in the
learner model, so a journal that recorded a backward step would be impossible to
replay. Appending one is refused.

A device clock really can be corrected backward mid-session. That is resolved at
the observation boundary, before the attempt is recorded, and the raw reading may
be kept in `observedWallTime` for diagnostics. Nothing computes decay from it.

## Records are contiguous, and ids do not collide

`journalSequence` counts attempts in append order, contiguously, so a lost line
is detectable rather than silently absorbed. It is distinct from
`indexInSession`, which is position within one sitting.

Idempotency is not first-write-wins. An attempt id that returns with identical
content is a retry and a no-op; an attempt id that returns with *different*
content is a collision and throws. In an authoritative log, silently keeping one
of two conflicting records is worse than refusing both.

## Canonical state advances only on a committed attempt

The one rule this boundary imposes on the app.

Time propagation is mathematically path-independent, but it is not
path-independent in floating point: advancing through three intervals and
advancing through their sum land on different bits, and a state hash is exact.
Replay propagates from one recorded attempt to the next, so the writer must do
the same.

A decision that admits nothing, a candidate preview, or any other look-ahead
therefore runs against a copy:

```dart
// Evaluating: scratch copy, because this may not produce an attempt.
final scratch = state.copy();
model.propagate(scratch, at);
final traces = pipeline.evaluate(state: scratch, session: session,
    candidates: candidates, at: at);
final chosen = pipeline.selectChoice(traces, session);
session.attemptsThisSession++;
if (chosen == null) return; // A slot with no selection records nothing.

// Committing: only now does canonical state advance.
model.propagate(state, at);
```

Propagating canonical state at a moment the journal does not record makes that
state unreachable by replay, which costs the journal its authority.

## Replay modes

| Mode | Question it answers |
| --- | --- |
| `exact` | Is the recorded past still reachable? Model versions must match, and every recomputed value is compared. |
| `counterfactual` | What would a different estimator have concluded from the same observations? |

The counterfactual boundary matters: an alternative estimator may be applied
only to the exercise that was actually presented. The journal holds no outcome
for an action never taken, so a scheduler replay showing a different choice says
nothing about what that choice would have achieved. Do not treat it as policy
evaluation.

## Usage

```dart
final profile = Profile.create(
  displayName: 'Alice',
  createdAt: DateTime.now().toUtc(),
);
final journal = AttemptJournal(
  JournalHeader(profileId: profile.id, createdAt: DateTime.now().toUtc()),
);

journal.append(
  AttemptRecord(
    journalSequence: journal.nextSequence,
    identity: AttemptIdentity(
      profileId: profile.id,
      attemptId: attemptId,
      sessionId: sessionId,
      indexInSession: index,
      occurredAt: at,
    ),
    provenance: ModelProvenance.of(
      learnerParams: model.params,
      schedulerModelVersion: pipeline.config.modelVersion,
    ),
    exercise: chosen.exercise,
    decision: SchedulerDecision.fromTrace(chosen, pipeline.config),
    outcome: outcome,
    weights: weights,
    memoryUpdate: diagnostics,
  ).withStateHashes(before: beforeHash, after: learnerStateHash(state)),
);

final result = replayJournal(journal, model: model, initial: initialState);
if (!result.isFaithful) {
  // Divergences name the attempt, the field, and both values.
}
```

Appending the same attempt twice is a no-op: the attempt id is the idempotency
key, so a retried commit after an interrupted write cannot fold the same
evidence in twice.

## Storage

Deliberately absent. The journal holds records in memory and encodes to JSON
lines, one record per line, so an adapter can append without rewriting what came
before and a person can read a journal with ordinary tools. A database or file
layer wraps this. Keeping the contract above any storage engine is what stops
the engine from deciding the schema.

## Schema versioning

`attemptSchemaVersion` and `checkpointSchemaVersion` move independently. A
reader that meets a version it does not understand fails rather than guessing:
this is the historical source of truth, and a misread record rewrites the past.

Changing a schema means a pure, versioned upgrade function, with upgrade tests
covering existing persisted state, historical golden journals, and genuinely new
material separately. A field copied because old history lacks a better estimate
is an upgrade expedient, and must be documented as one rather than as evidence
that the old estimator measured both meanings.

## Documentation

[`docs/learner-model/05-production-implementation-plan.md`](../../docs/learner-model/05-production-implementation-plan.md)
sections 5 through 8 are the contract this implements: the attempt transaction,
the journal record, material-memory serialization, and the replay modes and
acceptance tests.
