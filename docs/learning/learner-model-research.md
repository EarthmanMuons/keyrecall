# Learner Model Research

**Status:** Research foundation for learner-state and adaptive scheduling
design\
**Scope:** Transferable competencies, item memory, evidence modeling, level
setting, task difficulty, and practice scheduling

## 1. Purpose

KeyRecall needs a learner model that can estimate transferable competencies,
memory for exact practiced items, uncertainty, performance as difficulty
changes, effects of elapsed time, and the learning value of candidate exercises.

No single established model covers all of these requirements. The recommended
direction is therefore a **hybrid, interpretable learner and scheduler model
assembled from established research traditions**, rather than a novel opaque
"KeyRecall algorithm."

This document deliberately distinguishes research-supported findings from
KeyRecall-specific synthesis decisions that still require simulation and
empirical validation.

## 2. Architectural distinctions

The preceding motor analysis established:

```text
Motor/domain model
    describes what the exercise requires

Learner model
    describes what KeyRecall believes about the pianist

Evidence model
    connects observed performance to learner state
```

The learner model adds another distinction:

```text
TRANSFERABLE COMPETENCY
    persistent capability shared across related tasks

ITEM MEMORY
    time-sensitive state for an exact practiced item

TASK FEATURES
    conditions under which performance is requested

OBSERVATIONS
    what actually happened during the attempt
```

For example:

```text
RH scale execution           transferable competency
harmonic-minor topology      transferable competency
D harmonic minor             exact item
time since D harmonic minor  item-memory feature
phase 5                      task feature
92 BPM                       task feature
wrong C#                     observation
local hesitation             observation
```

This separation is foundational.

## 3. Knowledge tracing

Knowledge-tracing models infer unobserved learner knowledge from sequences of
observable performances. Classical Bayesian Knowledge Tracing (BKT) established
the general architecture of hidden knowledge state updated by evidence, commonly
using learned/unlearned state plus learning, guessing, and slipping parameters.

That architecture is useful to KeyRecall, but vanilla BKT is too coarse. MIDI
performance is not naturally binary and can expose pitch correctness, fingering
deviations, timing consistency, hesitation, tempo, continuity, crossing
execution, turnaround behavior, and hands-together synchronization. A single
exercise can also require several competencies simultaneously.

**KeyRecall implication:** preserve the knowledge-tracing distinction between
observation and latent state, but do not assume binary mastery is the final
mathematical model.

## 4. Performance Factors Analysis and logistic learner models

Pavlik, Cen, and Koedinger's Performance Factors Analysis (PFA) was developed as
an alternative to conventional knowledge tracing and explicitly addresses
limitations around actions requiring multiple skills.

A logistic family gives a useful general form:

\[ P(`\text{success}`{=tex}) =
`\sigma`{=tex}(`\text{learner/skill state}`{=tex} +
`\text{practice evidence}`{=tex} + `\ldots`{=tex}) \]

where:

\[ `\sigma`{=tex}(x) = `\frac{1}{1 + e^{-x}}`{=tex} \]

This is attractive because KeyRecall can eventually model:

\[ P(`\text{performance}`{=tex} `\mid `{=tex}`\text{competencies}`{=tex},
`\text{task features}`{=tex}, `\text{history}`{=tex}) \]

without turning every task feature into a separate latent skill.

**Primary source:** Pavlik, P. I., Cen, H., & Koedinger, K. R. (2009).
_Performance Factors Analysis: A New Alternative to Knowledge Tracing_.
Proceedings of AIED 2009, 531-538.\
https://doi.org/10.3233/978-1-60750-028-5-531

## 5. DAS3H: the closest conceptual match

Choffin, Popineau, Bourda, and Vie developed DAS3H specifically for adaptive
distributed practice where items involve **multiple underlying skills** and
those skills undergo learning and forgetting.

This closely resembles KeyRecall. A D harmonic-minor RH exercise can
simultaneously provide evidence about harmonic-minor topology, scalar motor
organization, RH execution, crossing facility, multi-octave continuation,
direction reversal, and rhythmic evenness.

