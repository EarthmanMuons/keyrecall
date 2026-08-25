# Onset grouping calibration

- **Status:** Evidence for a decision recorded in
  [`docs/domain-model/alignment-contract.md`](../../docs/domain-model/alignment-contract.md)
- **Recorded:** August 25, 2026, one player, one Bluetooth MIDI instrument

## The question

Alignment compares what was played against what the exercise asked for. Before
it can, hands-together observations have to be grouped into moments, because two
hands do not arrive together to the millisecond. How close is "at the same
time"?

The intent was to measure the gap and pick a tolerance. The measurement says a
tolerance is not enough.

## What was recorded

Five takes from the app's onset diagnostic, each a one-octave major scale, hands
together in octaves, up and back down, on a real instrument over Bluetooth MIDI.
Every timestamp is when the event reached the app, so human asynchrony, MIDI
serialization, transport behavior, and the input clock are all inside these
numbers. That is deliberate: it is the same quantity a grouping stage would see
in production.

| Take                         | What it is                               | Played     |
| ---------------------------- | ---------------------------------------- | ---------- |
| `comfortable-c-major`        | played comfortably                       | genuinely  |
| `fast-c-major-with-stumble`  | faster, with a stumble partway up        | deliberate |
| `uneven-d-major`             | comfortable but with an uneven tempo     | genuinely  |
| `deliberate-rolled-c-major`  | slow, deliberately spread                | deliberate |
| `hands-out-of-phase-c-major` | hands drifted a whole step or more apart | deliberate |

## What these takes are not

Three of the five were played badly on purpose, by someone who can play the
scale. That is enough to prove a failure mode is reachable, and not enough to
say how often it happens or what it usually looks like: a competent player
imitating a stumble is not a sample of a learner stumbling.

So the architectural conclusion below rests on existence, which deliberate
playing establishes honestly. Everything distributional here is provisional: the
width of the ambiguous region in particular needs takes from people who are
actually finding the material hard, and from more than one player and
instrument.

## What it shows

**Comfortable playing separates cleanly.** Pairs arrived within 30 ms, most
within 11, three in the same millisecond, while consecutive moments were 254 ms
apart or more. Any threshold between those two numbers would group that take
perfectly.

**Speed and stumbles do not.** This take was mis-played on purpose, so treat its
numbers as a demonstration rather than a measurement. The faster take stretched
pairs to 106 and 134 ms while its shortest step fell to 121 ms. A pair the
player intended as one moment arrived further apart than two moments they
intended as consecutive. The wide pairs sit at moments 3 to 5, around the
stumble.

**No threshold is error-free.** Pooled over 70 pairs and 65 steps, every
candidate either tears real moments apart or glues separate ones together:

```text
T=  40ms   14 moments torn apart    0 glued
T= 120ms   14 moments torn apart    0 glued
T= 150ms   12 moments torn apart    1 glued
T= 200ms   12 moments torn apart    6 glued
```

**Scaling the tolerance with tempo does not rescue it.** Normalizing each gap by
its take's median step was tested on the hypothesis that coordination spread is
proportional rather than absolute. It performs no better than an absolute
threshold, and is recorded here so the idea is not retried from scratch.

**Closeness in time does not mean correspondence.** Also a deliberate take, and
the one the architectural conclusion rests on, since what it establishes is that
the failure mode exists at all. In the out-of-phase take, the right hand ran a
whole step ahead of the left, so notes arrived 23 ms, 43 ms and 44 ms apart that
belong to _different_ moments, while notes belonging to one moment arrived a
second or more apart. A timing threshold there would not merely be uncertain, it
would be confidently wrong.

**Hand order is not stable.** The left hand led 8 of 12, 11 of 12, 10 of 13, 7
of 14, and 2 of 12 across the takes: usually the left, sometimes evenly split,
once mostly the right. Grouping cannot assume a hand starts a moment.

**There is no transport floor.** Seven arrivals landed in the same millisecond,
so Bluetooth is not serializing simultaneous note-ons into a minimum spacing
that the tolerance would have to absorb.

## What follows

Grouping cannot commit to a partition from timing alone. It may propose, and
where the timing is ambiguous it has to say so and let alignment resolve it
against the realization, which is the one place a correspondence judgment
belongs. The contract records that decision.

Still worth recording: attempts by people genuinely struggling with the
material, more players, and other instruments. Not to decide whether ambiguity
is necessary, which these takes settle, but to characterize how wide the
ambiguous region has to be, so a grouper can stay confident at the extremes and
hand over only the middle. Deliberate mis-playing cannot answer that, because
its shape is chosen rather than observed.

## Reproducing

```sh
uv run --no-project python analysis/onset-grouping/analyze.py
```

Takes in `takes/` are exactly what the diagnostic exported, with the file names
made descriptive. Assigning an observation to a hand and a scale degree uses the
fact that these are major scales in octaves, which is legitimate for measurement
and is exactly what the grouping stage is never allowed to know.
