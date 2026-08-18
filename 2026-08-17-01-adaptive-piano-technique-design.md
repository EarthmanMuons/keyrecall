# Adaptive Piano Technique Practice

## High-Level Product and Research Design

**Status:** Exploratory design document\
**Date:** August 17, 2026\
**Working scope:** Piano scales and arpeggios\
**Purpose:** Preserve the current product vision, pedagogical rationale,
architecture, research foundations, open questions, and near-term design
direction before moving into detailed domain modeling and
implementation.

------------------------------------------------------------------------

## 1. Executive Summary

This project explores a deliberately narrow but potentially very deep
piano-practice application: an adaptive system devoted to scales,
arpeggios, and closely related technical patterns.

The central product idea is not merely to teach scales, score MIDI
performances, track tempos, or implement conventional spaced repetition.
Existing products already do substantial pieces of those jobs. The
opportunity is to close the loop:

> **Teach -\> observe -\> diagnose -\> schedule -\> reassess -\>
> increase difficulty -\> retain.**

The application should know what the pianist can play because it has
observed the pianist playing it. It should maintain a longitudinal model
of the player's technical capabilities, uncertainty, retention, current
practice state, and goals. It should then choose the next exercise
automatically.

The desired primary interaction is therefore extremely simple:

> **Open the app. Play what it gives you. Continue for as long as you
> want. Stop whenever you want.**

The sophistication lives underneath that interaction.

The scheduler may use principles from spaced practice, contextual
interference/interleaving, motor learning, adaptive assessment,
knowledge tracing, prerequisite graphs, challenge-point theory, and
eventually empirical population data. None of those mechanisms
individually defines the product. A useful description is:

> **An adaptive technical-practice scheduler with memory.**

The domain remains intentionally constrained. It does not need to become
a general piano-learning application with repertoire, sight reading, ear
training, video lessons, or theory courses. Scales and arpeggios alone
can support years of progression: individual hands, hands together,
multiple octaves, major/minor forms, modes, tempo development,
articulation and rhythmic variants, contrary motion, arpeggios and
inversions, interval scales, and advanced technical regimens.

A major architectural principle is to distinguish **observable
exercises** from **latent skills or knowledge components**. "C major,
hands together, two octaves at 96 BPM" is an exercise. It provides
evidence about multiple underlying capabilities such as scale-pattern
familiarity, right- and left-hand crossings, hand synchronization,
multi-octave continuation, direction reversal, timing evenness, and
tempo tolerance. Those capabilities are shared by many exercises and
therefore create transfer relationships across keys and exercise types.

The initial system can be built from existing research, explicit
pedagogical assumptions, educated engineering judgment, and personal
experimentation. It should **not** be blocked on expert surveys, a
formal consensus process, a large research study, or a pre-existing
telemetry corpus. Assumptions should instead be documented and made
testable.

Optional, privacy-preserving telemetry can later improve the
population-level model. The personalized learner model itself can remain
completely local and functional without telemetry.

------------------------------------------------------------------------

## 2. Product Thesis

### 2.1 The problem

Scale and arpeggio practice presents a surprisingly large
self-management problem.

A pianist must decide:

-   what key to practice;
-   which scale or arpeggio form;
-   which hand configuration;
-   how many octaves;
-   what tempo;
-   whether to work on accuracy or speed;
-   whether to repeat an exercise;
-   when to stop repeating it;
-   when to revisit a previously learned skill;
-   which neglected skills are decaying;
-   when to introduce hands together;
-   when to introduce longer ranges;
-   when to add rhythmic or articulation variations;
-   how to balance acquisition, development, and maintenance;
-   how to respond to a recurring localized technical weakness;
-   how to distribute practice among immediate goals and long-term
    technical development.

Existing applications frequently help with one subset of these
decisions. The proposed application should make the decisions coherently
from longitudinal performance evidence.

### 2.2 Core value proposition

The user should generally choose **outcomes and areas of focus**. The
scheduler should choose **exercises**.

Examples of user intent:

-   Practice everything.
-   Focus on minor scales.
-   Learn all major scales hands together at 120 BPM.
-   Prepare the technical requirements for a particular exam syllabus.
-   Begin exploring modes.
-   Work on arpeggios.
-   Free-practice F-sharp harmonic minor right now.

The default should remain autonomous. The app should not recreate the
cognitive burden of practice planning through a large matrix of
checkboxes and routine editors.

### 2.3 Product boundary

The application is specifically **not** intended to become:

-   a repertoire-learning application;
-   a sight-reading course;
-   an ear-training suite;
-   a general music-theory application;
-   a video piano teacher;
-   a sheet-music library;
-   a generic practice timer;
-   a generic SRS application.

A narrow product boundary is a strength. The technical domain itself is
sufficiently deep to support long-term use.

------------------------------------------------------------------------

## 3. Competitive Landscape

A preliminary competitor sweep suggests that nearly every component
exists somewhere, but the complete adaptive loop remains unusual.

### 3.1 Piano Scale Coach

Piano Scale Coach is especially relevant to **initial acquisition and
progression**. Its model emphasizes clean repetitions, incremental
construction, hands separately before hands together, and tempo
progression.

This validates several ideas for acquisition:

-   construct difficult movements in manageable pieces;
-   use blocked repetition when a movement is genuinely new;
-   require evidence of repeatability before progressing;
-   increase difficulty only after successful execution.

The opportunity is to take those ideas beyond a linear "complete this,
then advance" curriculum and feed every result into a longitudinal
adaptive scheduler.

### 3.2 Pianolympics

Pianolympics is the strongest direct reference for **objective
MIDI-based technical assessment** found so far. It advertises more than
1,500 scales and arpeggios and analyzes details such as timing,
evenness, accuracy, hands separately/together, dynamics, articulation,
synchronization, and balance.

Reference:

-   https://pianolympics.net/

The implication is important: simple pitch correctness is unlikely to be
sufficient differentiation. Rich performance analysis is becoming
feasible and expected.

### 3.3 Scale Study

Scale Study is notable for treating scale progress as an evolving
relationship between **key, correctness, and tempo**. It uses MIDI,
confirms correct scales, records clean tempo, and tracks progress over
time.

