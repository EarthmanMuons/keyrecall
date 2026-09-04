# Arpeggio policy characterization

- **Status:** Full-catalog baseline and transfer diagnostic; no policy promoted
- **Date:** September 4, 2026
- **Corpus:** 24 provenance-backed major/minor root-position arpeggios

## Question

The arpeggio fixture has enough topology, fingering, progression, and practice
machinery to ask whether its provisional policy forms a viable practice system.
Synthetic trajectories cannot calibrate pedagogy. They can reveal dead ends,
concentration, and sensitivity before the catalog becomes expensive to change.

The experiment varies one assumption at a time:

| Arm                    | Difference from baseline                         |
| ---------------------- | ------------------------------------------------ |
| `transfer_0`           | `rhoFamily = 0`                                  |
| `transfer_0_70`        | `rhoFamily = 0.70`                               |
| `floor_separate_hands` | both separate hands may enter through the floor  |
| `floor_up_down`        | RH ascending-and-descending floor and candidates |
| `tempo_50`             | initial arpeggio tempo is 50 BPM                 |
| `tempo_70`             | initial arpeggio tempo is 70 BPM                 |

The baseline remains `rhoFamily = 0.35`, RH ascending acquisition at 60 BPM.
None of the arms changes production configuration.

## Entry-tempo contract

The first census found that arpeggio candidate generation could vary its initial
tempo while generic scheduler mechanisms continued to treat 60 BPM as the entry
realization. Scope resolution now carries a family-neutral `PracticeEntryPolicy`
into the scheduler. Candidate generation, acquisition floor generation,
new-material admission, gentle-condition admission, unmeasured-realization fit,
and guidance/retrieval probes therefore use one family entry tempo.

The remaining tempo rules have different ownership:

- `generatedTempi` is the scale family's offered tempo set, whose first value is
  also that family's declared entry tempo;
- `EligibilityConfig.gentleTempoBpm` is the fallback for scheduler callers that
  do not supply a resolved practice policy;
- transferable entry pace remains learner evidence, discounted by admission band
  where appropriate;
- hands-together entry remains one rung below the slower ready hand; and
- tempo and span progression remain adjacent moves from demonstrated frontiers.

Thus a family entry tempo replaces no evidence-derived pace. It supplies the
cold-start fact that was previously implicit in the scale generator.

## Method

`arpeggio_policy` runs the real scope resolver, requirement evaluator, practice
session, learner model, scheduler, and acquisition floor. The initial fixture
study used four narrow scopes. The full-catalog study replaces them with:

- all 48 supported scales, as the paired milestone control;
- C major and C minor arpeggios, preserving the small-fixture baseline;
- all 24 supported root-position arpeggios; and
- all 48 scales and all 24 arpeggios together.

Arpeggio requirements cover separate hands at one, two, and four octaves and
hands together at two and four octaves. Every selected attempt is played by the
existing synthetic archetype. A run stops only at caught up, blocked, invalid,
or the configured horizon.

The baseline census used four seeds, all eight archetypes, and 80 slots. The
counterfactuals used the same archetype/seed pairs. The original command was:

```console
dart run keyrecall_simulation:arpeggio_policy --seeds 4 --slots 80
```

Full-catalog trajectories are independent by scope, archetype, and seed. The
runner now evaluates them through bounded Dart isolates while preserving report
ordering. The recorded full-catalog baseline used four workers and completed 128
trajectories in 261 seconds; the CLI now defaults to eight workers on the
10-logical-CPU development machine. The recorded command was:

```console
dart run keyrecall_simulation:arpeggio_policy \
  --mode baseline --seeds 4 --slots 80 --jobs 4
```

The report includes family share, floor invocation and selection rates, longest
floor run, first hand/span milestones, admitted-prediction quantiles, in-band
share, progression-stop shares, terminal outcomes, paired scale-milestone
shifts, hand-configuration allocation, material coverage, and fingering-family
concentration.

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
reached the milestone in both paired runs, the first two-octave scale moved 2.8
to 4.0 slots later and the first hands-together scale moved 2.5 to 23.7 slots
later. Those shifts describe allocation in a curriculum with more than twice as
many requirements; they do not by themselves establish over-concentration.

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
beginner's single-material floor rate rose to 40.6% with a maximum run of 44. At
70 BPM it rose to 78.1%, including one complete 80-selection floor run.
Developing and several intermediate profiles also lost early left-hand or
hands-together milestones.

Those outcomes exposed mechanism coupling rather than evidence that 50 or 70 BPM
was intrinsically worse. The family varied candidate generation alone while
generic entry mechanisms still named 60 BPM.

## Family-coherent rerun

The same 704 trajectories were rerun after resolving entry tempo by family. The
60-BPM baseline results and paired scale-milestone shifts were unchanged.

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

## Full-catalog baseline

The complete corpus changed allocation and progression much more than it changed
terminal health. Every baseline run remained actionable through the 80-slot
horizon: no scale-only, small-fixture, arpeggio-only, or full-mixed run blocked,
caught up, or became invalid.

### Family and material allocation

In the full mixed scope, arpeggios received between 51.9% and 80.3% of
selections by archetype:

