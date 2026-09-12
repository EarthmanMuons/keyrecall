# The original product vision

> **Status:** superseded in its technical sections. Kept for the competitive
> landscape, the product thesis, and the UX principles, which are still what
> KeyRecall is trying to be.
>
> **Research cutoff:** August 2026, before domain modeling began.

This is the first document the project had: an exploratory survey and product
thesis written before any implementation existed. Its later sections proposed a
learner model, a session-state model, and a scheduler utility function, all of
which the built system contradicts in detail. Those are gone; the shipped
equivalents are in [`../../system/`](../../system/) and the reasoning that
replaced them in [`../../decisions/`](../../decisions/).

What survives here is the part no later document restates: **what else exists,
and why none of it does this.**

## The thesis

A deliberately narrow but potentially very deep piano-practice application,
devoted to scales, arpeggios, and closely related technical patterns.

The central idea is not to teach scales, score MIDI performances, track tempos,
or implement conventional spaced repetition. Existing products already do
substantial pieces of those jobs. The opportunity is to close the loop:

> **Teach -> observe -> diagnose -> schedule -> reassess -> increase difficulty
> -> retain.**

The application should know what the pianist can play because it has observed
the pianist playing it, maintain a longitudinal model of their technical
capabilities, uncertainty, retention, and goals, and then choose the next
exercise automatically. So the desired interaction is extremely simple:

> **Open the app. Play what it gives you. Continue for as long as you want. Stop
> whenever you want.**

The sophistication lives underneath that.

A useful one-line description: **an adaptive technical-practice scheduler with
memory.** The scheduler may draw on spaced practice, contextual interference,
motor learning, adaptive assessment, knowledge tracing, prerequisite graphs, and
challenge-point theory, and none of those mechanisms individually defines the
product.

The domain stays intentionally constrained. It does not need to become a general
piano-learning application with repertoire, sight reading, ear training, or
theory courses. Scales and arpeggios alone support years of progression:
individual hands, hands together, multiple octaves, major and minor forms,
modes, tempo development, contrary motion, inversions, interval scales, and
advanced technical regimens.

One methodological commitment from the start, and it held: the initial system
should be built from existing research, explicit pedagogical assumptions, and
engineering judgment, and should **not** be blocked on expert surveys, a formal
consensus process, a large research study, or a pre-existing telemetry corpus.
Assumptions get documented and made testable instead.

## Competitive landscape

A preliminary competitor sweep suggests that nearly every component exists
somewhere, but the complete adaptive loop remains unusual.

### Piano Scale Coach

Piano Scale Coach is especially relevant to **initial acquisition and
progression**. Its model emphasizes clean repetitions, incremental construction,
hands separately before hands together, and tempo progression.

This validates several ideas for acquisition:

- construct difficult movements in manageable pieces;
- use blocked repetition when a movement is genuinely new;
- require evidence of repeatability before progressing;
- increase difficulty only after successful execution.

The opportunity is to take those ideas beyond a linear "complete this, then
advance" curriculum and feed every result into a longitudinal adaptive
scheduler.

### Pianolympics

Pianolympics is the strongest direct reference for **objective MIDI-based
technical assessment** found so far. It advertises more than 1,500 scales and
arpeggios and analyzes details such as timing, evenness, accuracy, hands
separately/together, dynamics, articulation, synchronization, and balance.

Reference:

- https://pianolympics.net/

The implication is important: simple pitch correctness is unlikely to be
sufficient differentiation. Rich performance analysis is becoming feasible and
expected.

### Scale Study

Scale Study is notable for treating scale progress as an evolving relationship
between **key, correctness, and tempo**. It uses MIDI, confirms correct scales,
records clean tempo, and tracks progress over time.

References:

- https://scalestudy.app/en/
- https://apps.apple.com/us/app/scale-study-tempo-practice/id6758663846

Its "performance envelope" concept is useful. The proposed system should avoid
reducing a skill to an arbitrary single mastery percentage when it can instead
estimate things such as:

- reliable tempo;
- best observed clean tempo;
- performance variability;
- delayed first-attempt reliability;
- confidence/uncertainty in those estimates.

### Piano Marvel / Scale Ninja

Piano Marvel is a broad learning environment, but Scale Ninja and Piano Marvel's
technical-practice guidance are important precedents. Their material covers
progressive scale development and advanced approaches such as rhythmic variants,
grouped patterns, isolated crossings, incremental expansion, and advanced scale
forms.

Useful reading:

- https://pianomarvel.com/en/article/how-to-master-my-scales/1000
- https://pianomarvel.com/en/article/how-to-gain-speed-with-your-scales
- https://pianomarvel.com/en/feature/sasr

Piano Marvel also demonstrates that automated selection based on prior
performance can work as a user experience, even though its SASR system addresses
sight reading rather than this proposed technical domain.