References:

-   https://scalestudy.app/en/
-   https://apps.apple.com/us/app/scale-study-tempo-practice/id6758663846

Its "performance envelope" concept is useful. The proposed system should
avoid reducing a skill to an arbitrary single mastery percentage when it
can instead estimate things such as:

-   reliable tempo;
-   best observed clean tempo;
-   performance variability;
-   delayed first-attempt reliability;
-   confidence/uncertainty in those estimates.

### 3.4 Piano Marvel / Scale Ninja

Piano Marvel is a broad learning environment, but Scale Ninja and Piano
Marvel's technical-practice guidance are important precedents. Their
material covers progressive scale development and advanced approaches
such as rhythmic variants, grouped patterns, isolated crossings,
incremental expansion, and advanced scale forms.

Useful reading:

-   https://pianomarvel.com/en/article/how-to-master-my-scales/1000
-   https://pianomarvel.com/en/article/how-to-gain-speed-with-your-scales
-   https://pianomarvel.com/en/feature/sasr

Piano Marvel also demonstrates that automated selection based on prior
performance can work as a user experience, even though its SASR system
addresses sight reading rather than this proposed technical domain.

### 3.5 Piano Fitness

Piano Fitness is an especially relevant adjacent project because it
explicitly focuses on technical development, MIDI feedback, scales,
arpeggios, chord inversions, and structured progression.

References:

-   https://piano.fitness/
-   https://brylie.online/projects/piano-fitness/

This should remain on the competitor watch list.

### 3.6 The Hanon Method

The Hanon Method is another 2026 entrant emphasizing MIDI-measured
technique practice, precision, tempo stability, and long-view practice
history.

Reference:

-   https://thehanonmethod.com/

This is evidence that "measured technical practice" is becoming an
identifiable product category.

### 3.7 Scale Practice

The open-source Scale Practice application randomizes scales and
arpeggios but explicitly does not listen or provide feedback.

References:

-   https://f-droid.org/en/packages/com.scalepractice/
-   https://play.google.com/store/apps/details?id=com.scalepractice

This is useful as a conceptual "before" case: scheduling/order without
performance telemetry.

### 3.8 Other adjacent applications

Other applications discovered during the sweep include Scale Navi,
ScaleCoach, Piano Scales & Chords, Keyflow, Any Scale, and broader piano
practice tools. These reinforce the need to differentiate at the
**adaptive learner-model/scheduler** level rather than merely by
providing scales, fingerings, MIDI input, a metronome, or progress
charts.

### 3.9 Current market-gap hypothesis

Existing products tend to answer one or two of these questions well:

1.  **How do I learn this scale?**
2.  **How well did I just play it?**
3.  **What should I revisit?**

The proposed system should connect all three:

> **What should this particular pianist do next, given everything the
> system currently knows about their technique, retention, uncertainty,
> goals, and current practice state?**

That remains the strongest candidate for differentiated value.

------------------------------------------------------------------------

## 4. User Experience Principles

### 4.1 Start playing immediately

The default workflow should minimize configuration and navigation.

A mature user might see:

> C major · HT · 4 octaves\
> ♩ = 104

They play.

The app evaluates the attempt and immediately chooses the next exercise.

### 4.2 Sessionless by design

The user should not need to declare:

> "I have 20 minutes."

The atomic scheduling unit is an **exercise**, not a preplanned session.

Conceptually:

``` text
open app
    ↓
select highest-value exercise
    ↓
perform
    ↓
analyze
    ↓
update models
    ↓
select next exercise
    ↓
...
```

If the user stops after 7, 11, 23, or 50 minutes, nothing is incomplete.
The next time the app opens, it recalculates priorities from the current
state.

A scheduler may look ahead a few exercises to create desirable
interleaving or avoid repetition, but any queue should be soft and
continuously revisable.

### 4.3 No "behind" state

Irregular practice frequency is normal.

A user may practice on Monday, Tuesday, Sunday, disappear for three
weeks, and return on Thursday. The application should not present a pile
of overdue assignments.

Elapsed time changes predicted retention and uncertainty. On return, the
scheduler selects informative and useful exercises and rapidly
recalibrates.

The user is never "behind."

### 4.4 Repetition must have a reason

Do not impose a universal "seven repetitions" rule.

During acquisition, repeated correct execution may be pedagogically
useful. During maintenance, a single first-attempt performance after a
long interval may provide more useful evidence than seven consecutive
repetitions.

Principle:

> **Repetition is prescribed because repetition itself is useful or
> because the model needs additional evidence, not because every
> exercise has an arbitrary repetition count.**

### 4.5 Make the intelligence legible

Occasional lightweight explanations may increase trust:

-   *21-day review*
-   *Working on left-hand crossings*
-   *New challenge*
-   *Building hands-together coordination*
-   *Checking retention after your break*

This is particularly important when an experienced pianist receives
apparently easy material.

### 4.6 Respect expert time

If an advanced pianist demonstrates an easy skill immediately, move on.

The system should aggressively skip or infer prerequisite mastery rather
than requiring explicit completion of every beginner node.

------------------------------------------------------------------------

## 5. Placement and Continuous Calibration

### 5.1 Avoid a conventional placement exam

A lengthy formal assessment creates friction before the user has
experienced value.

Instead, collect only a rough prior such as:

-   New to scales
-   Some experience
-   Comfortable with most major/minor scales
-   Advanced technical practice

Then begin playing.

### 5.2 Placement as adaptive assessment

The system should select early exercises partly for **information
gain**.

For an advanced self-report, an initial exercise might be:

> C major · HT · 4 octaves · 100 BPM

If the performance is excellent, there is no need to test C-major RH one
octave at 60 BPM.

Those prerequisite states can become **inferred mastery** rather than
demonstrated mastery.

The next exercise should test a dimension still uncertain, perhaps
black-key navigation, harmonic minor fingering, or arpeggio
coordination.

### 5.3 Calibration never really ends

A pianist's experience is multidimensional. Someone may have:

-   advanced major scales;
-   intermediate harmonic minors;
-   weak melodic minors;
-   excellent arpeggios;
-   little contrary-motion experience;
-   no interval-scale experience.

