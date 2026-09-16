# Performance timing

- **Status:** accepted and implemented in `PerformanceClockMapper`.

Whether KeyRecall is entitled to say when somebody played a note, and what it
does when it is not.

The evidence is eleven recorded traces in
[`../../analysis/transport-clocks/`](../../analysis/transport-clocks/). What
they established about clocks is in that README; the sequencing is in
[`../roadmap.md`](../roadmap.md). This file is the contract the layer has to
meet.

The input boundary already answers what happened in the observed stream; see
[`../system/input.md`](../system/input.md). This answers when, if anywhere, we
may say it happened.

## Arrival time is not a fallback

**Decision.** When performance time is unavailable, timing evidence is
**absent**. Nothing substitutes the arrival clock.

**Why.** This was written as caution and characterization turned it into
correctness. Over a network session the arrival clock reported a scale played by
hand as 717 ms exactly, thirteen intervals out of twenty-eight, where the
transport clock ranged continuously from 669 to 825. Something in that delivery
path regularizes arrival, and the regularized version is what reaches Dart.

**Evidence.** `ios-network-pulse`, onset dispersion of 1.0 ms by arrival against
24.0 by transport, on playing that was known to be by hand because the person
who did it said so. Strong for that path; nothing establishes how widely it
generalizes.

**Consequences.** Temporal stability reads exactly that dispersion, so a
fallback would not be a weaker answer but a confidently wrong one, and it would
reach the learner model as evidence of evenness nobody produced. The cost is
that attempts on an unrecognized transport contribute no timing evidence at all,
which is the outcome this prefers.

It also means **lower dispersion is not better**. A clock reporting the same
interval thirteen times running may be more accurate or may be carrying less,
and no statistic computed from one clock decides which.

Arrival still has two narrower jobs, and the line between them and a fallback is
the whole point:

```text
transport determines elapsed performance time
arrival may only choose an epoch, or veto an interpretation
```

It chooses which epoch a wrapping counter is in, and it refuses a transport
interval that disagrees with it beyond a stated tolerance. It never supplies a
time, corrects one, or smooths toward one, and within the tolerance the answer
does not move by a microsecond however far arrival wanders.

The veto is taken twice, against the step and against the timeline:

```text
each delivery   the interval is one the two clocks can both describe
since anchoring abs(performanceMs - arrivalElapsedMs)
                <= deliverySlackMs + elapsedMs * maxDriftFraction
```

The second is not implied by the first. A clock that has stopped reports an
interval of zero forever, and zero sits inside any short wait's window, so a
whole performance would read as one instant while every step passed. A clock
running at the wrong rate survives the same way, one plausible step at a time.
Measuring from the anchor is what stops a disagreement that accumulates from
hiding by staying small. `maxDriftFraction` is 0.02, against a worst parting of
0.006 of the elapsed time across the recorded takes.

## The output is a time, not a count

**Decision.** The mapper answers with `PerformanceTiming`: either unavailable
with a reason, or available with a performance time in whole microseconds on a
monotonic timeline whose origin is arbitrary. Raw counts do not leave this
boundary.

**Why.** Three domains have been seen, stepping in units of 1, 100,000 and
1,000,000 counts, and the fourth will not be the last. Converting at this
boundary is the difference between adding a domain here and teaching every
reader of timing about a new unit.

Microseconds rather than milliseconds because the network clock resolves to a
tenth of a millisecond, and a whole-millisecond answer would discard the
resolution it was authorized for. Integers rather than a fraction of a
millisecond because these times are compared and replayed, and two runs of the
same arithmetic have to agree exactly. Every characterized clock has a quantum
that is a whole number of microseconds; a domain whose quantum is not cannot be
authorized without first deciding a rounding rule, which is a decision to make
against the trace that produces it.

**Consequences.** Nothing downstream can tell which domain produced a
measurement, which is the point. `available` carries a time and nothing else, so
diagnostics read the mapper's own status for the shape and the state rather than
the number. Measurement gets when; asking why it is believed is a separate
question with a separate answer.

## The origin is arbitrary and stays that way

**Decision.** The timeline is anchored on the first authorized complete sample
of an observation and measured from there. No affine mapping onto the arrival
clock, and no attempt to place performance time on a shared wall clock.

**Why.** Measurement reads intervals. Estimating a transform between two clock
domains is work nothing has asked for, and it would make the arrival clock an
input to performance timing, which is the thing this layer exists to avoid.

**Consequences.** Two observations cannot be compared to each other in
performance time, only within themselves. Nothing measures across an observation
boundary anyway, because an observation boundary is already a measurement
boundary.

## Unavailable is several different things

