# Transport clock characterization

- **Status:** Evidence being collected for a decision not yet made. Four takes,
  on one platform, from two instruments that behave differently.
- **Recorded:** September 13, 2026, iOS 26.6.2, a JamCorder adapter and a Yamaha
  P-525, both over BLE
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

## What the takes show

`analyze.py takes/*.json`. Four takes, all on **iOS 26.6.2**, over BLE, from one
phone. Two instruments, and they do not behave alike:

|                                   | JamCorder adapter          | Yamaha P-525 direct                  |
| --------------------------------- | -------------------------- | ------------------------------------ |
| Tick                              | 1.00000 ms per count       | 1.00009e-06 ms per count             |
| Granularity                       | every step a multiple of 1 | every step a multiple of 1000000     |
| Wrap                              | 8192, seen three times     | none in 23 s, starting near 29 hours |
| Drift against arrival             | 0 ms and 1 ms              | 0 ms and 0 ms                        |
| Jitter                            | -26 to +25 ms              | -14 to +16 ms                        |
| **Simultaneous notes kept apart** | **8 of 8**                 | **3 of 10**                          |
| **Onset dispersion, MAD**         | **8.5 vs 15.5 arrival**    | **14.0 vs 16.0 arrival**             |

The adapter's stamp is a 1 ms counter modulo 8192, which is the BLE MIDI
specification's 13-bit timestamp: six bits in the header byte and seven in the
timestamp byte. The piano's is a nanosecond counter with 1 ms resolution,
already at 29 hours when the take started, and it never wraps.

**The prediction was wrong, and the reason matters more than the prediction.**
These are not two devices disagreeing about a clock. They are two _routes_. The
plugin delivers by the host's own MIDI stack or by the BLE transport the app
injects, and reports which on every message. A BLE instrument the operating
system has paired into CoreMIDI arrives by the host route; one the app's BLE
transport is talking to arrives by the BLE route. KeyRecall was discarding that
field and reading the device's own description of itself instead, so the two
looked identical in the trace.

### One route carries the instrument's time, the other carries the host's

This is the finding with consequences, and it is not about wrapping:

```text
JamCorder, BLE route     two releases arrive in one millisecond
                         carrying stamps 14 ms apart
P-525, host route        a strike and a release arrive in one millisecond
                         carrying the same stamp, four times out of four
```

A host-receive timestamp is arrival time taken slightly earlier. It cannot
recover what the instrument spread out and delivery collapsed, because it is
applied after the collapse. The onset dispersion says the same thing more
quietly: halved on the BLE route, essentially unchanged on the host route.

So the useful reading is not "BLE timestamps work." It is:

> **The route decides whether the transport timestamp is evidence about playing
> at all.** The BLE route carries the instrument's own onset timing. The host
> route carries the host's receive time, which is what KeyRecall already has.

One consequence is worth stating plainly because it is counterintuitive: on this
phone, practising through the adapter yields better timing evidence than
connecting the piano directly.

### What is only inferred

The route is an inference from the shape of the clocks, not yet an observation.
These four traces were recorded before the harness kept the plugin's route
field, so nothing in them names it. Every later take carries `route`, and a
single new pair from the same two instruments will confirm or refute it
directly. Until then, treat the causal story as strongly supported rather than
settled.

The same gap applies to what the P-525 is sending: half its deliveries are
messages KeyRecall does not consume, and the envelope collapsed them all into an
unidentified `other`. Two of them precede every note-on and none precede a
note-off. Later takes record the MIDI type and controller number, so they will
say what those are rather than leaving them to be guessed at.

### What is still open

- **Which route each instrument arrives by**, observed rather than inferred, and
  whether an instrument can change route between sessions.
- **Whether the host route is worth anything at all.** If it is only arrival
  time taken earlier, the honest answer may be that timing evidence is
  unavailable on that route rather than slightly better.
- **What Android routes by.** The wire format is the same specification, so a
  difference there is the plugin or the platform not preserving what the wire
  carried. Which route its BLE instruments arrive by is the thing to read off
  the trace first, since that is what decided the answer here.
- **Unwrapping across a silence.** No take has a gap anywhere near 8192 ms, so
  nothing here tests it. A pause long enough to hide a whole epoch cannot be
  resolved from stamps alone, and the `pause` take is what says whether arrival
  elapsed time is a defensible wrap-count disambiguator or whether timing has to
  go unavailable after a long enough gap.
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
