# Service pressure

> **Status:** counterfactual, five paired seeds. Explicit requirement service
> repeatably shortens persistent deferral and modestly raises the developing
> learner's coverage, at a consistent cost to the maintenance of what is already
> covered. Its failure guard recreates starvation for the true beginner. Nothing
> is promoted; the scheduler stays at v1-14.

The [service census](service-census.md) found due, actionable requirements that
v1-14 almost never chooses. The question here is whether giving persistent
deferral explicit weight changes what learners go on to demonstrate, and what it
costs.

## The rule

A requirement counts missed actionable opportunities while it is due, and any
service clears the count. Past a threshold it may take a slot that ordinary
ranking decided, choosing its best fully eligible, structure-compatible
candidate from the final selectable set, so recovery, probes, acquisition, and
every filter still hold. Covered requirements that are not due build nothing.
Two promoted attempts that do not manage their execution suspend a requirement
until ordinary selection serves it, which can be never.

It runs beside the scheduler, inside the census pipeline. Without it the journal
is byte-identical to v1-14's, and a test holds every substitution to having
displaced a ranking winner with a candidate that survived selection.

```console
dart run keyrecall_simulation:service_pressure --player developing
```

Each archetype runs the demo window on five schedule:player seed pairs fixed
before the run (0:100 to 4:104), under v1-14 and at thresholds 50 and 100.
Outcomes are paired differences against v1-14, counted as the pairs that
improved and worsened. Five pairs are a robustness check, not a validation.

## Results

Pairs better and worse than v1-14, out of five, at threshold 50 and 100:

| Outcome                           | Developing | True beginner | Advanced  |
| --------------------------------- | ---------- | ------------- | --------- |
| Arpeggios covered                 | 5/0, 5/0   | 3/1, 4/1      | unchanged |
| Scales covered                    | 5/0, 4/0   | 3/1, 3/2      | unchanged |
| Worst missed run, arpeggio        | 5/0, 5/0   | 5/0, 5/0      | 4/1, 4/1  |
| Worst missed run, scale           | 5/0, 5/0   | 5/0, 5/0      | 5/0, 5/0  |
| Retrieval, all in scope, arpeggio | 5/0, 5/0   | 5/0, 4/1      | 5/0, 0/5  |
| Retrieval, all in scope, scale    | 5/0, 4/1   | 3/2, 3/2      | 5/0, 5/0  |
| Retrieval among covered, scale    | 0/5, 0/5   | 1/4, 1/4      | 0/5, 0/5  |
| Fading share of covered, scale    | 1/4, 0/5   | 1/4, 2/3      | 0/5, 2/3  |
| First timed attempt faltered      | 5/0, 5/0   | 2/3, 1/4      | 2/3, 4/1  |
| Incomplete attempts               | 4/1, 4/1   | 3/2, 2/3      | 2/3, 3/2  |
| Material switches                 | 0/5, 2/3   | 2/3, 3/2      | 0/5, 2/3  |

The developing learner gains one to four arpeggios and one to six scales covered
in every pair at 50, and its worst arpeggio missed run falls from 799 to 953
opportunities to 68 to 162 in four pairs and 810 in the fifth. The single seed
that first suggested 22 covered arpeggios at 50 was an outlier; on these pairs
it is 13 or 14.

The costs are consistent in direction: retrieval among covered scales falls in
every developing and advanced pair, by 0.004 to 0.07, the share of covered time
spent fading rises in most pairs (by up to 11 points for the developing learner
and 34 for the true beginner), and at 50 material switching rises one to four
points for the developing and advanced learners. Threshold 100 keeps most of the
deferral reduction with smaller costs.

Suspension behaves differently by learner. The developing learner ends at most
two requirements suspended, and the advanced none. The true beginner ends with
two to eight suspended in every pair at both thresholds, and 44 of those 46
stayed actionable afterward without ordinary service: the guard backs out of
work the learner cannot yet manage and then never returns to it.

## What this establishes

Persistent deferral is not incidental. A rule that only reorders slots ranking
already decided, among candidates every other stage accepted, changes what a
developing learner demonstrates, repeatably, while learners who already cover
everything lose little but maintenance and some continuity.

It does not establish this rule. The maintenance cost says service and retention
are competing for the same slots rather than being reconciled, and the
suspension result says the guard trades one starvation for another for the
learner who most needs a different exercise. A threshold is not the design: the
next step is how service obligations enter selection without a permanent
suspension or another override competing with the existing ones.