DAS3H builds on additive-factor models and incorporates the temporal
distribution of prior practice on skills associated with an item. Learning and
forgetting curves may differ by skill. The authors report improved prediction
over comparison educational-data-mining models on three real-world datasets.

This supports three KeyRecall decisions:

1.  exercises may involve multiple competencies;
2.  evidence may transfer through shared competencies; and
3.  elapsed time and forgetting belong inside the learner model rather than only
    in an external due-date mechanism.

DAS3H was developed for educational response data, not continuous piano motor
performance. KeyRecall would adapt the approach rather than apply it unchanged.

**Primary source:** Choffin, B., Popineau, F., Bourda, Y., & Vie, J.-J. (2019).
_DAS3H: Modeling Student Learning and Forgetting for Optimally Scheduling
Distributed Practice of Skills_.\
https://arxiv.org/abs/1905.06873

## 6. Exact-item memory: Half-Life Regression

Settles and Meeder introduced Half-Life Regression (HLR), modeling recall
probability as:

\[ P(`\text{recall}`{=tex}) = 2\^{-`\Delta`{=tex}/h} \]

where (`\Delta`{=tex}) is elapsed time and (h) is estimated memory half-life.

HLR provides precedent for maintaining time-sensitive state for an **exact
item**. Thus D harmonic minor can have its own practice/forgetting history while
the same attempt updates transferable competencies.

This supports:

```text
shared learner state
        +
exact scale-item memory
```

A piano scale is not a vocabulary item and successful execution is not binary
recall. HLR should therefore inform item-memory dynamics rather than serve as
the complete performance model.

**Primary source:** Settles, B., & Meeder, B. (2016). _A Trainable Spaced
Repetition Model for Language Learning_. ACL 2016, 1848-1858.\
https://doi.org/10.18653/v1/P16-1174

**Public implementation:**\
https://github.com/duolingo/halflife-regression

## 7. ACT-R-derived practice optimization

Pavlik and Anderson developed a quantitative memory model and used it to compute
practice schedules. Their optimization balances long-term spacing benefit
against recency, frequency, forgetting/failure risk, and the time cost of
difficult retrieval. As an item becomes more stable, its optimal interval
increases.

This is important to KeyRecall because:

- irregular practice is normal; elapsed time is an input, not a schedule
  violation;
- scheduling can optimize learning value per unit of practice time rather than
  merely determine what is "due"; and
- optimal spacing can change dynamically with the learner.

This supports sessions that require no declared duration:

```text
start practicing
      |
choose useful next exercise
      |
observe performance
      |
update state
      |
choose useful next exercise
      |
     ...
```

**Primary source:** Pavlik, P. I., Jr., & Anderson, J. R. (2008). _Using a Model
to Compute the Optimal Schedule of Practice_. Journal of Experimental
Psychology: Applied, 14(2), 101-117.\
https://doi.org/10.1037/1076-898X.14.2.101

## 8. Adaptive Response-Time-Based Sequencing (ARTS)

ARTS dynamically sequences learning using accuracy, response time, and trials
since last presentation. As measured learning strength increases, spacing
expands.

Piano practice lacks conventional question-response latency, but MIDI offers
richer analogous signals:

```text
accuracy
tempo
inter-onset timing
local hesitation
pauses
restarts
crossing slowdowns
continuity
```

**KeyRecall implication:** adaptive spacing need not depend on explicit
easy/hard ratings. Objective performance can drive sequencing.

**Source:** Mettler, E., Massey, C. M., & Kellman, P. J. (2013). _Adaptive
Response-Time-Based Category Sequencing in Perceptual Learning_. Vision
Research.\
https://pmc.ncbi.nlm.nih.gov/articles/PMC6124487/

## 9. Spacing and distributed practice

Cepeda et al.'s quantitative review examined 839 assessments from 317
experiments. Importantly, the spacing interval producing maximal retention
varies with the desired retention interval.

KeyRecall therefore should not treat a fixed progression such as:

```text
1 day -> 3 days -> 7 days -> 14 days
```

as the fundamental memory model. A dynamic model may produce similar intervals,
but they should emerge from estimated state and scheduling goals.

