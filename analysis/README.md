# Executable research

Two kinds of thing live here, and only one of them is still authoritative.

## Frozen: the V1 prototype

```text
learner-model/    the Python learner model, simulation, and its experiments
scheduler/        the Python scheduler pipeline and its diagnostics
```

This is the research prototype the V1 learner model and scheduler were designed
in. Its job is finished. The Dart implementation was written against it and then
checked against it attempt by attempt, and that reproduction is the evidence
this code exists to preserve rather than an obligation it continues to impose.

**The Dart implementation is canonical**: the learner model, the scheduler, the
configuration values, and the simulation harness. Nothing here has to be updated
when Dart gains a competency, a scheduling rule, or a parameter, and nothing in
Dart has to agree with it going forward.

What that means in practice:

- `scheduler/config.toml` and `learner-model/params.toml` record the values as
  of `v1-prototype-0`. They are provenance. The Dart registries are the live
  ones.
- `scheduler/pipeline.py` implements the stages as the prototype had them.
  Material admission and anything else added since exists only in Dart.
- The pinned digests and reference runs under
  `packages/keyrecall_simulation/test/` are historical equivalence evidence and
  now serve as Dart regression pins. A mismatch means Dart changed, which may be
  intended.
- The CSVs under `*/generated/` are the results of the research passes, and
  reading them does not require running anything.

Retained rather than deleted, because six months from now the reason an equation
or an update order looks strange is likely to be in here.

## Live: instrument calibration

```text
onset-grouping/     what "at the same time" means on a real instrument
timing-calibration/ what steady playing looks like on this input stack
```

These are current. They hold recorded takes from real playing and the scripts
that read them, and the constants they justify are consumed by the Dart
packages. Adding takes here is how those constants get better.
