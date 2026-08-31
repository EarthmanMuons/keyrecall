# The coordination transition

- **Status:** Proposed, not built. A specification to implement and simulate
  against, not a record of production behavior.
- **Written:** August 31, 2026
- **Scope:** When hands-together work should become admissible, relative to
  factual retrieval and single-hand execution competence.

This answers the one question the trajectory audit left open. The audit closed
three apparent scheduler defects by showing they were policy rather than
mechanism: entry tempo, hands-together ranking, and progression stalls. The
hands-together result was that neither `developing` nor `uneven_hands` ever
reached a fully eligible hands-together contest at all, so nothing was losing a
ranking it entered. What blocked them was admission, and admission is a
pedagogical choice this project had never made deliberately.

The chain from evidence to rule is recorded here rather than the rule alone. The
safeguard worth preserving is why this is a narrow exception for one transition
instead of a relaxation of general execution progression, because the second is
the tempting simplification and the evidence does not support it.

## 1. What production does today

Four facts, each of which narrows the question.

**The hands-together prerequisite is already independent of factual retrieval.**
`handsTogetherPrerequisiteSatisfied` (`keyrecall_scheduler/lib/src/`
`execution_progression.dart:174`) reads coordination readiness per hand for this
material at this span, or an existing hands-together record at this or the
narrower span. It asks nothing about whether the learner can retrieve the scale
unaided. The separation of "knows the scale" from "can coordinate the hands" is
therefore already true at the eligibility layer.

**The retrieval coupling lives in one predicate, and it is not
hands-together-specific.** `AdmissionException.executionProgression`
(`scheduler_pipeline.dart:876`) requires `memory.hasFactualRetrieval` alongside
full eligibility and an adjacent execution step. That exception governs every
out-of-band execution advance, so tempo and span advancement ride on the same
line. This is the reason the rule below is a separate path rather than an edit.

**`BAND_EXECUTION_FLOOR` is a different blocker.** The `uneven_hands` cohort was
stopped mostly by the band floor, not by retrieval. No change framed in terms of
retrieval moves that cohort at all. The two questions are independent and were
researched independently.

**The transition is already tightly bounded.** `isCoordinationTransition`
(`execution_progression.dart:334`) holds only while both hands know the scale
and the two have never been put together on it, so the first hands-together
attempt on that material that produced execution evidence ends it, however badly
it went; one that never started leaves it owed. Once per material, not once per
span, and direction is not read. That bound is what makes an exception here
cheap enough to justify: the whole exposure is one slot per scale across a
learner's history.

## 2. What the evidence supports

### Viable components are enough to begin

Early bimanual learning decomposes into a general coordination control policy
and a circuit-specific skill. The policy dominates the first minutes: after
fifteen minutes of training about eighty per cent of improvement was general and
twenty per cent specific to the particular sequence, and switching to a
different circuit after four minutes cost two per cent of performance against
nineteen per cent after fifteen (Yeganeh Doost et al., 2017). That is the
mechanism under Yokoi, Bai and Diedrichsen's (2016) finding of essentially no
sequence-specific transfer between unimanual and bimanual finger sequences.

Together they say the bimanual skill must be learned as a bimanual skill, and
that most of what a first exposure teaches is not tied to the specific scale. So
waiting for single-hand maturity spends the wait on an axis that does not
transfer. The threshold the evidence supports is viability of each component,
not mastery of it.

None of this makes single-hand work redundant. Hayashi and Nozaki (2016) found
that unimanual training _after_ a bimanual skill was nearly learned improved it
further, where the same additional bimanual practice did not. Read carefully,
that is a result about complementarity rather than about ordering: it says
hands-separate work keeps paying after coordination has begun, which is an
argument against treating the transition as a graduation from single-hand
practice, not an argument for delaying it.

### Cued pitch integrity is admissible evidence only for a supplied attempt

This is the piece most easily misapplied, so it is stated as a coupling rather
than a threshold.

The guidance hypothesis holds that performance under augmented feedback
confounds learning with the temporary support, and that frequent guidance
degrades retention once withdrawn; high-frequency physical guidance produced the
poorest retention of the conditions tested (Salmoni, Schmidt and Walter, 1984;
Winstein and Schmidt, 1990; Winstein et al., 1994). Music-specific corroboration
is unusually direct: eleven professional pianists sight-read a piece, practised
it for twenty minutes, then performed from memory without warning, and the
number of mistakes in sight-reading did not correlate with the number in the
memory trial (Aiba and Matsui, 2016).