There is no useful single "Level 8."

Initial calibration merely establishes enough information to produce a
useful practice sequence. Future practice continues to refine the model.

### 5.4 Long absences

After a long gap, uncertainty should increase.

The application can quietly choose several high-information exercises
and recalibrate while the user practices. No separate "welcome back
placement test" is necessary.

------------------------------------------------------------------------

## 6. Exercise Model vs. Skill Model

This is one of the most important architectural distinctions.

### 6.1 An exercise is an observable task

An exercise can be represented parametrically:

``` text
tonic        = C
collection   = major
pattern      = scale
hands        = together
motion       = parallel
octaves      = 2
direction    = up_down
tempo        = 96
rhythm       = even
articulation = legato
```

The exercise generator produces something the pianist can actually
perform.

### 6.2 A skill is a latent capability

The exercise provides evidence about multiple underlying capabilities,
for example:

``` text
C-major pattern familiarity
RH major-scale fingering
LH major-scale fingering
RH thumb crossing
LH thumb crossing
parallel-hand synchronization
multi-octave continuation
direction reversal
rhythmic evenness
tempo control
```

Those capabilities are not directly observed. They are inferred from
performance across exercises.

### 6.3 Why this matters

If the pianist struggles with left-hand thumb crossings in C, G, D, and
A minor, the system should become increasingly confident that this is a
generalized technical weakness.

A remedial exercise can then be selected because it loads heavily on
that capability, not merely because "C major is due."

### 6.4 Bipartite mental model

The domain can be thought of as a relationship between latent skills and
observable exercises:

``` text
LATENT SKILLS                         EXERCISES

RH thumb crossing ───────────┬────── C major RH
                             ├────── G major RH
scale evenness ──────────────┼────── D major RH
                             │
C-major pattern ─────────────┴────── C major HT
                                    │
LH thumb crossing ──────────────────┤
                                    │
hand synchronization ───────────────┘
```

This resembles the **knowledge-component/Q-matrix** perspective in
intelligent tutoring systems.

------------------------------------------------------------------------

## 7. Candidate Knowledge-Component Ontology

The initial ontology should remain small enough to understand and
revise.

### 7.1 Scale-specific components

Examples:

-   C-major pitch/movement topology
-   G-major pitch/movement topology
-   D-major pitch/movement topology
-   F-major pitch/movement topology
-   A-natural-minor pitch/movement topology
-   harmonic-minor alteration pattern
-   melodic-minor directional alteration pattern

### 7.2 Fingering and motor components

Examples:

-   RH 3→1 ascending crossing
-   RH 1→3 descending crossing
-   LH 1→3 ascending crossing
-   LH 3→1 descending crossing
-   RH fourth-finger scale patterns
-   LH fourth-finger scale patterns
-   multi-octave continuation
-   direction reversal
-   arpeggio thumb-under movement
-   arpeggio hand repositioning

### 7.3 Coordination components

Examples:

-   parallel-hand synchronization
-   contrary-motion synchronization
-   asymmetric hand transitions
-   synchronized direction reversal
-   balanced hand timing

### 7.4 Performance-control components

Examples:

-   pulse stability
-   subdivision evenness
-   tempo tolerance
-   velocity consistency
-   dynamic balance
-   articulation control

### 7.5 Generalized schemata

Potential higher-order inferred components:

-   major-scale fingering schema
-   minor-scale fingering schema
-   white-key navigation
-   black-key navigation
-   thumb-crossing fluency
-   rapid direction change
-   hand synchronization
-   technical pattern transfer

These should be treated cautiously. The application should earn evidence
that such generalized constructs predict performance rather than merely
asserting them.

------------------------------------------------------------------------

## 8. C Major as a Longitudinal Example

C major should not be one skill that simply increases in level.

### 8.1 Initial acquisition

Right hand:

``` text
C-D-E
C-D-E-F
C-D-E-F-G
C-D-E-F-G-A-B-C
```

with displayed fingering:

``` text
1 2 3 1 2 3 4 5
```

Then descending, followed by continuous up/down motion.

The initial objective is reliable motor construction, not maximum tempo.

### 8.2 Left hand

Left hand is a distinct motor task while sharing pitch-pattern knowledge
and some general scale schema.

Differences between RH and LH performance begin to inform player-level
technical estimates.

### 8.3 Hands together

Hands together should be a separate capability dependent on adequate
evidence from both hands.

It introduces new observables:

-   hand synchronization;
-   one hand leading or lagging;
-   asymmetric errors;
-   relative velocity;
-   synchronized hesitation;
-   crossing-related coordination failures.

### 8.4 Two and four octaves

Longer range is not simply "more of the same." It changes continuation
and turnaround behavior.

A two-octave task may require isolated work around the upper-octave
continuation before reintegration into the complete scale.

### 8.5 Later transformations

Over months or years, C major can support:

-   one, two, and four octaves;
-   hands separate and together;
-   parallel and contrary motion;
-   tempo development;
-   straight rhythm;
-   dotted/reverse-dotted rhythms;
-   grouped accents;
-   legato/staccato;
-   scales in thirds;
-   scales in sixths;
-   scales in tenths;
-   tonic arpeggios;
-   arpeggio inversions;
-   broken-chord patterns;
-   advanced regimen-derived patterns;
-   Russian-style technical patterns.

Some should be distinct skills. Others should be transformations applied
to established base skills. Determining that boundary is an important
domain-modeling task.

------------------------------------------------------------------------

## 9. Why C, G, D, F, and A Minor Are a Useful First Model

The next design exercise should model these keys simultaneously.

They expose different transfer relationships:

### C major

Good evidence for:

-   basic white-key navigation;
-   common crossings;
-   timing and evenness;
-   hand synchronization.

Poor evidence for:

-   black-key navigation.

### G major

Introduces a single black key while retaining a relatively familiar
major-scale structure.

### D major

Increases black-key involvement and provides stronger evidence about
transfer of the major-scale schema.

### F major

Introduces distinctive fingering behavior, especially in the right hand,
and helps test whether "major-scale fluency" is truly generalized.

### A natural minor

