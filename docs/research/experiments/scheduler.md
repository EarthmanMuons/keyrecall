# Scheduler experiments

Seventeen synthetic passes over the scheduler, compressed to what each one
settled. **Most promoted nothing**, and that is the point of keeping them: they
record which plausible mechanisms were tried and found not to earn their place,
so the same ideas are not rediscovered and re-implemented.

The scripts these ran under lived in the Python research prototype and are in
Git history rather than on disk; see
[`../../../analysis/README.md`](../../../analysis/README.md). The CSV artifacts
each pass wrote are gone with them. What survives is below.

## The stopping rule

Stated before the later passes ran, and honored: **scheduler exception search is
frozen**. Further gains should come from empirical calibration and richer
real-learner observation rather than more conditional synthetic policy branches.

Passes 13 through 17 each tested a plausible refinement, each found an effect
too small or too fragile to justify a branch, and each promoted nothing. That
consistency is what closed the search.

## Passes 1 and 2: the boundary contract holds

Pass 1 mechanically validated the stage information boundary. Pass 2
behaviorally validated the implemented admission mechanisms. Every numeric
threshold they used stayed an untuned heuristic placeholder throughout,
deliberately: characterize before retuning.

## Pass 3: the placeholder constants are robust

**Question.** How robust are the untuned thresholds, not which values are best.

**Method.** Pass 2's ten behavioral checks reused as a pass/fail oracle across a
sampled grid, one parameter at a time, then across four architecturally
motivated parameter pairs.

**Result.** All six defaults pass, and every bounded default has at least one
neighboring sampled value that also passes.

```text
p_min                  sampled passing: 0.40-0.70
p_max                  robust over the sampled 0.75-0.98 range
p_introduction_min     sampled passing: 0.15-0.25
shared probe interval  sampled passing: 1-5 days
repetition cap         sampled passing: 2-5
recency window         sampled passing: 10-25
```

**Read it correctly.** These are _sampled robustness findings, not estimated
boundaries_. A five-point grid can report that 0.60 passed and 0.50 failed, and
can never say the true boundary sits at 0.53. Every endpoint is a grid
observation, not a fitted value. The pass does not establish that any default is
preferable to its neighbors, and it changed no configuration.

**None of the four parameter pairs produced a brittle interaction.** Every
combined-cell failure was already predictable from an individually unsafe input.
Out-of-contract cells were executed and recorded separately rather than
conflated with an ordinary interaction finding, and failed as predicted, which
is a pre-registered positive control on the sweep's own plumbing.

**Method note worth keeping.** A minority of seeds do not reproduce a check's
own scripted precondition, which is inconclusive rather than evidence either
way. The sweep tracked three states per group, fails / holds / insufficient
coverage, rather than folding an absence of evidence into "holds". Five runs
were inconclusive and two groups lacked any conclusive run; in both cases the
same cell had an independently conclusive failure, so no classification rested
on missing evidence.

**Structural finding.** The aggressive grid exposed a genuine crash reachable
only when admission genuinely admits nothing: a documented fallback left
unranked candidates with a null rank key in a diagnostic sort. Fixed by
excluding them from that sort, touching neither selection nor admission. A state
no scripted scenario had reached before, rather than a policy disagreement.

## Pass 4: the memory redesign, characterized

Recorded calibration metrics alongside scheduler behavior: prediction bias and
MAE, observed retrieval frequency, and independent-retrieval bias, MAE, and
Brier score, with retrieval metrics restricted to attempts where retrieval was
actually observed. The same 250-trial matrix ran at the pre-redesign baseline
and at the redesign.

Incidentally, a substantial performance result: one representative
seven-material trial fell from about 4.25 seconds and 136 MB peak RSS to 2.66
seconds and 27 MB, and eight large trials ran 5.82 times faster with eight
workers than serially.

## Pass 5: what cold start can and cannot identify

**Question.** Holding estimator initialization constant, can the model tell a
technique-strong learner from a memory-strong one?

**Method.** Four fixtures (beginner, technique-strong/memory-weak,
memory-strong/technique-weak, broadly strong), identical priors, 60 decisions at
half-day intervals from one seven-material pool, 30 deterministic seeds.

**Result.** Retrieval observability is the binding constraint. A calibrated
retrieval band requires retrieval to actually be tested, and a learner kept
under continuous cues supplies none. This is the pass behind
`isRetrievalObserved` mattering as much as it does downstream.

## Pass 6: placement information is real, seeding durability is not

**Question.** Do early cross-material retrieval results carry learner-level
placement information?

**Result.** Yes, and this is the narrow inference the pass supports. It does
**not** support promoting either experimental mechanism it tested.

**What it explicitly ruled out.** Seeding durability directly from
cross-material evidence is a stronger claim and remains unsupported.