**Primary source:** Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., &
Rohrer, D. (2006). _Distributed Practice in Verbal Recall Tasks: A Review and
Quantitative Synthesis_. Psychological Bulletin, 132(3), 354-380.\
https://doi.org/10.1037/0033-2909.132.3.354

## 10. Motor learning: Challenge Point Framework

Guadagnoli and Lee's Challenge Point Framework explicitly considers the
interaction between performer skill and task difficulty. The same nominal task
does not create the same learning challenge for performers of different ability.

This supports treating:

```text
tempo
octave count
hands separately/together
direction
rhythmic variation
pattern complexity
```

as **difficulty/context dimensions**, not separate latent skills.

KeyRecall should eventually estimate something closer to:

\[ P(`\text{successful execution}`{=tex} `\mid`{=tex}
`\text{learner state}`{=tex}, `\text{tempo}`{=tex}, `\text{octaves}`{=tex},
`\text{hands}`{=tex}, `\ldots`{=tex}) \]

This suggests a **performance frontier** rather than a single static mastery
percentage.

The framework supports adapting difficulty to ability, but does not establish
one universal target success percentage that KeyRecall should hard-code.

**Primary source:** Guadagnoli, M. A., & Lee, T. D. (2004). _Challenge Point: A
Framework for Conceptualizing the Effects of Various Practice Conditions in
Motor Learning_. Journal of Motor Behavior, 36(2), 212-224.\
https://doi.org/10.3200/JMBR.36.2.212-224

## 11. Contextual interference and interleaving

Contextual-interference research provides a basis for varying tasks rather than
indefinitely blocking repetitions of one task.

A 2024 systematic review and meta-analysis found an overall medium effect on
motor-skill transfer favoring random practice, but with substantial
heterogeneity. Effects were stronger in laboratory settings; the applied-setting
effect was smaller and not statistically significant. The review also identified
methodological weaknesses in much of the underlying literature.

Therefore:

```text
interleaving is promising
```

does not imply:

```text
maximize randomness
```

Carter and Grahn (2016) provide particularly relevant piano-specific work
comparing blocked and interleaved practice in advanced musical performance.

**KeyRecall implication:** the scheduler should eventually contain a
diversity/interleaving pressure, but its strength may depend on ability, task
complexity, acquisition stage, uncertainty, retention need, and practice goal.

**Sources:**

Carter, C. E., & Grahn, J. A. (2016). _Optimizing Music Learning: Exploring How
Blocked and Interleaved Practice Schedules Affect Advanced Performance_.
Frontiers in Psychology, 7, 1251.\
https://doi.org/10.3389/fpsyg.2016.01251

Czyż, S. H., Wójcik, A. M., & Solarská, P. (2024). _The Effect of Contextual
Interference on Transfer in Motor Learning - A Systematic Review and
Meta-Analysis_. Frontiers in Psychology, 15, 1377122.\
https://doi.org/10.3389/fpsyg.2024.1377122

## 12. IRT, MIRT, and adaptive testing

Item Response Theory relates item performance to latent ability and item
characteristics. Multidimensional IRT generalizes ability to a vector.

A common multidimensional logistic form is:

\[ P_i(`\boldsymbol{\theta}`{=tex}) =
`\frac{\exp(\mathbf{a}_i^\prime\boldsymbol{\theta}+d_i)}`{=tex}
{1+`\exp`{=tex}(`\mathbf{a}`{=tex}\_i\^`\prime`{=tex}`\boldsymbol{\theta}`{=tex}+d_i)}
\]

Computerized Adaptive Testing selects items that are especially informative
about current ability estimates. Multidimensional CAT extends this to multiple
traits, with established selection criteria including Fisher information and
mutual information.

IRT/MIRT is probably not KeyRecall's complete longitudinal model because it is
fundamentally a measurement framework rather than a learning-and-forgetting
model. It is, however, highly relevant to:

```text
initial level setting
diagnostic probing
uncertainty reduction
selection of informative exercises
```

An experienced pianist should not have to grind through beginner material
because KeyRecall lacks history. A short adaptive diagnostic can rapidly select
exercises that reduce uncertainty across multiple competencies.

**Sources:**