Shares the same pitch classes as C major but starts, turns, and fingers
the sequence differently.

This is particularly informative. Strong C-major performance combined
with weak A-natural-minor performance helps distinguish pitch-set
familiarity from learned motor sequencing.

------------------------------------------------------------------------

## 10. Performance Model

The MIDI stack should produce rich local observations from every
attempt.

### 10.1 Basic correctness

-   expected notes;
-   correct notes;
-   missing notes;
-   extra notes;
-   wrong notes;
-   sequence errors;
-   restarts;
-   direction errors.

### 10.2 Timing

-   observed tempo;
-   inter-onset intervals;
-   timing variance;
-   local acceleration/deceleration;
-   pulse stability;
-   hesitation magnitude;
-   hesitation location;
-   turnaround timing;
-   crossing timing.

### 10.3 Hands-together metrics

-   median LH/RH onset difference;
-   distribution of hand asynchrony;
-   which hand tends to lead;
-   synchronization around crossings;
-   synchronization around reversals.

### 10.4 Velocity and control

Where MIDI hardware provides useful velocity data:

-   velocity variance;
-   left/right balance;
-   local accents;
-   unwanted dynamic spikes around crossings;
-   consistency across repetitions.

Velocity should be interpreted carefully because keyboard actions and
MIDI velocity curves vary substantially among instruments.

### 10.5 Fingering limitation

Ordinary MIDI does **not** identify which finger played a note.

The app can:

-   display proper fingering;
-   teach fingering explicitly;
-   infer probable crossing-related problems from timing and error
    location;

but should not claim to verify fingering directly.

------------------------------------------------------------------------

## 11. Learner Model

The learner model should distinguish estimated capability from
certainty.

Conceptually:

``` text
RH thumb crossing
  competence: 0.81
  uncertainty: 0.07

parallel coordination
  competence: 0.68
  uncertainty: 0.13
```

The exact mathematical representation remains open.

Important dimensions include:

-   estimated long-term competence;
-   uncertainty/confidence;
-   reliable tempo;
-   frontier tempo;
-   retention estimate;
-   history of first-attempt performance;
-   local error patterns;
-   transfer evidence from related exercises.

A mature skill might be represented as a **performance envelope**, not a
scalar mastery score.

------------------------------------------------------------------------

## 12. Session-State Model

Observed performance is not identical to long-term competence.

A useful conceptual decomposition is:

``` text
observed performance =
    long-term skill state
  + current session state
  + task difficulty
  + noise
```

### 12.1 Warm-up

A poor first attempt followed immediately by normal performance across
multiple skills may indicate warm-up rather than forgotten technique.

### 12.2 Fatigue

If timing, velocity control, and error rates deteriorate across many
unrelated skills late in practice, the system should consider fatigue
rather than concluding that all affected skills have decayed.

### 12.3 Why this matters

Without a transient session model, an adaptive system can overreact to
temporary performance changes and make inappropriate long-term
scheduling decisions.

------------------------------------------------------------------------

## 13. Acquisition, Development, and Maintenance

A skill's relationship with the learner should affect practice
methodology.

### 13.1 Acquisition

The movement is still being constructed.

Characteristics:

-   more visual guidance;
-   explicit fingering;
-   lower tempo;
-   fragments;
-   blocked repetition;
-   more immediate repetition;
-   forgiving timing thresholds.

### 13.2 Development

The basic movement exists but capability is expanding.

Characteristics:

-   increasing tempo;
-   longer ranges;
-   reduced visual scaffolding;
-   greater interleaving;
-   rhythmic variants;
-   articulation variants;
-   deliberate challenge near the player's frontier.

### 13.3 Maintenance

The skill is reliably available.

Characteristics:

-   infrequent delayed testing;
-   emphasis on first-attempt performance;
-   minimal unnecessary repetition;
-   dynamically expanding or contracting review intervals;
-   occasional variation to test robustness and transfer.

This state distinction helps avoid treating a complex motor skill like a
flashcard.

------------------------------------------------------------------------

## 14. Scheduler / Policy

The scheduler is the core product intelligence.

For every completed exercise, it should decide what to do next.

A conceptual utility function might consider:

``` text
utility(exercise) =
    retention_need
  + expected_learning_value
  + prerequisite_value
  + diagnostic_information
  + user_goal_weight
  + technique_weakness_weight
  + contextual_interference_value
  - fatigue_cost
  - redundancy_cost
  - excessive_difficulty_cost
```

This is a conceptual decomposition, not a validated equation.

### 14.1 Retention need

How uncertain are we that an established capability remains available
after elapsed time?

### 14.2 Expected learning value

How much improvement might this task reasonably produce?

### 14.3 Prerequisite value

Will improving this skill unlock or improve several downstream
capabilities?

### 14.4 Diagnostic information

Will this exercise resolve an important uncertainty in the learner
model?

This is especially important during initial placement and after long
gaps.

### 14.5 User-goal relevance

Does the exercise advance an explicit user objective?

### 14.6 Weakness targeting

Does the exercise strongly load a capability that appears systematically
weak?

### 14.7 Contextual interference

Would switching to this task create useful reconstruction/interference
at the learner's current stage?

### 14.8 Fatigue and redundancy

Has the user already overloaded the same movement? Is performance
declining globally? Would another repetition add little information or
learning value?

------------------------------------------------------------------------

## 15. Spaced Practice Without Flashcard Dogma

Conventional SRS provides useful concepts but should not dictate the
design.

A motor skill is not a vocabulary item.

The system should care about:

-   elapsed time;
-   delayed first-attempt success;
-   historical reliability;
-   task difficulty;
-   current tempo;
-   transfer among related skills;
-   uncertainty;
-   acquisition vs. maintenance state.

There should be no fixed universal sequence such as:

``` text
1 day -> 3 days -> 7 days -> 14 days
```

Instead, time-dependent retention should be estimated and updated from
evidence.

Importantly, piano-specific research has not always reproduced the large
spacing effects familiar from declarative-memory research. The 2017
paper *Lack of spacing effects during piano learning* is an important
caution against importing flashcard results uncritically.

Reference:

