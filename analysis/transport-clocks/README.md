# Transport clock characterization

- **Status:** Evidence being collected for a decision not yet made. Nothing here
  has been recorded yet.
- **Feeds:** the transport-timing entry in
  [`docs/roadmap.md`](../../docs/roadmap.md), step 1 of six

## The question

Input events are stamped with the shared monotonic arrival clock, read when Dart
processes the message. That orders the stream and says nothing reliable about
rhythm: a delayed batch turns separated strikes into near-simultaneous arrivals,
and a delivery stall reads as hesitation.

The transports also supply a timestamp of their own, which the input boundary
preserves on every envelope and deliberately does not interpret. Whether it can
become trustworthy performance time is the question. Substituting it blindly
would exchange one problem for another, because BLE stamps wrap and clock
domains differ between transports.

**None of this is settleable by inspection.** What the units are, whether a
stamp is packet time or message time, how batching behaves, and what a reconnect
does to the transport clock are properties of devices and plugin versions. The
conversion layer's design has to follow what they actually emit.

## How a take is recorded

The app's **Transport clocks** developer tool, which watches the raw boundary
and writes down what crossed it. It converts nothing and computes nothing: the
first traces exist to decide what is worth computing, and a recorder that had
already decided would bake its assumptions into the dataset meant to test them.

Deliveries are taken **ahead of admission and normalization**, so messages the
boundary rejected as foreign, stale, or malformed are in the file too. Those are
exactly the ones that might explain a discontinuity in the ones that were not.

Boundaries are recorded as well as deliveries, because the interesting ones are
otherwise invisible: an app backgrounded with nobody playing delivers no
messages at all, and a jump in the clocks either side of it would have nothing
to be attributed to.

## The takes

Deliberately boring. Each asks about the transport rather than about playing,
and scripting them is what makes the shape of the performance known in advance,
so a discontinuity can be attributed to delivery rather than to hesitation.

| Take         | At the instrument                                  | Answers                                     |
| ------------ | -------------------------------------------------- | ------------------------------------------- |
| `pulse`      | scale or repeated note to a metronome, known bpm   | what both clocks do while nothing is wrong  |
| `chords`     | three or four notes struck together, several times | packet time or message time                 |
| `pause`      | play, stop ten seconds, play again                 | what the clocks do across a gap             |
| `stall`      | keep playing while the app is made busy            | delivery delay, separated from playing      |
| `background` | play, background half a minute, return, play       | continuity across a suspension              |
| `reconnect`  | play, power off or walk away, return, play         | whether a transport clock survives its link |

Record each take on each combination worth comparing. One BLE keyboard on one
phone answers nothing on its own: iOS against Android, BLE against USB, and more
than one instrument are what turn a trace into a characterization.

## What a file holds

A header naming the take, the note the player added, the platform and OS
version, and the instrument and its transport. Then one flat record per line of
the trace, so a column can be read without walking a tree.

A delivery:

```json
{
  "seq": 41,
  "kind": "delivery",
  "arrival_ms": 8123,
  "transport_ts": 2416352,
  "device": "…",
  "transport": "ble",
  "session": "midi-2",
  "channel": 0,
  "message": "noteOn",
  "note": 64,
  "velocity": 91,
  "sustain": null,
  "live": true
}
```

A boundary:

```json
{
  "seq": 42,
  "kind": "boundary",
  "arrival_ms": 8130,
  "boundary": "observationFailed",
  "session": null,
  "adopted_device": "…",
  "adopted_session": "midi-2",
  "fault": "observationGap",
  "detail": "observation suspended"
}
```

`arrival_ms` is the shared monotonic input clock. `transport_ts` is the
transport's own stamp, in the transport's own domain, uninterpreted. Keeping
them apart is the whole point of the file: **arrival order is not performance
timing**, and a trace that had already merged them could not be used to find out
whether it should.

`live` says whether the subscription that delivered a message was still the
current one. `session` on a delivery is the subscription that delivered it;
`adopted_session` on a boundary is what input was being admitted from.

## No analysis script yet

Deliberately. What is worth computing should follow the first traces rather than
precede them, and a script written now would encode guesses about wrap behavior
and batching as if they were findings. Takes go in `takes/`.

## What must not happen to this data

Uncertain timing is never repaired into a plausible rhythm. That is the timing
analogue of the rule the input boundary already enforces for malformed input:
where transport timing cannot be trusted, timing evidence goes absent the way a
channel nothing observed goes absent, and pitch and order evidence continue. See
[`docs/system/input.md`](../../docs/system/input.md).
