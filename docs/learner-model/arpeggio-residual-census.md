# Arpeggio residual census

- **Status:** A validated null. No competency proposed.
- **Date:** September 4, 2026
- **Question:** After the allocation confound was controlled, does the model
  leave repeatable error that a material, hand, or fingering-geometry state
  would explain?

The introduction-breadth work removed the earlier ambiguity. A learner failing
to deepen material was two hypotheses at once: a model missing a competency, or
a scheduler that kept introducing new material and never revisited it. Breadth
is now a controlled variable, so the residual question can be asked on its own.

## What is measured

`residual_census` drives four archetypes through the arpeggio-only and full
mixed catalogs and reads each attempt back out of the journal as the difference
between what the model expected and what happened:

```console
dart run keyrecall_simulation:residual_census --seeds 4 --slots 80
```

The execution residual is `motorScore - executionP`, which is the quantity the
execution channel learns from, and the topology residual is
`topologyAccuracy - topologyP`. Per attempt rather than per material, because a
mean says the model is off and only a sequence says whether it is off the same
way twice.

## The instrument, and what it can see

A synthetic player cannot be asked whether a real learner has a
fingering-geometry weakness. Its motor outcome is
`ability(hands) - 3 x strain - spanPenalty x (octaves - 1)`, with no term for
material, geometry, direction, or family. Anything this census finds keyed to
those is either the model disagreeing with a generator it can be checked
against, or an artifact.

That is worth running anyway, for three reasons. A finding is real
misspecification against a known truth. A null is a calibrated reference for the
same analysis on real attempts. And the analysis itself has to be shown to work,
which `residual_census_test.dart` does: split-half reads near zero on pure
noise, above 0.9 on a stable per-cell offset, and exactly zero once a control
explains a cell entirely.

## Repeatability, which is the whole question

Split-half correlation of cell means, odd attempts against even, over cells with
at least four attempts. Noise correlates at zero however far apart the cell
means look, so this is what separates a repeatable effect from a spread of
averages.

| Cell          | Controlled for    | Cells | Arpeggios only | Full mixed |
| ------------- | ----------------- | ----: | -------------: | ---------: |
| material      | nothing           |    24 |          0.036 |     -0.130 |
| material      | hand, tempo, rung |    24 |         -0.018 |      0.125 |
| material-hand | nothing           | 69/54 |          0.319 |      0.230 |
| material-hand | hand              | 69/54 |         -0.119 |     -0.049 |
| material-hand | hand, tempo       | 69/54 |         -0.227 |     -0.146 |
| material-hand | hand, tempo, rung | 69/54 |          0.002 |      0.120 |
| geometry-hand | nothing           | 12/10 |          0.583 |      0.533 |
| geometry-hand | hand              | 12/10 |         -0.205 |     -0.538 |
| geometry-hand | hand, tempo, rung | 12/10 |          0.092 |     -0.396 |

Uncontrolled, both material-hand and geometry-hand look repeatable, and geometry
looks the more repeatable of the two. Neither survives controlling for the hand.
That is the finding: the apparent structure was the hand effect arriving through
cell keys that all contain the hand, and geometry scored highest because it has
the fewest cells and therefore separates hands most cleanly. Material identity
never had any, at 0.036 and -0.130 before controlling for anything.

The controlled figures scatter either side of zero, which is what a null looks
like at ten to seventy cells. Nothing here would be evidence for a material,
material-hand, or fingering-family state even if the generator had one to find.

## What is repeatable

Three effects survive, none of them keyed to material:

| Axis | Level           | Mean execution residual |
| ---- | --------------- | ----------------------: |
| hand | right           |                  +0.108 |
| hand | left            |                  +0.007 |
| hand | together        |                  -0.084 |
| rung | continuous cue  |                  +0.137 |
| rung | notes previewed |                  +0.049 |
| rung | unguided        |                  +0.002 |

Arpeggio-only scope. Quality splits nothing: major +0.043 against minor +0.034.

The topology residual is positive everywhere, around +0.17, so the model
underpredicts topology accuracy across the board rather than for any particular
material.

Requested tempo shows a monotone trend, from -0.146 at 60 BPM to about +0.13 at
the top of the ladder, but that one is confounded by selection rather than
interpretable: a fast rung is only offered to a learner whose frontier is
already there, so the population at 144 BPM is not the population at 60.

## What this does and does not establish

It does not say a fingering-family competency is unwarranted in a real learner.
It says this harness cannot supply evidence for one, that the obvious way to
look for it produces a confident false positive if the hand is not controlled,
and that the analysis reports a clean null on data with no such structure.

The next evidence has to be real attempts. When it exists, the same census runs
against it unchanged, and the controlled row is the one to read.
