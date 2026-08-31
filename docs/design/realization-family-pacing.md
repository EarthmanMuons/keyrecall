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
