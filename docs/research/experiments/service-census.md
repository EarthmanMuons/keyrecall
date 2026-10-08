# Service census

> **Status:** characterization at scheduler v1-14, the baseline for any
> allocation change. Nothing is promoted and no policy changes.

The fluency report on a four-month synthetic history showed most scales met and
most arpeggios not. Admission and the introduction handoff were corrected first
(v1-13, v1-14). The question left is about allocation: when work the practice
layer itself calls due could be chosen, how often is it chosen, how long does it
wait, and what wins instead?

## What a General Fluency requirement asks

The goal names no curriculum, so one is synthesized: a requirement per catalog
material, in introduction order, with no structural constraint, no tempo, and
retrieval that may be observed after a preview as well as unguided.

A requirement is covered by a single attempt that matches its structure, was
started and completed, retrieved the material, sounded at least 0.9 of its
pitches correctly, and carried a self-paced motor score of at least 0.5, plus
coordination of at least 0.75 where both hands played. It stays covered once
covered, and becomes due again while the material's retrieval health is below
0.75. An uncovered requirement is always due.

Two consequences matter below. Coverage needs a timed attempt, so a one-octave
ascending arpeggio, which cannot be timed, can never cover anything. And it is
stricter than the fluency report's "played from memory", which asks only for a
successful unguided retrieval: a material can show as played from memory and
stay uncovered, and therefore due, indefinitely.

## Method

The seeded demo schedule (June 1 to September 29, 2026, 64 sessions, 1,347
decisions) is run for the true beginner, developing, and advanced archetypes
through a pipeline that decides exactly as the production one and records each
decision for every scope requirement. A test holds it to a byte-identical
journal.

```console
dart run keyrecall_simulation:service_census
```

Per requirement and decision it records facts rather than one state, because
they overlap:

| Fact                 | Meaning                                                                         |
| -------------------- | ------------------------------------------------------------------------------- |
| Due                  | The practice layer's own judgment, above                                        |
| Admitted             | Some realization of the material passed admission                               |
| Actionable           | Due, and a fully eligible realization in the requirement's structure was ranked |
| Served               | The winner is the material, in the structure the requirement asks for           |
| Deferred             | Actionable and not served                                                       |
| Blocked              | Due and not actionable, held for recovery or otherwise                          |
| Progression (no due) | Covered and healthy, with a ranked realization that advances a frontier         |

A deferral is attributed to the rank term its best realization lost on against
the ordinary ranking winner, to the selection stage that removed it when it
would have won, or to the override that chose the winner instead. The term is an
explanation of one lexicographic comparison, checked against the scheduler's
own, not of the whole selection. Runs of missed opportunities count only
decisions at which the requirement was actionable. Progression is reported on
its own and never counts as a deferral.

## Results

Only one requirement can be served per decision and much of the catalog is due
at once, so deferral totals are large by construction. What a requirement's own
service looks like is the signal.

| Player        | Family   | Ever covered | Actionable and served | Actionable, never served | Due, never actionable | Served (due) | Served (not due) |
| ------------- | -------- | -----------: | --------------------: | -----------------------: | --------------------: | -----------: | ---------------: |
| True beginner | arpeggio |      9 of 24 |                    14 |                        0 |                    10 |          482 |               10 |
| True beginner | scale    |     19 of 48 |                    31 |                        7 |                    10 |          730 |                8 |
| Developing    | arpeggio |      8 of 24 |                    14 |                        0 |                    10 |          272 |                6 |
| Developing    | scale    |     45 of 48 |                    45 |                        3 |                     0 |        1,011 |               44 |
| Advanced      | arpeggio |     24 of 24 |                    24 |                        0 |                     0 |          230 |              194 |
| Advanced      | scale    |     48 of 48 |                    48 |                        0 |                     0 |          440 |              483 |

What deferred opportunities lost to:

| Player        | Family   | Rank: retention | Override: frontier step | Override: guidance probe | Other            |
| ------------- | -------- | --------------: | ----------------------: | -----------------------: | ---------------- |
| True beginner | arpeggio |             56% |                     10% |                      12% | acquisition 14%  |
| True beginner | scale    |             56% |                     14% |                      13% | acquisition 11%  |
| Developing    | arpeggio |             49% |                     25% |                      14% | coordination 4%  |
| Developing    | scale    |             46% |                     30% |                      15% | coordination 5%  |
| Advanced      | arpeggio |             38% |                     26% |                      14% | coordination 13% |
| Advanced      | scale    |             36% |                     29% |                      14% | coordination 12% |

Selection filters after ranking (echo, repetition, introduction breadth, pacing,
dose, novelty) account for 0.3 to 1.6 percent of it.

## Findings

**Persistent actionable deferral.** Some requirements reach ranking almost every
decision and are almost never chosen. The developing learner's C major arpeggio
is actionable at 892 decisions and served at 4, with a run of 880 missed
actionable opportunities. It is never covered: its four attempts, all among the
first eleven records, were one octave at 60 BPM, and the one that retrieved it
unguided was neither completed nor accurate enough. The developing learner's
fourteen actionable arpeggios were served 272 times between them in 1,347
decisions. Three of its scales, and seven of the true beginner's, were
actionable and never served.

**Persistent unavailability.** Ten arpeggio requirements for the developing
learner and the true beginner, and ten scales for the true beginner, are due
throughout and never actionable: their bands never become fully eligible. This
is an eligibility and readiness limit, separate from allocation.

**Competition among due requirements.** For the developing learner, 44 of 1,055
scale services went to requirements that were not due, and 8 of 738 for the true
beginner. The scales that win are mostly uncovered too, so more arpeggio
coverage means reallocating opportunities between genuinely competing due work,
not removing obvious waste. The advanced learner is the exception: about half of
its scale service is on covered, healthy requirements, as progression.

Progression on covered, healthy requirements is plentiful and seldom taken by
the two weaker learners: 10,166 opportunities and 37 served on the developing
learner's scales.

## What this does not establish

That retention decided a comparison does not mean demoting retention would let
the requirement win once every other stage and override has run, or that
retrieval maintenance would survive it. The purposes recorded for a winner name
its admission bypass where it has one, so "execution progression" means work
admitted as an out-of-band execution step. The players are synthetic, and a real
learner's coverage would follow from what they actually play.

Above all, it does not say whether General Fluency's completion contract is what
the goal should ask. Most of this run's due work is due because it is uncovered,
and it is uncovered because coverage asks for one timed, accurate, self-paced
attempt that the developing learner's arpeggios rarely produce. A counterfactual
allocation change belongs after that question, and should ask whether persistent
requirement-level deferral deserves explicit priority rather than assume
retention should be demoted globally.