**Decision.** Unavailability carries a typed reason, at least: `detecting`,
`nonPerformanceDomain`, `unknownDomain`, `ambiguousWrap`, `continuityLost`,
`missingTransportTimestamp`, `implausibleClockStep`.

Each one says what happens next, because that is what the reason is for:

```text
detecting                    transient; becomes active or unauthorized as
                             the measured shape refines

nonPerformanceDomain         no timing while that classification holds, and
unknownDomain                not a clock failure; refinement can lift either

missingTransportTimestamp    this event only; a later complete sample is
                             timed again if continuity still holds

ambiguousWrap                terminal for this observation
implausibleClockStep
continuityLost
```

The three terminal reasons partition cleanly, which is what keeps them worth
distinguishing:

```text
ambiguousWrap          several epoch counts fit, so the reading would be a
                       guess

implausibleClockStep   the domain offers readings and none of them is one the
                       transport and the observation can both be describing

continuityLost         structural: the shape or the authorization changed, or
                       a clock with no characterized wrap ran backward
```

**Why.** Not for the learner model, which treats them alike, but so that
"unavailable" does not become a bucket whose recovery semantics nobody can
state. Three of these are terminal, one is event-local, and the rest can lift on
their own, and that difference is invisible if they share a name.

**Consequences.** More surface to keep honest, and reasons that will turn out to
be the same thing under two names until a trace separates them. The reason
travels for diagnostics, not for measurement: `available` carries a time and
nothing else, and anything wanting to know why that time is believed asks the
mapper's status instead.

## A quantum is not a rate

**Decision.** An authorized clock carries two numbers that are not
interchangeable: the **quantum**, what every observed step is a multiple of,
which is the clock's resolution, and the **rate** `g`, how many counts it
advances per millisecond. The detector measures the quantum and never the rate.
The rate is characterized, and it is what conversion divides by.

**Why.** They coincide on two of the three domains, at 1 and at 1,000,000, and
differ by a factor of ten on the third: the network session steps only in
100,000 counts on a counter running near 1,000,000 counts to the millisecond, so
it resolves to a tenth of a millisecond. Converting by the quantum would run
that one clock ten times fast while passing every test written against the other
two. Measuring the rate instead would put the arrival clock back into the
conversion, which is the thing this layer exists to avoid.

**Consequences.** `ClockDomainShape` stays what was measured, and
`PerformanceClockDefinition` holds the quantum, the rate, and the counter width
that characterization supplies. Authorizing a new domain means recording all of
them, from the trace, in one place.

A definition asserts that one quantum is a whole number of microseconds:

```text
countsPerMillisecond > 0
quantum * 1000 % countsPerMillisecond == 0
```

The characterized clocks satisfy it, at 1000 us and 100 us per quantum. The
assertion is evaluated where the definitions are written, so a domain that does
not satisfy it cannot enter a policy at all, and whoever adds it has to make the
rounding decision first rather than discover later that it was made for them by
a truncation. It is also what makes the conversion exact: every step is a
multiple of the anchored shape's granularity, so every delta converts to whole
microseconds with nothing thrown away.

## A wrap is inferred only when one answer fits

**Decision.** For a wrapping domain of modulus `M` counts and rate `g` counts
per millisecond, a raw delta `r` counts, an arrival elapsed `a` milliseconds,
and a tolerated arrival uncertainty `u` milliseconds:

```text
candidate(k) = r + k * M,  for integer k where candidate(k) >= 0

accept iff exactly one candidate(k) lies within [(a - u) * g, (a + u) * g]
```

No candidate means the clocks disagree beyond what policy tolerates, which is
`implausibleClockStep`; more than one means the wrap count would be a guess,
which is `ambiguousWrap`. Neither is guessed.

A reading outside an established counter is neither of those. A counter modulo
8192 cannot hold 8193, so a sample that does contradicts the shape the timeline
was anchored to: that is `continuityLost`, checked before any candidate is
considered.

A clock with no characterized wrap is the same rule with `M` absent: it offers
one candidate, `r` itself, and the same window either admits it or vetoes it.
Without that, a non-wrapping domain would be trusted without bound, and a raw
clock lurching by twenty seconds under a 700 ms delivery would become a
confident twenty-second interval.

`g` is the rate and not the quantum, which is the whole point of writing it in.
Counts and milliseconds coincide only for the one wrapping domain characterized
so far, at 1 count per millisecond, and a wrapping clock at 100,000 would make
the comparison nonsense while still appearing to work on every recorded trace.
The comparison is made in counts because both bounds convert to counts by
multiplication, which is exact, while converting a candidate to microseconds is
a division that would have to round at the bounds. `u` stays stated in
milliseconds, which is the unit it is reasoned about in.

