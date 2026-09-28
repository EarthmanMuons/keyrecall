# Pulse remediation

> **Status:** characterization. The mechanism it fixed the grain of is recorded
> in
> [`acquisition-and-guidance.md`](../../decisions/acquisition-and-guidance.md);
> its thresholds are still provisional.

Whether the players a supplied pulse is for can be told apart from the players
it must leave alone, and whether a sitting brings the same kind of timing
evidence back often enough for a detector to act on it within one.

## What was run

`keyrecall_simulation/bin/pulse_census.dart`, in two parts, over
`PlayerArchetypes.pulseCharacterization`:

```text
intermediate                  steady, ordinary
advanced                      steady, fast
unsteady_pulse_transfers      intermediate, loses half its steadiness alone,
                              a click makes up 80% of that, 15% of it stays
unsteady_pulse_relapses       the same, and none of it stays
unsteady_pulse_unresponsive   the same, and a click makes up none of it
true_beginner                 unsteady because the hands are
reliable_self_paced           the device sitting the calibration was fitted to
```

The unsteady players are `intermediate` with only the pulse traits turned, so
anything separating them is about the pulse. Every trait defaults to zero, and a
player with none plays bit for bit as before.

**Response.** C major, right hand, one octave, asked for 80, twenty seeds of six
count-in attempts, six under a metronome, and six count-in attempts again.

**Recurrence.** Four seeds of every player through the production scheduler on
the 48-scale catalog, `normal_month` (seven sittings across thirty days), at
twelve and at twenty-four slots a sitting. An observation is an attempt that
started and tested the pulse; nothing judges whether its timing was good,
because no threshold for that exists yet. Each row asks the same question with a
different meaning of "the same kind":

```text
execution context   material x hands x hand motion
material            the scale, any hands
hands               right, left, or together, any scale
sitting             everything in the sitting
```

## Findings

**The unsteady players separate, and only on steadiness.** Continuity does not
move for any of them, which is the trait working as specified: a weak pulse
drifts rather than stops.

```text
                              steadiness                  tempo ratio
                              before  supplied  withdrawn before  supplied
intermediate                   0.59    0.61     0.63      1.16    1.03
advanced                       0.82    0.81     0.82      1.38    1.07
unsteady_pulse_transfers       0.29    0.56     0.46      1.16    1.03
unsteady_pulse_relapses        0.29    0.55     0.32      1.16    1.03
unsteady_pulse_unresponsive    0.29    0.31     0.32      1.16    1.03
true_beginner                  0.05    0.06     0.06      0.96    0.99
reliable_self_paced            0.88    0.84     0.86      1.38    1.07
```

Transfer and relapse are indistinguishable under the click and apart only once
it is withdrawn, which is why a withdrawal attempt is the evidence and the
supported one is not. An unresponsive player looks the same before and during,
so a remediation policy that reads the supported attempt at all can tell
"responds" from "does not" before withdrawing.

Every player follows a click's tempo most of the way, the unresponsive one
included: being steadied by a pulse and hearing what speed it is going are
separate traits, so a fast player asked for 80 plays near 80 under a click
without needing remediation to get there. Steadiness is otherwise untouched for
the steady players. `true_beginner` reads as unsteady for the same reason it
reads as broken: continuity is as low as steadiness, which is what a
clean-performance precondition exists to separate from a pulse problem.

**Per execution context, a sitting almost never brings the evidence back.**

```text
12 slots a sitting   obs/sit  keys/sit  keys 2+  keys 3+  sits 2+  sits 3+  gap
execution context      9.8      9.3       5%       1%      34%       6%    1
material               9.8      8.0      19%       4%      85%      28%    1
hands                  9.8      2.9      89%      69%     100%      99%    2
sitting                9.8      1.0     100%     100%     100%     100%    1
```

At twelve slots, one sitting in three sees any context twice and one in sixteen
sees one three times. A rule waiting for "the last few attempts in this context"
would almost never fire under the scheduler's interleaving. Grouped by hand
configuration, nearly every sitting has a hand observed three times.

When a context does come back, it comes back within a slot or two. The
candidates for that are the mechanisms that repeat an exercise on purpose,
recovery above all, and a recovery's first attempt failed retrieval, so it would
not pass a clean-notes precondition either. The census does not yet say which
mechanism it was.

Doubling the sitting does not rescue the per-context rule. Twice the
observations spread over twice the contexts, so the share of contexts seen twice
barely moves, and a context seen three times is still a sitting in six:

```text
24 slots a sitting   obs/sit  keys/sit  keys 2+  keys 3+  sits 2+  sits 3+  gap
execution context     19.7     18.1       7%       1%      69%      17%    2
material              19.7     14.9      23%       6%      99%      63%    1
hands                 19.7      3.0      96%      94%     100%     100%    2
sitting               19.7      1.0     100%     100%     100%     100%    1
```

## Remediation under the scheduler

The mechanism as built: per hand configuration within a sitting, three clean
attempts in a row below 0.5 steadiness, then one attempt with a pulse and one
without, once a sitting. Clean means played through, pitch integrity at least
0.9, continuity at least 0.5, and a pulse the player held. Eight seeds of every
player, `normal_month`, twelve slots a sitting, through the production scheduler
with `PulseRemediationConfig` in force:

```text
                              sittings  cycles  withdrawn  steady with  after
intermediate                     0%        0        0          -          -
advanced                         0%        0        0          -          -
unsteady_pulse_transfers        21%       12        5        0.65       0.48
unsteady_pulse_relapses         23%       13        6        0.66       0.42
unsteady_pulse_unresponsive     23%       13        6        0.39       0.42
true_beginner                    0%        0        0          -          -
reliable_self_paced              0%        0        0          -          -
```

**Nobody it must leave alone is given a pulse.** Steady, fast, and self-paced
players never qualify, and neither does `true_beginner`, whose continuity fails
the clean gate before its steadiness is read.

**The supported attempt tells responsive from unresponsive.** 0.65 against 0.39,
where the three had been indistinguishable before it.

**One cycle cannot tell transfer from relapse.** A single supported attempt
moves a transferring player's weakness by an eighth, which the withdrawal cannot
resolve against attempt noise. Six supported attempts in a row did separate them
above, so the question is answerable, just not in one cycle.

**A withdrawal regresses to the mean.** Every unsteady player, the unresponsive
one included, withdraws at about 0.42, above the qualifying attempts that were
selected for being below 0.5. Anything that reads a withdrawal as improvement
has to compare it with unaided attempts that were not selected, never with the
ones that qualified the hand.

**Half the cycles lose their withdrawal.** A hand that qualifies late in a
sitting has its supported attempt and then the sitting ends. At twelve slots
that is roughly half of them. Nothing is recorded wrongly, since a withdrawal
that never happened closes nothing, but a sitting that ends on a supported
attempt has spent it on support alone.

## Consequences

- Qualification is per hand configuration within a sitting, the finest grain the
  evidence reaches, and still session-scoped rather than a trait.
- The intervention stays on the exercise that qualified.
- A player whose continuity is as poor as their steadiness has an execution
  problem, and the clean gate excludes them before steadiness is read.
- The thresholds remain unfit. `temporalStability` saturates on real device
  attempts (see [`player-calibration.md`](player-calibration.md)), so the
  unsteady archetypes are a hypothesis about a learner nobody has recorded yet.

## What the model does not express

- Every player follows a click's tempo by the same default proportion. Nobody
  has been recorded following one, so that number is a placeholder rather than a
  measurement.
- Transfer comes only from supported practice. Unsupported practice never
  improves the pulse, which leaves "improved on its own" out of the picture.
