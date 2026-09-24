# Altered forms

> **Status:** characterization of the altered-form foundation across goal and
> focus shapes. The same-tonic prerequisite, exact per-hand breadth, the
> scope-aware cap, and live support are promoted; the breadth numbers are not
> revisited.

The altered-form gate decides when harmonic and melodic minor may first be met.
It was built against the general goal, where the catalog always holds more
ordinary material. The question here is what it does when a goal or focus holds
little, and how much each part of the gate contributes.

## Method

A real practice session per trajectory, so scope resolution, coverage, and the
journal-derived facts are the ones a device uses. Thirteen archetypes, four
seeds, 120 slots, four scopes:

| Scope            | Goal and focus                                                        |
| ---------------- | --------------------------------------------------------------------- |
| `general`        | the production catalog under the general goal                         |
| `broad`          | C G F D A Bb major; A E D G B in natural, harmonic, and melodic minor |
| `narrowAltered`  | the general goal, exclusively focused on D harmonic minor             |
| `foundationOnly` | C and G major, A and D natural minor, A harmonic minor                |

Every first introduction of an altered form records the majors, natural minors,
and bands the profile had retrieved at that moment, whether its own natural
minor was among them, and whether the hands-together waiver was open.

```console
dart run keyrecall_simulation:altered_forms --seeds 4 --slots 120 --jobs 8
dart run keyrecall_simulation:altered_forms --factorial --seeds 4 --slots 120 --jobs 8
```

Retrieval counts at introduction are profile-level memory, not per hand, so they
read the same way before and after the exact per-hand fact existed.

## Commit by commit

The shipped configuration at each step of the change, 52 runs per scope. Each
cell is runs reaching harmonic minor, then runs ending blocked.

| Step                        | general | broad   | narrowAltered | foundationOnly |
| --------------------------- | ------- | ------- | ------------- | -------------- |
| before                      | 33 / 0  | 23 / 30 | 0 / 52        | 0 / 44         |
| natural minor declared      | 32 / 0  | 21 / 29 | 0 / 50        | 0 / 44         |
| same-tonic prerequisite     | 32 / 0  | 21 / 29 | 0 / 50        | 0 / 44         |
| exact per-hand breadth      | 32 / 0  | 18 / 37 | 0 / 50        | 0 / 44         |
| capped at reachable breadth | 32 / 0  | 20 / 25 | 12 / 40       | 17 / 28        |

In the general scope, the mean first harmonic slot moved from 48.7 before to
67.3 after, with 5.3 majors and 4.4 natural minors behind it becoming 6.3 and
4.5, and melodic minor reached in 22 runs rather than 31. All of that arrived
with exact breadth.

## The factorial

The same-tonic prerequisite and the cap crossed, at the final commit:

| Arm           | general | broad   | narrowAltered | foundationOnly |
| ------------- | ------- | ------- | ------------- | -------------- |
| neither       | 32 / 0  | 18 / 39 | 0 / 50        | 0 / 44         |
| same tonic    | 32 / 0  | 18 / 37 | 0 / 50        | 0 / 44         |
| cap           | 32 / 0  | 20 / 25 | 12 / 40       | 17 / 28        |
| both, shipped | 32 / 0  | 20 / 25 | 12 / 40       | 17 / 28        |

## What it shows

**The same-tonic prerequisite costs almost nothing.** Before it existed, 29 of
33 first harmonic introductions in the general scope already followed their own
natural minor, because the foundation band holds both A and D natural minor. The
rule formalizes what the ordinary path mostly did, changes no introduction slot,
and unblocks two runs in the broad scope. Its value is the guarantee, and the
narrow scopes where nothing else would supply it.

**Exact breadth is the change that matters.** The projection credited a hand
with every scale memory held a retrieval of and that hand had played, so a scale
produced by the right hand and played cued by the left counted twice. Counting
each hand's own retrievals delays harmonic minor by about twenty slots and
roughly one more major scale, and melodic minor, which asks for more, loses a
quarter of its arrivals. That is the gate asking for what it always said it
asked for.

**The cap does nothing where it should do nothing.** The general scope always
offers more ordinary material than the requirement, so every general row is
identical with and without it. It acts only where the scope runs out: blocked
runs fall by a third in the broad and foundation-only scopes, and melodic minor
in the broad scope goes from 5 arrivals to 17.

## Coverage retired what the gate waited on

After the cap, the runs still blocked in the narrow scopes were mostly the
strongest archetypes, blocked within a slot or two. From one advanced run
focused on D harmonic minor:

1. Slot 0 offers D natural minor, the declared support, and the right hand
   retrieves it at the notes-previewed rung.
2. That covers the support requirement, and with healthy retrieval it is no
   longer due, so it leaves the slot's candidates.
3. Right-hand D harmonic minor now waits on the phase marker "both hands
   observed", and left-hand D harmonic minor waits on the left hand's own D
   natural minor. Neither can happen: the material both need has been retired.

The broad scope's blocks were the same shape one level up, with core targets
covered before the phase markers were met.

The cap deliberately does not touch the phase markers, which are what the phase
is. The fix is on the offering side and leaves coverage alone: covered material
stays **live** while a due requirement is barred in every realization it asks
for and is waiting on that material. The scheduler, which owns the gate, says
what a barred exercise is waiting on, as material and hand configuration; the
session offers live material only in those configurations and retires it the
moment the dependent moves.

Two narrower versions were tried first and are worth recording:

- **Live while the dependent is barred, whatever it waits on.** An altered form
  waiting on breadth kept its own natural minor live, which adds nothing to a
  breadth it is already counted in, and crowded out the material that would. A
  `fast_but_placed_low` run in the broad scope spent 40 of 60 slots on it.
- **Live material offered in every hand.** The scheduler practiced the hand it
  found easiest, already covered and healthy, and never the hand the barrier was
  waiting for: 45 of 60 slots for `uneven_hands` in the foundation-only scope.

Hands-together waits also name a hand not yet ready at the gentlest span, since
hands together is reached through the separate hands.

With live support, 52 runs per scope, harmonic minor reached and runs blocked:

| Scope            | Harmonic reached | Blocked | Live picks per run |
| ---------------- | ---------------: | ------: | -----------------: |
| `general`        |               32 |       0 |                0.0 |
| `broad`          |               46 |       0 |                5.3 |
| `narrowAltered`  |               52 |       0 |                5.3 |
| `foundationOnly` |               45 |       0 |                2.8 |

Against the capped shipped policy before it, blocked runs fall from 25, 40, and
28 to none, and harmonic minor is reached in 46, 52, and 45 runs rather than 20,
12, and 17. The general scope never offers live support, since it offers
everything already, and is unchanged. Live picks after the first altered form
opened are zero in the narrow scopes; the 1.4 in the broad scope are other
altered forms still waiting on their own natural minors. The runs that end
without harmonic minor end caught up or at the slot limit, not blocked.

## Interpretation boundary

Synthetic players, one sitting, no spacing. The census says when the gate opens,
what it opened on, and whether a scope can finish. It does not say that meeting
harmonic minor twenty slots later teaches it better, and the six and eight
retrievals over two bands remain first guesses for real sittings to revise.