So cued accuracy is poor evidence for "has learned the scale." But that is not
the claim this gate makes. It needs only "these two hands will not be guessing
at their notes during this attempt," which is a statement about the conditions
of the attempt, and it holds if the attempt is itself supplied. The fading
literature adds that support should be dense early and faded later, with faded
schedules beating constant ones on retention and transfer (Sato-Klemm et al.,
2025), which is what the guidance rungs already do.

**The coupling is load-bearing.** Admitting a cued-evidence transition to an
unguided realization would silently convert "cued single-hand pitch integrity is
sufficient evidence" into "cued single-hand performance proves independent
knowledge," which is exactly the inference the guidance literature warns
against. The supplied requirement is what keeps the first claim from becoming
the second.

### Asymmetry is not a reason to wait

Bimanual piano practice in right-handers produces more symmetric performance,
driven mainly by gains in the left hand, and appears to rebalance
interhemispheric inhibition that otherwise favors the dominant hemisphere
(Chieffo et al., 2016; Kilincer et al., 2019). The piano-specific review reaches
the pedagogical form of the same conclusion: bimanual practice with explicit
attention to the weaker hand, rather than indefinite isolated weak-hand work
(Pang et al., 2023).

No head-to-head trial of continued weak-hand-only work against early slow
bimanual work was found, so this is convergent rather than decisive. Nothing
found supports withholding hands-together work until the hands converge, which
is what `BAND_EXECUTION_FLOOR` currently does to `uneven_hands`.

### Familiarity is material-specific, not general

Two findings pull apart, and a curriculum resolves them.

Against a general gate: most of what the first exposure teaches is not
circuit-specific, so unfamiliar geography does not waste the exposure.

For a scoped one: attentional cost and pattern stability covary, so an unstable
pattern is also an expensive one (Temprado et al., 2002), and interlimb
interference falls when the two hands' patterns unify into a single spatial
conception (Franz et al., 2001).

The ABRSM ladder settles which kind of familiarity is meant, and it is unusually
legible evidence:

```text
grade 1    C G F major, A D minor          hands separately
           C major                          contrary motion
grade 2    G F major, A D minor             hands together   <- grade 1's keys
           D A major, E G minor             hands separately <- new this grade
grade 3    D A major, E G minor             hands together   <- grade 2's keys
           Bb Eb major, B C minor           hands separately <- new this grade
```

Hands-together promotion is per scale, one grade behind that scale's own
hands-separate introduction, while the keys newly introduced at each grade stay
separate. That is a material's own record gating its own coordination, not a
general attainment level gating all coordination. It is the same argument
already written into the band-before-band rule in `eligibilityFor`: the
material's own record is a stronger claim than a general execution mean. Applied
here, the coordination-readiness requirement on both hands for this material at
this span already carries every bit of familiarity the evidence asks for, and
the band floor on top of it is the general estimate vetoing the specific record
a second time.

This does not license relaxing `BAND_EXECUTION_FLOOR` anywhere else. Elsewhere
there is no per-material record standing behind the candidate.

### Contrary motion first

Pedagogy is close to unanimous that the first hands-together scale should be
contrary motion: the hands mirror, the same fingers align, and the thumb
crossings happen simultaneously, whereas parallel motion pairs non-homologous
fingers. ABRSM encodes it by putting contrary-motion C major at grade 1, before
any similar-motion hands-together scale exists.

`isCoordinationTransition` deliberately does not read direction, and its stated
reason survives intact: up and up-down are not two first encounters with playing
a scale using both hands. But that argues against a _second transition_, not
against a _preference_ in how the single one is spent. Since the transition is
consumed by whichever hands-together exercise wins it, a parallel-motion winner
spends the once-per-material budget on the harder of the two realizations.

**The domain now represents contrary motion but cannot yet produce it, so this
is not a scheduler change yet.** See section 5; the argument above is why the
representation was worth adding, not a rule to implement now.

## 3. Proposed policy shape

A coordination-transition-specific admission path, alongside
`AdmissionException.executionProgression` rather than inside it.

```text
admit when
    isCoordinationTransition(state, exercise)        already once-per-material
    and each hand's pitch integrity on this material
        at this span clears CALIBRATION                       see section 5
    and exercise.guidance.isMaterialSupplied                  load-bearing
bypass, for this transition only
    memory.hasFactualRetrieval
    BAND_EXECUTION_FLOOR
retain
    handsTogetherEntryTempo, a rung below the slower hand
    once-per-material consumption, ended by the first attempt
```

Coordination readiness on both hands is already the entry condition of
`isCoordinationTransition`, so the pitch-integrity requirement is an additional
bar on the same records rather than a second source of truth.

