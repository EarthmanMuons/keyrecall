# keyrecall_alignment

Relates an observed performance to the notes an exercise asked for.

```text
ExerciseRealization + PerformanceTranscript
    -> align()
    -> Alignment
         Match | Substitution | Insertion | Deletion
```

`align` answers one question: which played note corresponds to which expected
one, and what is left over on either side. It is the only place a correctness
judgment is allowed to be made, which is why the neutral echo the practice
screen draws does not go anywhere near it.

The search is global. A single extra note early in a scale has one cheap
explanation, an insertion, and one expensive one, a substitution at every
remaining position; deciding locally picks the expensive one and never recovers.
Resynchronizing after a skip, an extra, or a correction falls out of choosing
the whole explanation at once.

## What it deliberately does not do

- **Two hands.** Hands-together material needs observations grouped into
  moments, and recorded performances show that grouping cannot be decided from
  timing alone. See
  [`analysis/onset-grouping/`](../../analysis/onset-grouping/README.md).
- **Timing.** Relating arrival times to expected times needs a tempo model that
  does not exist, and inventing one inside an aligner would hide it.
- **Evidence.** Turning an edit script into an outcome the learner model
  consumes is a further step and a separate set of judgments.
- **Interpretation.** `AlignmentReading` answers whether an attempt was
  complete, first-pass clean, or repaired. Those are readings of the
  correspondence, and they live beside it rather than inside it.

## The costs are the policy

`AlignmentPolicy` decides readings rather than tuning them. The load-bearing
comparison is one substitution against one deletion plus one insertion, because
those are two accounts of the same wrong note. V1 prefers the substitution: a
learner who plays one wrong note has played a wrong note, not skipped one and
added another.

Ties in the traceback break in a fixed order, so one performance always aligns
the same way. Evidence derived from an aligner that could return either of two
equal-cost readings would not be reproducible, and replay is a production gate
here.

See
[`docs/domain-model/alignment-contract.md`](../../docs/domain-model/alignment-contract.md)
for what is settled, what is open, and why.
