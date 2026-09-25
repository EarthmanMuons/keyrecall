# Placement convergence

> **Status:** the fixed-history half of the placement question. Under identical
> evidence, predictions converge and decisions do not, because gates read
> competency means the evidence does not identify one at a time. No policy is
> changed here. The closed-loop half waits on the finite-goal realization
> envelope.

Placement asks a new learner where to start, and the promise worth keeping is
that it only decides where: that choosing the wrong level makes the first
exercises too easy or too hard and does not keep the learner there. That has two
halves. **Inference:** does the same evidence bring the three starting levels to
the same learner state? **Policy:** does the scheduler gather that evidence
whatever the start? This is the first.

## Method

Each archetype's history is generated once by the scheduler over the production
catalog, both families, 25 daily sittings of 20 attempts, from its own
placement. Its exercises, outcomes, and times alone are then replayed into a
fresh state for each tier, so all three see exactly the same evidence and any
gap left is the prior. At each checkpoint the three are compared, taking the
largest gap over the three pairs:

- competency means, over competencies all three have observed, and over those
  none has;
- predicted success over every generated candidate, about 20,000;
- the share of candidates whose challenge-band membership differs, and whose
  eligibility tier differs;
- whether one decision from a fresh sitting picks the same exercise.

Thirteen archetypes, two seeds, 897 seconds.

```console
dart run keyrecall_simulation:placement_convergence --seeds 2 --jobs 4 \
  --out placement_convergence.jsonl
```

## Results

Placement starts the tiers two apart on the logit scale competencies use,
beginner at -1 and advanced at +1. Means over the 26 histories:

| Attempts | Observed competency gap | Prediction gap | Band differs | Eligibility differs | Same pick |
| -------: | ----------------------: | -------------: | -----------: | ------------------: | --------: |
|       30 |                    1.91 |          0.295 |        28.8% |               15.8% |      2/26 |
|       60 |                    1.92 |          0.281 |        33.9% |               18.2% |      1/26 |
|      120 |                    1.82 |          0.236 |        32.0% |               17.1% |      3/26 |
|      200 |                    1.71 |          0.182 |        31.3% |               12.1% |      5/26 |
|      500 |                    1.35 |          0.077 |        15.0% |                6.9% |      7/26 |

The prediction gap shrinks to about a quarter of where it began. The competency
gap barely moves, and after 500 identical attempts the three placements still
disagree about the challenge band of one candidate in seven, about the
eligibility of one in fourteen, and about what to offer next in 19 histories
of 26.

## Why: the evidence identifies sums, not parts

One intermediate history after 500 attempts. Every competency's variance is at
its floor of 0.05, so none of these are uncertain in the model's own terms:

| Competency                  | Observations | Beginner | Some experience | Advanced |
| --------------------------- | -----------: | -------: | --------------: | -------: |
| RH scale execution          |          151 |     0.56 |            0.89 |     1.22 |
| LH scale execution          |          169 |     0.59 |            0.86 |     1.14 |
| scalar crossing             |          251 |     1.76 |            1.58 |     1.42 |
| arpeggio transition         |           67 |     0.01 |            0.59 |     1.18 |
| multi-octave continuation   |          166 |     0.65 |            0.94 |     1.22 |
| hands-together coordination |          111 |     0.59 |            0.61 |     0.64 |

An attempt's outcome is predicted from several competencies at once, and the
evidence corrects their combination rather than each of them. The beginner
placement's lower execution is offset by a higher scalar crossing, which runs
the wrong way; the sum the outcomes see is nearly the same in all three, so
prediction converges, while how it is divided keeps the placement's shape.
Hands-together coordination, which has an outcome channel of its own, is the one
that converged.

The decisions that still differ are the ones that read a competency mean
directly: the admission band execution floors and the multi-octave floor read
one hand's execution mean, and that is exactly the part of the state the
evidence leaves where placement put it.

## What it means

**Inference converges only where evidence identifies the quantity.** Prediction
is identified, and converges slowly. Individual competency means are not
identified from outcomes that load several at once, so their placement offsets
persist, and at the variance floor nothing marks them as unresolved.

**So the placement promise does not hold today, and the scheduler is where it
breaks.** A gate that reads an unidentified mean inherits the placement. A gate
that read an identified quantity, such as the predicted success of a reference
exercise at that band, would not. That is a scheduler policy question as much as
a model one.

**It is not yet a reason to reopen the learner model.** The roadmap's gate for
that asks for real, replayable observations, and this is synthetic evidence
generated by a model of the same shape. What it establishes is that the failure
is structural rather than a matter of too few attempts: 500 identical attempts
at the variance floor did not remove it.

Directions, none argued for yet:

- eligibility floors that read a predicted success rather than a competency
  mean;
- a placement prior over one general ability rather than an equal offset on
  every competency, so the evidence corrects the part it can see;
- a variance floor that keeps competencies placement seeded, and evidence has
  not separated, visibly uncertain rather than settled.

## Interpretation boundary

Synthetic players whose performance is generated from the same competency
structure the model assumes, which if anything flatters identifiability. The
closed-loop half, whether the scheduler's own choices widen or narrow these
gaps, is still to run, after the finite-goal realization envelope.
