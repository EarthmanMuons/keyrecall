# Learner-model experiments

What the synthetic analysis established about the model itself, and the
invariants that keep it established.

## Why simulate at all

A simulation is a **mechanism test, not evidence that the parameters are
calibrated for real pianists**. Its value is that it knows the hidden truth, and
can therefore expose contradictions, contamination between state layers, and
policy dead ends that no amount of reading the code will surface.

One discipline makes it worth anything: **the synthetic truth uses its own
coefficients on purpose.** If the generator and the estimator shared one
equation, a run would mostly confirm that the model can invert its own
arithmetic.

## The synthetic learners

Each profile isolates a way the model could go wrong, rather than representing a
kind of person. They are test fixtures and were never intended as product
vocabulary.

```text
BEGINNER                      weak broad competencies, high uncertainty
INTERMEDIATE                  moderate shared competencies
ADVANCED                      strong shared competencies
RH_STRONG_LH_WEAK             asymmetric hands
TECHNIQUE_STRONG_MEMORY_WEAK  strong motor state, weak material retrieval
MEMORY_STRONG_TECHNIQUE_WEAK  strong topology knowledge, weak execution
RETURNING                     historically strong, long nonuse interval
MATERIAL_SPECIFIC_DIFFICULTY  strong general skill, one persistently awkward scale
```

The three the model most needs to tell apart are the memory/technique pair and
the asymmetric hands, because conflating memory with technique or treating the
hands as one system are the two failures that would be invisible in aggregate
scores.

## The invariants

Thirty-two checks, all bounded to `[0,1]`, run against the model rather than
against a scheduler. They are the standing proof that the state layers stay
separate.

**Priors.** A new learner has broad uncertainty; a new material residual is near
zero; shared state dominates cold-start prediction.

**Learning.** Consistent success raises the relevant competency estimates and
consistent failure lowers them; **irrelevant competencies do not move**;
uncertainty contracts with informative evidence.

**Transfer.** Practicing one scale improves predictions for related unpracticed
scales **without creating fictitious direct attempts**. That second clause is
the whole point: borrowing is prediction, never an update.

**Material-specific residual.** One persistently awkward scale develops a
negative residual while other scales stay governed by shared state, and **sparse
evidence does not create extreme residuals**.

**Memory.** Retrievability decreases with elapsed time; independent retrieval
strengthens memory more than prompted execution; retrieval failure changes
memory state appropriately.

**Guidance.** Full cueing produces **zero** independent-memory evidence, not
merely weak evidence. Categorical, not a continuous attenuation. Unguided
success produces strong memory evidence, and failed unguided retrieval does not
strongly penalize motor execution.

**Nonuse.** Competency uncertainty increases, the execution residual becomes
less influential, and material retrievability decreases. Note what is absent:
the competency _mean_ does not move. Nonuse erodes confidence rather than
implying decline.

**Reacquisition.** A returning learner does not behave identically to a true
novice.

## The four findings that changed the design

These were each identified in simulation and then reduced to one of the
invariants above, which is the pattern worth repeating: a finding that stays a
narrative is a finding that regresses.

### 1. Separate prediction channels are necessary

**Superseded: a single shared logit.** One logit combining memory and execution
contaminated the state layers: a memory failure moved execution estimates and a
motor failure moved memory. The invariant suite found it, and the fix was
separate retrieval availability, execution, and topology channels.

This is the most consequential negative result in the set, because the
single-logit form is the obvious one and is what most of the literature's
logistic models use. It is correct for their setting and wrong here, because
KeyRecall observes the two failures separately and would be discarding that.

### 2. "Not tested" must not mean "failed weakly"

Treating fully cued practice as attenuated evidence made repeated supported
practice accumulate into false evidence of forgetting. The three-valued factual
outcome replaced it: untested retrieval carries **exactly zero** memory evidence
and moves neither factual clock.

### 3. Memory needs surprise-driven, bounded dynamics

**Superseded: multiplicative memory updates.** They compounded without bound and
had no equilibrium. The replacement works in log space on current durability and
logit space on cold-start belief, driven by prediction error rather than by
outcome alone.

The log-half-life equilibrium property was first identified in the invariant
suite and then pinned there.

### 4. Retained-durability inference cleared the production gate

Factual retrieval intervals can revise estimated retained consolidation
independently of the causal transition, and the separation is real:

```text
retrieval inference   evidence about durable memory that existed before practice
causal formation      durable memory created by the current practice event
```

Inference runs only when retrieval is observed **and** an anchor already
existed, so a first success establishes memory rather than revising a belief
about it. This is the one mechanism the scheduler experiment series promoted;
see [`scheduler.md`](scheduler.md), Passes 8 and 9.

## What the Q-matrix work settled

**Superseded: qualitative `PRIMARY`/`SECONDARY` Q entries.** Three questions
were being answered by one table, and separating them is what made the mapping
tractable:

```text
Q[e,k]   structural: does this exercise create an opportunity at all?
q[e,k]   loading: how much should this competency weigh in the prediction?
w[a,k]   evidence: how much did this attempt actually tell us about it?
```

Absent better information, loading splits credit evenly within a channel. Every
competency belongs to exactly one prediction channel, and
`HANDS_TOGETHER_COORDINATION` is the only member of the coordination channel.

## The reference pins

The pinned digests and reference runs under
`packages/keyrecall_simulation/test/` began as evidence that the Dart model
reproduced the Python prototype attempt by attempt. That prototype is retired
and the reproduction is in Git history.

**They are now regression pins against this implementation.** A mismatch means
this implementation changed, which may be intended, and the pins are then
regenerated. What they never mean any more is that two implementations disagree
and one of them is wrong.

The digest runs choose exercises with `randomExercise` rather than through the
scheduler, which is why they still hold: they exercise the model, and Dart-only
scheduler policy never enters them.
