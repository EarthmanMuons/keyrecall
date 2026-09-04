# keyrecall_practice

The attempt transaction behind
[KeyRecall](https://github.com/EarthmanMuons/keyrecall), and the durable store
it writes through. Pure Dart apart from `dart:io` in the file store.

## The transaction

```text
decide()   propagate a scratch copy, evaluate candidates, select,
           persist the decision, then present
commit()   compute the whole transition on a copy,
           append the attempt durably,
           then replace canonical state and clear the decision
```

Nothing the session keeps moves until the attempt is history. The ordering
exists to prevent three specific failures.

**A crash after presenting** leaves a decision with no outcome. On the next
`open` it surfaces as `pending`, and the caller resolves it explicitly rather
than having one invented: present it again and close it from what is played, or
`abandonPending()` where it cannot be presented. The attempt id was durable
before the exercise was shown, so a resumed attempt lands in history under the
id it was given. An abandoned one moves no state and leaves no evidence, so
history does not claim it happened.

**A crash during commit** is safe in either order it can fail. The attempt id is
chosen at decide time and is the journal's idempotency key, so on restart the
journal either already contains the attempt, in which case the stale decision is
cleared, or it does not, in which case the attempt is still pending. The update
is never applied twice because learner state is not stored: it is replayed from
the journal, and the journal holds each attempt exactly once.

**A storage failure that does not kill the process** is the third case, and it
needs more than crash safety. A close computes the whole transition on a copy
and replaces canonical state only once the append has succeeded, so a throwing
append leaves the session exactly where it started with the decision still
pending. Retrying is then genuinely safe. Applying the update first would leave
state ahead of the journal, and the retry would fold the same outcome in again
from an already-advanced state.

A pending decision is deliberately **not** part of the journal. An attempt with
no outcome produced no evidence and moved no state, and putting it in the replay
stream would invite exactly the manufactured outcome this prevents.

It is also the one input here that is neither replayed nor hash-checked, and
committing it writes an attempt keyed on the slot's own profile id. So it is
validated on recovery: a slot belonging to another profile, targeting a journal
position that is not the next one, or predating the profile is refused rather
than accepted.

## Usage

```dart
final session = await PracticeSession.open(
  store: FilePracticeStore.at('/path/to/practice'),
  profile: profile,
  materials: v1ScaleCatalog,
);

// A pending decision is one the last run showed and never closed. Present it
// again rather than deciding past it: closing it writes the attempt under the
// id it already has.
final exercise = switch (session.pending) {
  final PendingDecision pending => pending.exercise,
  null => switch (
    await session.decideOutcome(at: DateTime.now().toUtc()),
  ) {
    final PresentedAttempt presented => presented.exercise,
    PracticeBlocked(:final reason) => throw StateError(
      'practice blocked: ${reason.name}',
    ),
    PracticeCaughtUp() => null,
    // Something the session owns changed while the decision was being
    // computed, so the answer is about inputs that have moved. Deciding again
    // produces a current one.
    PracticeSuperseded() => null,
    PracticeInvalidScope(:final failures) => throw ArgumentError(
      'invalid practice scope: $failures',
    ),
  },
};

// ... present exercise, collect what happened ...

await session.closeFromPerformance(transcript);
await session.saveCheckpoint(); // optional; only ever saves replay time
```

A session decides through a `SchedulerHost`, which chooses where the decision is
computed and nothing else. Passing none decides on the calling isolate, which is
what a test and a simulation want. The app passes an `IsolateScheduler`, because
a mature full-catalog decision blocks its isolate for a fifth of a second on a
mid-range phone. Either way the session binds the scope, the learner, and the
policy constants, applies the returned sitting effect, and writes the pending
decision itself.

Placement state is anchored at `Profile.createdAt`, so every attempt must fall
at or after it, and the caller supplies the instant a new journal is stamped
with. A wall clock the caller does not control would give replay a different
origin on every run. `JournalHeader.createdAt` is storage provenance only;
nothing derives a model timestamp from it.

The session attempt cap counts scheduler **decision opportunities**, not only
presented attempts, so a blocked result still consumes one. Caught-up and
invalid-scope results return before scheduling and consume none. None creates a
pending decision: only an exercise that was durably selected and shown can later
become an attempt.

## Storage

`PracticeStore` is the port. Three kinds of thing live behind it with different
durability requirements:

|                  | Shape                         | If lost                                   |
| ---------------- | ----------------------------- | ----------------------------------------- |
| Attempts         | Append-only, authoritative    | History is gone                           |
| Pending decision | One slot, replaced or removed | An interrupted attempt cannot be resolved |
| Checkpoint       | One slot, replaced            | Only replay time                          |

`FilePracticeStore` is the reference implementation:

```text
<root>/<profileId>/journal.jsonl     append-only, authoritative
<root>/<profileId>/pending.json      one slot
<root>/<profileId>/checkpoint.json   one slot
```

Attempts are appended and flushed. The single-slot files are written to a
temporary name and renamed over the target, so a reader sees the old content or
the new one and never a half-written file.

Erasing writes a marker before removing any practice file. If deletion is
interrupted, the next access finishes it before exposing storage, so a journal,
pending decision, and checkpoint from opposite sides of an erase cannot mix.

A crash mid-append can leave a final line without its newline. That attempt was
never committed, so the torn tail is dropped on read and truncated before the
next append. A malformed line _anywhere else_ is real corruption of history and
fails loudly, because quietly skipping it would lose evidence.

A database can replace this without the transaction noticing, as long as it
keeps those guarantees.

## Documentation

[`docs/learner-model/05-production-implementation-plan.md`](../../docs/learner-model/05-production-implementation-plan.md)
section 5 is the canonical attempt transaction this implements.