| Archetype            | Arpeggio share | Materials selected | Peak material share |
| -------------------- | -------------: | -----------------: | ------------------: |
| true beginner        |          57.8% |                 16 |               10.8% |
| developing           |          80.3% |                 24 |                6.2% |
| intermediate         |          55.3% |                 23 |               11.3% |
| advanced             |          52.2% |                 24 |                8.4% |
| fast but placed low  |          74.7% |                 24 |                6.7% |
| tempo noncompliant   |          51.9% |                 24 |               10.8% |
| uneven hands         |          57.2% |                 24 |                8.7% |
| coordination limited |          58.4% |                 24 |               10.2% |

The 24-material arpeggio-only scope selected 23 materials for the true beginner
and all 24 for every other archetype. Its peak individual-material share stayed
between 6.3% and 7.2%. The corpus therefore does not collapse onto a few tonics,
but the developing and fast-but-placed-low mixed trajectories allocate a large
majority of practice to the newly introduced family.

### Fingering-family concentration

Fingering-family shares closely track their representation in the corpus. Each
hands-together selection contributes one exposure to each hand:

| Fingering family | Corpus share | Arpeggio-only | Full mixed |
| ---------------- | -----------: | ------------: | ---------: |
| RH `1235`        |        33.3% |         32.5% |      31.3% |
| RH `2124`        |        14.6% |         16.1% |      17.4% |
| RH `2312`        |         2.1% |          2.2% |       1.6% |
| LH `5421`        |        22.9% |         23.5% |      22.3% |
| LH `5321`        |        10.4% |          8.9% |       8.6% |
| LH `2142`        |        12.5% |         13.1% |      15.2% |
| LH `3213`        |         4.2% |          3.7% |       3.5% |

No geometry is dramatically over- or under-selected. The largest full-mixed
absolute deviation from corpus prevalence is 2.8 percentage points. The
synthetic player has no fingering-geometry trait, so this is a scheduler and
state-sharing check rather than evidence that the physical families are equally
difficult.

### Entry, hands, and progression

The 60-BPM baseline produces no terminal failure, but breadth exposes a
cold-start progression problem. Acquisition-floor invocation and selection are
both zero throughout the full arpeggio and full mixed scopes. Another
new-material candidate remains available before the scheduler needs the floor.
The floor's RH-only shape therefore does not cause RH dominance; it is inactive.

Absence of a terminal failure is not evidence that 60 BPM is a healthy entry.
The true-beginner and developing profiles admit no ranked arpeggio candidate
inside the challenge band in either full scope; fast-but-placed-low admits 3.2%
in the arpeggio-only scope and 0.2% in the mixed scope. New-material bypasses
keep those runs actionable. The census therefore leaves 60 BPM provisional and
shows that catalog breadth can mask entry-fit weakness rather than resolving it.

The true beginner's arpeggio-only selections were 43.8% RH, 55.9% LH, and 0.3%
hands together. All four seeds reached LH near slot 2, but only one reached
two-octave and hands-together work, at slot 79. In the full mixed scope the same
archetype selected 16 arpeggio materials, split 42.7% RH and 57.3% LH, and no
seed reached two-octave or hands-together arpeggio work. The learner escapes RH
immediately but spreads across new separate-hand materials instead of building
depth.

The developing arpeggio-only runs reached hands together in every seed around
slot 15 and two octaves in three of four seeds around slot 68. Intermediate and
stronger profiles reached hands together in every arpeggio-only seed, while
four-octave work appeared only once, for the advanced archetype at slot 78.
Within 80 slots, a realistic-width requirement set primarily measures
introduction and early span progression rather than completion.

The first scale selection remains unchanged in every paired full-mixed run.
Where both paired runs reached the milestone, first two-octave scale work moved
2.8 to 4.0 slots later. First hands-together scale work moved 3.5 slots for the
developing archetype and 13.0 to 45.0 slots for intermediate and stronger
profiles. Several weak or uneven profiles did not reach the same milestone in
both runs, so no delta is reported for them. The broader arpeggio family thus
displaces deeper scale milestones materially even though it does not delay the
first scale.

### Transfer diagnostic

The breadth effects justified a targeted second matrix at `rhoFamily = 0` and
`0.70`, limited to the full arpeggio and full mixed scopes:

```console
dart run keyrecall_simulation:arpeggio_policy \
  --mode transfer --seeds 4 --slots 80 --jobs 4
```

Transfer remains low-sensitivity. The true beginner, developing, intermediate,
advanced, tempo-noncompliant, uneven-hand, and coordination-limited profiles
retain the same family shares and first hand/span milestones across all three
values. Prediction quantiles move by only a few thousandths, and fingering
family distributions are effectively unchanged.

The fast-but-placed-low mixed profile is the only visible allocation exception.
At zero transfer its arpeggio share falls from 74.7% to 72.8%, first
hands-together arpeggio moves from slot 34.3 to 23.8, and one seed reaches four
octaves at slot 51. The `0.70` arm reproduces the baseline categorical summary.
This localized difference does not explain the catalog-wide breadth behavior.

## Decision

No parameter changes follow from this experiment. The 60-BPM entry remains
structurally executable but pedagogically unvalidated, `rhoFamily = 0.35`
remains uncalibrated and low-sensitivity in this harness, and the RH ascending
floor remains unpromoted.

The full corpus does not reveal tonic or fingering-family concentration. It does
reveal that broad new-material availability can dominate acquisition-floor use
and defer within-material progression, while deeper scale milestones move
substantially in the mixed scope. That is the concrete input to the next
learner-model extension analysis: determine whether shared arpeggio execution
plus material-hand residuals represent the observation structure adequately, and
separate state-model limitations from introduction-allocation policy before any
product promotion.
