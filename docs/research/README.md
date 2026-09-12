# Research

The evidence KeyRecall is built on, and what we measured about it. Two
directories, because they answer different questions.

**[`foundations/`](foundations/)** asks: _what does outside evidence suggest?_
Learning science, motor learning, piano pedagogy, and the fingering and motor
corpora they produced.

**[`experiments/`](experiments/)** asks: _what did we learn about KeyRecall
itself?_ Synthetic characterization, policy sweeps, calibration work, and the
negative findings.

[`REFERENCES.md`](../REFERENCES.md) carries every citation. Documents here cite
by key and still say in their own prose what a source established, because a
citation key is not an argument.

## foundations

| Document                                               | Covers                                             |
| ------------------------------------------------------ | -------------------------------------------------- |
| [`literature.md`](foundations/literature.md)           | Learner modeling, memory, motor learning, guidance |
| [`fingering.md`](foundations/fingering.md)             | The canonical fingering corpus and its provenance  |
| [`motor-structure.md`](foundations/motor-structure.md) | Derived motor families, phases, crossings          |
| [`arpeggios.md`](foundations/arpeggios.md)             | Arpeggio vocabulary, evidence, and promotion gates |
| [`product-vision.md`](foundations/product-vision.md)   | The competitive landscape and the original thesis  |

## experiments

| Document                                                         | Question it answered                                       |
| ---------------------------------------------------------------- | ---------------------------------------------------------- |
| [`learner-model.md`](experiments/learner-model.md)               | Do the state layers stay separate, and what broke them     |
| [`scheduler.md`](experiments/scheduler.md)                       | Seventeen passes; most promoted nothing                    |
| [`trajectories.md`](experiments/trajectories.md)                 | What goes wrong over a trajectory rather than a decision   |
| [`introduction-breadth.md`](experiments/introduction-breadth.md) | How much new material may be open at once                  |
| [`arpeggio-policy.md`](experiments/arpeggio-policy.md)           | Is the arpeggio policy viable, and is a competency missing |
| [`player-calibration.md`](experiments/player-calibration.md)     | Can a synthetic player be fitted to a real sitting         |

## How to read a negative result here

Most of what these record is that something did **not** work, or worked too
weakly to justify a branch. That is deliberately preserved: an idea that was
tried and rejected costs far more the second time, when nobody remembers the
first.

Three distinctions run through all of them and are worth carrying:

- **Sampled is not identified.** A grid can report that one value passed and
  another failed. It cannot report where the boundary is.
- **An invariant is not an observation.** An invariant is a property any healthy
  system should hold, stated without a tuned number, and is asserted. An
  observation is a count against a threshold picked by judgment, and is reported
  for a person to read. Asserting an observation freezes today's behavior as the
  definition of correct.
- **A mechanism test is not calibration.** Simulation knows the hidden truth, so
  it can expose contradiction and contamination. It cannot tell you a constant
  is right for real pianists.

## What is no longer here

The Python research prototype these experiments ran in has been retired, along
with the CSV artifacts they wrote. The reproduction of the Dart model against it
is in Git history. See [`../../analysis/README.md`](../../analysis/README.md)
for what that removal did and did not change.

Live executable analysis, with recorded playing behind it, remains under
`analysis/`: `onset-grouping/` for what "at the same time" means on a real
instrument, `timing-calibration/` for what steady playing looks like on this
input stack, and `scale-motor/` for the motor realization corpus.

## Extending the model

[`extending-the-model.md`](extending-the-model.md) is the method for proposing,
testing, and promoting a new competency or prediction channel. It is a process
rather than an authorization, and nothing in it permits adding anything.
