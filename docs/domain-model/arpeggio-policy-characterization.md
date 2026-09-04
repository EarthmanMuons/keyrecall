# Arpeggio policy characterization

- **Status:** Family-coherent rerun; no policy promoted
- **Date:** September 4, 2026
- **Fixture:** Sourced C major and C minor root-position arpeggios

## Question

The arpeggio fixture has enough topology, fingering, progression, and practice
machinery to ask whether its provisional policy forms a viable practice system.
Synthetic trajectories cannot calibrate pedagogy. They can reveal dead ends,
concentration, and sensitivity before the catalog becomes expensive to change.

The experiment varies one assumption at a time:

| Arm                   | Difference from baseline                         |
| --------------------- | ------------------------------------------------ |
| `transfer_0`          | `rhoFamily = 0`                                  |
| `transfer_0_70`       | `rhoFamily = 0.70`                               |
| `floor_separate_hands` | both separate hands may enter through the floor |
| `floor_up_down`       | RH ascending-and-descending floor and candidates |
| `tempo_50`            | initial arpeggio tempo is 50 BPM                 |
| `tempo_70`            | initial arpeggio tempo is 70 BPM                 |

The baseline remains `rhoFamily = 0.35`, RH ascending acquisition at 60 BPM.
None of the arms changes production configuration.

## Entry-tempo contract

The first census found that arpeggio candidate generation could vary its
initial tempo while generic scheduler mechanisms continued to treat 60 BPM as
the entry realization. Scope resolution now carries a family-neutral
`PracticeEntryPolicy` into the scheduler. Candidate generation, acquisition
floor generation, new-material admission, gentle-condition admission,
unmeasured-realization fit, and guidance/retrieval probes therefore use one
family entry tempo.

The remaining tempo rules have different ownership:

- `generatedTempi` is the scale family's offered tempo set, whose first value
  is also that family's declared entry tempo;
- `EligibilityConfig.gentleTempoBpm` is the fallback for scheduler callers that
  do not supply a resolved practice policy;
- transferable entry pace remains learner evidence, discounted by admission
  band where appropriate;
- hands-together entry remains one rung below the slower ready hand; and
- tempo and span progression remain adjacent moves from demonstrated
  frontiers.

Thus a family entry tempo replaces no evidence-derived pace. It supplies the
cold-start fact that was previously implicit in the scale generator.

## Method

`arpeggio_policy` runs the real scope resolver, requirement evaluator, practice
session, learner model, scheduler, and acquisition floor. Its four scopes are:

- two scale materials only, as the paired milestone control;
- C major arpeggio only;
- C major and C minor arpeggios; and
- the two scales and two arpeggios together.

Arpeggio requirements cover separate hands at one, two, and four octaves and
hands together at two and four octaves. Every selected attempt is played by the
existing synthetic archetype. A run stops only at caught up, blocked, invalid,
or the configured horizon.

The baseline census used four seeds, all eight archetypes, and 80 slots. The
counterfactuals used the same archetype/seed pairs. The command was:

```console
dart run keyrecall_simulation:arpeggio_policy --seeds 4 --slots 80
```

The report includes family share, floor invocation and selection rates, longest
floor run, first hand/span milestones, admitted-prediction quantiles, in-band
share, progression-stop shares, terminal outcomes, and paired scale-milestone
shifts.

## Baseline observations

The mixed scope selected arpeggios for 39.7% to 53.1% of slots across
archetypes. Arpeggios were therefore active but did not consume a majority for
every learner merely because their state was new.

All archetypes reached both separate hands. Intermediate and advanced learners
reached four-octave work quickly in the single-arpeggio scope; true beginners
did not reach two-octave or hands-together work within 80 slots. This is a
progression observation, not evidence that the synthetic pace is desirable.

No baseline narrow scope blocked, became invalid, or caught up within 80 slots.
The system remained actionable, but this horizon does not demonstrate exercise
exhaustion or maintenance behavior. A longer session would encounter the
scheduler's session cap and would not be evidence about an ordinary product
sitting.

The true beginner used the acquisition floor on 17.5% of selections in the
single-material scope and 10.6% in the two-material scope. The longest
consecutive baseline floor run was three. The floor therefore escaped locally,
although the learner still did not advance to wider work within the horizon.

Adding arpeggios left the first scale slot unchanged. Among archetypes that
reached the milestone in both paired runs, the first two-octave scale moved
2.8 to 4.0 slots later and the first hands-together scale moved 2.5 to 23.7
slots later. Those shifts describe allocation in a curriculum with more than
twice as many requirements; they do not by themselves establish
over-concentration.

## Initial sensitivity observations

Changing `rhoFamily` from 0.35 to 0 or 0.70 produced small admitted-prediction
changes and almost no progression-timing changes in this fixture. The largest
visible allocation change was the true beginner's mixed arpeggio share moving
from 39.7% to 44.1% at zero transfer. Synthetic evidence does not justify a
coefficient, but current scheduling is not broadly dominated by it.

The separate-hand floor changed little outside the true beginner. It increased
that learner's mixed arpeggio share from 39.7% to 46.6% without shortening the
maximum floor run. The ascending-and-descending arm mostly lowered admitted
prediction quantiles, as expected from adding reversal difficulty, without
creating a new terminal failure.

Initial tempo appeared to be the high-sensitivity assumption. At 50 BPM the true
beginner's single-material floor rate rose to 40.6% with a maximum run of 44.
At 70 BPM it rose to 78.1%, including one complete 80-selection floor run.
Developing and several intermediate profiles also lost early left-hand or
hands-together milestones.

Those outcomes exposed mechanism coupling rather than evidence that 50 or 70
BPM was intrinsically worse. The family varied candidate generation alone while
generic entry mechanisms still named 60 BPM.

## Family-coherent rerun

The same 704 trajectories were rerun after resolving entry tempo by family.
The 60-BPM baseline results and paired scale-milestone shifts were unchanged.

Neither tempo arm blocked or became invalid. The maximum floor run was three at
both 50 and 70 BPM; the former 44- and 80-selection runs disappeared. Every
true-beginner seed reached the left hand at both tempi. Other than the true
beginner, no archetype used the floor in either single-arpeggio tempo arm.

Tempo still affects predicted difficulty and therefore practice allocation. In
the true beginner's single-arpeggio scope, the floor-selection rate was 5.0% at
50 BPM, 17.5% at baseline, and 52.8% at 70 BPM. The corresponding mixed-scope
arpeggio shares were 50.9%, 39.7%, and 56.9%. At 50 BPM, three of four
single-arpeggio runs and two of four mixed runs reached hands-together work;
none did so at 60 or 70 BPM within the horizon. These are coherent consequences
of challenge prediction and synthetic outcomes, not evidence for choosing one
tempo.

For intermediate and advanced archetypes, the first separate-hand, two-octave,
and four-octave milestones were nearly invariant across the three tempi.
Hands-together reach varied by seed at 70 BPM in some mixed trajectories, but
without floor dependence or a terminal failure. That remains a policy
sensitivity to revisit with real observations.

## Decision

No parameter changes follow from this experiment. The 60-BPM fixture remains
provisional, `rhoFamily = 0.35` remains uncalibrated, and the RH ascending floor
remains unpromoted. The coherent contract removes the structural blocker to
expanding provenance-backed major/minor root-position fingering coverage.

Real pianist observations remain necessary to choose a tempo, transfer
coefficient, or acquisition-floor shape. Full-catalog characterization must be
repeated before learner-facing promotion.
