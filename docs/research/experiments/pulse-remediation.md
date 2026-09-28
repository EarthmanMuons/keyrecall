# Pulse remediation

> **Status:** characterization. Nothing here decides what opens timing
> remediation; it says what a rule for that has to work with.

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
intermediate                   0.59    0.61     0.63      1.16    1.16
advanced                       0.82    0.81     0.82      1.38    1.38
unsteady_pulse_transfers       0.29    0.56     0.46      1.16    1.03
unsteady_pulse_relapses        0.29    0.55     0.32      1.16    1.03
unsteady_pulse_unresponsive    0.29    0.31     0.32      1.16    1.16
true_beginner                  0.05    0.06     0.06      0.96    0.96
reliable_self_paced            0.88    0.84     0.86      1.38    1.38
```

Transfer and relapse are indistinguishable under the click and apart only once
it is withdrawn, which is why a withdrawal attempt is the evidence and the
supported one is not. An unresponsive player looks the same before and during,
so a remediation policy that reads the supported attempt at all can tell
"responds" from "does not" before withdrawing.

Steady players are untouched. `true_beginner` reads as unsteady for the same
reason it reads as broken: continuity is as low as steadiness, which is what a
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

## What this leaves step 3

- Qualification cannot be per execution context and fire in practice. Per hand
  configuration, within a sitting, is the finest grain the evidence reaches.
  That is a claim about the sitting's pulse on that hand, still session-scoped
  and still not a trait.
- The intervention itself can stay on one exercise, since what it holds fixed is
  a choice the scheduler makes, not something it has to wait to observe.
- A player whose continuity is as poor as their steadiness has an execution
  problem, and qualification has to exclude them by that rather than by a
  steadiness threshold alone.
- The thresholds remain unfit. `temporalStability` saturates on real device
  attempts (see [`player-calibration.md`](player-calibration.md)), so the
  unsteady archetypes are a hypothesis about a learner nobody has recorded yet.

## What the model does not express

- One responsiveness governs both how much a click steadies the player and how
  far it pulls their tempo, so a steady player with no pulse traits ignores a
  metronome's tempo entirely. Harmless while nothing supplies a pulse to them,
  and worth splitting before any run does.
- Transfer comes only from supported practice. Unsupported practice never
  improves the pulse, which leaves "improved on its own" out of the picture.
