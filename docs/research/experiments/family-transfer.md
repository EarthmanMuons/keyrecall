# Family transfer

> **Status:** characterization. Scale and arpeggio evidence reach each other's
> predictions by two paths, and the undeclared one carries most of it. No model
> change is made.

Placement convergence left one exception: the arpeggio-strong, scale-weak
player, where a placement offset rather than boundary noise survived 500
attempts, and the suspected carrier was transfer between scale and arpeggio
execution. The question here is narrower: does one family's evidence move the
other family's predictions beyond what that evidence justifies?

## Method

Each player starts from each placement and is given 300 attempts of one family
only, then 300 of the other. A control is given only the second family's 300, at
the same instants, from the same placement, with the same draws. Evidence cycles
through four materials of the family, C, G, and F major and A minor, in eight
shapes, from each hand ascending over one octave to hands together over two
octaves up and down, unguided at 60 BPM, twenty a day. No scheduler is involved.

The synthetic players' abilities are kept per family: practising scales never
improves their arpeggios. Whatever the model moves across families, the evidence
did not justify, and each probe is also played thirty times without practising
to say what the player could actually do.

A probe's execution logit is split exactly into its sources: each motor
competency's own mean times its loading, what the effective means borrow through
the declared family transfer and through the paired hand, the material's own
execution residual, and difficulty. Eligibility is counted over every catalog
material, both hands alone, ascending, asked cued so that the rule holding a
material's first unguided encounter does not mask the execution floors.

```console
dart run keyrecall_simulation:transfer_census --jobs 5 --out transfer.jsonl
```

## Two paths

**Declared family transfer.** Arpeggio execution borrows 35% of its gap to scale
execution, shrinking as its own evidence arrives. Scale execution borrows
nothing from arpeggios.

**Shared competencies.** An exercise's motor prediction splits its credit evenly
over the competencies in play. Multi-octave continuation and direction reversal
belong to neither family, so a two-octave, up-and-down arpeggio takes half its
motor logit from competencies that scale evidence trains, and its own execution
competency a quarter. The one-octave ascending reference the eligibility floors
read has neither.

## Results

After 300 attempts of the first family, the change in the other family's
predictions, and what the player manages on the two-octave probe:

| Player          | Placement | Evidence  | Reference moved | By transfer, logit | Two-octave moved | By shared, logit | Two-octave predicted | Manages |
| --------------- | --------- | --------- | --------------: | -----------------: | ---------------: | ---------------: | -------------------: | ------: |
| Arpeggio-strong | beginner  | arpeggios |           0.000 |              0.000 |           +0.140 |           +0.706 |                0.348 |   0.000 |
| Arpeggio-strong | some exp. | arpeggios |           0.000 |              0.000 |           +0.110 |           +0.443 |                0.527 |   0.000 |
| Arpeggio-strong | some exp. | scales    |          -0.002 |             -0.008 |           +0.004 |           +0.018 |                0.421 |   0.633 |
| Scale-strong    | beginner  | scales    |          +0.094 |             +0.423 |           +0.139 |           +0.599 |                0.347 |   0.000 |
| Scale-strong    | some exp. | scales    |          +0.064 |             +0.260 |           +0.110 |           +0.378 |                0.527 |   0.000 |
| Intermediate    | beginner  | scales    |          +0.082 |             +0.370 |           +0.117 |           +0.512 |                0.325 |   0.567 |
| Intermediate    | beginner  | arpeggios |           0.000 |              0.000 |           +0.117 |           +0.606 |                0.325 |   0.567 |

The within-family gain on the reference over the same attempts is 0.28 to 0.57
from a beginner placement, so cross-family movement on two-octave work is a
quarter to a half of it. It does not depend on the player: the balanced player
moves exactly as much as the split ones, and only for the split ones is it
wrong.

**Persistence.** Against the control, what the first family left in the second
family's predictions after the second family's own evidence:

| Player          | Placement | First     | Two-octave, +10 |   +100 |   +300 | Reference, +300 |
| --------------- | --------- | --------- | --------------: | -----: | -----: | --------------: |
| Arpeggio-strong | beginner  | arpeggios |          +0.133 | +0.109 | +0.071 |          -0.080 |
| Arpeggio-strong | some exp. | arpeggios |          +0.100 | +0.072 | +0.043 |          -0.050 |
| Scale-strong    | beginner  | scales    |          +0.127 | +0.079 | +0.043 |          -0.062 |
| Intermediate    | beginner  | arpeggios |          +0.119 | +0.093 | +0.047 |          -0.044 |

The two-octave excess fades slowly, and as it fades the family's own one-octave
reference falls below the control's. The model reconciles an inflated shared
competency with the family's poor two-octave outcomes by lowering that family's
own execution, so part of the transferred error moves to the reference rather
than disappearing. It is the same identification failure the placement work
found: outcomes load several competencies at once and the evidence corrects
their sum.

**Eligibility.** Transfer changed a count in one cell of the eighteen: the
arpeggio-strong player at some experience, after scale evidence, lost 8 of 22
arpeggios from full eligibility at one octave, while managing 70% of the
reference. The floors read the one-octave reference, which shared competencies
do not reach directly and which family transfer reaches only from scales to
arpeggios.

## What it shows

**The shared competencies carry most of it, and structurally.** Every run moves
two-octave, up-and-down predictions across families by 0.1 to 0.14, three to
five times what the declared transfer moves the reference. A single latent for
multi-octave continuation, and one for direction reversal, cannot be high for
one family and low for the other, and with credit split evenly the family's own
execution term holds a quarter of the logit, too little to absorb the
difference.

**The declared transfer is intentional and bounded, and hurts the wrong way
round.** From scales to arpeggios it moves a beginner's reference by up to 0.09,
and fades with arpeggio evidence. For a player whose families differ, it moves
arpeggio eligibility in the direction of their scales, which is how the
arpeggio-strong player lost arpeggios they could play.

**Not an implementation artifact.** The decomposition sums exactly to the
prediction, and each path does what its code says. The equal split of credit is
a stated V1 simplification; this is what it costs.

Directions, none argued for yet:

- family-specific multi-octave and reversal competencies, or a family term
  inside them, so the shared latent carries only what both families share;
- loadings that give the family's own execution more than an equal share;
- a family transfer that also reads the evidence against it, so a learner whose
  families differ stops borrowing.

## Interpretation boundary

Synthetic players with no true transfer between families, by construction. Real
learners surely carry some, and how much is the question the evidence cannot
settle here: what this measures is how much the model moves, how long it lasts,
and where it goes, not what the right amount is.