**What it set up.** Whether that evidence may stay operative after first success
until a material has supplied an informative elapsed interval, testable as an
epistemic prediction bridge without changing stored half-lives. That became
Pass 7.

## Pass 7: the interval-identifiability bridge

Extended Pass 6's construction to the post-success regime, as the bridge Pass 6
specified: prediction may borrow, stored durability may not.

## Pass 8: retained durability can be inferred separately

**Question.** Can factual retrieval intervals revise estimated retained
consolidation independently of the quality-weighted causal transition?

**Method.** Distinguished two sources of movement in the same field:

```text
retrieval inference   evidence about durable memory that existed before practice
causal formation      durable memory created by the current practice event
```

**Result.** Yes, structurally. Retrieval inference runs only when factual
retrieval is observed _and_ an anchor already existed, so a first success
establishes memory rather than revising a belief about it.

**This is one of the few passes that promoted something.**

## Pass 9: promoted, and validated in the posterior

Pass 8's structural result entered the production estimator. A factual retrieval
observation with a pre-existing anchor now runs three transitions in a fixed
order:

```text
retained-consolidation posterior inference
current-durability evidence correction
causal consolidation formation, or productive-nonsuccess learning
```

The ordering is part of the contract, because the transitions are not
commutative in floating point and replay reproduces them exactly.

## Pass 10: prior knowledge at first encounter, not promoted

**Question.** Should cross-material confidence change how an unseen material is
first encountered?

**Result.** No policy promoted. Cross-material confidence that only grants
permission for the same test the bootstrap encounter already performs is
redundant.

**Limitation recorded.** Reducing the residual unnecessary-cueing count would
need a separate experiment on post-observation guidance-probe and recovery
decisions, including whether the "unnecessary cueing" metric is counting
intentional supported probes as a cost. The pass deliberately did not broaden
into that phase.

## Pass 11: what supported selection costs

**Result.** No production policy change. It narrowed the remaining scheduler
questions to two: whether guidance-probe cadence can terminate sooner once
evidence is sufficient, and whether recovery should target the predicted failing
dimension. Passes 12 through 17 are those two questions, and neither survived.

## Pass 12: recovery modality, not promoted

**Question.** Does recovery target the wrong kind of support, isolated as a
possible mismatch by Pass 11?

**Result.** No change promoted. It specified its own successor: if recovery is
revisited, the experiment should be **factorial**, independently varying motor
simplification and memory guidance to test a hybrid and estimate each
contribution. That became Pass 17.

## Pass 13: guidance-probe marginal yield, not promoted

**Result.** No production policy. A future probe-policy intervention would need
an explicit alternative action or a different admission pathway, **not only a
cooldown**. That specific negative is the useful part: a cooldown is the obvious
first idea and it does not work.

## Pass 14: alternative actions for a low-yield probe, not promoted

**Result.** A generic cooldown, an attempt-clock substitution, and unconditional
session termination are all unsupported. Three plausible mechanisms, all
recorded as tried and rejected.

## Pass 15: retention against information

Characterized the tradeoff between the two ranking terms with the production
ranking and challenge contracts held visible. No reordering promoted; the
lexicographic order stands.

## Pass 16: probe-failure completion need, not promoted

**Question.** Can completion need be identified from pre-selection state well
enough to justify censoring a factual probe?

**Result.** No. The synthetic analysis cannot identify it strongly enough, so no
classifier and no further scheduler experiment. **This is the pass that invoked
the stopping rule**: exception search frozen, further gains from empirical
calibration rather than more conditional branches.

## Pass 17: factorial recovery support, not promoted

**Question.** Pass 12's successor: does a hybrid of motor simplification and
memory guidance beat either alone?

**Result.** The hybrid completion effect is **repeatable and calibration-safe**,
and is only 1.5 to 1.8 percentage points. It does not shorten recovery episodes
or accelerate factual return, and does not clear the predeclared requirement for
a material localized improvement.

**Promoted nothing.** Recovery policy is frozen alongside probe and ranking
policy. Further recovery calibration should use real learner outcomes.

This is the most instructive negative in the set: the effect was real,
reproducible, and safe, and was still not worth a production branch. A
predeclared effect-size requirement is what made that call available.

## What the whole series established

- The stage information boundary holds under adversarial parameter settings.
- The heuristic constants are robust in the neighborhood of their defaults, and
  nothing here says they are optimal.
- Retrieval observability, not estimator quality, is the binding constraint on
  cold-start identifiability.
- Early cross-material results carry placement information; using them to seed
  durability does not follow from that.
- Retained durability can be inferred from factual intervals separately from
  causal formation, which is the one mechanism the series promoted.
- Every refinement to probes, recovery, and ranking that was tried produced
  either no effect or an effect too small to justify a branch.
