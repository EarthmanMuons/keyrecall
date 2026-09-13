# Performance timing

- **Status:** accepted. The state machine and conversion for a domain that does
  not wrap are built; the wrap arithmetic is not.

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
`missingTransportTimestamp`, `implausibleClockStep`, `unresolvedWrap`.

Each one says what happens next, because that is what the reason is for:

```text
detecting                    transient; becomes active or unauthorized as
                             the measured shape refines

nonPerformanceDomain         no timing while that classification holds, and
unknownDomain                not a clock failure; refinement can lift either

missingTransportTimestamp    this event only; a later complete sample is
                             timed again if continuity still holds

unresolvedWrap               no timing while that clock is in use, and not a
                             clock failure; the counter is recognized and
                             cannot be placed on a continuous timeline

ambiguousWrap                terminal for this observation
implausibleClockStep
continuityLost
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
candidateUs(k) = (r + k * M) * 1000 / g,  for integer k where the result is >= 0

accept iff exactly one candidateUs(k) lies within [(a - u) * 1000, (a + u) * 1000]
```

No candidate means the clocks disagree beyond what policy tolerates; more than
one means the wrap count is ambiguous. Neither is guessed.

The division by `g` is the whole point of writing it this way. Counts and
milliseconds coincide only for the one wrapping domain characterized so far, at
1 count per millisecond, and a wrapping clock at 100,000 would make the
comparison nonsense while still appearing to work on every recorded trace.
Candidates are converted to time rather than `a` and `u` converted to counts, so
that the uncertainty bound stays a quantity somebody can reason about and the
mapper's public unit is the one the arithmetic is done in.

**Why.** A silence longer than the modulus hides whole epochs, and no sequence
of stamps can say how many. Arrival elapsed time can, and this is the one job it
is trusted with: choosing an integer, not supplying a time.

**Evidence.** `ios-jamcorder-pause` carries a 13,667 ms silence hiding two whole
moduli. Counting one wrap per backward step read it as 1.39 ms per count;
rounding elapsed-minus-step to whole moduli read 1.00044 with no drift across
the gap. Across every take the worst gap sat 0.496 of a modulus from an
ambiguous rounding.

**Consequences.** `u` is a parameter with a stated value, not a constant
discovered to be comfortable. The measured margin is evidence about these
traces; the bound is a claim about what the system will tolerate, and the two
must not be confused. A gap wide enough to make two candidates fit yields
`ambiguousWrap`, which is terminal.

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

## Building it in three slices

**Decision.** The state machine first, with a seam for tests to drive
authorization and transitions, and no conversion at all. Then conversion for an
authorized domain that does not wrap, which is a count delta over the clock's
rate, measured from the anchor rather than accumulated so that no interval's
rounding can build up. Then the modulus and the unique-candidate arithmetic,
which is what `unresolvedWrap` stands in for until it exists.

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
three attempts failed to arrange one. Whether the host-style domain is worth
anything at all under conditions nothing has recorded. Each would change the
policy in `ClockDomainPolicy`, which is where they would change it, and none
would change the arithmetic that measures a clock.
