# keyrecall_testing

The property-testing conventions KeyRecall's packages share.

**Used by:** the property tests in `keyrecall_input`, `keyrecall_journal`,
`keyrecall_alignment`, and the invariant runs in `keyrecall_simulation`, as a
development dependency only.

**Does not:** hold any package's generators. Those describe that package's
domain and stay beside its tests.

## What it holds

- `propertySeed`, the fixed seed every property runs under, so a run is
  reproducible and a failure names its seed.
- `propertyBudget`, which multiplies a property's example or seed count by
  `KEYRECALL_SEED_SCALE` for a wide search on demand.
- `failingOnErrors`, which reports a thrown `Error` as a failure so kiri_check
  shrinks it and names its seed.
- `weighted`, `optional`, and `choiceOf`, the generator combinators every
  package's generators are written with.