Reckase, M. D. (2009). _Multidimensional Item Response Theory_. Springer.\
https://doi.org/10.1007/978-0-387-89976-3

van Groen, M. M., Eggen, T. J. H. M., & Veldkamp, B. P. (2016).
_Multidimensional Computerized Adaptive Testing for Classifying Examinees With
Within-Dimensionality_. Applied Psychological Measurement, 40(6).\
https://doi.org/10.1177/0146621616648931

## 13. Contextual bandits: later, not foundational

Contextual-bandit methods can eventually choose among candidate exercises from
learner context and observed reward, balancing exploitation and exploration.

They are potentially attractive once substantial real-world data exists, but
should not be the V1 foundation. Starting there would make the system more
data-hungry, less interpretable, more telemetry-dependent, and harder to
validate pedagogically.

A future policy-learning layer could optimize scheduler weights from
privacy-preserving aggregate data while retaining an interpretable model-based
core.

## 14. Proposed KeyRecall synthesis

The following is a **KeyRecall design synthesis**, not a single published model:

```text
                       LEARNER STATE
                            |
              +-------------+-------------+
              |                           |
     transferable competencies       exact item memory
              |                           |
     logistic / DAS3H-like         HLR / ACT-R-like
              |                           |
              +-------------+-------------+
                            |
                     PERFORMANCE MODEL
                            |
           P(performance | task, learner, history)
                            |
          +-----------------+-----------------+
          |                 |                 |
    learning value     retention need    information value
          |                 |                 |
          +-----------------+-----------------+
                            |
                    difficulty/challenge
                            |
                    diversity/interleave
                            |
                         SCHEDULER
                            |
                    next useful exercise
```

Research precedent by requirement:

KeyRecall requirement Research foundation

---

Persistent transferable state Knowledge tracing, PFA, logistic KT Multi-skill
exercises PFA, DAS3H, multidimensional models Forgetting of shared skills DAS3H
Exact-item memory HLR, ACT-R-derived memory models Irregular elapsed time HLR,
DAS3H, ACT-R scheduling Adaptive difficulty Challenge Point Framework Objective
performance strength ARTS Initial level setting IRT/MIRT, CAT
Information-seeking practice CAT/MIRT Interleaving Contextual-interference
research Future policy optimization Contextual bandits

## 15. Transferable competency vs. exact item state

For:

```text
D harmonic minor RH
```

an attempt can update transferable state such as:

```text
harmonic-minor topology
diatonic scale motor
RH execution
crossing facility
multi-octave continuation
rhythmic evenness
```

while also updating a memory trace for the exact D-harmonic-minor item.

When the pianist later encounters B-flat harmonic minor for the first time,
shared competencies can establish a strong prior without pretending that B-flat
harmonic minor itself has been practiced.

Conversely, D harmonic minor may need reinstatement after a long gap even if
general harmonic-minor competence remains high.

This gives a principled mechanism for both **transfer** and **spaced
retrieval**.

## 16. Scale topology as hierarchical shared knowledge

A provisional hierarchy remains plausible:

```text
SCALE_TOPOLOGY
|
+-- MAJOR
|
`-- MINOR
    +-- NATURAL_MINOR
    +-- HARMONIC_MINOR
    `-- MELODIC_MINOR
```

The hierarchy and numerical transfer strengths are **KeyRecall hypotheses**, not
conclusions established by the sources above.

Tonic should initially remain a task feature rather than twelve independent
mastery variables:

```yaml
pitch_context:
  tonic: D
  form: harmonic_minor
```

Preserving tonic context in observations lets later data determine whether
persistent key-specific effects justify explicit latent parameters.

## 17. Scheduler objective

A useful conceptual utility is:

\[ U(e) = w_L L(e) + w_R R(e) + w_I I(e) + w_G G(e) + w_D D(e) - w_C C(e) \]

where:

- (L(e)): expected learning gain;
- (R(e)): retention/review need;
- (I(e)): information value;
- (G(e)): relevance to selected goals;
- (D(e)): useful diversity/interleaving; and
- (C(e)): excessive difficulty, frustration, or time cost.

