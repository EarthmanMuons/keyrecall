# Allocation counterfactual

> **Status:** counterfactual, five paired seeds, first stage of
> [`allocation.md`](../../system/allocation.md). Breadth-relative service
> priority removes pathological waits for every learner and fixes the asymmetric
> learners' starved family outright, where service pressure did not. At the
> slack that does most, maintenance of what is already covered pays for it; at
> the slack that keeps maintenance, the developing learner's scales pay instead.
> Nothing is promoted; the scheduler stays at v1-14.

## What was run

The allocation-only stage: on slots ordinary ranking decided, a requirement is
owed once its missed actionable opportunities exceed `k` times the number of
requirements actionable now; the most overdue owed requirement with a feasible,
fully eligible, structure-compatible candidate in the final selectable set takes
the slot; and a winner that can observe retrieval of a covered requirement below
the protection floor is never displaced. No acquisition, recovery, or
prerequisite path changed. With an unreachable bound the journal is
byte-identical to v1-14's, and a test holds every substitution to its contract.

```console
dart run keyrecall_simulation:allocation_counterfactual --player developing
dart run keyrecall_simulation:allocation_counterfactual --report runs.jsonl
```

Five players (true beginner, developing, advanced, scale-strong and
arpeggio-weak, arpeggio-strong and scale-weak), five fixed seed pairs (0:100 to
4:104), eight arms: v1-14, service pressure at 100, and `k` of 2, 4, 8 at
protection floors 0.60 and 0.70. 200 trajectories.

Validation on one seed per player first caught a defect: the allocator gave the
slot to the best protected review anywhere in scope whenever something was owed,
so most of its substitutions were maintenance and owed scale work barely moved.
Protection was corrected to keep a protected winner's slot and claim no other
before the grid ran.

## Results

Medians across the five pairs, at floor 0.60. The 0.70 floor differed little and
inconsistently in every player. Retrieval is averaged over every decision:
across every in-scope scale (comparable between arms) and across covered scales
only (descriptive, since arms cover different sets).

| Player          | Arm          | Arpeggios covered | Scales covered | Worst wait, arpeggio | Worst wait, scale | Scale retrieval, all | Scale retrieval, covered | Switching |
| --------------- | ------------ | ----------------: | -------------: | -------------------: | ----------------: | -------------------: | -----------------------: | --------: |
| True beginner   | v1-14        |                 7 |             21 |                  720 |               729 |                0.181 |                    0.729 |     0.484 |
|                 | pressure 100 |                 9 |             24 |                  479 |               552 |                0.171 |                    0.655 |     0.479 |
|                 | k = 2        |                13 |             22 |                   93 |               112 |                0.183 |                    0.668 |     0.512 |
|                 | k = 8        |                 9 |             21 |                  294 |               313 |                0.182 |                    0.711 |     0.489 |
| Developing      | v1-14        |                10 |             47 |                  870 |               378 |                0.414 |                    0.730 |     0.554 |
|                 | pressure 100 |                14 |             47 |                  106 |               112 |                0.441 |                    0.707 |     0.562 |
|                 | k = 2        |                14 |             47 |                  105 |               124 |                0.445 |                    0.709 |     0.566 |
|                 | k = 8        |                14 |             42 |                  193 |               262 |                0.392 |                    0.731 |     0.553 |
| Advanced        | v1-14        |                24 |             48 |                  129 |               370 |                0.718 |                    0.849 |     0.887 |
|                 | pressure 100 |                24 |             48 |                  121 |               119 |                0.761 |                    0.838 |     0.882 |
|                 | k = 2        |                24 |             48 |                  111 |               119 |                0.761 |                    0.835 |     0.897 |
|                 | k = 8        |                24 |             48 |                  129 |               296 |                0.727 |                    0.848 |     0.886 |
| Scale-strong    | v1-14        |                 5 |             48 |                  989 |               387 |                0.671 |                    0.808 |     0.693 |
|                 | pressure 100 |                 9 |             48 |                  783 |               114 |                0.673 |                    0.791 |     0.705 |
|                 | k = 2        |                19 |             48 |                  123 |               121 |                0.666 |                    0.768 |     0.716 |
|                 | k = 8        |                14 |             48 |                  305 |               291 |                0.651 |                    0.791 |     0.704 |
| Arpeggio-strong | v1-14        |                23 |             14 |                  956 |             1,040 |                0.154 |                    0.878 |     0.761 |
|                 | pressure 100 |                24 |             41 |                  106 |               817 |                0.346 |                    0.804 |     0.735 |
|                 | k = 2        |                24 |             48 |                  113 |               148 |                0.472 |                    0.792 |     0.741 |
|                 | k = 8        |                24 |             48 |                  179 |               213 |                0.387 |                    0.792 |     0.721 |

Paired, every allocation arm shortens both families' worst waits in nearly every
pair for every player, except the advanced learner's arpeggios at `k` of 4 and
8, which v1-14 already served within about 130. Coverage of the weak family
rises in every pair for both asymmetric players at every `k`. Retrieval among
covered scales falls in every pair for both asymmetric players at every `k`, for
the advanced learner at `k` of 2 and 4, and for the developing learner in four
or five pairs at `k` of 2 and 4. At `k` of 8 the developing learner keeps it in
four pairs of five, but covers fewer scales in four or five and leaves up to
eight scales actionable and never served.

Across all in-scope scales, which every arm is measured over alike, retrieval is
no worse at `k` of 2 for any player in most pairs, and better in every pair for
the advanced and arpeggio-strong players. At `k` of 4 and 8 it falls in most
pairs for the developing and scale-strong players.

The allocator's own contract, per run:

| Diagnostic, per run                         | Range across players and arms       |
| ------------------------------------------- | ----------------------------------- |
| owed selections                             | 9 to 191                            |
| service withheld for a protected winner     | 0 to 124                            |
| decisions where breadth growth postponed    | 11 to 4,086; usually over 1,000     |
| decisions with an owed requirement unserved | 46 to 67 advanced, 236 to 696 other |
| journal counter acted, relative to exact    | 0.8 to 11.5 times as often          |

## What this establishes

Breadth-relative service priority over the existing selectable set does what
service pressure did and more where it matters most: pressure at 100 left the
scale-strong learner's arpeggios and the arpeggio-strong learner's scales
waiting 783 and 817 opportunities, where `k` of 2 holds both under 150 and
covers 19 and 48 of them. Persistent deferral is not specific to one archetype;
it is how v1-14 treats whichever family a learner is weaker in.

There is a capacity frontier, and the floor does not move along it. Small `k`
serves incomplete work and costs retention among what is covered; large `k`
keeps that retention and gives back service, for the developing learner by
covering fewer scales. The protection floor withheld service up to 124 times a
run and still made little consistent difference between 0.60 and 0.70.

The journal-reproducible counter is not an approximation of exact waiting. It
acted on up to eleven times as many decisions and chose differently on most of
them, so building allocation on the journal alone would be choosing a different
policy.

## What it does not establish

Retrieval among covered material is descriptive: the asymmetric players' arms
that look worse on it cover up to three times as many scales. Thousands of
breadth postponements per run say the bound drifts as the catalog opens, not
that any requirement was harmed by it. And hundreds of decisions per run had an
owed requirement with nothing in the selectable set to serve it: whatever kept
it out, the allocation-only stage cannot reach it, which is the support-aware
and prerequisite-aware stages' question. These are synthetic players, and the
frontier informs the product policy rather than choosing it.
