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

`analyze.py takes/*.json`. Six takes: a JamCorder adapter on iOS and on Android,
and a Yamaha P-525 connected directly on iOS, all over BLE.

|                                        | JamCorder, iOS  | JamCorder, Android | P-525 direct, iOS |
| -------------------------------------- | --------------- | ------------------ | ----------------- |
| Route                                  | ble (inferred)  | **ble (recorded)** | host (inferred)   |
| Tick, ms per count                     | 1.00000         | 0.99941            | 1.00009e-06       |
| Granularity                            | 1               | 1                  | 1000000           |
| Wrap                                   | 8192, 3 seen    | 8192, 5 seen       | none in 23 s      |
| Drift against arrival                  | 0 ms, 1 ms      | 0 ms, 0 ms         | 0 ms, 0 ms        |
| Jitter                                 | -26 to +25 ms   | -30 to +30 ms      | -14 to +16 ms     |
| **Chord spread, arrival vs transport** | **16 vs 18 ms** | **6 vs 15 ms**     | **11 vs 10 ms**   |
| **Onset MAD, transport vs arrival**    | **8.5 vs 15.5** | **15.5 vs 21.5**   | **14.0 vs 16.0**  |

**Android preserves the BLE MIDI timebase.** Same 8192 modulus, same 1 ms tick,
the same zero cumulative drift over a take. Whatever differs between the
platforms, the clock the wire carries is not it, and one BLE-route contract can
cover both.

**The route field works, and the adapter goes by the BLE route on Android.**
That half of the causal story is now observed rather than inferred. The other
half, that the directly-connected piano goes by the host route, still rests on
the shape of its clock: those takes predate the field.

### What a chord costs each clock

Counting how often several notes land in one arrival millisecond does not
compare across platforms, because they coalesce differently: iOS put eight
chords into single milliseconds, Android almost none. The width of a group
somebody struck together does compare.

```text
JamCorder, Android   played 15 ms wide, arrival says 6 ms
JamCorder, iOS       played 18 ms wide, arrival says 16 ms
P-525 direct, iOS    played 10 ms wide, arrival says 11 ms
```

On the BLE route, delivery narrows a chord and the transport clock knows how
wide it really was; Android narrows it by more than half. On the host route the
two clocks say the same thing, which is the clearest statement yet that a
host-receive stamp carries nothing about onset that arrival does not.

### One route carries the instrument's time, the other carries the host's

This is the finding with consequences, and it is not about wrapping:

```text
JamCorder, BLE route     two releases arrive in one millisecond
                         carrying stamps 14 ms apart
P-525, host route        a strike and a release arrive in one millisecond
                         carrying the same stamp, four times out of four
```

A host-receive timestamp is applied after the collapse, so it cannot recover
what the instrument spread out and delivery ran together. The onset dispersion
says the same thing more quietly: halved on the BLE route, essentially unchanged
on the host route.

That makes it weaker than instrument time. It does not make it worthless, and
the difference is worth keeping straight, because there are three clocks here
and not two:

```text
BLE route        the instrument's own message time
                 survives host delivery and batching
host route       the host's receive time
                 cannot recover what was collapsed before the host saw it,
                 but is taken before anything Dart does
arrival clock    Dart processing time
                 everything above, plus Dart-side scheduling
```

The `stall` take is what separates the second from the third. Nothing here does:
these takes were played while the app was idle, so host time and arrival time
had no reason to diverge. If a loaded app pulls them apart, host time is
carrying something real and discarding it would throw away evidence.

So the useful reading is not "BLE timestamps work." It is:

> **The route decides what a transport timestamp is evidence about.** The BLE
> route carries the instrument's own onset timing. The host route carries the
> host's receive time, which is a weaker claim and not yet a worthless one.

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

- **Which route the directly-connected piano arrives by**, observed rather than
  inferred, and whether an instrument can change route between sessions. One
  re-recorded iOS pair settles the first half.
- **What the host route is worth.** It cannot carry onset timing, and that is
  settled. Whether it still protects against Dart-side scheduling delay is not,
  and `stall` on a host-routed instrument is what answers it. The layer this
  feeds is likely capability-based rather than binary: source-timed, host-timed,
  or unavailable.
- **Whether Android also exposes a host route.** Its adapter arrives by the BLE
  route and preserves the wire's clock. Whether a directly-paired instrument
  there lands on the host route the way the piano does on iOS is untested, and
  route selection may well differ by platform.
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
