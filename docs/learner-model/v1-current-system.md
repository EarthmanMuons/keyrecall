# The KeyRecall V1 Adaptive System

- **Status:** Current integrated specification for the initial production model
- **Last aligned:** August 20, 2026
- **Audience:** Developers, product designers, and researchers who need to
  understand what V1 does without reading the experiment history first

## 1. Start here

This document explains the learner model and scheduler that KeyRecall plans to
ship in V1. It begins with the product problem, builds the mathematics one layer
at a time, and ends with the evidence that supports the design.

We've tried to explain the reasoning in plain English before or alongside each
formula, so you shouldn't need a statistics background to follow the argument.
The formulas are still here in full, though: they're the precise contract that
the code, the TOML parameter files, and the other documents in this folder rely
on, and prose alone would lose that precision.

A few symbols recur throughout and are worth knowing up front:

| Plain text     | Math            | Meaning                                                       |
| -------------- | --------------- | ------------------------------------------------------------- |
| `mu`           | $\mu$           | mean / best current estimate of something                     |
| `sigma^2`      | $\sigma^2$      | variance: how uncertain that estimate is (bigger = less sure) |
| `t`, `Delta t` | $t$, $\Delta t$ | a point in time / elapsed time since some reference point     |
| `p`, `p-hat`   | $p$, $\hat p$   | probability; "hat" marks a model prediction                   |
| `y`            | $y$             | observed outcome or bounded observed score                    |

[`GLOSSARY.md`](../GLOSSARY.md) is the canonical, terse lookup for every term
and symbol; this document is where each of them gets explained and motivated.

A few standard mathematical and statistical terms below link out to Wikipedia on
first use, for anyone who wants one level deeper than the plain-English
explanation given here. Those links are explanatory aids, not citations: they
are not evidence for why V1 made a particular design choice. The research basis
for V1's choices is in §11 and [`01-research.md`](01-research.md).

This is the **current view**. It deliberately omits abandoned equations,
unsuccessful policy branches, future model ideas, and the chronology of how the
design evolved. Those remain available in the research and experiment documents
for anyone auditing the reasoning:

- [`01-research.md`](01-research.md) preserves the literature review;
- [`02-v1-design.md`](02-v1-design.md) preserves the architectural reasoning;
- [`03-v1-math.md`](03-v1-math.md) contains the detailed mathematical and
  simulation record;
- [`04-v1-scheduler.md`](04-v1-scheduler.md) contains the scheduler boundary
  contract and experiment reports; and
- [`05-production-implementation-plan.md`](05-production-implementation-plan.md)
  defines persistence, replay, and implementation gates.

When implementing V1, use this document for the integrated behavior, the
executable prototypes for precise operational semantics, and the TOML files for
the current provisional numbers:

```text
analysis/learner-model/params.toml
analysis/scheduler/config.toml
```

These sources were required to agree while the Python prototype was live. It is
now frozen provenance and the Dart packages are canonical, including the
parameter registries; see `analysis/README.md`. The paragraphs below describe
that earlier arrangement and the values it settled on, which the Dart registries
inherited.

The TOML registries were authoritative for numeric values, executable code
defines machine-level mechanics, and this specification defines the intended
semantic contract. A disagreement among them is a defect to reconcile, not a
precedence rule for silently choosing one.

The architecture and transition boundaries are settled for initial production.
The numeric values are versioned starting points, not scientific constants.

## 2. What the system is trying to do

KeyRecall repeatedly answers one practical question:

> Given what we currently believe about this pianist, which valid scale exercise
> should they play next?

Answering well requires more than remembering whether the learner passed the
same exercise last time. A pianist might:

- remember the notes but struggle to execute them at tempo;
- have strong general right-hand technique but an unusual problem with one key;
- perform well only while the notes remain visible;
- retain a scale after a long gap despite weak recent performance; or
- play a related scale well because previous practice transferred.

V1 therefore separates three persistent-state questions:

1. What transferable knowledge and technique does the learner have?
2. Can the learner independently recall this exact material?
3. Does this material/context have a persistent execution deviation from what
   the transferable competencies predict?

It stores an uncertain answer to each question. Prediction then breaks those
beliefs into four separate numbers, each answering a narrower question about one
upcoming attempt:

1. **independent retrieval**: could they recall it with no help at all?
2. **supported material availability**: can they produce it right now, given
   whatever help this attempt provides?
3. **conditional motor execution**: assuming the material is available, can
   their hands actually carry it out?
4. **topology knowledge**: do they understand the underlying scale pattern,
   separate from whether they can play it?

The scheduler admits candidates at an appropriate challenge level, and the
evidence model updates only the state that a completed attempt actually supplied
real evidence for.

At a high level, here is the loop that runs every time a learner is about to
practice:

```text
propagate state to now
    -> generate valid exercises
    -> apply prerequisites and safety
    -> predict each candidate
    -> admit an appropriate challenge or named exception
    -> rank admitted candidates
    -> present one exercise
    -> observe what happened
    -> attribute evidence by channel
    -> update learner state
    -> repeat
```

## 3. The exercise being predicted

Before getting into beliefs and predictions, it helps to be precise about what
one `Exercise` actually is. It's not a single row in a database, but a small
bundle of independent choices:

```text
TechnicalMaterial      what is being played: e.g. F# harmonic minor scale
ExercisePattern        ordering/transformation: LINEAR in V1
ExecutionConditions    hand, direction, octaves, tempo
GuidanceContext        cues shown before or during the attempt
MotorRealization       canonical fingering and derived motor structure
Opportunities          observable crossing, continuation, and reversal sites
```

Material identity excludes hand, tempo, octaves, direction, and guidance. That
is why an F-sharp harmonic minor scale has one memory state while its
right-hand, left-hand, and hands-together performances can have different
execution states.