-   https://journals.plos.org/plosone/doi?id=10.1371/journal.pone.0182986

------------------------------------------------------------------------

## 16. Interleaving and Contextual Interference

Interleaving should be treated as an adjustable scheduling strategy, not
an unconditional rule.

A plausible progression:

``` text
NEW ACQUISITION

C RH
C RH
C RH
C RH

EARLY INTERLEAVING

C RH
C LH
C RH
C LH

ESTABLISHED PRACTICE

C RH
G LH
D HT
F# minor RH
C arpeggio
Bb HT
```

The scheduler can increase contextual interference as skill stability
increases.

Recent meta-analyses are useful but also caution against simplistic
claims. High contextual interference has shown beneficial overall
effects for motor-skill retention and transfer, but effects are
heterogeneous and applied settings can show much smaller effects than
laboratory tasks.

Useful research:

-   Czyż et al. (2024), *High contextual interference improves retention
    in motor learning: systematic review and meta-analysis*\
    https://www.nature.com/articles/s41598-024-65753-3

-   Czyż et al. (2024), *The effect of contextual interference on
    transfer in motor learning - a systematic review and meta-analysis*\
    https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2024.1377122/full

-   Ammar et al. (2024), *The Effects of Contextual Interference
    Learning on the Acquisition and Relatively Permanent Gains in
    Skilled Performance*\
    https://link.springer.com/article/10.1007/s10648-024-09892-z

The correct product interpretation is therefore:

> Interleaving is a candidate mechanism whose intensity should depend on
> learner capability, task complexity, and empirical outcomes.

------------------------------------------------------------------------

## 17. Challenge Point and Functional Difficulty

Guadagnoli and Lee's **Challenge Point Framework** is highly relevant.

The central idea is that useful task difficulty depends on both nominal
task difficulty and the performer's skill level. A task that is trivial
for an advanced pianist may overwhelm a novice at a different
configuration.

Reference:

-   Guadagnoli & Lee (2004), *Challenge Point: A Framework for
    Conceptualizing the Effects of Various Practice Conditions in Motor
    Learning*\
    DOI: 10.3200/JMBR.36.2.212-224\
    https://www.researchgate.net/publication/8574634_Challenge_Point_A_Framework_for_Conceptualizing_the_Effects_of_Various_Practice_Conditions_in_Motor_Learning

A scheduler therefore should not simply maximize probability of success.

If estimated first-attempt probabilities were hypothetically:

``` text
C major HT @ 72   P(clean) = .99
C major HT @ 96   P(clean) = .94
C major HT @ 116  P(clean) = .76
C major HT @ 144  P(clean) = .18
```

the 72-BPM exercise may provide little learning value, while 144 BPM may
be excessively difficult. A useful challenge region may lie somewhere
between.

The optimal region should be treated as an empirical question rather
than hard-coded as a universal probability.

------------------------------------------------------------------------

## 18. Intelligent Tutoring and Knowledge Tracing

### 18.1 Bayesian Knowledge Tracing

Corbett and Anderson's work on knowledge tracing provides an important
conceptual precedent: infer a latent learner state from observable task
performance and use that estimate to individualize subsequent exercises.

Reference:

-   Corbett & Anderson (1995), *Knowledge Tracing: Modeling the
    Acquisition of Procedural Knowledge*\
    User Modeling and User-Adapted Interaction, 4, 253-278.

A useful overview and reading list is available through Ryan Baker's
educational-data-mining course materials:

-   https://learninganalytics.upenn.edu/ryanbaker/EDM2017/course-schedule-2017.html

Vanilla BKT is too simple for this application because it generally
models binary learned/unlearned states and correct/incorrect
observations. The conceptual structure is nevertheless valuable.

### 18.2 Knowledge components and Q-matrix thinking

The domain should be decomposed into latent components that many
exercises can load upon.

This makes transfer explicit and gives the learner model interpretable
state.

### 18.3 Prefer interpretability initially

A deep neural knowledge-tracing model might eventually predict
performance well, but an opaque model is not the appropriate starting
point.

Interpretability matters because the product should be able to support
statements such as:

> "This exercise was selected because your left-hand crossings are less
> stable."

The initial model should therefore favor explicit, inspectable
assumptions.

------------------------------------------------------------------------

## 19. Trainable Retention Models

Duolingo's **Half-Life Regression** is a useful example of learning a
retention model from longitudinal user data.

Reference:

-   Settles & Meeder (2016), *A Trainable Spaced Repetition Model for
    Language Learning*\
    https://aclanthology.org/P16-1174/

Code/data:

-   https://github.com/duolingo/halflife-regression

The important transferable idea is not the exact formula. It is that
retention can be modeled as a trainable individual/item property rather
than a fixed review schedule.

Pavlik and colleagues' work is also relevant to quantitatively optimized
scheduling:

-   Eglington & Pavlik (2020), *Optimizing practice scheduling requires
    quantitative tracking of individual item performance*\
    https://www.nature.com/articles/s41539-020-00074-4

These models arise largely from declarative or educational learning and
should therefore inform rather than dictate the motor-learning
implementation.

------------------------------------------------------------------------

## 20. Adaptive Exercise Selection and Exploration vs. Exploitation

The scheduler faces an exploration/exploitation problem.

**Exploitation:** choose an exercise because an identified weakness is
likely to benefit from practice.

**Exploration:** choose an exercise because the learner's capability is
uncertain and observing it would improve the model.

This is related to multi-armed/contextual-bandit and sequential
decision-making approaches in intelligent tutoring.

The first version should not require a learned reinforcement-learning
policy. A transparent heuristic utility function is preferable until
real data exist.

The eventual architecture should nevertheless preserve enough
information to support more sophisticated policies later.

------------------------------------------------------------------------

## 21. Piano-Specific Adaptive-Practice Research

The paper most directly aligned with the product concept found so far
is:

-   Moringen, Rüttgers, Zintgraf, Friedman & Ritter (2021), *Optimizing
    piano practice with a utility-based scaffold*\
    https://arxiv.org/abs/2106.12937

The authors propose dynamically choosing piano practice modes according
to expected utility for the individual learner, using learner skill and
practice history and modeling expected improvement with a Gaussian
process.

