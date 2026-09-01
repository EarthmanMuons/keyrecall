# Validation boundaries

- **Status:** Implemented.
- **Written:** September 1, 2026

Constructor arguments fall into two classes, and each is rejected differently.
The class is decided by where the value comes from, not by how numerical the
type is.

## Values that cross a trust boundary

Anything reconstructed from storage, decoded from the journal, or supplied by a
person. Their constructors reject bad values at runtime, with
`ArgumentError`/`RangeError` in the domain and `JournalFormatException` at the
codecs.

Assertions would be insufficient here: they are compiled out of release builds
and are off by default under `dart run`, which is exactly where a corrupt
journal or a hand-edited file is read.

| Type                                                | Enters from                       |
| --------------------------------------------------- | --------------------------------- |
| `ExecutionConditions`                               | `decodeExercise`                  |
| `Outcome`                                           | `decodeOutcome`                   |
| `TechnicalMaterial`, `SpelledPitch`                 | decoded material and pitch labels |
| `PerformanceTranscript`                             | live input                        |
| `Profile`, `LearnerStateCheckpoint`, `LearnerState` | stored files                      |

## Calibrated constants

The parameter registries and policies: `LearnerParams`, `SchedulerConfig`,
`AlignmentPolicy`, `MeasurementPolicy`, `ObservationGroupingPolicy`. Their
invariants are held by `assert`.

These are `const` and are written in Dart rather than loaded, so the assertions
run during constant evaluation: a shipped constant that violates one is a
compile error, and stays one with runtime assertions disabled.

Constructing them outside constant evaluation is not a supported boundary.
Nothing loads or edits them at runtime, so no value reaches them that compiling
the source did not already check.

Converting them to throwing constructors would trade that compile-time check for
a runtime one and force the registries off `const`.

## Moving a type between the classes

A registry that becomes loadable from a file or editable by a person has crossed
into the first class, and its constructor moves with it.
