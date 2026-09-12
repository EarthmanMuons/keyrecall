# The learner model

What KeyRecall believes about a player, how it turns those beliefs into a
prediction about the next attempt, and how it revises them afterward.

The model is a deterministic library in `packages/keyrecall_learner`. It reads
no clock of its own, does no I/O, and mutates only the state it is handed, so a
recorded attempt replays to the same result.

The formulas below are the precise contract that the code and the parameter
registries rely on, and each is explained in plain English alongside. You should
not need a statistics background to follow the argument. A few symbols recur:

| Plain text     | Math            | Meaning                                                       |
| -------------- | --------------- | ------------------------------------------------------------- |
| `mu`           | $\mu$           | mean, the best current estimate of something                  |
| `sigma^2`      | $\sigma^2$      | variance: how uncertain that estimate is (bigger = less sure) |
| `t`, `Delta t` | $t$, $\Delta t$ | a point in time, and elapsed time since some reference point  |
| `p`, `p-hat`   | $p$, $\hat p$   | probability; "hat" marks a model prediction                   |
| `y`            | $y$             | an observed outcome or bounded observed score                 |

Links to Wikipedia mark borrowed statistical vocabulary, for anyone who wants
one level deeper than the explanation here. They are explanatory aids, not
evidence for a design choice; the evidence is in
[`../research/foundations/`](../research/foundations/).

## 1. What KeyRecall believes about the learner

### 1.1 Transferable competencies