Both bypasses are load-bearing and each carries a cohort: section 5 measures
`BAND_EXECUTION_FLOOR` as what blocks `uneven_hands` and admission as what
blocks `developing`, so a path that dropped either would leave one of them where
it is.

Contrary-motion preference is **not** part of this. It is deferred to future
domain support, in section 5.

## 4. Explicit non-changes

Recorded as decisions, because each is a place where a later reader will be
tempted to generalize this exception and the evidence does not support it.

- **Ordinary execution-progression admission is unchanged.** Its retrieval
  requirement stays as written.
- **Factual retrieval still gates tempo and span advancement.** Nothing
  researched here concerns those axes.
- **`BAND_EXECUTION_FLOOR` is not weakened generally.** It is bypassed for this
  one transition, on the material's-own-record argument, and nowhere else.
- **No second transition by direction or by hand motion**, and no
  contrary-motion ranking preference in this change. Hand motion is a
  realization condition, not a new skill state; see section 5.
- **No ranking changes outside the coordination transition.** The rank key,
  repetition policy, and tempo policy are untouched. The audit gave no evidence
  to disturb them.
- **No change to new-material policy.** `unseenMaterialRequiresCue` and the
  admission bands govern introduction as before.

## 5. What measurement settled, and what it did not

**The per-hand pitch-integrity threshold is not literature-derived.** Nothing
found licenses a specific value, and the honest reason is that the literature
studies movement learning rather than the three-way separation this project
maintains between retrieving the pitch structure, executing each hand, and
coordinating both. It should be introduced as a named calibration parameter on
`SchedulerConfig`, versioned like every other provisional number, and candidate
values tested in simulation.

It should not be chosen first and then described as pedagogically established.
The literature supports the _shape_ of the rule, which is that per-hand pitch
integrity rather than factual retrieval is the right channel to read. It
supports no number in it.

### Contrary motion: represented, not yet reachable

**The representation exists.** `HandMotion` is a persisted execution condition,
carried in `ExecutionConditions` identity, equality, hashing and the journal,
and rejected for anything but two hands. No exercise is contrary yet: nothing in
realization or generation can produce one.

The two axes are kept apart because they are orthogonal. Both hands traverse the
same `upDown` exercise whether they move together or apart, so folding contrary
motion into `ScaleDirection` would conflate the temporal traversal of one line
with the relationship between two.

```text
ScaleDirection   up | upDown            the traversal of one line in time
HandMotion       parallel | contrary    the relationship between two hands
                                        contrary needs hands together
```

The dependency chain, with the first step done:

```text
[x] represent hand motion as a persisted execution condition
[ ] realize contrary motion, and generate candidates for it
[ ] give it fingering and expected notes
[ ] prefer it in ranking while the coordination transition is unspent
[ ] re-baseline the cohorts
[ ] then calibrate the pitch-integrity threshold
```

Nothing before the fourth step is a scheduler change. Two consequences of the
first step are recorded elsewhere: the transition stays once per material rather
than becoming one per hand motion, in
[`../domain-model/progression-graph.md`](../domain-model/progression-graph.md);
and learner execution state is **not** keyed by hand motion today, so parallel
and contrary hands-together work still share one frontier. Splitting that is the
next model decision, and the argument for it is that a contrary-motion frontier
should not certify parallel-motion execution nobody has demonstrated.

The reference digest is the other loose end. `discreteDigestFields` has no hand
motion column, which is harmless while every exercise is parallel and stops
being harmless the moment one is not, since two runs differing only in hand
motion would then hash the same. That digest is computed on both the Dart and
frozen Python sides, so closing the gap and retiring the Python provenance are
the same decision, taken when the second step above lands.

**This ordering also gates the calibration above.** Contrary motion is the
easier first coordination task, so a pitch-integrity threshold tuned while every
first hands-together attempt is parallel motion would be tuned against a
harder-than-intended task and would read as higher than it needs to be.
Calibrate after the representation exists, not before.

### Three cohort facts, measured

From `keyrecall_simulation/bin/ht_admission.dart` over every evaluated candidate
carrying the transition term, 20 seeds by 60 slots:

```text
                    slots   supp    elig  admit    won
uneven_hands          642    642      55     66     50
developing            480    480     480    109    102
true_beginner           5      5       0      0      0
```

**`uneven_hands` is blocked by `BAND_EXECUTION_FLOOR`.** 642 slots hold a
transition candidate and 55 hold a fully eligible one. Of 29,004 blocked
candidates, 19,336 are material-supplied, which is the two-thirds the three
generated guidance rungs predict. So a supplied-only exception can bypass that
blocker with no change to generation.