This is an important conceptual precedent for the idea that the
scheduler should ask:

> **Which available practice activity has the greatest expected utility
> for this learner now?**

It deserves a deeper read as the mathematical design evolves.

------------------------------------------------------------------------

## 22. Architecture

The current high-level architecture is:

``` text
┌───────────────────────────────────┐
│ DOMAIN MODEL                      │
│                                   │
│ latent skills / KCs               │
│ prerequisites                     │
│ transfer relationships            │
│ exercise ↔ skill mappings         │
└──────────────────┬────────────────┘
                   │
                   ▼
┌───────────────────────────────────┐
│ LEARNER MODEL                     │
│                                   │
│ long-term competence estimates    │
│ uncertainty                       │
│ retention state                   │
│ performance envelopes             │
│ individualized transfer evidence  │
└──────────────────▲────────────────┘
                   │ observations
┌──────────────────┴────────────────┐
│ PERFORMANCE MODEL                 │
│                                   │
│ MIDI event interpretation         │
│ accuracy                          │
│ timing/evenness                   │
│ synchronization                   │
│ velocity/control                  │
│ localized errors                  │
│ tempo                             │
└───────────────────────────────────┘

┌───────────────────────────────────┐
│ SESSION MODEL                     │
│                                   │
│ warm-up                           │
│ fatigue                           │
│ current readiness                 │
│ transient performance state       │
└───────────────────────────────────┘

                   │
                   ▼
┌───────────────────────────────────┐
│ SCHEDULER / POLICY                │
│                                   │
│ retention need                    │
│ expected learning value           │
│ challenge point                   │
│ diagnostic information            │
│ user goals                        │
│ contextual interference           │
│ prerequisite value                │
│ fatigue / redundancy              │
└──────────────────┬────────────────┘
                   │
                   ▼
             NEXT EXERCISE
                   │
                   ▼
┌───────────────────────────────────┐
│ EXERCISE GENERATOR                │
│                                   │
│ tonic / collection / pattern      │
│ hands / motion / octaves          │
│ direction / tempo                 │
│ rhythm / articulation             │
│ visual guidance / fingering       │
└───────────────────────────────────┘
```

Supporting systems:

``` text
LOCAL HISTORY
    complete personal longitudinal data

OPTIONAL RESEARCH TELEMETRY
    minimized pseudonymous observations

ASSUMPTION REGISTRY
    why pedagogical/scheduler decisions exist
```

------------------------------------------------------------------------

## 23. Local-First Privacy Architecture

The personalized learner model does **not** require a server.

The device can locally store:

-   exercise history;
-   learner state;
-   scheduler state;
-   performance summaries;
-   goals;
-   preferences;
-   retention estimates;
-   local model parameters.

A user who opts out of telemetry should retain full adaptive
functionality.

### 23.1 Two distinct learning systems

**The app learns the individual:** local.

**The project learns how pianists learn in aggregate:** optional
telemetry.

Keeping these conceptually separate is important.

### 23.2 Avoid raw MIDI telemetry by default

The device can transform raw MIDI into derived observations and then
discard the raw event stream.

Potential research event:

``` text
pseudonymous_install_id
model_version
exercise_definition_id

prior_skill_estimates
prior_uncertainty

performance_summary:
    note_accuracy
    timing_variance
    tempo
    crossing_delay
    hand_asynchrony

elapsed_since_prior_observation
```

Raw timestamped key histories should not be collected merely because
they are available.

### 23.3 Do not casually promise "anonymous"

Longitudinal behavioral records can be identifying even without names.

A more accurate design goal is:

> **pseudonymous, data-minimized research telemetry with no account
> identity attached**

More advanced techniques such as differential privacy or federated
learning may eventually be worth investigating if they meaningfully
improve privacy without destroying research utility.

------------------------------------------------------------------------

## 24. Telemetry Controls

If telemetry is implemented:

### Required product principles

-   Explicitly explain what leaves the device.
-   Opt-out must preserve full application functionality.
-   Use a pseudonymous identifier unrelated to account identity.
-   Do not retain IP addresses alongside research observations beyond
    unavoidable transient infrastructure processing.
-   Minimize fields.
-   Version schemas and models.
-   Encrypt transport and server-side storage.
-   Rate-limit ingestion.
-   Treat all incoming telemetry as untrusted.
-   Provide a local profile reset.
-   Deliberately design whether/how contributed research data can be
    deleted.

### Reset semantics

"Reset my practice history" should:

-   erase local learner history;
-   reset scheduler state;
-   reset inferred capabilities;
-   generate a new telemetry identifier if telemetry remains enabled.

There is a real tradeoff between strong unlinkability and the ability to
later locate/delete previously contributed records. This should be
resolved explicitly rather than obscured in privacy language.

------------------------------------------------------------------------

## 25. Telemetry Integrity and Bad Data

Population data should be treated as untrusted observational data.

### Ingestion controls

-   schema validation;
-   known app/model versions;
-   valid exercise identifiers;
-   bounded numeric ranges;
-   rate limiting;
-   install-level quotas;
-   duplicate detection;
-   sequence sanity checks.

### Analysis controls

Distinguish:

1.  technically impossible/invalid observations;
2.  obvious automated or abusive submissions;
3.  statistical outliers that remain physically plausible.

Category 3 should not automatically be discarded. Exceptional pianists
are legitimate outliers.

Robust statistical techniques should be preferred over brittle manual
exclusion.

------------------------------------------------------------------------

## 26. Scientific Development Philosophy

The project should be academically informed without becoming
academically blocked.

Principle:

> **Research establishes priors and constraints. Product data refines
> them. Neither should prevent a reasonable initial implementation.**

The project does **not** initially require:

-   an expert Delphi study;
-   a survey of piano teachers;
-   a formal pedagogical consensus process;
-   an IRB study before implementation;
-   thousands of telemetry users;
-   a validated machine-learning model.

Where research provides good evidence, use it.

Where evidence is suggestive, use it cautiously.

Where the literature does not answer a product question, make an
explicit educated assumption and make that assumption testable.

------------------------------------------------------------------------

## 27. Assumption Registry

