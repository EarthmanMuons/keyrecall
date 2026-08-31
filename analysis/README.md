# Executable research

## Retired: the V1 prototype

The Python research prototype the V1 learner model and scheduler were designed
in has been removed. Its job was finished: the Dart implementation was written
against it and checked against it attempt by attempt, and that reproduction is
recorded in the Git history rather than kept on disk.

It was retired when hand motion became an execution condition. The prototype had
no way to express the difference between parallel and contrary hands together,
so a digest computed on both sides could no longer describe the same domain, and
keeping it would have meant maintaining a comparison that could only be wrong.

Two of its files stay, because live Dart tests read them:

```text
learner-model/params.toml    the learner values as of v1-prototype-0
scheduler/config.toml        the scheduler values as of v1-prototype-0
```

They are provenance. The Dart registries are the live ones, and the tests that
read these treat them as a change detector rather than a source to conform to.

The pinned digests and reference runs under
`packages/keyrecall_simulation/test/` are **Dart regression pins**, not
cross-implementation evidence. A mismatch means this implementation changed,
which may be intended, and the values are then regenerated from a Dart run.

## Live: instrument calibration

```text
onset-grouping/     what "at the same time" means on a real instrument
timing-calibration/ what steady playing looks like on this input stack
```

These are current. They hold recorded takes from real playing and the scripts
that read them, and the constants they justify are consumed by the Dart
packages. Adding takes here is how those constants get better.