**`developing` is blocked by admission, not eligibility.** Every transition
candidate is `FOUNDATION_MATERIAL` and fully eligible, and only 109 slots of 480
see one admitted. Dropping the retrieval requirement in the same
coordination-specific path is what reaches this cohort.

**`true_beginner` barely reaches the predicate at all**, 5 slots in 1200. This
policy should not be presented as solving beginner hands-together onset. Whether
coordination readiness is reachable that early is a separate reachability and
calibration question.

**These facts survive the contrary-motion work.** They are about the admission
path, not about the direction of the scale, which is why the sequence above
measures the mechanism now and re-baselines latency later.

### A measurement invariant this cost us

The first version of the diagnostic aggregated over a slot's winner and
alternatives and reported the opposite conclusion. `TrajectorySlot.alternatives`
is built from the selectable set, so it holds only candidates that already
survived admission and the repetition guard. See
[`trajectory-simulation.md`](trajectory-simulation.md).

## Sources

Motor learning:

- Yeganeh Doost, Orban de Xivry, Bihin and Vandermeeren, "Two Processes in Early
  Bimanual Motor Skill Learning," _Frontiers in Human Neuroscience_ 11:618
  (2017), doi:10.3389/fnhum.2017.00618.
- Yokoi, Bai and Diedrichsen, "Restricted transfer of learning between unimanual
  and bimanual finger sequences," _Journal of Neurophysiology_ (2016),
  doi:10.1152/jn.00387.2016.
- Hayashi and Nozaki, "Improving a Bimanual Motor Skill Through Unimanual
  Training," _Frontiers in Integrative Neuroscience_ 10:25 (2016),
  doi:10.3389/fnint.2016.00025.
- Salmoni, Schmidt and Walter, "Knowledge of results and motor learning: a
  review and critical reappraisal," _Psychological Bulletin_ (1984).
- Winstein and Schmidt, "Reduced frequency of knowledge of results enhances
  motor skill learning," _JEP: Learning, Memory, and Cognition_ (1990).
- Winstein, Pohl et al., "Effects of physical guidance and knowledge of results
  on motor learning: support for the guidance hypothesis," _Research Quarterly
  for Exercise and Sport_ 65(4) (1994), PMID 7886280.
- Sato-Klemm, Williams, Chisholm and Lam, "Comparing the effects of faded vs.
  constant knowledge of results on the acquisition, retention, and transfer of a
  skilled walking task," _Human Movement Science_ (2025).
- Temprado, Monno, Zanone and Kelso, "Attentional demands reflect
  learning-induced alterations of bimanual coordination dynamics," _European
  Journal of Neuroscience_ 16(7) (2002).
- Franz, Zelaznik, Swinnen and Walter, "Spatial conceptual influences on the
  coordination of bimanual actions: when a dual task becomes a single task,"
  _Journal of Motor Behavior_ 33(1) (2001).

Piano-specific:

- Pang, Zhao, Wang, Wang and Fang, "Piano practice with emphasis on left hand
  for right handers: Developing pedagogical strategies based on motor control
  perspectives," _Frontiers in Psychology_ (2023),
  doi:10.3389/fpsyg.2023.1124508.
- Chieffo et al., "Motor Cortical Plasticity to Training Started in Childhood:
  The Example of Piano Players," _PLOS One_ (2016),
  doi:10.1371/journal.pone.0157952.
- Kilincer, Ustun, Akpinar and Kaya, "Motor Lateralization May Be Influenced by
  Long-Term Piano Playing Practice," _Perceptual and Motor Skills_ 126(1)
  (2019).
- Aiba and Matsui, "Music Memory Following Short-term Practice and Its
  Relationship with the Sight-reading Abilities of Professional Pianists,"
  _Frontiers in Psychology_ (2016), doi:10.3389/fpsyg.2016.00645.

Curriculum:

- ABRSM Piano Practical Grades syllabus, 2025 and 2026.
- ABRSM Piano Star 1.

Curriculum evidence gives progression landmarks. It does not by itself establish
a learner-model gate, and the ladder above is used for the per-material shape of
the distinction rather than for any threshold.

## Related

- [`future-planning.md`](future-planning.md) §4.10 records the two prerequisite
  fixes that preceded this and the remaining selection latency, which is a
  ranking question this note does not touch.
- [`../domain-model/progression-graph.md`](../domain-model/progression-graph.md)
  is the authority for the separate-hands-to-hands-together edge itself.
- [`../domain-model/material-admission.md`](../domain-model/material-admission.md)
  covers why grades are not bands, which is the constraint the ABRSM ladder
  above is read under.
