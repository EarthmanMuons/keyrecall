# Placement convergence

> **Status:** the fixed-history half of the placement question. Under identical
> evidence, predictions converge and decisions did not, because gates read
> competency means the evidence does not identify one at a time. Floors reading
> a predicted reference instead, measured below, cut the eligibility
> disagreement to a third at 500 attempts; they are not yet the shipped setting.

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

## Floors that read a predicted reference

The two floors that read an execution mean, the admission band and the
multi-octave floor, can read instead the predicted execution of a reference
exercise: the same material and hand, one octave, ascending, at the gentle
tempo, the weaker hand where both play. Their probability floors are that
reference's execution for a learner sitting at each raw floor, rounded down:
0.528, 0.625, and 0.714 for the three later bands and 0.404 for two octaves. At
cold start the reference depends on the tier alone, 0.292, 0.529, and 0.753 for
every material, so a test pins that placement alone decides every generated
candidate exactly as the raw floors do. The topology floor and the
hands-together waiver keep their own channels.

Both readings scored on the same replayed states:

| Attempts | Eligibility differs, raw | Reference | Overlap, raw | Reference | Same pick, raw | Reference |
| -------: | -----------------------: | --------: | -----------: | --------: | -------------: | --------: |
|       30 |                    15.8% |     15.5% |        0.231 |     0.242 |           2/26 |      2/26 |
|      120 |                    17.1% |     15.0% |        0.413 |     0.476 |           3/26 |      4/26 |
|      200 |                    12.1% |      7.8% |        0.613 |     0.721 |           5/26 |      7/26 |
|      500 |                     6.9% |      2.2% |        0.784 |     0.907 |           7/26 |     15/26 |

Overlap is the mean over histories of the least-overlapping pair's fully
eligible sets, intersection over union. Challenge-band disagreement is the same
in both, 15% at 500, since the band reads prediction either way.

The disagreement now decays with evidence rather than holding, and what remains
sits at the floors: the median candidate still disagreeing at 500 has a
reference execution 0.009 from the nearest one. Eleven histories agree on every
candidate. The exception is the arpeggio-strong, scale-weak archetype, at 10%
with overlap 0.60 and disagreements 0.03 to 0.04 from a floor, which is the one
place a placement offset rather than boundary noise survives, and the likely
carrier is the prediction-only transfer between scale and arpeggio execution.

What is left between the three placements after this is the challenge band, and
that reads the prediction gap itself. Closing it is the model's question, not a
gate's.

## With the scheduler choosing

The same player run three times under a goal, once per placement, over 25 daily
sittings of 20 slots, with the shipped floors. Each placement is offered
different work and so gathers different evidence, which is the question the
fixed history could not ask: whether the scheduler lets them converge. After 3,
6, 10, and 25 sittings the three are compared on coverage, on the largest total
variation distance between two placements' mix of picks since the previous
checkpoint, and on the least overlap between two placements' fully eligible
sets, read from their own learner states. Thirteen archetypes, two seeds, two
goals, 2980 seconds.

```console
dart run keyrecall_simulation:closed_loop_placement --seeds 2 --jobs 4 \
  --out closed_loop_placement.jsonl
```

Means over the 26 groups per goal:

| Goal        | Sittings | Coverage gap | Guidance | Hands | Octaves | Direction | Family | Eligible overlap |
| ----------- | -------: | -----------: | -------: | ----: | ------: | --------: | -----: | ---------------: |
| Foundations |        3 |        0.085 |    0.095 | 0.052 |       - |     0.084 |      - |            0.696 |
| Foundations |       25 |        0.075 |    0.054 | 0.081 |       - |     0.038 |      - |            0.975 |
| General     |        3 |        0.095 |    0.145 | 0.122 |   0.197 |     0.084 |  0.085 |            0.205 |
| General     |       10 |        0.150 |    0.136 | 0.142 |   0.125 |     0.058 |  0.250 |            0.360 |
| General     |       25 |        0.106 |    0.060 | 0.103 |   0.070 |     0.045 |  0.169 |            0.584 |

Mean slot at which each placement first reached a milestone, and in how many
groups:

| Goal        | Milestone         | Beginner | Some experience | Advanced |
| ----------- | ----------------- | -------: | --------------: | -------: |
| Foundations | first unguided    |   8 (26) |          7 (26) |   6 (26) |
| Foundations | half covered      | 109 (23) |         83 (23) |  98 (24) |
| Foundations | fully covered     | 197 (20) |        209 (23) | 198 (23) |
| General     | first unguided    |  21 (26) |          7 (26) |   6 (26) |
| General     | first two octaves |  37 (26) |          4 (26) |   4 (26) |
| General     | half covered      | 312 (19) |        212 (20) | 226 (20) |

**Foundations does what placement promises.** The three placements end within a
few percent of each other in what they practice and nearly agree on what is
eligible, and a beginner placement finishes the goal as soon as an advanced one
does. Its envelope keeps the route short, so the prior has little room to steer
it.

**General technique converges, slowly.** Eligible overlap rises steadily and is
still rising at 500 slots, and the mix of span, guidance, and hands narrows. The
beginner placement is the transient: it reaches two octaves thirty slots later
and half its catalog about a hundred slots later, and the family mix is the last
facet to agree. Nothing in the data says it stops converging; it does say that
over a catalog this wide the start costs something for a long time.

**Same next pick is too strict a measure here.** No group's three placements
picked the same exercise from a fresh sitting at any checkpoint, which reads
less as divergence than as three genuinely different histories breaking every
tie differently. Overlap is the measure that carries the result.

## Interpretation boundary

Synthetic players whose performance is generated from the same competency
structure the model assumes, which if anything flatters identifiability, and 500
slots is still a finite horizon for general technique.
