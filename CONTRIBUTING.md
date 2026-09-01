# Contributing to KeyRecall

## Getting set up

KeyRecall is a Flutter app over a Dart workspace. The Flutter version is pinned
in [`pubspec.yaml`](pubspec.yaml) and is what CI runs; install that version
however you normally manage Flutter, and check it with `flutter --version`.

[mise](https://mise.jdx.dev/) provides the rest of the toolchain (Node for
Prettier, Python and uv for the analysis tooling) and defines every task the
project runs:

```console
mise install     # the toolchain
flutter pub get  # workspace dependencies, from the repository root
mise tasks       # everything you can run
```

`mise.local.toml` is yours and is not tracked. Machine-specific environment
belongs there.

Then run the app:

```console
flutter run
```

Practice needs a MIDI keyboard: the app starts on MIDI and offers no way to
switch. There is a synthetic instrument behind `InputSourceKind.demo`, but it is
selected explicitly by tests and simulations rather than from the UI, so running
the loop end to end by hand means attaching an instrument.

## Checks

`mise run dart:check` is what CI runs, and it is the one to run before pushing:

```console
mise run dart:check     # format, imports, analyze, test
```

The pieces are separately runnable when one of them is what you are iterating
on:

```console
mise run dart:format    # or dart:format-check
mise run dart:imports   # or dart:imports-check
mise run dart:analyze
mise run dart:test
```

`dart:test` picks the right runner per package: a package depending on the
Flutter SDK gets `flutter test`, everything else gets `dart test`. Running one
package's tests directly works too, but **use `dart test` rather than
`flutter test` inside a pure-Dart package**. The Flutter runner fails to load
it, and it rewrites that package's `analysis_options.yaml` on the way past.

Markdown and the Python analysis tooling have their own tasks
(`markdown:format`, `python:check`), also run by CI when those files change.

Two things the analyzer will not tell you:

- **There is no code generation.** No `build_runner`, no `.g.dart`. If you find
  yourself reaching for it, that is a decision rather than a step.
- **`packages/keyrecall_midi` is excluded from formatting and import ordering.**
  It is vendored; see [its `VENDORED.md`](packages/keyrecall_midi/VENDORED.md)
  before touching anything in it.

Every package shares one analyzer baseline,
[`analysis_options_package.yaml`](analysis_options_package.yaml), and the app
adds the Flutter lints on top of it. Change the shared file rather than a
package's.

## The workspace

Dependencies point downward. Nothing below the app knows about Flutter except
where it has to.

```text
lib/                     the Flutter app: screens, providers, audio, input choice
packages/
  keyrecall_domain       exercises, material, conditions, realization, fingering
  keyrecall_input        the normalized live-input vocabulary (pure Dart)
  keyrecall_input_sources  the shared clock every input source stamps against
  keyrecall_midi         Bluetooth MIDI transport (vendored)
  keyrecall_alignment    which played note corresponds to which expected one
  keyrecall_measurement  what an aligned performance was, on separate channels
  keyrecall_learner      the learner model: competencies, memory, execution
  keyrecall_scheduler    what to present next, as a traceable staged pipeline
  keyrecall_journal      the durable record, its codecs, and replay
  keyrecall_practice     the attempt transaction over storage
  keyrecall_simulation   synthetic players, invariants, and the sweep
analysis/                instrument calibration data the tests read
docs/                    design, domain model, and learner-model record
```

As a conceptual data flow, an attempt moves through them in roughly that order:
input becomes a transcript, alignment puts it beside what was asked for,
measurement says what happened, the learner model folds it in, and the journal
records it. The durable transaction is not that tidy: the scheduler's decision
is persisted before the exercise is presented, so an interrupted run can be
resolved rather than guessed at. `PracticeSession` is where that ordering lives.

## Before changing behavior

Three things about this codebase will surprise you if nobody says them first.

**The journal is the history, and learner state is not stored.** Every attempt
is appended and never rewritten, and what the app believes about a player is
recomputed by replaying that journal. A checkpoint is only a cache of that
replay and is discarded whenever it cannot be trusted. So a change to how the
model learns changes what the whole history means: `LearnerParams.modelVersion`
has to move with it, or old attempts get reinterpreted under constants that were
never used to produce them.

**Recorded exercises are not regenerated.** What was presented is stored with
the attempt, including its motor structure, because replaying an old decision
under a newer generator would silently rewrite historical evidence.
`Exercise.recorded` exists for that and is not how new exercises are built.

**Erasing is the one destructive operation.** It is deliberately not part of the
practice loop. If you are touching storage, read
[`docs/domain-model/validation-boundaries.md`](docs/domain-model/validation-boundaries.md)
for where invalid values are rejected and why the parameter registries are
allowed to use assertions.

Simulation is the fastest way to find out whether a scheduler change is sane.
`packages/keyrecall_simulation/bin/sweep.dart` runs every synthetic player over
many seeds and reports what went wrong; the invariant tests run a handful of
seeds on every commit. One is skipped on purpose; see
[`docs/design/future-planning.md`](docs/design/future-planning.md) section 4.9
before you try to make it pass.

## Which document is authoritative

`docs/` keeps its history, so more than one document may describe the same
mechanism. In order:

1. The code, for what happens now.
2. [`docs/learner-model/v1-current-system.md`](docs/learner-model/v1-current-system.md),
   for the model and scheduler as a whole.
3. `docs/domain-model/`, for the contracts each part is written against:
   alignment, attempt termination, material admission, validation boundaries.
4. `docs/design/future-planning.md`, for what is deliberately deferred, and why.
   Each deferred item names the code that has to change when it is taken.
5. Everything else, for provenance: why the current design exists, and which
   alternatives were tried and rejected.

The [documentation map](docs/README.md) is the index. When implementation
changes a mechanism these documents describe, the document moves in the same
commit.

## Pull requests

CI runs the checks above on changed files and requires them to pass. Beyond
that:

- Match the surrounding code. Comments are sparse and explain why, not what.
- A behavior change wants a test that fails without it.
- Prove UI behavior from the classes underneath when it can be proved there.
  Widget tests are for what only exists at the widget layer, such as lifecycle.
- Keep the commit that changes a mechanism and the commit that documents it the
  same commit.