Pedagogically consequential heuristics should be recorded in a
lightweight assumption registry.

Example:

``` text
ID: A017
Title: Initial cross-key interleaving threshold

Assumption:
After acquisition, introduce cross-key interleaving when
estimated first-attempt success exceeds 80%.

Basis:
- contextual-interference literature
- Challenge Point Framework
- implementation judgment

Evidence strength:
Suggestive

Confidence:
Low/medium

Observable:
Compare delayed performance among users exposed to different
interleaving thresholds.

Introduced:
scheduler v1

Status:
Unvalidated
```

Potential registry entries:

-   acquisition success criterion;
-   initial tempo selection;
-   promotion threshold;
-   retention-decay prior;
-   interleaving threshold;
-   long-gap recalibration policy;
-   fatigue detection;
-   transfer weights among keys;
-   number of consecutive acquisition repetitions;
-   challenge-region target;
-   visual-guidance fadeout;
-   inferred-mastery threshold.

This creates scientific discipline without pretending the initial
heuristics are established facts.

------------------------------------------------------------------------

## 28. Model and Data Versioning

Every observation should be interpretable in historical context.

At minimum:

``` text
domain_model_version
performance_model_version
learner_model_version
scheduler_version
telemetry_schema_version
```

If the meaning of "crossing delay" changes in version 4, historical
observations must remain distinguishable from version-4 measurements.

This will be essential if the data ever support formal analysis or
publication.

------------------------------------------------------------------------

## 29. Long-Term Research Questions

Potential empirical questions include:

### Transfer

-   How strongly does C-major performance predict G-major performance?
-   How does transfer change with increasing black-key involvement?
-   Does C-major competence predict A-natural-minor competence despite
    shared pitch classes?
-   Which observed technical components generalize across keys?

### Retention

-   How does first-attempt performance change with elapsed time?
-   Does decay differ for accuracy, tempo, evenness, and
    synchronization?
-   Do advanced players retain established scales differently from newer
    players?

### Interleaving

-   At what skill state does cross-key interleaving improve delayed
    performance?
-   How much interference is useful before it becomes excessive?
-   Does interleaving benefit simple and complex technical tasks
    differently?

### Challenge

-   At what predicted success probability does subsequent improvement
    tend to peak?
-   Does the useful challenge region vary by experience or skill type?

### Diagnostic validity

-   Does a latent "LH thumb crossing" estimate predict future crossing
    performance in unseen keys?
-   Are localized hesitation metrics stable enough to represent
    technical weaknesses?

### Session effects

-   Can warm-up be distinguished reliably from forgetting?
-   Can cross-skill deterioration identify fatigue?
-   Should the scheduler respond to fatigue by reducing difficulty,
    changing skill families, or suggesting that the user stop?

### Scheduling

-   Which utility components best predict subsequent improvement?
-   Does explicit user focus improve engagement without harming
    long-term coverage?
-   How aggressively can inferred mastery skip prerequisite exercises
    without creating hidden gaps?

------------------------------------------------------------------------

## 30. Initial Implementation Philosophy

Do not begin with reinforcement learning or opaque neural models.

A strong V1 can use:

-   expert-authored exercise/skill mappings;
-   explicit prerequisites;
-   interpretable skill estimates;
-   transparent uncertainty updates;
-   simple retention priors;
-   performance-derived observations;
-   rule-based/weighted scheduler utility;
-   documented assumptions.

The application should log enough local state that later models can be
evaluated against historical observations.

A more sophisticated population-trained policy becomes appropriate only
when sufficient trustworthy data exist.

------------------------------------------------------------------------

## 31. Likely Early Development Sequence

### Phase 0: Domain-model exploration

Before significant UI work:

1.  Define a small latent-skill ontology.
2.  Model C, G, D, F, and A minor.
3.  Define representative exercises.
4.  Map exercises to skills.
5.  Define prerequisites and transfer assumptions.
6.  Identify which parameters are exercise transformations versus
    distinct skills.
7.  Test whether the model remains understandable.

### Phase 1: Performance prototype

Reuse the existing cross-platform MIDI experience where practical.

Implement:

-   expected-note generation;
-   MIDI capture;
-   exercise boundary detection;
-   pitch/sequence scoring;
-   timing/evenness;
-   hands-together synchronization;
-   localized error reporting.

### Phase 2: Local learner model

Track:

-   observed skill evidence;
-   uncertainty;
-   reliable/frontier tempo;
-   first-attempt performance;
-   acquisition/development/maintenance state.

### Phase 3: Rule-based adaptive scheduler

Implement:

-   continuous next-exercise selection;
-   rough placement/calibration;
-   inferred mastery;
-   retention checks;
-   acquisition repetition;
-   basic interleaving;
-   goal weighting;
-   long-gap recalibration.

### Phase 4: UX refinement

Optimize for:

-   minimal interaction;
-   immediate playing;
-   graceful interruption;
-   clear feedback;
-   occasional scheduler rationale;
-   optional free practice.

### Phase 5: Optional research telemetry

Only after local functionality is useful:

-   define minimized schema;
-   implement consent;
-   ingestion security;
-   data-quality rules;
-   model/schema versioning;
-   reset/deletion semantics.

### Phase 6: Empirical model refinement

Use aggregate observations to test assumptions and fit improved
parameters.

------------------------------------------------------------------------

## 32. Project Name and Product Vocabulary

### 32.1 Working project name: KeyRecall

The current working name for the project is **KeyRecall**.

The name reflects two related ideas at the center of the product:

-   the pianist must recall and reliably reproduce technical skills after
    time has elapsed;
-   the adaptive scheduler recalls previously learned skills into practice
    when reassessment or reinforcement is useful.

This makes the name relevant to the product's longitudinal learner model
without defining the application as a conventional flashcard-style spaced
repetition system.

The project is currently envisioned as a **free and open-source project**, in
the same general spirit as WhatChord, rather than as a product being developed
primarily for eventual commercialization. Consequently, commercial trademark
defensibility is not a primary design constraint at this stage. The name
should still avoid obvious conflicts and confusion, but further formal
clearance work is unnecessary unless the project's goals change.