### Piano Fitness

Piano Fitness is an especially relevant adjacent project because it explicitly
focuses on technical development, MIDI feedback, scales, arpeggios, chord
inversions, and structured progression.

References:

- https://piano.fitness/
- https://brylie.online/projects/piano-fitness/

This should remain on the competitor watch list.

### The Hanon Method

The Hanon Method is another 2026 entrant emphasizing MIDI-measured technique
practice, precision, tempo stability, and long-view practice history.

Reference:

- https://thehanonmethod.com/

This is evidence that "measured technical practice" is becoming an identifiable
product category.

### Scale Practice

The open-source Scale Practice application randomizes scales and arpeggios but
explicitly does not listen or provide feedback.

References:

- https://f-droid.org/en/packages/com.scalepractice/
- https://play.google.com/store/apps/details?id=com.scalepractice

This is useful as a conceptual "before" case: scheduling/order without
performance telemetry.

### Other adjacent applications

Other applications discovered during the sweep include Scale Navi, ScaleCoach,
Piano Scales & Chords, Keyflow, Any Scale, and broader piano practice tools.
These reinforce the need to differentiate at the **adaptive
learner-model/scheduler** level rather than merely by providing scales,
fingerings, MIDI input, a metronome, or progress charts.

### Current market-gap hypothesis

Existing products tend to answer one or two of these questions well:

1.  **How do I learn this scale?**
2.  **How well did I just play it?**
3.  **What should I revisit?**

The proposed system should connect all three:

> **What should this particular pianist do next, given everything the system
> currently knows about their technique, retention, uncertainty, goals, and
> current practice state?**

That remains the strongest candidate for differentiated value.

## User experience principles

### Start playing immediately

The default workflow should minimize configuration and navigation.

A mature user might see:

> C major · HT · 4 octaves\
> ♩ = 104

They play.

The app evaluates the attempt and immediately chooses the next exercise.

### Sessionless by design

The user should not need to declare:

> "I have 20 minutes."

The atomic scheduling unit is an **exercise**, not a preplanned session.

Conceptually:

```text
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

If the user stops after 7, 11, 23, or 50 minutes, nothing is incomplete. The
next time the app opens, it recalculates priorities from the current state.

A scheduler may look ahead a few exercises to create desirable interleaving or
avoid repetition, but any queue should be soft and continuously revisable.

### No "behind" state

Irregular practice frequency is normal.

A user may practice on Monday, Tuesday, Sunday, disappear for three weeks, and
return on Thursday. The application should not present a pile of overdue
assignments.

Elapsed time changes predicted retention and uncertainty. On return, the
scheduler selects informative and useful exercises and rapidly recalibrates.

The user is never "behind."

### Repetition must have a reason

Do not impose a universal "seven repetitions" rule.

During acquisition, repeated correct execution may be pedagogically useful.
During maintenance, a single first-attempt performance after a long interval may
provide more useful evidence than seven consecutive repetitions.

Principle:

> **Repetition is prescribed because repetition itself is useful or because the
> model needs additional evidence, not because every exercise has an arbitrary
> repetition count.**

### Make the intelligence legible

Occasional lightweight explanations may increase trust:

- _21-day review_
- _Working on left-hand crossings_
- _New challenge_
- _Building hands-together coordination_
- _Checking retention after your break_

This is particularly important when an experienced pianist receives apparently
easy material.

### Respect expert time

If an advanced pianist demonstrates an easy skill immediately, move on.

The system should aggressively skip or infer prerequisite mastery rather than
requiring explicit completion of every beginner node.

## What became of these principles

Every one of them survived into the built system, which is why this section is
worth keeping rather than the equations that did not:

| Principle                     | Where it lives now                                                   |
| ----------------------------- | -------------------------------------------------------------------- |
| Start playing immediately     | One practice screen, no lesson list                                  |
| Sessionless by design         | A sitting ends when the player stops; the session cap ships unset    |
| No "behind" state             | No streaks, no due counts, and a scope can report caught up honestly |
| Repetition must have a reason | The repetition guard, diversity ranking, and dose control            |
| Make the intelligence legible | `CandidateTrace` on every candidate; the Fluency Profile             |
| Respect expert time           | Placement seeds the prior, and direct evidence overrides it quickly  |

The sections this document originally carried on the learner model, session
state, acquisition/development/maintenance regimes, and the scheduler utility
function have been removed. They proposed a single weighted utility function and
a discrete practice-regime state, and the built system uses neither: ranking is
lexicographic with no weighted sum, and practice regime is derived presentation
rather than stored state. See
[`../../system/scheduler.md`](../../system/scheduler.md) and
[`../../GLOSSARY.md#retired-terms`](../../GLOSSARY.md).