**Why.** A silence longer than the modulus hides whole epochs, and no sequence
of stamps can say how many. Arrival elapsed time can, and this is the one job it
is trusted with: choosing an integer, not supplying a time.

**Evidence.** `ios-jamcorder-pause` carries a 13,667 ms silence hiding two whole
moduli. Counting one wrap per backward step read it as 1.39 ms per count;
rounding elapsed-minus-step to whole moduli read 1.00044 with no drift across
the gap. Across every take the worst gap sat 0.496 of a modulus from an
ambiguous rounding.

**Consequences.** `u` is 1000 ms: wide enough for a late delivery and for the
drift between two clocks across a long silence, and far enough inside half a
modulus that two candidates cannot both fit, since candidates on the
characterized counter stand 8192 ms apart. It is a parameter with a stated
value, not a constant discovered to be comfortable. The measured margin is
evidence about these traces; the bound is a claim about what the system will
tolerate, and the two must not be confused. A gap wide enough to make two
candidates fit yields `ambiguousWrap`, which is terminal.

## Losing continuity is terminal; a quiet domain is not a fault

**Decision.** Two different things, and the state machine keeps them apart.

> While neither active nor failed, reclassification moves freely between
> `detecting` and `unauthorized`, or enters `active` when the currently measured
> shape becomes authorized. `active` holds only while that same shape stays
> authorized; anything else, including a continuity loss, fails the observation,
> and only a new observation or session returns anything to `detecting`.

Stated as the invariant rather than as a list of edges, because the edges are
policy and the invariant is not. In particular **`unauthorized` reaches `active`
directly.** Granularity is a running greatest common divisor, so a shape can
narrow from an unfamiliar 200,000 straight to a characterized 100,000, and
policy then moves from `unknownDomain` to `performance` with nothing making it
transiently `detecting` on the way. A state machine that only authorized out of
`detecting` would leave that clock unavailable forever.

An authorized domain that then loses continuity **fails for the rest of that
observation**: an ambiguous wrap, an implausible step, an unexplained
regression, or a shape that changes under it.

An **unexplained regression** is a backward step that wrap resolution cannot
justify for the authorized domain. A backward step is not itself a fault, and
saying so would be wrong in the most ordinary case there is: a wrap of the
modulo-8192 counter is exactly a timestamp running backward, several times a
minute. For a characterized shape that has never been seen to wrap, any
regression is unexplained the moment it happens; for a wrapping one, only a
regression that no unique candidate explains.

A **shape that changes** is the other one. Granularity is a running greatest
common divisor, so it can narrow as more steps arrive, and a domain authorized
on eight steps can turn out to be a different one on eighty. While the mapper is
still detecting, that is refinement and costs nothing. Once it is active, the
timeline was built on a shape now known to be wrong, so it fails rather than
reinterpreting what it already emitted.

Staying active takes both halves of what activated it. A reading that keeps the
shape but loses the authorization is the same loss by another route, and an
authorization arriving with no measured shape activates nothing, so there is no
arrangement of readings that anchors a timeline to no domain.

A domain that is recognized and not authorized, or not recognized at all, never
becomes active. It is not a fault, there is nothing to recover from, and it is
not terminal either: the same refinement that can invalidate an active shape can
turn an unfamiliar intermediate one into a characterized shape, so the
classification keeps being re-asked.

**Why.** Once the absolute unwrapped position is lost, later samples cannot
recover it without assuming what happened during the interval that was missed,
and that assumption is exactly the fabrication this layer refuses. It is the
same shape as `InputReducer` being terminal for input integrity until a new
epoch, and for the same reason.

**Consequences.** One bad interval costs the rest of the attempt's timing rather
than one note's. Pitch and order evidence are untouched: a timing failure is not
an input-integrity failure, and only the input boundary may say an observation
was not one continuous performance.

## A clock belongs to the path that stamped it

**Decision.** Every raw envelope can carry a `TimestampSource`: the path that
produced its stamp, and the shape that path's format defines where it defines
one. A change of path is a new clock session for the mapper rather than a shape
changing under the old one. A declared shape stands in for detection until the
stream contradicts it, and policy authorizes it exactly as it would a measured
shape.

**Why.** On iOS the MIDI plugin connects a BLE instrument through its own BLE
decoder, which delivers the BLE MIDI packet timestamp (a 1 ms counter modulo
8192), and then hands the instrument to CoreMIDI in the background once the
operating system exposes it, after which the platform delivers host nanosecond
stamps. Both arrive labeled `ble`, because the plugin names the transport after
the device type. Read as one stream, that handoff either failed an active
timeline for the rest of the observation or, before the first wrap, left the
detector measuring a mixture of two clocks that never identified. Both were
persistent loss of timing across every exercise that followed. Separately, a
millisecond counter is only identified by a wrap, so every observation spent its
first 8.2 seconds of stamped deliveries untimed even though the decoder already
knew the format.

