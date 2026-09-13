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

`analyze.py takes/*.json`. Nine takes across two platforms and two instruments,
all over BLE.

|                                    | JamCorder, iOS | JamCorder, Android | P-525 direct, iOS |
| ---------------------------------- | -------------- | ------------------ | ----------------- |
| Route, as reported                 | ble            | ble                | **ble**           |
| Tick, ms per count                 | 1.00000        | 0.99941            | 1.00009e-06       |
| Granularity                        | 1              | 1                  | 1000000           |
| Wrap                               | 8192, seen     | 8192, seen         | none in 23 s      |
| Drift against arrival              | 0 ms           | 0 ms               | 0 ms              |
| Jitter, idle                       | -26 to +25 ms  | -30 to +30 ms      | -14 to +16 ms     |
| Chord spread, arrival vs transport | 16 vs 18 ms    | 6 vs 15 ms         | 11 vs 10 ms       |
| Onset MAD, transport vs arrival    | 8.5 vs 15.5    | 15.5 vs 21.5       | 14.0 vs 16.0      |

**Android preserves the BLE MIDI timebase.** Same 8192 modulus, same 1 ms tick,
the same zero cumulative drift. One BLE clock contract covers both platforms.

**The route does not explain the piano.** It was recorded once the harness kept
the field, and it says `ble` for the P-525 as well. Two instruments reach the
app by the same route and carry clocks from different domains: a 1 ms counter
modulo 8192 from the adapter, a nanosecond counter with millisecond granularity
and no wrap in 23 seconds from the piano. The earlier reading here, that the
piano arrived by the host route, was an inference from the shape of its clock
and it was wrong.

What follows is a constraint on the mapper rather than a loose end: **the clock
domain has to be detected from the data, not looked up from metadata.**
Granularity and magnitude are observable at runtime and they separate these two
cleanly. Nothing the transport reports about itself does.

### What a chord costs each clock

Counting how often several notes land in one arrival millisecond does not
compare across platforms, because they coalesce differently. The width of a
group somebody struck together does.

```text
JamCorder, Android   played 15 ms wide, arrival says 6 ms
JamCorder, iOS       played 18 ms wide, arrival says 16 ms
P-525 direct, iOS    played 10 ms wide, arrival says 11 ms
```

Delivery narrows a chord and the BLE stamp knows how wide it was, by more than
half on Android. The piano's nanosecond clock adds nothing: its two readings
agree, which is what a stamp applied after delivery looks like.

### A silence past the wrap, resolved

The `pause` take has a 13,667 ms gap, which hides **two whole moduli**. No
sequence of stamps can say how many epochs went by; arrival elapsed time can, by
rounding elapsed-minus-step to whole moduli.

It is not a close call. Across every take the worst gap sat **0.496 of a
modulus** away from an ambiguous rounding: arrival time would have to be wrong
by about four seconds to pick the wrong epoch, against jitter measured in tens
of milliseconds. After unwrapping that way the pause take reads 1.00044 ms per
count with zero drift across the silence, the same as every other take.

That is the wrap rule, and also where it stops. A gap where arrival time could
be wrong by half a modulus is a gap where timing has to go unavailable rather
than be guessed.

### The stall did not show what it was meant to, on either clock

Under a deliberately loaded app, delivery jitter widened from -26..+25 ms to
**-40..+40 ms** while cumulative drift stayed at zero. So the transport clock
kept tracking through the load, which is the thing that had to be true.

What did not happen is the interesting part: onset dispersion was **26.5 ms by
transport against 25.5 by arrival**, no better. At this scale human timing
variance swamps the delivery jitter the stall added, so the take cannot show a
difference even where one exists. A stall heavy enough to produce multi-hundred
millisecond delivery delays would; this one did not.

The P-525 under the same load says the same thing more flatly: **28.0 ms by
transport against 28.0 by arrival**, and of two arrival instants carrying
several notes, neither kept the stamps apart. Its clock adds nothing under load
either, which is consistent with everything else it has shown.

**Reported as a negative result rather than smoothed over.** The case for
transport time still rests on the chord spreads and the idle onset dispersion,
both of which are real and repeatable. It does not yet rest on the stall.

### What the piano was sending

Half the P-525's deliveries were messages KeyRecall does not consume, two before
every note-on and none before a note-off. They are now identified: **CC 19 and
CC 88**. CC 88 is the MIDI high-resolution velocity prefix, which carries the
low bits of the velocity that follows. CC 19 is undefined in the specification
and is presumably the instrument's own per-note data.

Neither is sustain and neither ends notes, so the reducer ignores both, which is
correct. What changed is that the trace now says so instead of leaving half an
instrument's traffic unidentified.

### What is still open

- **Why two BLE instruments carry different clock domains**, given the same
  reported route. The answer is somewhere in how the plugin obtains a timestamp
  per device, and it decides whether detection can rely on granularity alone.
- **Whether a heavy enough stall separates the clocks.** The one recorded did
  not, on either instrument, and that is a limit of the take rather than a
  finding about the transport. The take that would answer it is a deliberately
  pathological stall against a steady pattern: visible hundreds of milliseconds
  of delivery distortion, where arrival spacing has to collapse or stretch if
  the BLE clock is reconstructing anything arrival time is not.
- **What the host route does**, if anything here ever uses it. Nothing recorded
  so far has.
- **Whether the origin needs mapping at all.** Measurement reads intervals, so
  an unwrapped transport timeline with its own arbitrary origin, held within one
  observation, may be enough.

Takes go in `takes/`, named for the platform, the instrument, and the take.

### The traces check themselves

Several were transcribed by hand from a phone, so `analyze.py` validates each
file before concluding anything from it: contiguous sequence numbers,
non-decreasing arrival time, one device, transport, route, and session
throughout, notes and velocities inside 0..127, a message KeyRecall does not
consume carrying no note, and a timestamp granularity it recognizes. A file that
reports a `PROBLEM` is not evidence, whatever it appears to show. All nine pass.

## What must not happen to this data

Uncertain timing is never repaired into a plausible rhythm. That is the timing
analogue of the rule the input boundary already enforces for malformed input:
where transport timing cannot be trusted, timing evidence goes absent the way a
channel nothing observed goes absent, and pitch and order evidence continue. See
[`docs/system/input.md`](../../docs/system/input.md).