This is **not an established canonical formula**. It is a proposed KeyRecall
abstraction whose terms have research foundations:

```text
retention need        spacing / memory models
information value     IRT / adaptive testing
difficulty            Challenge Point / performance models
diversity             contextual interference
learning/time cost    model-based practice optimization
goal relevance        KeyRecall product requirement
```

The scheduler should not require a declared session duration. It should
continually select a useful next exercise, observe performance, update state,
and repeat until the user stops.

## 18. Initial level setting

A research-consistent hybrid approach is:

1.  optionally collect a small amount of self-reported context;
2.  select an exercise with high diagnostic value;
3.  observe rich MIDI performance;
4.  update uncertainty across competencies;
5.  choose the next exercise to distinguish plausible ability levels;
6.  increase difficulty rapidly when evidence supports doing so;
7.  stop explicit assessment once uncertainty is sufficiently low; and
8.  continue refining estimates during normal practice.

This borrows CAT's information-seeking principle without turning KeyRecall into
a standardized test.

## 19. Irregular practice

No special "missed practice" state is required. Elapsed time simply advances.

Depending on the eventual model, time can affect:

```text
exact-item retrievability
shared-skill forgetting features
uncertainty
scheduler priority
recommended challenge
```

A player returning after two days and one returning after two months can be
handled by the same model with different elapsed-time inputs. Early exercises
after a long absence may also have high diagnostic value.

## 20. Telemetry and scientific improvement

The V1 learner model should work **without population telemetry**.

Research-supported priors and conservative assumptions can provide a functional
starting system, while local learner history personalizes it immediately.

Optional privacy-preserving telemetry could later help answer questions such as:

```text
Does phase have a stable independent difficulty effect?
Which keyboard geometries produce persistent crossing difficulty?
How strongly does motor competence transfer between scale forms?
How much should harmonic-minor competence transfer between tonics?
Which MIDI features best predict later retention?
What challenge level produces the best subsequent improvement?
How much interleaving is useful at different ability levels?
```

Population data should calibrate and refine the model rather than be a
prerequisite for building it.

## 21. Research-supported vs. KeyRecall-specific decisions

### Strongly research-supported principles

- distributed practice improves long-term retention;
- useful spacing depends on memory state and retention goals;
- elapsed time and forgetting can be modeled quantitatively;
- adaptive scheduling can outperform fixed scheduling;
- learner state can be inferred from repeated performance;
- tasks can involve multiple underlying skills;
- multidimensional adaptive testing can select informative items;
- task difficulty interacts with performer ability in motor learning;
- interleaving/contextual interference can improve retention or transfer under
  some conditions; and
- objective performance measures can drive adaptive sequencing.

### KeyRecall synthesis decisions

- exact scale items should have memory state separate from transferable
  competencies;
- DAS3H-like shared-skill dynamics and HLR/ACT-R-like item memory should be
  investigated together;
- scale topology should initially be represented hierarchically;
- tonic, phase, and keyboard geometry should initially remain contextual
  features;
- MIDI observations should remain fine-grained even when latent competencies are
  coarse;
- tempo and octave count should parameterize difficulty rather than create new
  skills;
- the scheduler should combine learning, retention, information, goals,
  diversity, and cost;
- explicit session duration should not be required; and
- population telemetry should refine rather than enable the core model.

The second list is a set of design hypotheses subject to simulation and later
empirical revision.

## 22. Recommended modeling sequence

### Stage 1: Formalize state and evidence

Define latent competencies, exact item state, task features, technical-event
opportunities, and MIDI observations without yet choosing complicated update
equations.

### Stage 2: Build an interpretable predictive baseline

Prototype a logistic/DAS3H-inspired performance model. First answer:

```text
Given current learner state and this exercise,
what performance should we expect?
```

### Stage 3: Add item-memory dynamics

Introduce a simple interpretable time-dependent exact-item memory model inspired
by HLR/ACT-R work.

### Stage 4: Simulate learners and scheduling

Test synthetic profiles:

```text
beginner
intermediate
advanced
asymmetric hands
weak topology / strong technique
strong topology / weak technique
long practice gap
irregular short sessions
```