**Consequences.** The route now tells the two paths apart by the device object
the plugin delivers, the BLE route declares its format, and timing through the
plugin's decoder starts with the second delivery. The host route is still
detected rather than declared, since nothing documents its format, so a
handed-off instrument is untimed for the eight steps it takes to identify its
nanosecond clock and is timed after that; see
[`analysis/transport-clocks/`](../../analysis/transport-clocks/) for why that
domain is authorized.

## Events are marked; measurement decides what that is worth

**Decision.** The mapper marks each event timed or untimed and stops there.
Whether a partly timed attempt may be measured for timing, and under what rule,
belongs to measurement.

**Why.** An attempt can begin before the domain is identified, so its first
notes have no performance time and its later ones do. Whether that is a usable
observation is the same kind of question as the five-wait floor in
`TimingEvidence`, and it is answered where the other assessability rules live. A
mapper deciding it silently would be a measurement policy hidden in a transport
layer.

**Consequences.** Transcript notes carry observation time always and performance
time sometimes, and every timing reader has to handle both. The first version
does not retroactively upgrade the notes that preceded authorization; buffering
raw timing to revisit them is a later choice, not a default to fall into.

The representation, which is implemented: `InputTemporalEvent.timing` carries
the mapper's whole answer, including the reason when there is no time, and is
null for a boundary nobody played. `PlayedNote.performanceTimeUs` is what
survives into the transcript, an integer or nothing, with the reason dropped
because measurement has no use for it. Neither layer has a path from observation
time to performance time. What amount and continuity of performance time
justifies a measurement claim is not settled here; those floors belong with the
metrics that consume them, in
[`evidence-and-measurement.md`](evidence-and-measurement.md).

## What the learner is told about an unavailable clock

**Decision.** Unavailable timing is explained where its absence is visible, and
nowhere else. The mapper's own states say which case a learner is in:

```text
detecting                  nothing said; the first notes of an
                           observation are expected to be untimed while
                           the clock is being identified

nonPerformanceDomain,      a quiet, persistent explanation under Ready,
unknownDomain              before the attempt: this connection does not
                           report usable timing, so notes and completion
                           are what will be measured

failed                     the same place, with the recovery: reconnecting
                           opens a new observation, which is the only
                           thing that restores a lost timeline

an event-local hole        nothing said, unless it left a metric
                           unavailable for that attempt

metrics absent on review   explained where they would otherwise be blank,
                           with the attempt's own reason: the clock still
                           being identified, a clock KeyRecall does not
                           read, a lost timeline, missing timestamps, a
                           source that stamps nothing, or too few timed
                           notes
```

**Why.** The attempt is valid and useful, so this is a capability of the
observation path rather than a judgment about the playing, and it must not read
as an error with the performance. A domain that is recognized and unauthorized
is persistent rather than intermittent, which is what earns it an explanation at
the connection rather than per attempt.

**Consequences.** Nothing is shown during an attempt. The transcript keeps no
reason, so the capture keeps why its most recent untimed note was untimed, and
the review turns that into a `TimingShortfall`. An attempt whose notes were all
timed and still has no timing was too short, which is not the connection's doing
and is not said to be.

## Building it in three slices

**Decision.** The state machine first, with a seam for tests to drive
authorization and transitions, and no conversion at all. Then conversion for an
authorized domain that does not wrap, which is a count delta over the clock's
rate, measured from the anchor rather than accumulated so that no interval's
rounding can build up. Then the modulus and the unique-candidate arithmetic,
which keeps the same anchor-relative conversion and only has to establish the
unwrapped position it converts from.

**Why.** The refusals are the part worth being certain of, and they can be
proved before there is anything to convert: that arrival time never produces
`available`, that an unauthorized domain never manufactures a time, that
`failed` stays failed through input that looks fine, that a new observation
clears it, and that a timing failure never becomes an input-integrity failure.
Every one of those is a property of the state machine, and none needs
arithmetic. Leaving them until the wrap logic exists would mix the easiest bugs
in with the hardest.

**Consequences.** A seam that exists for tests, which has to be narrow enough
not to become a second way of driving the mapper in production.

## What this does not decide

Whether the 100,000-count domain generalizes beyond the one session that
produced it. Whether a stall heavy enough to separate the clocks exists, after
three attempts failed to arrange one. Whether the host route stamps every
instrument from its own clock, as it does the two recorded, or somewhere applies
a stamp on receipt. Each would change the policy in `ClockDomainPolicy`, which
is where they would change it, and none would change the arithmetic that
measures a clock.
