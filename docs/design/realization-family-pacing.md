# Realization-family pacing

- **Status:** Diagnostic framing, not production policy.
- **Written:** August 31, 2026.
- **Scope:** Allocation among right hand, left hand, parallel hands together,
  and contrary hands together over a practice trajectory.

Candidate admission asks whether one exercise is defensible. Realization-family
pacing asks whether another exercise from the same family is the best use of the
next slot. The distinction matters once several materials, spans, hand
configurations, and motions can all independently produce admissible progression
candidates.

## External constraints

Graded curricula support ordering and coexistence, not a session quota. The
[ABRSM 2025–2026 syllabus](https://www.abrsm.org/sites/default/files/2024-06/Piano%202025%20%26%202026%20Prac%20syllabus%2020240524_access.pdf)
places C major in both similar and contrary motion hands together at Grade 1
while other Grade 1 scales remain hands separately. The
[RCM 2022 syllabus](https://teacherportal.rcmusic.com/getattachment/57f3734d-97e5-4777-b67e-4b1111ee31a3/piano-syllabus-2022-edition.pdf)
likewise combines hands-separate scales with C-major contrary motion hands
together at its early levels. Both treat hand configuration and motion as
parallel strands of technical work rather than a single ladder on which
hands-together practice replaces single-hand practice.

Motor-practice research gives a reason to measure concentration without
declaring every concentrated block wrong. A 2024
[systematic review and meta-analysis](https://pmc.ncbi.nlm.nih.gov/articles/PMC11349744/)
found an overall transfer benefit for higher contextual interference, but the
effect in applied settings was small and not statistically significant, and the
effect for younger participants was negligible. The evidence supports keeping
varied work visible and evaluating transfer; it does not supply a defensible
maximum number of consecutive hands-together attempts.

## Questions the diagnostic answers

For each synthetic archetype, report:

- attempt share, managed-execution yield, frontier movement, and evidence yield
  for right hand, left hand, parallel hands together, and contrary hands
  together;
- new-context, progression, recovery, and ordinary-band work within each family;
- maximum hands-together and unmanaged-hands-together concentration in 20- and
  40-slot windows;
- longest uninterrupted hands-together and unmanaged-hands-together runs;
- which family follows an unmanaged hands-together progression attempt and how
  long the scheduler takes to return to single-hand work;
- first hands-together motion and later switching between motions;
- the fewest realization families represented in any 20-slot window.

These are observations, not pass/fail checks. They give a policy experiment a
trajectory-level outcome to improve without choosing the policy in advance.

## Current control surface

The scheduler has no realization-family allocation state. Session diversity
counts recent material ids, so switching from C-major contrary hands together to
G-major parallel hands together satisfies material diversity while leaving the
family of work unchanged. The coordination-transition preference decides which
motion receives one first exposure and then expires. Recovery exclusively
targets the failed exercise's supported sibling. None of these mechanisms asks
how much recent work was right hand, left hand, or hands together, or what yield
that family produced.

This explains why removing one hands-together progression subtype can expose
another without materially changing the trajectory. Candidate-local ranking
still sees a large set of admissible hands-together progression exercises, and
no later stage compares that class of work with recent family allocation.

## Baseline census

Ten independent 60-slot trajectories for each primary archetype produce four
different allocation shapes:

- `true_beginner` receives no hands-together work. Its session remains split
  between right- and left-hand foundations.
- `developing` spends 43.7% of all slots on hands together, with 0% managed
  parallel attempts and 0.8% managed contrary attempts. The median run's most
  concentrated 20-slot window is 75% hands together; the maximum is 95%.
  Unmanaged hands-together runs reach 18 consecutive slots. After an unmanaged
  hands-together progression attempt, another hands-together family is selected
  in 104 of 143 next-slot observations, and returning to single-hand work takes
  a median of three slots and as many as eighteen.
- `uneven_hands` spends 5.7% of slots on hands together. Those attempts are also
  unmanaged, but the median maximum concentration is 15% of a 20-slot window and
  the scheduler returns to single-hand work after a median of one slot. Its poor
  hands-together yield is therefore not the same allocation failure as
  `developing`.
- `advanced` spends 13.2% of slots on hands together and manages 75.0% of
  parallel and 82.1% of contrary attempts. Its unmanaged hands-together runs
  have a median maximum length of one slot.

Contrary motion is the first hands-together motion in every run that reaches
hands-together work. Developing exposure is then divided between parallel and
contrary motion, with a median of eight motion switches per run. Motion ordering
and breadth are functioning; the unresolved baseline is sustained low-yield
hands-together allocation for the developing cohort.

## Interpretation boundary

A low immediate managed rate is not by itself proof that a family should be
suppressed. Recovery may deliberately generate difficult but useful evidence,
and variable practice can reduce acquisition performance while helping later
transfer. Conversely, the existence of another admissible hands-together
candidate does not show that selecting it is productive after a run of low-yield
hands-together work.

The next production policy, if one is warranted, should therefore act on a
measured allocation failure: persistent family concentration with poor yield and
a useful alternative. It should not be inferred from candidate-local probability
ordering alone.

## Generic pressure experiment

`family_pacing_ab` runs each archetype twice on the same seed, once against the
current pipeline and once against `FamilyPacedPipeline`, and reports allocation,
yield, concentration, breadth, and starvation for both arms.

Families are declared string keys, not an enum the scheduler branches on. A
right- or left-hand exercise declares one key; a hands-together exercise
declares `hands:together` alongside `motion:parallel` or `motion:contrary`, so
rotating between motions still accumulates pressure on the shared strand while
each motion is paced separately. A later realization would join the same
accounting by naming the strands it belongs to, without the pacing algorithm
gaining a case for it.

Pressure over a rolling window of recent selections is
`max(0, share - floor) x (1 - managed fraction)`. It rises when a family holds
much of the window and little of that work was productive, and falls both as
the family produces managed execution and as the window fills with other
families. A family over the set-aside pressure has its candidates removed from
the available set, exactly where the repetition guard acts, and never when
nothing else is admitted. Admission is untouched: a pressured candidate stays
eligible and ranked, and still wins a slot where it is the only thing there.
Ranking is lexicographic, so a penalty term could only have broken exact ties.

## Experiment results

Ten paired 60-slot runs per archetype at window 12, floor 0.5, minimum four
family attempts, set-aside at 0.15:

- `developing` moves 29 of 262 hands-together slots to single-hand work. The
  median most concentrated 20-slot window falls from 75% to 65% and its maximum
  from 95% to 75%; the longest unmanaged hands-together run falls from a median
  of 8 and a maximum of 18 to 6 and 10. Frontier advances rise from 108 to 122,
  all of the gain single-hand. Hands-together work does not disappear: every run
  still reaches it, first exposure is unmoved at slot 12.7, recovery still fires
  94 times, and motion switching stays at a median of 7 per run.
- `advanced` is bit-identical. Pressure never reaches the set-aside threshold in
  any of its 600 slots, because its hands-together work is managed.
- `uneven_hands` stays a low hands-together trajectory, 5.7% to 6.2%, with
  frontier advances within two of the current arm. Its 18 set-aside slots act on
  the right-hand family it over-allocates, not on hands together.

The signature holds across settings. At a 0.20 or 0.25 set-aside threshold, or
at a window of 16, `developing` still loses 19 to 27 hands-together slots, still
gains frontier advances, and still never loses hands-together work entirely;
only the magnitude moves. No arm produced a terminal run.

## Open question the experiment raised

The mechanism is family-agnostic by construction, so it also paces single-hand
families. `true_beginner` allocates 58.8% of its slots to the left hand and
advances a frontier 11 times in 600 slots, so almost everything in its window
reads as unproductive and left-hand pressure fires. Two of ten runs then reach
hands-together work they never reached before: five attempts, none managed,
three of them recovery. The gentler settings reduce this to one or two attempts
but do not remove it.

That is the mechanism working as specified and the yield signal being wrong for
this cohort. Managed execution is a demanding definition of productive work for
a learner who is not yet managing anything, and a family that is unproductive
because the learner is early is not the same as a family that is unproductive
because it is being over-allocated. A production policy would need a yield
signal that separates those, or a floor that keeps a family whose alternatives
are all less prepared from being paced at all.

## Alternative readiness at set-aside points

`family_pacing_relief` records both sides of every substitution the filter
makes: the best candidate pressure removed, the best candidate that replaced
it, their predicted success, band membership, bypass category, and what the
replacement went on to do.

Predicted success separates the cohorts cleanly:

| | set-asides | relieving at least as ready | median gap | relieving managed |
| --- | --- | --- | --- | --- |
| `developing` | 43 | 95.3% | +0.059 | 28.6% |
| `uneven_hands` | 18 | 44.4% | -0.030 | 21.4% |
| `true_beginner` | 66 | 19.7% | -0.016 | 0.0% |

`developing` substitutes a hands-together progression candidate for a
better-predicted single-hand one in 39 of 43 cases, and the replacement manages
execution and advances a frontier in 12 of them. `true_beginner` substitutes
left-hand new material for right-hand new material at slightly worse predicted
success, and not one of its 63 replacements managed execution or advanced
anything. Low yield means the opposite thing in the two cohorts, and the
readiness of the alternative is what says which.

Band membership does not discriminate: no pressured candidate and no relieving
candidate is inside the challenge band in any archetype, because every
set-aside substitutes one bypass candidate for another. Eligibility does not
either; both sides are fully eligible in every case. Predicted success is the
only one of the three that separates them.

## Relievable pressure

`requireReadyAlternative` adds one condition to relief: the best surviving
candidate must be at least as ready as the best candidate pressure would
remove. Pressure still detects concentration with poor yield; relief now also
requires somewhere better to put the slot. The rule names no family and no
learner stage, so a later strand inherits it without a clause of its own.

Against the same ten paired runs per archetype:

- `true_beginner` set-asides fall from 66 to 20 and its hands-together leak
  from five attempts to one, in one run of ten rather than two. Frontier
  advances rise from 11 to 15, better than the 11 the ungated filter produced,
  so the single-hand pacing that survives the gate is the useful part of it.
- `developing` is essentially unchanged: the same 29 hands-together slots move
  to single-hand work, concentration still falls to 65% median and 75% maximum
  of a 20-slot window, and the longest unmanaged run still falls to 6 median and
  10 maximum. Only 3 of its 43 set-asides fail the gate. Frontier advances rise
  by 10 rather than 14, which is what those three slots cost.
- `uneven_hands` keeps 7 of 18 set-asides and ends 4 frontier advances below the
  current arm rather than 2. Its pressure is genuinely ambiguous: single-hand
  concentration with alternatives that are readier only half the time.
- `advanced` remains bit-identical; pressure never fires.

The gate therefore removes most of the regression at a small cost to the case it
was meant to serve, without a beginner exemption or a family-specific
prerequisite.

## What is still unsettled

Predicted success answers whether an alternative is likelier to succeed, not
whether it is the more useful next work; a comfortable candidate scores well on
it. The `uneven_hands` result is where that shows: half its alternatives are
readier, the gate keeps those, and the trajectory still ends slightly behind the
current scheduler. A comparison reading the ranking facts already computed at
this point, band position, progression opportunity, recovery target, and
frontier potential, is the next thing to test against these same three cohorts.
The constants and the definition of productive work are untouched, since neither
is what the readiness result turned on.