The repository/package-style name can therefore use:

``` text
keyrecall
```

The name remains provisional in the ordinary sense that an early open-source
project can still be renamed if a compelling reason emerges, but no additional
naming work is currently necessary.

### 32.2 Fluency as the learner-facing construct

**Fluency** remains particularly useful vocabulary even though it is not the
project name.

The system is not merely measuring whether a pianist remembers the notes in a
scale. The desired outcome is increasingly fluent technical execution across
multiple dimensions, potentially including:

-   accuracy;
-   timing and evenness;
-   tempo capability;
-   hand synchronization;
-   consistency;
-   automaticity;
-   delayed first-attempt reliability;
-   retention;
-   robustness across related technical patterns.

A useful learner-facing concept is therefore a **Fluency Profile**: an
interpretable representation of the pianist's evolving technical state across
scale families, arpeggios, coordination skills, tempo ranges, and other latent
capabilities.

This creates a useful vocabulary distinction:

``` text
KeyRecall        = the project/application
Fluency Profile  = the learner's evolving technical state
recall/retention = one component of technical fluency
scheduler        = the policy that selects what is useful to practice next
```

**KeyFluency** was the other leading working-name candidate and remains a good
description of the desired outcome, but **KeyRecall** is the current project
name. Earlier candidate-name exploration is decision history rather than a
core part of the product design and does not need to be preserved here.

## 33. Research Reading List

### Highest priority

1.  **Moringen et al. (2021), *Optimizing piano practice with a
    utility-based scaffold***\
    Directly relevant adaptive piano-practice model.\
    https://arxiv.org/abs/2106.12937

2.  **Guadagnoli & Lee (2004), *Challenge Point: A Framework for
    Conceptualizing the Effects of Various Practice Conditions in Motor
    Learning***\
    Foundation for matching functional difficulty to learner
    capability.\
    DOI: 10.3200/JMBR.36.2.212-224\
    https://www.researchgate.net/publication/8574634_Challenge_Point_A_Framework_for_Conceptualizing_the_Effects_of_Various_Practice_Conditions_in_Motor_Learning

3.  **Czyż et al. (2024), *High contextual interference improves
    retention in motor learning***\
    Current systematic review/meta-analysis; important nuance about lab
    vs. applied effects.\
    https://www.nature.com/articles/s41598-024-65753-3

4.  **Czyż et al. (2024), *The effect of contextual interference on
    transfer in motor learning***\
    Companion systematic review/meta-analysis on transfer.\
    https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2024.1377122/full

5.  **Wiseheart, D'Souza & Chae (2017), *Lack of spacing effects during
    piano learning***\
    Essential caution against assuming declarative-memory spacing
    results transfer directly to piano motor learning.\
    https://journals.plos.org/plosone/doi?id=10.1371/journal.pone.0182986

### Learner modeling / scheduling

6.  **Corbett & Anderson (1995), *Knowledge Tracing: Modeling the
    Acquisition of Procedural Knowledge***\
    Classic latent-skill learner-model precedent.

7.  **Settles & Meeder (2016), *A Trainable Spaced Repetition Model for
    Language Learning***\
    Half-Life Regression and trainable retention modeling.\
    https://aclanthology.org/P16-1174/

8.  **Duolingo Half-Life Regression implementation/data**\
    https://github.com/duolingo/halflife-regression

9.  **Eglington & Pavlik (2020), *Optimizing practice scheduling
    requires quantitative tracking of individual item performance***\
    https://www.nature.com/articles/s41539-020-00074-4

### Contextual-interference nuance

10. **Ammar et al. (2024), *The Effects of Contextual Interference
    Learning on the Acquisition and Relatively Permanent Gains in
    Skilled Performance***\
    Useful counterweight to overly broad claims about interleaving.\
    https://link.springer.com/article/10.1007/s10648-024-09892-z

### Applied piano-practice perspective

11. **Piano Practice Assistant: Interleaved Practice**\
    https://pianopracticeassistant.com/interleaved-practice/

12. **Piano Practice Assistant: Spaced Repetition**\
    https://pianopracticeassistant.com/spaced-repetition/

13. **Piano Marvel technical-practice articles**\
    https://pianomarvel.com/en/article/how-to-master-my-scales/1000\
    https://pianomarvel.com/en/article/how-to-gain-speed-with-your-scales

------------------------------------------------------------------------

## 34. Important Caveats

Several research traditions being borrowed here were developed for
declarative learning, academic problem solving, or relatively simple
laboratory motor tasks.

Piano scale and arpeggio practice is a complex fine-motor domain with:

-   two-hand coordination;
-   continuous timing;
-   varying tempo;
-   physical technique;
-   pattern knowledge;
-   instrument-specific mechanics;
-   fatigue and warm-up;
-   substantial prior experience differences.

Therefore:

> **Use established learning science to formulate defensible priors and
> testable hypotheses, not to claim that piano pedagogy has already been
> mathematically solved.**

This distinction should remain explicit in both product decisions and
any eventual academic work.

------------------------------------------------------------------------

## 35. Immediate Next Design Task

The next exploratory artifact should be a small but concrete domain
model covering:

-   C major;
-   G major;
-   D major;
-   F major;
-   A natural minor.

For each, define:

1.  observable exercise families;
2.  latent skills/KCs loaded by those exercises;
3.  prerequisite relationships;
4.  expected transfer relationships;
5.  exercise transformations versus genuinely distinct skills;
6.  performance metrics that provide evidence for each KC;
7.  initial priors/assumptions;
8.  how competence and uncertainty should update;
9.  how acquisition, development, and maintenance differ;
10. what the scheduler can infer without explicitly testing.

The goal is not to create the entire piano-technique ontology.

The goal is to discover whether the proposed representation remains
**elegant, interpretable, and useful** when several related keys
interact.

If it does, the project has a strong conceptual foundation for
implementation.

------------------------------------------------------------------------

## 36. One-Sentence Product Vision

> **A privacy-first adaptive piano technique coach that listens to your
> scales and arpeggios, learns what you can actually play, and
> continuously chooses the most useful thing for you to practice next.**

That is the idea worth preserving as the implementation details evolve.