For each transferable competency `k`, KeyRecall keeps two numbers: a best guess
(mean) and how uncertain that guess is
([variance](https://en.wikipedia.org/wiki/Variance)). Statisticians write that
as a [normal distribution](https://en.wikipedia.org/wiki/Normal_distribution)
("bell curve"):

```math
\theta_{u,k} \sim \mathcal{N}(\mu_{u,k}, \sigma^2_{u,k})
```

The mean is the current capability estimate. The variance is uncertainty about
that estimate. The normal distribution is an interpretable engineering
approximation; it is not a claim that human ability is literally Gaussian.

The current model estimates fifteen competencies:

```text
Pitch/form topology
    MAJOR_SCALE_TOPOLOGY
    NATURAL_MINOR_TOPOLOGY
    HARMONIC_MINOR_TOPOLOGY
    MELODIC_MINOR_TOPOLOGY
    MAJOR_ARPEGGIO_TOPOLOGY
    MINOR_ARPEGGIO_TOPOLOGY

Broad execution
    RH_SCALE_EXECUTION
    LH_SCALE_EXECUTION
    RH_ARPEGGIO_EXECUTION
    LH_ARPEGGIO_EXECUTION

Localized technique
    SCALAR_CROSSING
    ARPEGGIO_TRANSITION
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
left-hand observation. The provisional arpeggio family uses the same
prediction-only mechanism to borrow cautiously from same-hand scale execution.
Its topology, transition, exact-material memory, and execution residual remain
new state, while hands-together coordination is shared.

During nonuse, the mean estimate doesn't move. KeyRecall doesn't assume skill
declined just because a learner took a break; only the model's confidence in
that estimate erodes, growing over time:

```math
\sigma_k^2(t + \Delta t) = \sigma_k^2(t) + \gamma_k\Delta t
```

The model becomes less certain that an old estimate is still right; it does not
invent directional skill loss without evidence.

### 1.2 Exact-material memory

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
notes-previewed, but not concurrently cued; see §4.1). Before that first
success, there's no anchor to measure decay from, so elapsed-time durability
isn't identifiable yet. It falls back on a separate time-independent cold-start
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

### 1.3 Material-specific execution

Alongside the shared competencies, the model also tracks small,
material-specific exceptions: a "residual" left over after accounting for
general skill and task difficulty, for each material and execution context:

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

The same record also carries the **execution frontier**: the fastest tempo this
learner has managed at each octave span, for this material, hand configuration,
and hand motion. It sits here because it is the same kind of claim about the
same thing. Two octaves in the right hand says nothing about a left hand that
has played one, hands together is a third frontier, and contrary motion does not
certify parallel execution.

A tempo per span rather than a widest span and a fastest tempo. Those are two
maxima and the pair of them is not a place anybody has been: one octave at 96
and two at 60 would read as two octaves at 96, and stepping on from there would
ask for something a step past nothing. Execution conditions form a small lattice
and this is its shape.

It moves only on an attempt that was managed — through to the end, and with a
motor score at the midpoint or above — so a tempo somebody could not get through
does not become the place they are asked to go on from. It is a maximum per
span, so working slowly on something already taken faster does not walk it back
down.

### 1.4 Session state is separate

Persistent `LearnerState` contains competencies, material memory, and execution
residuals. `SessionState` contains short-lived scheduling context such as the
attempt count, recently selected materials, and the last failed exercise.

This boundary prevents a temporary session condition from automatically being
stored as persistent ability. In the scheduler, session state drives the attempt
cap, diversity history, repetition guard, and exact recovery action.

These pieces do not all have the same lifetime. The attempt cap and the recovery
context are per-sitting: a restart begins a new sitting, and a recovery context
that outlived the failure it answered would be answering a question nobody is
still asking. The diversity history is rebuilt from the tail of the journal, so
the repetition guard keeps working across a restart rather than immediately
re-offering whatever was played last.

## 2. Connecting exercises to competencies

It's easy to conflate three related but different ideas: "this exercise involves
a competency," "this attempt was informative about it," and "how much weight
should this competency get in the prediction." The model keeps them as three
separate quantities.

### 2.1 Structural opportunity

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

### 2.2 Predictor loading

If one exercise touches several competencies, how much should each count toward
the prediction? Absent better information, it just splits the credit evenly
among whichever competencies are actually in play for that channel:

```math
q^{(C)}_{e,k} =
\frac{Q_{e,k}}{\sum_{j \in K_C} Q_{e,j}}
```

Here `C` denotes one prediction channel and `K_C` is that channel's competency
set. There are three: motor, topology, and coordination. Every competency
belongs to exactly one of them.

Each channel is normalized within itself. Otherwise the presence of a topology
opportunity would artificially dilute the motor predictor, and a two-hand
exercise would predict execution partly from how together the hands are rather
than from the two hands that execute.

Equal loading avoids inventing precise relative weights before real data exists.

### 2.3 Attempt-specific evidence

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

## 3. Predicting an attempt

Rather than one "will they succeed" number, the model makes five separate
predictions for each candidate exercise: independent retrieval, supported
material availability, conditional motor execution, bilateral coordination, and
topology.

### 3.1 Retrieval versus supported availability

Let `d_e` be retrieval demand: how much independent, unassisted production a
given guidance level actually requires.

```text
continuous pitch cues     d = 0.05
notes previewed           d = 0.6
unguided                  d = 1.0
```

The independent, unguided-recall probability is just the memory-decay number
from §1.2, unchanged:

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

### 3.2 Conditional execution

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
one, the same squashing shape used for cold-start memory in §1.2:

```math
\widehat p_{\mathrm{exec}}(e) =
\frac{1}{1+e^{-\eta_{\mathrm{exec}}(e)}}
```

Guidance is absent from motor difficulty. It helps make the material available;
it does not make the physical task easier once the material is available.

### 3.3 Topology belief

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

### 3.4 Overall acceptable-performance probability

Challenge admission combines material availability with the weaker of the two
correlated motor-control channels: can the material be produced, and can both
execution and bilateral coordination support the requested task?

```math
\widehat p_{\mathrm{overall}}(e) =
\widehat p_{\mathrm{available}}(e)\,
\min(\widehat p_{\mathrm{exec}}(e),
\widehat p_{\mathrm{coordination}}(e))
```

This factorization is the key interpretability boundary:

```text
failure to recall        primarily a memory observation
failure after starting   primarily an execution observation
clean cued performance   useful execution evidence, not retrieval evidence
```

`p_coordination` is one for single-hand work. For hands-together work, execution
and coordination are correlated views of the same performance, so their weaker
probability is the motor-control bottleneck rather than multiplying them under
an independence assumption. `p_overall` multiplies that bottleneck by the
separate material-availability hurdle. It is not a universal latent "quality"
variable and does not replace the multidimensional observed outcome.

## 4. Turning an attempt into evidence

Predicting is only half the job. Once the learner actually plays, the model has
to turn what happened into updates to its beliefs.

The observation pipeline preserves rich MIDI-derived outcomes, including pitch
integrity, continuity, timing stability, achieved tempo, topology accuracy, how
far apart the hands were at each moment both of them played, and localized
motor-event behavior. The model reduces these only where a particular state
update needs a bounded target.

Four predictions have independent observed targets and therefore their own
"surprise" number: actual outcome minus predicted outcome. A positive delta
means the learner did better than expected; negative means worse. Supported
material availability is derived from retrieval and guidance, so it has no
separate outcome or update error. The four errors are:

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
\delta_{\mathrm{coord}}=
y_{\mathrm{coord}}-\widehat p_{\mathrm{coord}}
```

```math
\delta_M=
y_{\mathrm{retrieval}}-\widehat p_{\mathrm{retrieval}}
```

`y_coord` reads how together the hands were, from the moments where both of them
corresponded to something that arrived. It is three-valued in effect: a
single-hand attempt has no such moment, and neither does a two-hand attempt
where one hand never landed, and in both cases the channel is absent rather than
zero. Zero would say the hands were as far apart as playing gets, which is not
what an unobserved attempt shows.

There is intentionally no universal prediction error. Each state layer learns
only from a residual that its own prediction helped generate.

### 4.1 Retrieval has three factual outcomes

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

### 4.2 Competency and residual updates

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

Each competency uses its own channel's error: motor competencies use
`delta_exec`, topology competencies `delta_topology`, and coordination
`delta_coord`. An attempt that measured no coordination carries no weight for
that competency at all, so it is left untouched rather than taught from a motor
score that never observed it. The execution residual uses the same motor-only
error and the same update shape:

```math
\mu'_r = \mu_r + \alpha_r w_r\delta_{\mathrm{exec}}
```

These are conservative online engineering updates rather than exact Bayesian
posteriors. Their required qualitative behavior is simple: informative evidence
moves the appropriate mean and reduces its uncertainty; unrelated or unobserved
evidence does neither.

### 4.3 Cold-start memory correction

Before an anchor exists (§1.2), a tested attempt still teaches us something: it
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

### 4.4 Retained-consolidation inference

This step answers a different question than §4.3: not "did they get it right
just now," but "given how long it's been and what happened, what does that imply
about the learner's deeper, retained durability?" The model does not know that
retained half-life `h_c` for certain, so it does a small piece of
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
at `h_c`. The model approximates its belief about `h_c` as a bell curve, but
over `log(h_c)` rather than `h_c` itself. Half-lives are always positive and can
span orders of magnitude, and working in log-space handles both cleanly. To
update that belief, it checks a grid of candidate half-life values, scores each
by how well it would have predicted the observed outcome (weighted by `w_M`, how
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

### 4.5 Current-durability correction

Same log-space trick as §4.4, now applied to current durability itself: write
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

### 4.6 Causal memory formation and restoration

So far, §4.4 and §4.5 corrected the model's estimate of durability that already
existed. This section covers the other half: durability the practice itself just
created.

Estimator correction and learning caused by practice are recorded separately.
For an anchored factual retrieval, this execution order is mandatory:

1. retained-consolidation likelihood inference
2. current-durability evidence correction
3. causal consolidation/current-durability transition

The ordering separates evidence about durability that existed before the attempt
from learning caused by the attempt itself.

On a successful factual retrieval, the model:

1. anchors activation at the attempt time;
2. records factual success;
3. grows consolidation toward a saturating target in proportion to execution
   quality and retrieval context; and
4. grows current durability toward the resulting consolidation envelope.

The complete successful-retrieval update cannot leave current durability below
its pre-attempt value. Estimator correction may revise it downward before causal
learning runs, but that correction cannot make a successful practice event net
destructive in the final state.

On productive supported practice without a successful factual retrieval, it can
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

## 5. One attempt from end to end

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

## 6. The numbers

Every constant lives in `LearnerParams` in `packages/keyrecall_learner`, which
is the live registry and the only place the values are stated. This document
deliberately does not restate them: a table of numbers in prose drifts away from
the code silently, and a reader who trusts the stale copy is worse off than one
who opens the registry.

Two things about the registry are design rather than calibration, and belong
here:

**The version names one transition function.** `LearnerParams.modelVersion` is
recorded on every attempt, and replay refuses to reinterpret history under a
different one. It has to move whenever the model learns differently, because an
old attempt replayed under new constants is a silently rewritten past. The
preserved prototype registry carries its own version for the same reason, so the
two can never be confused for each other.

**The architecture gives each parameter a stable meaning.** The initial values
are heuristic starting points drawn from the literature and from synthetic
characterization. Recalibrating any of them is expected and does not reopen a
design question.

### 6.1 Every parameter carries a provenance class

A value's class says what kind of claim it is, and **no parameter may silently
move between them**:

```text
research-structured   the literature supports the model family or the
                      qualitative relationship, but not this number
                      e.g. logistic response modeling, partially pooled item
                      effects, time-dependent retrievability

literature-inspired   the form is borrowed or adapted from prior research, and
                      its use here still needs validation
                      e.g. the half-life forgetting curve, multi-skill logistic
                      structure

heuristic             chosen for engineering reasons before enough data exists
                      e.g. initial half-life, evidence coefficients, learning
                      rates, prior variances, difficulty coefficients, the
                      guidance mapping, the challenge band, scheduler constants

empirically fitted    estimated from KeyRecall longitudinal data
                      nothing is in this class yet
```

The distinction that matters most: a research-structured parameter has evidence
for its _shape_ and none for its _value_. Citing the literature for such a
number would overclaim, and several of these carry a citation for exactly the
former.

### 6.2 What is frozen and what remains provisional

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