V1 supports major, natural minor, harmonic minor, and fixed-form melodic minor
scales, the linear pattern, canonical fingerings, and right, left, and
hands-together contexts where supported. The domain catalog and connected
instrument decide which combinations physically exist before the learner model
is consulted.

## 4. What KeyRecall believes about the learner

### 4.1 Transferable competencies

For each transferable competency `k`, V1 keeps two numbers: a best guess (mean)
and how uncertain that guess is
([variance](https://en.wikipedia.org/wiki/Variance)). Statisticians write that
as a [normal distribution](https://en.wikipedia.org/wiki/Normal_distribution)
("bell curve"):

```math
\theta_{u,k} \sim \mathcal{N}(\mu_{u,k}, \sigma^2_{u,k})
```

The mean is the current capability estimate. The variance is uncertainty about
that estimate. The normal distribution is an interpretable engineering
approximation; it is not a claim that human ability is literally Gaussian.

V1 estimates ten competencies:

```text
Pitch/form topology
    MAJOR_SCALE_TOPOLOGY
    NATURAL_MINOR_TOPOLOGY
    HARMONIC_MINOR_TOPOLOGY
    MELODIC_MINOR_TOPOLOGY

Broad execution
    RH_SCALE_EXECUTION
    LH_SCALE_EXECUTION

Localized technique
    SCALAR_CROSSING
    MULTI_OCTAVE_CONTINUATION
    DIRECTION_REVERSAL
    HANDS_TOGETHER_COORDINATION
```

Practice of any relevant material can update these shared states. This is the
main mechanism for transfer across the repertoire.

At placement, self-report changes the initial mean but never makes the model
confident. The current tiers initialize every competency mean to `-1.0`
(`beginner`), `0.0` (`some experience`), or `1.0` (`advanced`), with broad
variance `1.5` in every tier. Direct performance can therefore override the
self-report quickly.

Right- and left-hand execution are tracked separately, but if one hand is
under-observed, its prediction gets a nudge toward the better-observed hand,
without ever pretending we actually watched that hand play:

```math
\widetilde\mu_k = \mu_k
  + \rho_{\mathrm{hand}}\frac{\sigma_k^2}{\sigma_k^2 + \tau_{\mathrm{hand}}}
    (\mu_{\mathrm{paired}} - \mu_k)
```

The adjustment is largest while the target hand is uncertain and shrinks as its
own direct evidence accumulates. It never records right-hand practice as a
left-hand observation.

During nonuse, the mean estimate doesn't move. KeyRecall doesn't assume skill
declined just because a learner took a break; only the model's confidence in
that estimate erodes, growing over time:

```math
\sigma_k^2(t + \Delta t) = \sigma_k^2(t) + \gamma_k\Delta t
```

V1 becomes less certain that an old estimate is still right; it does not invent
directional skill loss without evidence.

### 4.2 Exact-material memory

This is the part of memory most people actually mean when they say "I don't
remember that scale anymore." That's not "I never learned the skill," but "I
haven't touched this exact material in a while." `MaterialMemoryState` answers
whether one exact scale is independently available. It separates four meanings:

```text
activation              when operative memory was last anchored
current durability      how quickly current availability decays
retained consolidation  slower durability retained for savings/reacquisition
factual history         when retrieval was actually tested and succeeded
```

After a successful retrieval has established an anchor, independent
retrievability follows a [half-life](https://en.wikipedia.org/wiki/Half-life)
curve, borrowed from radioactive decay: it's how long it takes for a quantity to
fall to half its previous value. Here, that's how long until the modeled
probability of unaided recall falls to 50% after the most recent activation
anchor:

```math
M_m(t) = 2^{-\Delta t/h_{\mathrm{current},m}}
```

`M = 0.5` means the model predicts a 50% chance of independently retrieving the
material after the elapsed interval. It does **not** mean a 50% chance of
successfully executing the requested exercise.

The half-life curve above only makes sense once we know when the clock started,
that is, after at least one successful factual retrieval (unguided or
notes-previewed, but not concurrently cued; see §7.1). Before that first
success, there's no anchor to measure decay from, so elapsed-time durability
isn't identifiable yet. V1 falls back on a separate time-independent cold-start
probability instead, using the standard
[logistic](https://en.wikipedia.org/wiki/Logistic_function) ("sigmoid") shape
that squashes any raw score into a 0-1 probability:

```math
M_m(t) = \frac{1}{1+e^{-c_m}}
```

Current and consolidated durability obey a simple ordering: current durability
is always positive, never decays slower than retained/consolidated durability,
and both are capped at a maximum:

```math
0 < h_{\mathrm{current},m} \le h_{\mathrm{consolidated},m} \le h_{\mathrm{max}}
```

Consolidation is retained learning, not current readiness: think of it as skill
held in reserve. It does not directly enter prediction or scheduler ranking. It
matters when later practice restores current durability, allowing reacquisition
to be faster than first acquisition.

### 4.3 Material-specific execution

Alongside the shared competencies, V1 also tracks small, material-specific
exceptions: a "residual" left over after accounting for general skill and task
difficulty, for each material and execution context:

```math
r_{u,m,c} \sim \mathcal{N}(\mu_{r,u,m,c}, \sigma^2_{r,u,m,c})
```

This represents a persistent deviation not already explained by shared
competencies or task difficulty. A learner who is broadly strong but repeatedly
struggles with F major left hand can acquire a negative F-major/LH residual
without weakening the global left-hand estimate by the entire discrepancy.

New residuals start at zero with broad uncertainty, so sparse evidence remains
strongly shrunk toward the shared prediction, a
[shrinkage](https://en.wikipedia.org/wiki/Shrinkage_%28statistics%29) idea
common in statistical models: don't fully trust a material-specific deviation
until repeated evidence supports it. During nonuse, the same idea as competency
uncertainty above applies: an unreinforced residual fades back toward the shared
prediction while the model grows less sure about it:

```math
\mu_r(t + \Delta t) = \mu_r(t)e^{-\Delta t/\tau_r}
```

```math
\sigma_r^2(t + \Delta t) = \sigma_r^2(t) + \gamma_r\Delta t
```

The material-specific exception gradually returns toward the shared prediction
while uncertainty grows.

### 4.4 Session state is separate

Persistent `LearnerState` contains competencies, material memory, and execution
residuals. `SessionState` contains short-lived scheduling context such as the
attempt count, recently selected materials, and the last failed exercise.

This boundary prevents a temporary session condition from automatically being
stored as persistent ability. In the current V1 scheduler, session state drives
the attempt cap, diversity history, repetition guard, and exact recovery action.

These pieces do not all have the same lifetime. The attempt cap and the recovery
context are per-sitting: a restart begins a new sitting, and a recovery context
that outlived the failure it answered would be answering a question nobody is
still asking. The diversity history is rebuilt from the tail of the journal, so
the repetition guard keeps working across a restart rather than immediately
re-offering whatever was played last.

## 5. Connecting exercises to competencies

It's easy to conflate three related but different ideas: "this exercise involves
a competency," "this attempt was informative about it," and "how much weight
should this competency get in the prediction." V1 keeps them as three separate
quantities.

### 5.1 Structural opportunity

This is a plain yes/no map baked into the exercise's structure: a statement
about what the exercise _could_ teach us, not a belief about the learner:

```math
Q_{e,k} \in \{0,1\}
```

`Q[e,k] = 1` means exercise `e` creates an opportunity to observe competency
`k`. It is generated from exercise composition:

- the scale form selects one topology competency;
- right, left, or together selects the relevant hand competencies;
- generated event structure selects crossing, continuation, and reversal; and
- hands together selects coordination.

Guidance does not change `Q`. A cued harmonic-minor exercise still contains
harmonic-minor topology, even if that attempt provides almost no evidence that
the learner independently knew it.

### 5.2 Predictor loading

If one exercise touches several competencies, how much should each count toward
the prediction? Absent better information, V1 just splits the credit evenly
among whichever competencies are actually in play for that channel:

```math
q^{(C)}_{e,k} =
\frac{Q_{e,k}}{\sum_{j \in K_C} Q_{e,j}}
```

Here `C` denotes one prediction channel and `K_C` is that channel's competency
set. V1 uses separate motor and topology versions of this loading.

Motor and topology loadings are normalized separately. Otherwise the presence of
a topology opportunity would artificially dilute the motor predictor.

Equal loading avoids inventing precise relative weights before real data exists.

### 5.3 Attempt-specific evidence

`Q` says an exercise _could_ tell us something about a competency. `w` says how
much this particular attempt actually did, and those are different questions:

```math
w_{a,k} \in [0,1]
```

`w[a,k]` describes how informative attempt `a` actually was about competency
`k`. It can be zero even when `Q[e,k] = 1`. For example, failure to begin
because the notes could not be recalled says very little about motor execution.

Material memory and execution use their own weights, `w_M` and `w_r`. These are
not one universal confidence score: an attempt can be strong execution evidence
and no retrieval evidence at all.

## 6. Predicting an attempt

Rather than one "will they succeed" number, V1 makes four separate predictions
for each candidate exercise: independent retrieval, supported material
availability, conditional motor execution, and topology.

### 6.1 Retrieval versus supported availability

Let `d_e` be retrieval demand: how much independent, unassisted production a
given guidance level actually requires.

```text
continuous pitch cues     d = 0.05
notes previewed           d = 0.6
unguided                  d = 1.0
```

The independent, unguided-recall probability is just the memory-decay number
from §4.2, unchanged:

```math
\widehat p_{\mathrm{retrieval}}(e) = M_m(t)
```

Guidance can prop up availability even when independent recall would fail: the
more support given (the lower `d_e`), the closer availability gets to 1
regardless of memory strength:

```math
\widehat p_{\mathrm{available}}(e) = 1 - d_e(1-M_m(t))
```

Thus continuous cueing makes availability almost certain, previewed notes
partially compensate for weak memory, and an unguided attempt uses the
independent retrieval probability unchanged. Continuous cueing still provides
zero _retrieval evidence_: demand in the prediction and factual observability in
the update are deliberately separate.

### 6.2 Conditional execution

Motor difficulty adds up everything that makes the physical task harder: faster
tempo, extra octaves, hands together, or a change of direction mid-scale:

```math
D_{\mathrm{motor}}(e) =
\beta_t\log\left(\frac{b_e}{b_0}\right)
+ \beta_o\max(0, o_e-1)
+ \beta_h I_{\mathrm{HT}}(e)
+ \beta_d I_{\mathrm{UD}}(e)
```

Here `b_e` is requested BPM, `b_0` is reference BPM, `o_e` is octave count, and
`I_HT`/`I_UD` indicate hands-together and ascending-then-descending tasks.

The conditional execution logit combines shared motor skill, this material's own
residual exception, and the difficulty score above into one raw score:

```math
\eta_{\mathrm{exec}}(e) =
\sum_{k\in K_{\mathrm{motor}}}q^{(\mathrm{motor})}_{e,k}\widetilde\mu_k
+ \mu_{r,m,c}
- D_{\mathrm{motor}}(e)
```

That raw score (a "[logit](https://en.wikipedia.org/wiki/Logit)," or log-odds)
isn't itself a probability. The logistic/sigmoid formula below converts it into
one, the same squashing shape used for cold-start memory in §4.2:

```math
\widehat p_{\mathrm{exec}}(e) =
\frac{1}{1+e^{-\eta_{\mathrm{exec}}(e)}}
```

Guidance is absent from motor difficulty. It helps make the material available;
it does not make the physical task easier once the material is available.

### 6.3 Topology belief

Pitch/form knowledge gets the same treatment as motor execution: a parallel
predictor scored against topology competencies instead, with no motor-difficulty
penalty, because this channel represents knowledge of the pitch/form structure
rather than the physical demands of executing it:

```math
\eta_{\mathrm{topology}}(e) =
\sum_{k\in K_{\mathrm{topology}}}q^{(\mathrm{topology})}_{e,k}\widetilde\mu_k
```

```math
\widehat p_{\mathrm{topology}}(e) =
\frac{1}{1+e^{-\eta_{\mathrm{topology}}(e)}}
```

This is an inference target with its own outcome channel. It is not multiplied
into the scheduler's success prediction, because material availability already
answers whether the notes can be produced on this attempt.

### 6.4 Overall acceptable-performance probability

Multiplying the two hurdle probabilities gives the probability used for
challenge admission: can the material be produced, and, conditional on that, can
the requested motor task be executed?

```math
\widehat p_{\mathrm{overall}}(e) =
\widehat p_{\mathrm{available}}(e)\widehat p_{\mathrm{exec}}(e)
```

This factorization is the key interpretability boundary:

```text
failure to recall        primarily a memory observation
failure after starting   primarily an execution observation
clean cued performance   useful execution evidence, not retrieval evidence
```

`p_overall` is the scheduler's challenge-admission probability: the modeled
conjunction of material availability and conditional motor execution. It is not
a universal latent "quality" variable and does not replace the multidimensional
observed outcome. State updates retain the separate prediction and outcome
channels.

## 7. Turning an attempt into evidence

Predicting is only half the job. Once the learner actually plays, V1 has to turn
what happened into updates to its beliefs.

The observation pipeline preserves rich MIDI-derived outcomes, including pitch
integrity, continuity, timing stability, achieved tempo, topology accuracy, and
localized motor-event behavior. V1 reduces these only where a particular state
update needs a bounded target.

Each prediction channel gets its own "surprise" number: actual outcome minus
predicted outcome. A positive delta means the learner did better than expected;
negative means worse. The three prediction errors are:

```math
y_{\mathrm{motor}} =
\frac{y_{\mathrm{continuity}}+y_{\mathrm{stability}}}{2}
```

```math
\delta_{\mathrm{exec}}=
y_{\mathrm{motor}}-\widehat p_{\mathrm{exec}}
```

```math
\delta_{\mathrm{topology}}=
y_{\mathrm{topology}}-\widehat p_{\mathrm{topology}}
```

```math
\delta_M=
y_{\mathrm{retrieval}}-\widehat p_{\mathrm{retrieval}}
```

There is intentionally no universal prediction error. Each state layer learns
only from a residual that its own prediction helped generate.

### 7.1 Retrieval has three factual outcomes

```text
True     factual retrieval was tested and succeeded
False    factual retrieval was tested and failed
None     retrieval was not factually tested because concurrent cues supplied
         the material
```

`None` is not a weak failure. It gives `w_M = 0` exactly and changes neither
factual retrieval timestamp. This categorical distinction prevents repeated
fully cued practice from accumulating into false evidence of remembering or
forgetting.

"Factual" means retrieval was tested without concurrent answer-supplying cues.
An unguided attempt is the strongest independent test. Previewing notes and then
hiding them remains a real, lower-demand factual test; it produces `True` or
`False` with less weight than an unguided attempt.

### 7.2 Competency and residual updates

For a relevant competency, this is a simple online error-correction update:
nudge the mean toward the surprise (`delta`), scaled by how involved this
competency was (`q`) and how informative this attempt was (`w`), times a
learning-rate knob (`alpha`):

```math
\mu'_k = \mu_k + \alpha_k q^{(C)}_{e,k}w_{a,k}\delta_C
```

And shrink the uncertainty a bit whenever informative evidence arrived, bounded
so it never drops below a floor:

```math
\sigma_k'^2 =
\max(\sigma^2_{\mathrm{min},k},\sigma_k^2(1-\lambda_k w_{a,k}))
```

Motor competencies use `delta_exec`; topology competencies use `delta_topology`.
The execution residual uses the same motor-only error and the same update shape:

```math
\mu'_r = \mu_r + \alpha_r w_r\delta_{\mathrm{exec}}
```

These are conservative online engineering updates rather than exact Bayesian
posteriors. Their required qualitative behavior is simple: informative evidence
moves the appropriate mean and reduces its uncertainty; unrelated or unobserved
evidence does neither.

### 7.3 Cold-start memory correction

Before an anchor exists (§4.2), a tested attempt still teaches us something: it
just updates the time-independent cold-start probability instead of a decay
curve:

```math
c' = c + w_M\left[\alpha_c\left(y_{\mathrm{retrieval}}-\frac{1}{1+e^{-c}}\right)
-\lambda_c(c-c_0)\right]
```

`alpha_c` controls how fast a surprising outcome moves the estimate; the
`lambda_c` term gently pulls it back toward a neutral prior `c_0`, so one lucky
or unlucky attempt can't permanently swing the estimate on its own.

The current half-life and its uncertainty do not move, because the attempt did
not contain an elapsed anchored interval from which to infer durability. A first
success anchors the clock and forms memory through the causal transition below;
it still does not pretend to estimate a forgetting rate from a zero-length
history.

### 7.4 Retained-consolidation inference

This step answers a different question than §7.3: not "did they get it right
just now," but "given how long it's been and what happened, what does that imply
about the learner's deeper, retained durability?" V1 doesn't know that retained
half-life `h_c` for certain, so it does a small piece of
[Bayesian inference](https://en.wikipedia.org/wiki/Bayesian_inference): it
represents a range of plausible values for `h_c` and updates their relative
plausibility as evidence arrives, rather than collapsing to a single number. If
a factual retrieval observation occurs after a pre-existing anchor, the elapsed
interval supplies evidence about that distribution. The formula below just says:
"if the true retained half-life were `h_c`, this is the probability we'd have
seen this outcome after this many days":

```math
P(y=1\mid h_c,\Delta t)=2^{-\Delta t/h_c}
```

That's a
[Bernoulli likelihood](https://en.wikipedia.org/wiki/Bernoulli_distribution):
the probability of one success/failure outcome, evaluated for a candidate guess
at `h_c`. V1 approximates its belief about `h_c` as a bell curve, but over
`log(h_c)` rather than `h_c` itself. Half-lives are always positive and can span
orders of magnitude, and working in log-space handles both cleanly. To update
that belief, it checks a grid of candidate half-life values, scores each by how
well it would have predicted the observed outcome (weighted by `w_M`, how
informative this attempt was), and folds the result back into an updated mean
and variance. The result is projected only as needed to preserve
`h_current <= h_consolidated`.

This inference does not run on:

- the first retrieval;
- an untested retrieval;
- zero-weight evidence; or
- an interval shorter than the configured minimum.

Success and failure are both evidence. Execution quality is not. The update
revises what the estimator believes was already retained; it does not claim that
the attempt just caused that consolidation.

The stored mean and variance describe this approximate inference
[posterior distribution](https://en.wikipedia.org/wiki/Posterior_probability),
the updated belief after folding in the evidence above. The causal transition
that follows may then change the consolidation mean, but causal formation does
not itself contract the posterior variance.

### 7.5 Current-durability correction

Same log-space trick as §7.4, now applied to current durability itself: write
`ell = log(h_current)`. Working in log space keeps the half-life positive and
puts big and small values on a comparable scale. Factual retrieval evidence
updates:

```math
\ell' = \ell + w_M\left[\alpha_M
(y_{\mathrm{retrieval}}-\widehat p_{\mathrm{retrieval}})
-\lambda_M(\ell-\ell_0)\right]
```

The result is bounded and capped by retained consolidation. Because
retained-consolidation inference runs first, this cap uses the consolidation
state produced by step 1 of the memory update; newly inferred consolidation can
therefore create headroom for current-durability correction. Using prediction
error makes surprising outcomes move the estimate more than outcomes the model
already expected, while the reversion term creates a stable interior equilibrium
under repeated expected failure.

### 7.6 Causal memory formation and restoration

So far, §7.4 and §7.5 corrected the model's estimate of durability that already
existed. This section covers the other half: durability the practice itself just
created.

Estimator correction and learning caused by practice are recorded separately.
For an anchored factual retrieval, this execution order is mandatory:

1. retained-consolidation likelihood inference
2. current-durability evidence correction
3. causal consolidation/current-durability transition

The ordering separates evidence about durability that existed before the attempt
from learning caused by the attempt itself.

On a successful factual retrieval, V1:

1. anchors activation at the attempt time;
2. records factual success;
3. grows consolidation toward a saturating target in proportion to execution
   quality and retrieval context; and
4. grows current durability toward the resulting consolidation envelope.

The complete successful-retrieval update cannot leave current durability below
its pre-attempt value. Estimator correction may revise it downward before causal
learning runs, but that correction cannot make a successful practice event net
destructive in the final state.

On productive supported practice without a successful factual retrieval, V1 can
move an existing activation anchor partway toward the present and restore
current durability partway toward consolidation. It does **not** write a factual
retrieval success or grow consolidation.

This is how supported practice can help reacquisition without manufacturing an
event the learner never demonstrated.

For auditability, every update trace separates:

```text
consolidation_delta_from_retrieval_inference
consolidation_delta_from_causal_formation
```

These are the non-negotiable rules the implementation must never violate,
regardless of which numeric parameters are in play. The production memory update
must preserve these semantic invariants:

```text
h_current <= h_consolidated
first success creates no interval inference
unobserved retrieval creates no memory evidence
near-zero intervals create no retained-durability inference
factual failure can lower inferred consolidation
successful factual retrieval cannot leave current durability
    below its pre-attempt value
execution quality affects causal formation, not retained-durability inference
supported practice cannot create factual retrieval history
```

## 8. Choosing the next exercise

The scheduler is a staged policy. Each stage answers one question and has an
explicit information boundary.

An **attempt slot** is a scheduler decision opportunity. A **selection** exists
only when that decision produces an exercise to present; a no-admission slot has
no selection and no presented attempt. This distinction must be preserved in
session caps, replay, diagnostics, and telemetry.

1. candidate generation
2. eligibility and safety
3. challenge admission
4. priority ranking and selection

### 8.1 Candidate generation

The generator combines valid material, hand, octave, direction, tempo, and
guidance options. It reads the domain catalog and `InstrumentProfile`, but no
learner or session state.

An impossible exercise should never become a candidate. This stage handles
physical and product validity, not pedagogy.

### 8.2 Eligibility and safety

The `REQUIRES` relationship creates an ordered eligibility tier from competency
state. In the current implementation, hands-together work is fully eligible when
both RH and LH execution means meet the configured threshold; otherwise it is
provisionally eligible.

This is a soft pedagogical gate. A provisional candidate remains reachable, but
cannot outrank a fully eligible candidate.

The stage answers two questions that are worth keeping apart. Whether a material
is appropriate yet is a question about the material and the learner's
competencies. Whether it may be attempted _at this rung_ yet is a question about
guidance, and the one rule of that kind reads whether the material has any
history in this profile at all: material nothing is known about may be
introduced, but not tested from memory the first time it appears. That is a
statement about what has been established here, not a claim that the learner
does not know the scale.

A third rule asks a question of its own: whether the learner's vocabulary of
scale forms should grow yet. Harmonic and melodic minor are not harder keys,
they are new ideas about what minor means, and meeting one while ordinary scales
are still unsettled enlarges the vocabulary faster than the base under it. They
wait on a breadth of major and natural-minor material the learner has actually
retrieved, spread over more than one band, and the wait is lifted for someone
already fluent in the hand the exercise asks for, since the rule exists so a
beginner's vocabulary does not outrun their base rather than to make an
experienced player re-earn what they arrived with. Per hand, by the same reading
the bands use: a fluent right hand is not evidence about the left.

So eligibility reads competency state and factual observation history: whether a
material has an entry at all, and whether it has ever been retrieved. It does
not read what the model believes about that history. Durability, uncertainty and
retrievability are estimates, and estimates belong to prediction, which runs
later.

The safety policy is a separate hard gate based only on session/workload state.
V1 implements a configurable session-attempt cap. It does not diagnose fatigue
or injury from MIDI behavior.

### 8.3 Challenge admission

Ordinary candidates must land in a "not too easy, not too hard" band on the
overall probability computed in §6.4:

```math
p_{\mathrm{min}}\le\widehat p_{\mathrm{overall}}(e)\le p_{\mathrm{max}}
```

The current provisional band is 0.60 to 0.90. This is a configurable engineering
choice inspired by Challenge Point reasoning, not a research-established
universal optimum.

Five named mechanisms can admit a candidate outside the ordinary band:

```text
new material       only above a lower introduction floor
guidance probe     one step less support after an anchored success and interval
bootstrap probe    a retrieval test for never-successful material after interval
recovery           exact failed exercise with one step more guidance
tempo probe        exact easy exercise at the tempo it was actually played at
```

Recovery is reactive and exclusive: after a factual retrieval failure, only the
same material and motor task with one additional guidance step survives that
decision. Tempo, direction, octave span, and hand configuration do not silently
collapse.

The tempo probe is its mirror, and exclusive for the same reason. An attempt
that was completed cleanly, evenly, unbroken, from memory, and comfortably
faster than requested is evidence about the task rather than about the
performance: it was beneath the learner. The next decision then asks for the
same task at the fastest offered tempo they were already reaching, instead of
climbing toward it a step at a time. Only the tempo moves, for the reason
recovery moves only guidance.

Every one of those conditions is required, because speed alone is ambiguous:
rushing and finding it trivial look identical on the tempo axis and differ on
every other one. Retrieval must have been tested and succeeded, since playing
quickly while reading the notes off the screen says nothing about the exercise.

This is the selection half of a division the attribution rule makes necessary.
Execution evidence is credited at the tempo that was asked for and never above
it (§7), so a learner cannot be credited with a difficulty nobody posed. The
only way to earn evidence at a faster tempo is to be asked for it, and this is
what does the asking.

Guidance and bootstrap probes use different factual clocks:

```text
guidance probe     time since last successful factual retrieval
bootstrap probe    time since last factual retrieval attempt
```

### 8.4 Priority ranking

Surviving candidates are ordered
[lexicographically](https://en.wikipedia.org/wiki/Lexicographic_order), exactly
like alphabetizing a dictionary: compare the first field, and only move to the
next field if the first is tied:

```text
(eligibility tier, retention, information, diversity, goals)
```

So eligibility tier always wins first; no amount of retention, information, or
diversity advantage lets a provisional candidate outrank a fully eligible one.
There is no hidden weighted sum blending these together.

The terms are:

```math
R(e)=
(1-\widehat p_{\mathrm{retrieval},m})\,o_{\mathrm{retrieval}}(e)
```

`R` is the retention score: how urgent it is to test this material before it's
forgotten, weighted by whether this candidate can actually produce real
retrieval evidence. It's high when a material is at risk and this candidate can
actually test retrieval. A continuously cued candidate has zero retrieval
opportunity and cannot win by exploiting a memory deficit it cannot resolve.

```text
Info(e)   weighted uncertainty exposed by this candidate's competency,
          memory, and execution evidence opportunities

Div(e)    negative count of this material in the recent-history window

Goal(e)   external learner-goal relevance; explicitly 0 until the product has
          a goal data model
```

Lexicographic ranking means retention decides first within an eligibility tier,
then information, diversity, and goals break ties in that order. V1 has no
hidden weighted sum.

Finally, a repetition guard prevents the same material from winning more than
the configured consecutive-attempt cap when another admitted material exists. It
never removes the only admitted option.

### 8.5 What each scheduler stage may know

| Stage        | Reads                                                   | Decides                    |
| ------------ | ------------------------------------------------------- | -------------------------- |
| Generation   | domain and instrument validity                          | whether an exercise exists |
| Prerequisite | transferable competencies                               | full or provisional tier   |
| Safety       | session/workload state                                  | suppress or allow          |
| Challenge    | candidate `p_overall` and named-exception clocks        | admit or reject            |
| Priority     | tier, actionable retention, uncertainty, history, goals | ordering                   |
| Selection    | ordered candidates and repetition history               | one next exercise          |

Retained consolidation is absent from this table by design. With activation and
current durability held fixed, consolidation alone cannot change prediction,
admission, or ranking.

## 9. One attempt from end to end

Here's what all of the above looks like for one concrete attempt. Suppose the
scheduler considers an 80 BPM, two-octave, right-hand G-major scale with notes
previewed and then hidden.

1. The domain structure marks opportunities for major topology, right-hand
   execution, scalar crossing, multi-octave continuation, and reversal.
2. Material memory supplies the independent G-major retrieval probability.
3. Previewed notes reduce retrieval demand, increasing predicted material
   availability without changing conditional motor execution.
4. Shared motor competencies, the G-major/RH residual, and task difficulty
   produce `p_exec`.
5. `p_available * p_exec` determines challenge admission.
6. If admitted, the candidate receives retention, information, diversity, and
   goal values and competes within its eligibility tier.
7. After performance, previewed notes still permit a factual retrieval result,
   but with less memory weight than an unguided attempt.
8. Continuity and timing update motor competencies and the G-major/RH residual.
9. Topology accuracy separately updates major-scale topology.
10. Factual retrieval evidence updates cold-start belief or durability, and a
    success causally strengthens current and consolidated memory.

If continuous cues had remained visible, steps 2-6 would still predict a highly
available exercise and steps 8-9 could still provide execution evidence. Step 10
would receive `retrieval_succeeded = None`: no retrieval belief or factual
retrieval clock would move.

## 10. Provisional numeric snapshot

The architecture gives each parameter a stable meaning, but the initial values
remain heuristic. This table is a readable snapshot, not a second parameter
registry. The TOML files record what the prototype carried; `LearnerParams` and
`SchedulerConfig` in the Dart packages are the live registries.

| Area                         | Current V1 prototype values                                                                                                        |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Placement                    | means `-1 / 0 / 1`; broad variance `1.5`                                                                                           |
| Competency update            | learning rate `0.15`; evidence shrinkage `0.3`; minimum variance `0.05`; uncertainty diffusion `0.01/day`                          |
| Memory prior                 | retrievability `0.4`; current half-life `3d`; uncertainty `1.0`                                                                    |
| Current durability           | evidence coefficient `0.7`; reversion `0.05`; bounds `0.001d-1000d`                                                                |
| Cold start                   | evidence coefficient `0.7`; reversion `0.05`; probability bounds `0.001-0.999`                                                     |
| Consolidation posterior      | prior log variance `2.0`; variance floor `0.2`; interval floor `1h`; likelihood weight `1.0`; grid `301` points                    |
| Causal memory                | consolidation growth `0.05` toward `60d`; current-durability success/restoration rate `0.022556...`; activation restoration `0.05` |
| Practice factors             | continuous cues `0.3`; notes previewed `0.7`; unguided `1.0`                                                                       |
| Retrieval-success factors    | notes previewed `0.7`; unguided `1.0`                                                                                              |
| Execution residual           | prior variance `0.5`; learning rate `0.2`; mean-reversion time `14d`; uncertainty diffusion `0.02/day`                             |
| Hand transfer                | correlation strength `0.3`; shrinkage scale `0.5`                                                                                  |
| Motor difficulty             | tempo `0.4`; extra octave `0.3`; hands together `0.2`; up/down `0.15`; reference tempo `80 BPM`                                    |
| Scheduler eligibility/safety | HT competency threshold `0.0`; session cap `40` attempts                                                                           |
| Scheduler challenge          | ordinary band `0.60-0.90`; new-material floor `0.15`                                                                               |
| Scheduler history            | recent window `10`; consecutive-material cap `5`; probe interval `5d`                                                              |

The learner registry is version `v1-prototype-2`; the scheduler registry is
`v1-prototype-0`. Attempt records must persist the relevant model and parameter
versions so later replay does not reinterpret old evidence using new constants.

### 10.1 What is frozen and what remains provisional

| Frozen for initial production           | Still provisional           |
| --------------------------------------- | --------------------------- |
| State decomposition                     | Priors                      |
| Prediction-channel separation           | Learning rates              |
| Three-valued retrieval semantics        | Difficulty coefficients     |
| Memory transition ordering              | Half-life targets and rates |
| Consolidation/current envelope          | Challenge thresholds        |
| Scheduler stages/information boundaries | Probe intervals             |
| Named exception semantics               | Evidence weights            |
| Lexicographic ranking structure         | Numeric uncertainty scales  |
| Recovery semantics                      | Other calibrated constants  |

Reopening a frozen structural decision requires new empirical evidence or a
demonstrated invariant or implementation failure. Numeric recalibration does not
require reopening the architecture.

## 11. Why this design is defensible

Research supports the model families and qualitative constraints. It does not
supply piano-specific coefficients or this exact combined architecture. You
don't need to know this literature to use the system; the citations below are
for anyone who wants to go deeper.

| V1 choice                                | Research basis                                                     | What KeyRecall contributes                                                                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Shared competencies updated across tasks | PFA, DAS3H, knowledge tracing, multidimensional IRT                | The ten scale-specific competency ontology and MIDI evidence mapping                                                                         |
| Exact-material time-dependent memory     | HLR and ACT-R-derived practice scheduling                          | Separate current durability, retained consolidation, activation, and factual clocks                                                          |
| Shrinkage of material effects            | Hierarchical and crossed-effects modeling                          | Zero-centered material/context residuals with broad initial uncertainty and reversion toward shared state; population-level fitting deferred |
| Separate motor and material state        | Procedural-retention and effector-specific motor-learning evidence | The retrieval/availability/execution hurdle split                                                                                            |
| Guidance-sensitive retrieval evidence    | Retrieval-practice and guidance-fading research                    | Three-valued factual retrieval and a categorical no-evidence boundary under continuous cues                                                  |
| Challenge admission                      | Challenge Point framework                                          | A broad configurable probability band plus explicit exceptions                                                                               |
| Retention and information priorities     | Spacing models and adaptive testing                                | Actionable retention, stage-specific information boundaries, and lexicographic V1 policy                                                     |
| Repertoire variation                     | Contextual-interference evidence, with important task dependence   | A conservative diversity term plus a hard repetition guard                                                                                   |

The core sources and their limitations are discussed in
[`01-research.md`](01-research.md), especially sections 19-22 and 26-30. The
most direct foundations are:

- Pavlik, Cen, and Koedinger on Performance Factors Analysis;
- Choffin et al. on DAS3H;
- Settles and Meeder on Half-Life Regression;
- Pavlik and Anderson on model-based practice scheduling;
- Reckase and multidimensional CAT work on uncertain multidimensional ability;
- Guadagnoli and Lee on Challenge Point; and
- motor-learning and contextual-interference literature summarized in the
  research document.

The scientific boundary matters: the forgetting-curve shape, logistic
predictions, partial-pooling structure, and qualitative policy goals are
research-grounded. The initial priors, learning rates, half-lives, difficulty
coefficients, thresholds, and scheduler constants are heuristic V1 values.

## 12. What the synthetic analysis established

Synthetic analysis is a mechanism test, not evidence that the parameters are
calibrated for real pianists. Its value is that the simulator knows the hidden
truth and can expose contradictions, contamination between state layers, policy
dead ends, and regression tradeoffs before production code exists.

The current prototype is guarded by:

```text
32 learner-model invariants
13 scheduler information-boundary invariants
10 longitudinal scheduler scenarios
```

The analysis led to five production conclusions.

### 12.1 Separate prediction channels are necessary

A shared success signal allowed one weak layer to manufacture updates in
another. Splitting retrieval availability, motor execution, and topology gave
each state its own prediction error and improved correction across the synthetic
profiles.

### 12.2 "Not tested" must not mean "failed weakly"

When fully cued attempts were given a small nonzero memory weight, 50
repetitions could erode an established 100-day half-life by roughly 80%, even
though no retrieval had occurred. The three-valued retrieval outcome and exact
zero-weight boundary removed that false evidence while preserving learning from
genuine lower-demand tests.

### 12.3 Memory needs surprise-driven, bounded dynamics

The original fixed multiplicative half-life change collapsed toward zero under
repeated failure regardless of whether failure was already expected. The
log-space prediction-error update reaches a stable interior equilibrium and
keeps the state finite. Cold-start belief needed the same treatment in logit
space and its own uncertainty.

### 12.4 Retained-durability inference cleared the production gate

Controlled posterior validation covered latent half-lives from 1 to 90 days.
With the current provisional prior and variance floor, mean absolute log error
was 0.288 and nominal 90% interval coverage was 96.2%. A 301-point grid agreed
with a 1001-point grid within the declared 1% tolerance.

Across the matched 250-trial scheduler matrix, enabling retained inference
improved retrieval [MAE](https://en.wikipedia.org/wiki/Mean_absolute_error) from
0.124 to 0.120 and [Brier score](https://en.wikipedia.org/wiki/Brier_score) from
0.077 to 0.067, while overall-performance MAE remained 0.187. Recovery,
guidance-probe, and no-admission rates were essentially unchanged. Concentration
and maximum-gap tails rose modestly and remain explicit calibration guardrails.

### 12.5 The scheduler requires narrow structural safeguards

Longitudinal scenarios exposed absorbing cueing, endless repetition, overly easy
recovery, and fixed new-material behavior. The production mechanisms that
resolved them are:

```text
candidate-actionable retention
repetition guard
guidance and bootstrap probes
exact exclusive recovery
learner-sensitive new-material admission through predicted p_overall
and a separate introduction floor
```

Later diagnostics tested cross-material durability seeding, prediction bridges,
placement-based support reduction, probe cooldown or suppression, alternative
ranking exceptions, and motor-only or hybrid recovery. None met the declared
combined calibration and behavior gates. The strongest unpromoted hybrid
recovery result improved immediate completion by only 1.46-1.80 percentage
points and did not shorten recovery or accelerate factual return.

The production conclusion is therefore conservative: preserve the validated
mechanisms, keep coefficients configurable, and move to real-data validation
instead of adding more synthetic policy branches.

## 13. Production contract

This section specifies the durability, ordering, and replay guarantees the
implementation must not break. Every presented attempt must be reconstructable
as one ordered transaction:

1. establish decision time and propagate state
2. evaluate and select from traced candidates
3. persist the decision before presentation
4. collect observations and derive the factual outcome
5. compute evidence weights
6. run estimator inference
7. run causal state transitions
8. update session state
9. persist the outcome, transition trace, and state-after reference

Outcome persistence and the resulting learner/session transition must be
recoverable atomically. After an interruption, replay must resolve to either the
pre-outcome state or the complete post-outcome state, never an intermediate
update. The implementation may satisfy this with a database transaction,
event-journal replay, or another mechanism that preserves the same semantic
guarantee.

The local attempt journal is append-only and model-versioned. Replay must
reproduce learner state and scheduler choices deterministically. Factual
retrieval `true`, `false`, and `null` must survive serialization exactly.

Replay-critical inputs include every versioned learner and scheduler
configuration, the domain/catalog and candidate-generation semantics, instrument
capabilities, session context, exact decision time and pre-propagation state,
and any tie-breaking randomness. The journal must also preserve the exercise
that was actually presented rather than relying only on a later recomputation. A
changed catalog or candidate generator must not silently change the
interpretation of a historical decision. The implementation plan owns the exact
storage schema for this contract.

The app must function with no account, network connection, or research
telemetry. Optional research export is a minimized projection of the richer
local history; it is not the source of truth.

## 14. V1 in one paragraph

KeyRecall V1 models a pianist with uncertain transferable competencies, one
time-sensitive memory state per exact scale, and a shrinkage-based execution
residual per scale and hand context. It predicts whether the material will be
available, whether it can be executed under the requested conditions, and what
topology knowledge the performance may reveal. It admits valid exercises through
prerequisite, safety, and challenge stages, ranks them lexicographically by
eligibility, actionable retention, information, diversity, and goals, and then
updates only the state channels the attempt genuinely observed. The structure is
frozen for initial production; all current numeric constants remain provisional,
versioned, and subject to validation with real learner data.
