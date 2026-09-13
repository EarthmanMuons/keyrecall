# Transport clock characterization

- **Status:** Evidence being collected for a decision not yet made. Two takes
  recorded, on one platform through one adapter.
- **Recorded:** September 13, 2026, iOS 26.6.2, a JamCorder adapter over BLE
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

The app's **Transport clocks** developer tool: pick the take, add a note if
there is anything the protocol does not say, press **Start take**, play, press
**Stop**, then save from the toolbar. The take and the note lock while a take is
running, because what they name is the file. It watches the raw boundary and
writes down what crossed it. It converts nothing and computes nothing: the first
traces exist to decide what is worth computing, and a recorder that had already
decided would bake its assumptions into the dataset meant to test them.

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

## What the first two takes show

`analyze.py takes/*.json`. On **iOS 26.6.2, a JamCorder adapter over BLE**, in a
`pulse` and a `chords` take:

| Question                    | What the traces say                                   |
| --------------------------- | ----------------------------------------------------- |
| Tick unit                   | 1.0000 and 1.0001 ms per count, over 8.7 s and 16.1 s |
| Modulus                     | 8192, from three wraps measured at 8166, 8185, 8205   |
| Packet time or message time | message time                                          |
| Short-term jitter           | -26 to +25 ms, median 0                               |
| Cumulative drift            | 0 ms over 8.7 s, 1 ms over 16.1 s                     |
| Stamps absent or repeated   | none absent; one tie, at 1 ms resolution              |

**The transport stamp is message time, not packet time.** Eight arrival instants
in the chords take carried more than one message, and all eight kept distinct
transport stamps. Two releases arrive in the same millisecond carrying stamps 14
ms apart; a four-note chord arrives with three notes in one millisecond and
stamps of 1873, 1885, 1886, 1886. That is precisely the information arrival time
destroys.

**It is already the better witness to rhythm.** In the `pulse` take, the same
playing read through the two clocks:

```text
onsets by arrival     median 586 ms   MAD 15.5   range 538..632
onsets by transport   median 582 ms   MAD  8.5   range 556..625
```

Half the dispersion and a range 25 ms narrower, for one scale played once.
Whatever produced that extra spread in the arrival series happened after the
keys went down.

### Why 8192 is worth believing before the other traces arrive

It is not a device quirk. The BLE MIDI specification carries a **13-bit
millisecond timestamp**, six bits in the header byte and seven in the timestamp
byte, which is exactly an 8192 ms modulus at 1 ms resolution. The measured
behavior is the specified behavior.

So this predicts what the remaining traces should show, which makes them a test
rather than an exploration:

- **Yamaha direct, iOS.** Should be 1 ms modulo 8192 as well. If it is not, the
  JamCorder is synthesizing timestamps rather than passing them through, and the
  mapper has to characterize per source rather than per transport.
- **Android, either instrument.** The wire format is the same specification, so
  a difference here would be the plugin or the platform not preserving what the
  wire carried. This is the one that decides whether one BLE clock contract can
  cover both platforms.

### What is still open

- **Unwrapping across a silence.** The two takes have no gap anywhere near 8192
  ms, so nothing here tests it. A pause long enough to hide a whole epoch cannot
  be resolved from stamps alone, and the `pause` take is what says whether
  arrival elapsed time is a defensible wrap-count disambiguator or whether
  timing has to go unavailable after a long enough gap.
- **Whether delivery ever stretches rather than collapses.** The `stall` take is
  the proof of value: if the transport intervals keep matching the playing while
  the arrival intervals come apart, that settles which clock rhythm is read
  from.
- **Whether the origin needs mapping at all.** Measurement reads intervals, so
  an unwrapped transport timeline with its own arbitrary origin, held within one
  observation, may be enough. That would avoid continuously estimating an affine
  transformation between two clock domains, with arrival time kept as the
  observation clock and as a check on the transport one.

Takes go in `takes/`, named for the platform, the instrument, and the take.

## What must not happen to this data

Uncertain timing is never repaired into a plausible rhythm. That is the timing
analogue of the rule the input boundary already enforces for malformed input:
where transport timing cannot be trusted, timing evidence goes absent the way a
channel nothing observed goes absent, and pitch and order evidence continue. See
[`docs/system/input.md`](../../docs/system/input.md).