### Stage 5: Add diagnostic information value

Use adaptive-testing principles to improve onboarding and uncertainty-driven
practice.

### Stage 6: Add challenge optimization

Model performance as tempo/octave/hand difficulty changes.

### Stage 7: Add interleaving constraints

Introduce diversity conservatively and test its interaction with difficulty.

### Stage 8: Calibrate from optional telemetry

Only after real data exists consider splitting competencies, estimating
population priors, learning transfer coefficients, learning scheduler weights,
or adding contextual-bandit methods.

## 23. Immediate design questions

### Latent competency vocabulary

Current provisional candidates:

```text
scale topology / scale-form knowledge
diatonic scale motor
RH scale execution
LH scale execution
crossing facility
multi-octave continuation
direction reversal
hands-together coordination
rhythmic evenness
```

These should be challenged against identifiability and available evidence.

### Observation model

Define how MIDI becomes evidence for:

```text
pitch accuracy
fingering adherence
timing/evenness
hesitation
continuity
crossing execution
turnaround execution
synchronization
```

### Item identity

What unit owns a memory trace?

```text
scale form + tonic
scale form + tonic + hand
scale form + tonic + hand + octave configuration
```

Too coarse loses specificity; too fine fragments history.

### Transfer structure

How should evidence transfer between hands, directions, scale forms, tonics,
octave counts, and hands-separate/hands-together conditions?

### Difficulty model

At minimum:

```text
tempo
octaves
hands
direction
```

Phase and keyboard geometry are plausible additional contextual predictors.

## 24. Working research position

> KeyRecall should use an interpretable, multidimensional learner model that
> combines shared transferable competencies with time-sensitive exact-item
> memory. Rich MIDI observations should update that state through an evidence
> model. Scheduling should dynamically balance retention, expected learning,
> diagnostic information, task difficulty, learner goals, and useful
> interleaving. The initial system should be grounded in established
> learning-science and psychometric models and should not depend on population
> telemetry to function.

The closest existing model family for shared-skill/forgetting is DAS3H and
related logistic knowledge-tracing work. HLR and ACT-R-derived scheduling
provide strong foundations for exact-item memory and time-dependent practice.
IRT/MIRT and adaptive testing provide a mathematical foundation for rapid level
setting and uncertainty reduction. Challenge Point and contextual-interference
research constrain motor difficulty and practice ordering.

These traditions do not prescribe one final KeyRecall equation. They provide a
defensible foundation from which the learner model and scheduler can be
designed, simulated, and refined.

## 25. Core reading list

- Pavlik, Cen, & Koedinger (2009), _Performance Factors Analysis: A New
  Alternative to Knowledge Tracing_.
  https://doi.org/10.3233/978-1-60750-028-5-531
- Choffin et al. (2019), _DAS3H_. https://arxiv.org/abs/1905.06873
- Settles & Meeder (2016), _A Trainable Spaced Repetition Model for Language
  Learning_. https://doi.org/10.18653/v1/P16-1174
- Pavlik & Anderson (2008), _Using a Model to Compute the Optimal Schedule of
  Practice_. https://doi.org/10.1037/1076-898X.14.2.101
- Cepeda et al. (2006), _Distributed Practice in Verbal Recall Tasks_.
  https://doi.org/10.1037/0033-2909.132.3.354
- Mettler, Massey, & Kellman (2013), _Adaptive Response-Time-Based Category
  Sequencing in Perceptual Learning_.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC6124487/
- Guadagnoli & Lee (2004), _Challenge Point_.
  https://doi.org/10.3200/JMBR.36.2.212-224
- Carter & Grahn (2016), _Optimizing Music Learning_.
  https://doi.org/10.3389/fpsyg.2016.01251
- Czyż, Wójcik, & Solarská (2024), contextual-interference systematic
  review/meta-analysis. https://doi.org/10.3389/fpsyg.2024.1377122
- Reckase (2009), _Multidimensional Item Response Theory_.
  https://doi.org/10.1007/978-0-387-89976-3
- van Groen, Eggen, & Veldkamp (2016), multidimensional computerized adaptive
  testing. https://doi.org/10.1177/0146621616648931
