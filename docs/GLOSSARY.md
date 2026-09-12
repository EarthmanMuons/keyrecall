# Glossary

Every entry opens with a sentence anyone can read, then gets precise enough to
implement against.

Two kinds of link appear here. **Borrowed vocabulary** links outward, to
Wikipedia or a source, for anyone who wants the underlying idea rather than
KeyRecall's use of it. **Our vocabulary** links inward, to the `system/`
document that governs it. If an entry links outward, the concept is not ours; if
it links inward, it is.

This is a lookup reference. It records no design history, supersessions, or
derivations.

## Terms

### Acquisition floor

The safe entry realizations a family offers when nothing else is admissible.

It is a family's answer to "what may this learner be given at all", not a
ranking term: the scheduler reaches for it only after ordinary admission
produces nothing, and a slot it cannot fill is a reasoned block rather than an
absence. It offers **ordinary exercises**, unlike
[below-floor acquisition](#acquisition-task). See
[`system/curriculum.md`](system/curriculum.md).

### Acquisition observation

What an attempt at an [acquisition task](#acquisition-task) produces instead of
an [Outcome](#outcome): no retrieval credit, no tempo reading, and no ordinary
evidence of any kind.

### Acquisition task

A deliberately relaxed version of part of a normal exercise, used to get a
learner started on something they cannot yet do at all.

An `AcquisitionTask` names a parent `Exercise` and relaxes the portion played,
the timing demand, or who advances the sequence. A portion may also ask for the
whole parent more than once, supplying evidence a short pattern cannot supply in
one pass without changing what the material is.

It is **not an `Exercise` and is not convertible to one**, so no ordinary
admission, ranking, or learner-model path can consume it. A criterion success,
meaning a clean first pass with established continuity, makes the unchanged
parent eligible for a [probe](#probe), and only that probe establishes ordinary
readiness. See [`system/practice.md`](system/practice.md).

### Activation

When memory for one exact material was last refreshed.

Represented by `MaterialMemoryState.memory_anchor_at`. A factual retrieval
success sets the anchor to the attempt time; productive supported practice may
move an existing anchor partway toward the present without recording a retrieval
success. Distinct from [current durability](#current-durability) and
[retained consolidation](#retained-consolidation).

### Admission band

The "not too easy, not too hard" window an ordinary candidate has to land in.

`pMin` to `pMax` on the predicted probability of acceptable performance, with a
lower `pIntroductionMin` for material never practiced. A candidate outside it
survives only through a [challenge bypass](#challenge-bypass). Grounded in the
[challenge point framework](REFERENCES.md#motor-learning). See
[`system/scheduler.md`](system/scheduler.md).

### Alignment

The decision about which played note corresponds to which expected note.

Produced by `align()` in `keyrecall_alignment` as an
[edit script](https://en.wikipedia.org/wiki/Edit_distance) over expected moments
and observed arrivals. It is the **only place a correctness judgment is allowed
to be made**, which is why the neutral echo the practice screen draws never
touches it. The search is global rather than incremental, so resynchronizing
after a skip or an extra note falls out of choosing the whole explanation at
once. See [`system/observation.md`](system/observation.md).

### AlignmentReading

The interpretive questions answered beside an [alignment](#alignment) rather
than inside it: whether the attempt was complete, whether it was first-pass
clean, and where it first departed.

It counts repair-shaped patterns rather than naming intentions. An extra note
followed by the right one is what a correction looks like, and also what a
hesitation or a bounced finger looks like.

### Attempt

One presentation and performance of an `Exercise`.

The record includes the decision context, observations, derived outcome,
evidence weights, state transitions, and the state references needed for
deterministic [replay](#replay).

### Attempt journal

The append-only record of every attempt, and the only authority in the system.

Learner state is not stored; it is whatever replaying the journal produces.
Nothing rewrites a record, nothing is aggregated or dropped, and a lost line is
detectable because `journalSequence` is contiguous. See
[`system/history.md`](system/history.md).

### Attempt slot

One scheduler decision opportunity.

Distinct from a [selection](#selection), which exists only when that decision
produces an exercise. A slot that admits nothing is still a slot, and session
caps, replay, diagnostics, and telemetry all have to keep the two apart.

### Bootstrap probe

A [challenge bypass](#challenge-bypass) that offers notes previewed and then
hidden, for material that has been tested but never successfully retrieved.

Its clock uses `last_retrieval_attempt_at`. It exists so never-successful
material cannot become permanently trapped under continuous cueing.

### Candidate

A domain-valid `Exercise` the scheduler is considering.

Candidate generation reads the catalog and the
[instrument profile](#instrumentprofile) and nothing else. It takes no learner
or session parameter at all, and that absence is the enforcement of the boundary
rather than a convention.

### CandidateTrace

The record of what happened to one candidate in one decision: which stage
touched it, which exception admitted or refused it, and where it ranked.

Every candidate comes back with one. The scheduler is a traceable staged policy
rather than a scoring function, and this is what makes that inspectable.

### Caught up

The state where nothing in the current scope warrants practice right now.

Deliberately distinguished from **blocked**, where unresolved requirements exist
but every admission path is closed. Calling blocked "caught up" would turn a
model failure into false progress. The scheduler cannot report either, because
it sees exercises rather than curriculum requirements. See
[`system/curriculum.md`](system/curriculum.md).

### Challenge bypass

The named reason a candidate outside the [admission band](#admission-band) was
admitted anyway.

One of: an explicit override, [recovery](#recovery), a tempo,
[guidance](#guidance-probe), [bootstrap](#bootstrap-probe) or observation probe,
[consolidation](#consolidation-exception), new material,
[execution progression](#execution-progression), or the
[acquisition floor](#acquisition-floor). Every admitted candidate carries either
a bypass or membership in the band, and the trace records which.

### Checkpoint

A cached snapshot of learner state at a point in the journal, so a replay need
not start from the beginning.

**Disposable acceleration and never evidence.** Losing one costs time and
nothing else. It carries the hash of its own content, the journal position it
covers, the model version that produced it, and a chained digest of the history
it skips, and all of those are verified before it is trusted. See
[`system/history.md`](system/history.md).

### Cold-start estimate

The model's belief about recalling material it has never seen recalled, before
there is any anchor to measure forgetting from.

Stored in [logit](https://en.wikipedia.org/wiki/Logit) form, with uncertainty
separate from current-durability uncertainty. Until a first successful
retrieval, elapsed-time durability is not identifiable, so this time-independent
probability stands in for the [half-life](#half-life) curve.

### Competency

A general capability that many different exercises draw on, estimated from
practice across all of them.

This is the mechanism by which evidence transfers: playing G major is evidence
about the major-scale pattern in general. Fifteen are estimated, covering scale
and arpeggio topology, right- and left-hand execution for each family, scalar
crossing, arpeggio transition, multi-octave continuation, direction reversal,
and hands-together coordination. Compare
[material execution state](#materialexecutionstate), which holds what is
specific to one material. `Competency` is the canonical term; see
[retired terms](#retired-terms). See
[`system/learner-model.md`](system/learner-model.md).

### Consolidation exception

A [challenge bypass](#challenge-bypass) offering a scale already met and not yet
produced from memory, at the previewed rung, when the slot has nothing
appropriate left to introduce.

Not to be confused with [retained consolidation](#retained-consolidation), which
is a memory state.

### Continuity

How unbroken a performance was, as an outcome channel.

Reacts to a single interruption, where [temporal stability](#temporal-stability)
reacts to spread across the whole traversal. Both are absent rather than zero
when the playing supplied too few waits to judge one against the others.

### Coordination

How together the two hands were.

An outcome channel, absent for a single-hand attempt and for a two-hand attempt
where no moment had both hands, since zero would say the hands were as far apart
as playing gets. `HANDS_TOGETHER_COORDINATION` is the only competency that
learns from it, and it is deliberately kept out of the motor score.

### Coordination readiness

The spans at which one hand has played a material well enough for the other to
join it, and the tempo it managed there.

Held beside the [execution frontier](#execution-frontier) on
`MaterialExecutionState`, and recorded on any completed attempt whose pitch
integrity reaches `handsTogetherPitchIntegrity`. That is a different claim from
the frontier's and reads a different channel: the frontier asks whether a tempo
and span were played rather than endured, because it is the place a learner is
asked to go on from; this asks whether the notes are known, so that putting the
hands together would be a coordination exercise rather than the simultaneous
remediation of two parts nobody has learned.

The two came apart on exactly the learner the distinction is for. A weak hand
rarely clears the frontier's motor bar, so its frontier stayed empty and
hands-together work was never offered at all.

### Count-in

The beats played before every attempt, at every [guidance rung](#guidance-rung).

Not a reward and not part of the support ladder. The [metronome](#metronome) is
a separate opt-in choice.

### Current durability

How quickly memory for one material is currently fading.

The half-life currently governing decay from [activation](#activation). Always
positive, correctable by factual elapsed retrieval evidence, and never longer
than [retained consolidation](#retained-consolidation).

### Curriculum

A provenance-backed set of requirements describing a coherent body of
capability.

Each `CurriculumRequirement` describes an observable capability in the common
exercise vocabulary rather than naming a scheduler route or an ordered lesson.
Named curricula carry their source and edition, so a syllabus update creates a
new definition rather than silently changing what a completed goal meant. See
[`system/curriculum.md`](system/curriculum.md).

### Decision epoch

A version number on the scheduler's inputs, so an answer computed in the
background can be discarded if the question changed while it was being answered.

Owned by `PracticeSession` and advanced whenever anything a decision reads
changes: a committed attempt, an abandoned decision, a scope change.
[Optimistic concurrency](https://en.wikipedia.org/wiki/Optimistic_concurrency_control),
and deliberately not one of the state hashes, which establish that persisted
history is what it claims to be.

### Derived evidence

The interpretation of raw and summarized observations used to update one
particular state channel, including factual retrieval status and
channel-specific [evidence weights](#evidence-weight).

### Diagnostic fairness guard

A selection rule that eventually takes a ranked independence probe that keeps
losing free contests.

Exploration legitimately dominates a capable learner's early sittings; what it
may not do is dominate indefinitely. It counts opportunities rather than offers,
so a slot narrowed to one candidate was never a contest and nothing lost it. A
selection rule rather than a rank term, because strictly lexicographic ranking
cannot express an urgency that grows.

### Eligibility tier

An ordered classification from pedagogical prerequisites: `FULLY_ELIGIBLE` or
`PROVISIONALLY_ELIGIBLE`.

The **first ranking key, not a weighted term**. No amount of retention or
information advantage lets a provisional candidate outrank a fully eligible one.

### Erase

The one destructive operation, deliberately kept out of the practice loop.

### Evidence weight

How informative one attempt is about one state channel.

Competencies use `w[a,k]`; material memory and execution use distinct `w_M` and
`w_r`. There is deliberately no universal attempt-confidence scalar, because an
attempt can be strong evidence about the fingers and no evidence at all about
memory.

### Execution advance

Which execution axis a candidate advances against the
[frontier](#execution-frontier): none, tempo, span, hands together, or multiple.

Only a single adjacent step is admissible. `multiple` exists so that going wider
and faster at once is structurally excluded rather than merely outranked.

### Execution frontier

The fastest tempo a learner has managed at each octave span, for one material
and one hand configuration.

A tempo per span rather than a widest span and a fastest tempo, since those are
two separate maxima and the pair of them need never have been played together.
It advances only on an attempt that completed with a motor score at or above
`demonstratedMotorScore`, and it is the baseline
[execution progression](#execution-progression) steps from. Held on
`MaterialExecutionState`. Compare [paced tempo](#paced-tempo).

### Execution progression

A [challenge bypass](#challenge-bypass) offering one adjacent execution step on
material already produced from memory: the next tempo rung, one octave wider, or
the same work with both hands.

Exactly one axis moves per candidate. Distinct from
[consolidation](#consolidation-exception), which offers material met and not yet
produced; together with introduction for material never met, the three partition
what is known about a material.

### ExecutionConditions

The requested hand configuration, direction, hand motion, octave count, and
tempo.

These parameterize task difficulty. They are **not** part of material identity.

### Exercise

A requested task, composed rather than enumerated.

`TechnicalMaterial` + `ExercisePattern` +
[`ExecutionConditions`](#executionconditions)

- [`GuidanceContext`](#guidancecontext) + `MotorRealization` + observable
  [opportunities](#opportunity). An exercise is an observable task; a
  [competency](#competency) is the latent capability it gives evidence about.
  See [`system/domain.md`](system/domain.md).

### ExerciseDirection

Which way one line is traversed in time: `UP` or `UP_DOWN`.

Says nothing about the relationship between two hands; that is
[HandMotion](#handmotion).

### ExercisePattern

The ordering or transformation applied to technical material. `LINEAR` today.

### ExerciseRealization

The ordered notes an exercise actually asks for, spelled by scale degree.

One answer, so a staff and a keyboard diagram cannot disagree. The counterpart
to [`PerformanceTranscript`](#performancetranscript).

### Factual retrieval

Whether the learner produced the material from memory, on an attempt where that
was genuinely tested.

Three-valued, and all three must survive serialization exactly:

```text
true    retrieval was tested and succeeded
false   retrieval was tested and failed
null    retrieval was not factually tested
```

"Factual" means tested without concurrent answer-supplying cues. Continuous cues
produce `null`, **not** a weak failure: collapsing the two manufactures evidence
of forgetting out of supported practice. Notes previewed and then hidden remain
a real, lower-demand factual test. Grounded in
[retrieval-practice research](REFERENCES.md#learning-and-memory).

### Family dose control

How often a realization family is offered, given what its recent attempts
actually produced.

Distinct from [realization-family pacing](#realization-family-pacing), which
reads how much of a sitting a family holds rather than what it yielded. In
longitudinal runs the two never change the same slot. See
[`decisions/pacing-and-tempo.md`](decisions/pacing-and-tempo.md).

### Feedback exposure

An append-only record of what the post-attempt review actually showed.

Records the feedback level, whether personal progress appeared, and every named
progress event in the displayed statement. Keyed to an attempt already in the
journal, but **not learner evidence**: it never changes evidence weight and does
not participate in replay.

### Fingering

The concrete canonical fingers expected for one material and hand.

The implemented type is `CanonicalFingering`, reached by
`canonicalFingering(material, hand)`, covering all 48 scales and all 24
supported arpeggios in both hands. Fingering is domain structure, not
presentation metadata. The research behind which fingerings are canonical is in
[`research/foundations/fingering.md`](research/foundations/fingering.md).

### Fluency Profile

The user-facing reading of internal state, such as "recall strong; right-hand
execution developing".

Derived presentation, not an additional latent state.

### Focus

A temporary selection constraint or preference: what should KeyRecall draw from
right now?

Two explicit modes, and not two ends of one slider: `exclusive` stops candidates
outside it from being generated at all, while `emphasis` leaves them eligible
and gives matching ones goal relevance. Compare [goal](#goal).

### Goal

A durable destination: what capability am I trying to establish or maintain?

Multiple goals union their target requirements. Goal relevance is the last
weighted ranking key and must never override eligibility or challenge.

### Guidance probe

A [challenge bypass](#challenge-bypass) presenting anchored material with one
step less guidance, after a configured interval since its last factual retrieval
success.

It tests whether support can fade.

### Guidance rung

One of the three levels of pitch support, from most to least independent:

```text
unguided             no cues at all
notesPreviewedOnly   shown before the attempt, then hidden
continuouslyCued     visible throughout; retrieval is never tested
```

Exactly those three exist, and the constructor is private so no fourth can be
built. The ladder governs **pitch support only**: the [count-in](#count-in)
happens at every rung and the [metronome](#metronome) is a separate choice. See
[`system/domain.md`](system/domain.md).

### GuidanceContext

The instructional and cueing conditions around an attempt.

It changes retrieval demand and how evidence is interpreted. It never changes
how hard the physical task is, and never changes the [Q-matrix](#q-matrix).

### Half-life

How long until the predicted chance of unaided recall falls by half.

```math
M(t)=2^{-\Delta t/h}
```

Borrowed from [radioactive decay](https://en.wikipedia.org/wiki/Half-life), and
from
[Half-Life Regression](REFERENCES.md#adaptive-instruction-and-knowledge-modeling)
in spaced-repetition research. `M = 0.5` means a 50% chance of independently
retrieving the _material_; it does not mean a 50% chance of successfully
performing the requested exercise.

### HandMotion

How two hands move relative to each other: `PARALLEL` or `CONTRARY`.

Valid as `CONTRARY` only when the hand configuration is `TOGETHER`; a single
hand carries `PARALLEL` as its canonical value. Orthogonal to
[ExerciseDirection](#exercisedirection): both hands traverse the same `UP_DOWN`
exercise whether they move together or apart.

### InstrumentProfile

What the connected instrument can physically play.

Enough range information to keep the generator from producing exercises that do
not fit. Other hardware metadata stays descriptive unless validated as a model
input.

### Introduction cap

An experimental limit on how much introduced-but-unretrieved material one scope
may hold open at once.

Carried by `IntroductionConfig` and **null in the shipped configuration**. It
filters the available set beside [pacing](#realization-family-pacing), never
empties it, and leaves admission untouched.

### LearnerState

Everything persistent the model believes about one player:

```text
LatentCompetencyState     what carries across the repertoire
MaterialMemoryState       whether one exact material is retrievable
MaterialExecutionState    what is specific to one material in one hand
```

Excludes short-lived scheduling context, which is [SessionState](#sessionstate).
It deliberately knows nothing about profiles.

### Material family

The declared grouping a `TechnicalMaterial` belongs to: `SCALE` or `ARPEGGIO`.

It decides candidate generation, the acquisition floor, the entry tempo, and
which execution and topology competencies load. **A declared key rather than an
enum the scheduler branches on**, and a source-level test keeps family policy
out of the scheduler package.

### MaterialExecutionState

What is persistently true about one material in one hand that general skill and
task difficulty do not already explain.

A dynamic, [partially pooled](#partial-pooling) learner-by-material-by-context
residual. It also carries the [execution frontier](#execution-frontier),
[coordination readiness](#coordination-readiness), and
[paced tempo](#paced-tempo).

### MaterialMemoryState

Whether one exact material is independently retrievable.

Holds [activation](#activation), [current durability](#current-durability),
[retained consolidation](#retained-consolidation),
[cold-start belief](#cold-start-estimate), uncertainty, and factual retrieval
history. Keyed by learner and `TechnicalMaterial`, **not** by hand or exercise
variant, which is why material identity excludes hand.

### Metronome

An opt-in click during an attempt.

A separate choice the player makes, not a reward unlocked by progress and not
part of the [guidance](#guidance-rung) ladder.

### Metronome ladder

Maelzel's tempo progression, 40 to 208, used as an **adjacency relation rather
than a candidate set**: it defines what the next and previous tempo are.

Its steps grow with the tempo, which is the right shape for a quantity where a
fixed count of beats per minute does not mean a fixed amount at both ends.

### MotorFamily

A higher-level equivalence class over mechanically derived motor realizations,
such as `DIATONIC_3_4_CYCLE`.

**Analysis vocabulary, not learner state.** Nothing in the packages implements
it, and whether it earns a [competency](#competency) is the open question the
residual census exists to answer. From
[`research/foundations/motor-structure.md`](research/foundations/motor-structure.md).

### MotorRealization

The mechanically derived realization of a fingering, including phases,
crossings, continuations, and reversals.

Analysis vocabulary from the same source. What the packages carry is narrower:
`MotorOpportunitySite` for where such an event occurs, and
[`ExerciseRealization`](#exerciserealization) for the notes an exercise resolves
to.

### Observation

A raw or derived fact about an attempt: MIDI events, pitch integrity,
continuity, temporal stability, tempo, or local behavior near an expected motor
event.

Observations stay richer than the persistent latent state, deliberately.

### Observation grouping

Which arrivals plausibly made up one performed moment.

A separate stage before [alignment](#alignment), so the aligner is never asked
to discover simultaneity and musical correspondence at once. It is the only
place a timing tolerance lives, and it knows nothing about keys, octaves, hands,
or scale degrees. **Everything it says is a proposal**, entering alignment as a
cost rather than a constraint.

### Opportunity

A place in an exercise where a competency could be observed: a scalar crossing,
an octave continuation, a reversal, a hands-together event.

Structural only. It does not claim the expected fingering was actually used,
which nothing can observe.

### Outcome

The model-facing reading of one attempt, on separate channels.

Whether execution started, [factual retrieval](#factual-retrieval), completion,
material retrieval, [pitch integrity](#pitch-integrity),
[continuity](#continuity), [temporal stability](#temporal-stability), achieved
tempo, topology accuracy, and [coordination](#coordination). An absent channel
is absent all the way through, never zero.

### Paced tempo

The fastest tempo a learner has actually played a material cleanly, whatever
they were asked for.

Held beside the [execution frontier](#execution-frontier) and deliberately not
folded into it. The frontier records what was _asked for_ and managed, which is
the only thing a step goes on from; this records how fast somebody plays when
nobody is holding them back. Keeping them apart preserves the rule that evidence
at a tempo is earned by being asked for that tempo, while letting an unseen
scale arrive near the speed the learner actually plays. Read by
`transferableTempoFor`.

### Parameter Registry

The versioned numeric configuration for learner and scheduler behavior.

`LearnerParams` and `SchedulerConfig` in the Dart packages are the live
registries and the only statement of the values.
`analysis/learner-model/params.toml` and `analysis/scheduler/config.toml` are
frozen prototype provenance, read by tests as a change detector rather than a
source to conform to.

### Partial pooling

Learning something specific about one material while still borrowing from what
is known in general.

Sparse material-specific evidence stays close to the shared prediction, while
repeated direct evidence permits a larger personalized residual. Approximated
locally with zero-centered priors, conservative updates, and mean reversion.
Standard practice in
[multilevel models](https://en.wikipedia.org/wiki/Multilevel_model); see
[REFERENCES](REFERENCES.md#assessment-and-measurement).

### PerformanceMeasurement

The factual reading of an aligned performance, channel by channel.

Says what was observed, never whether it was any good and never what to do about
it. Produced after [alignment](#alignment) has settled correspondence, so timing
can be read as a property of the performance rather than as further evidence
about which note was which.

### PerformanceTranscript

What was played, in arrival order, with no relation to what was expected.

A literal, append-only record carrying a stable sequence, the spelled pitch, and
an uninterpreted timestamp. Carrying no expected positions is what makes it
usable before alignment exists, and what makes the neutral echo safe.

### Pitch integrity

How correct the sounded pitches were, as an outcome channel.

Reduced by an octave slip, where topology accuracy, material retrieval, and
factual retrieval are all unaffected by one. There is deliberately no register
competency: inventing one because the measurement system can see register would
be letting the sensors write the ontology.

### PlacementTier

The self-report that seeds a cold-start state: beginner, some experience, or
advanced.

It changes the initial competency mean but never makes the model confident, so
direct performance overrides it quickly. Recorded in the journal genesis,
because every posterior is a function of it.

### Probe

An attempt at the unchanged parent exercise, earned by an
[acquisition task](#acquisition-task) criterion success.

Only a probe establishes ordinary readiness or a frontier. An earned probe can
be owed, dormant, or lapsed, and service covers all earlier criterion successes
in event order.

### Profile

One independent practice history on a shared install: its own journal, its own
state, its own session.

The id is opaque and stable, never derived from a display name, because names
change and repeat. Every persisted artifact is scoped by it, and a history's
owner is checked before its content is read.

### Q-matrix

Which competencies each exercise creates an opportunity to observe.

```math
Q_{e,k}\in\{0,1\}
```

`Q[e,k] = 1` means exercise `e` creates an opportunity to observe competency
`k`. It says nothing about how strong the predictor loading or the actual
evidence is. Standard vocabulary in
[cognitive diagnosis](REFERENCES.md#adaptive-instruction-and-knowledge-modeling).

### Realization family

A declared grouping a realization consumes, such as right hand, left hand,
parallel hands together, or contrary hands together.

The pacing and dose mechanisms read these keys without interpreting them.

### Realization fit

How near an unmeasured realization is to the one a learner should be entering
at, as a negative rung distance.

The last term of `RankKey`, and zero for every realization the frontier can
already speak about. `unmeasured` is true of every tempo at an unreached span at
once, so without this the tempi there tie and generation order decides between
them. A distance rather than more ordinal categories, because what is being
compared _is_ a distance and any boundary between "near" and "far" would be
arbitrary.

### Realization key

What the guidance-independent prediction channels vary with: material, pattern,
and execution conditions.

Execution, coordination, and topology are computed once per realization and
shared across the guidance rungs above it.

### Realization rank

Where a candidate sits against the learner's [frontier](#execution-frontier):
advancing, holding, unmeasured, or surpassed.

The eighth term of `RankKey`, and the first that reads execution conditions. The
earlier terms ask which _material_ to practice; this asks which _realization_ of
it. Consulted only when they come out even, which for two candidates on the same
scale they always do, so it changes how a scale is asked for and never which
scale wins.

### Realization-family pacing

Allocation control over the declared families a realization consumes.

Pressure is `max(0, share - floor) x (1 - managed fraction)` over a rolling
window, and a family over the set-aside threshold has its candidates removed
where a comparably ready alternative exists. It never makes an inadmissible
exercise admissible and never empties a selectable set. Compare
[family dose control](#family-dose-control).

### Recovery

An exclusive [challenge bypass](#challenge-bypass) immediately after a factual
retrieval failure.

The target is the same material and motor task with exactly one step more
guidance. Exclusive means only that survives the stage.

### Repetition guard

A selection rule preventing an over-repeated material from winning while another
admitted material exists.

It never removes the only admitted option, and it counts **materials**, not
kinds of work, so rotating between materials satisfies it while the technical
strand stays unchanged.

### Replay

Recomputing learner state by reapplying the journal from the beginning.

`exact` asks whether the recorded past is still reachable, comparing every
recomputed value. `counterfactual` asks what a different estimator would have
concluded from the same observations, and may be applied **only to the exercise
actually presented**: the journal holds no outcome for an action never taken, so
it is not policy evaluation. See [`system/history.md`](system/history.md).

### Retained consolidation

Durable learning held in reserve below current readiness.

It supports [savings](#savings) and the restoration of
[current durability](#current-durability), but does not directly enter
prediction or scheduling. With activation and current durability held fixed,
consolidation alone cannot change any decision.

### Retrieval demand

How much independent production a guidance configuration requires, in `[0,1]`.

A heuristic mapping rather than a research-established coefficient. Continuous
cues still have zero [retrieval opportunity](#retrieval-opportunity), because
retrieval is not observed at all.

### Retrieval opportunity

Whether a candidate can produce genuine retrieval evidence.

Zero when retrieval is not observed, and otherwise equal to
[retrieval demand](#retrieval-demand). Retention and information scores multiply
by it, so a candidate cannot win by exploiting a memory deficit it is
structurally unable to resolve.

### Rho

How much a competency may borrow from a paired hand or a source family when
predicting.

`rhoHand` and `rhoFamily` are the fraction of the gap that may be borrowed,
bounded to `[0, 1]` and shrunk by how uncertain the borrower is. **A transfer
coefficient, not a measured correlation.** Prediction only, never an update:
borrowing changes what is expected of an exercise and never what an attempt
teaches.

### Safety stage

Conservative workload constraints applied before challenge admission.

Carried by `SafetyConfig`. A session-attempt cap exists and is unset in
production: a sitting ends when the player stops. It is a guard against a
runaway decision loop, and makes no medical or injury judgment from performance
data.

### Savings

Reacquiring something faster than learning it the first time, because
[retained consolidation](#retained-consolidation) survived below current
readiness.

A learner with prior durable practice need not behave like a true beginner even
when current performance looks similar.

### Scheduler host

Where a decision is computed, and nothing else.

A session binds the resolved scope, the learner, and the policy constants, then
asks for one slot's decision; the host answers with the winning candidate or a
reason there was none, plus the effect to apply to the sitting. Production
computes on a worker isolate so the isolate that draws stays free.

### Selection

The exercise a decision actually produced.

Distinct from an [attempt slot](#attempt-slot): a slot that admits nothing has
no selection and no presented attempt.

### SessionState

Transient scheduler context within one sitting.

The attempt count, recent material history, the last failed exercise, an open
tempo probe, unserved guidance-probe opportunities, and the rolling window
[pacing](#realization-family-pacing) reads. Separate from
[LearnerState](#learnerstate), and a sitting rebuilds it from the journal rather
than storing it.

### Sitting

One continuous period of practice.

Distinct from a history, which spans many. `journalSequence` counts across all
of them; `indexInSession` is position within one.

### Structural opportunity

See [Q-matrix](#q-matrix).

### TechnicalMaterial

The underlying musical object being practiced.

For a scale, identity is tonic plus scale form. **Hand, tempo, octave count,
direction, hand motion, pattern, and guidance are not part of material
identity**, which is what gives one scale one memory state across all its
realizations.

### Temporal stability

How evenly spaced the notes were, as an outcome channel.

Reacts to spread across the traversal, where [continuity](#continuity) reacts to
a single interruption. Both use
[robust statistics](https://en.wikipedia.org/wiki/Robust_statistics) so they
stay independent, and both are absent below five measurable waits, because
interpolated quartiles would otherwise include the extremes they exist to
ignore.

### TimingEvidence

The waits between played notes, and which of them could be judged.

The one place the evidence threshold for timing is decided, for everything that
reads timing.

### Topology accuracy

How correct the underlying pitch and form structure was, independent of motor
quality.

Unaffected by an octave slip, because scale-degree structure is a different
question from which register it sounded in.

### Transition census

Stalls accumulated across attempts at one [acquisition task](#acquisition-task),
so a repeatedly troublesome transition can be told apart from generally uneven
playing.

A stall is a gap the measurement policy already reads as a break.

## Mathematical symbols

| Symbol                                                            | Meaning                                       |
| ----------------------------------------------------------------- | --------------------------------------------- |
| $u$                                                               | learner                                       |
| $m$                                                               | technical material                            |
| $c$                                                               | execution context, primarily RH/LH/HT         |
| $e$                                                               | exercise                                      |
| $a$                                                               | attempt                                       |
| $k$                                                               | transferable competency                       |
| $\theta_{u,k}$                                                    | latent competency state                       |
| $\mu_{u,k}$, $\sigma^2_{u,k}$                                     | competency mean and variance                  |
| $M_m(t)$                                                          | predicted independent material retrievability |
| $h_{\mathrm{current},m}$, $h_{\mathrm{consolidated},m}$           | current and retained half-lives               |
| $r_{u,m,c}$                                                       | material-specific execution residual          |
| $Q_{e,k}$                                                         | binary structural opportunity                 |
| $q^{(C)}_{e,k}$                                                   | derived predictor loading for channel $C$     |
| $w_{a,k}$, $w_M$, $w_r$                                           | channel-specific evidence weights             |
| $d_e$                                                             | retrieval demand                              |
| $D_{\mathrm{motor}}(e)$                                           | conditional motor-task difficulty             |
| $R(e)$, $\mathrm{Info}(e)$, $\mathrm{Div}(e)$, $\mathrm{Goal}(e)$ | scheduler priority terms                      |

## Retired terms

| Retired                                            | Use instead                                                                    |
| -------------------------------------------------- | ------------------------------------------------------------------------------ |
| `KnowledgeComponent`, `KC`, `Component`            | `Competency`                                                                   |
| `FingeringGroup`                                   | `FingeringPattern`, `MotorRealization`, or `MotorFamily`, according to meaning |
| `ScaleDirection`                                   | `ExerciseDirection`                                                            |
| `CompetencyCategory`                               | nothing; competencies have no implemented grouping                             |
| `SchedulerSafetyPolicy`                            | `SafetyConfig`                                                                 |
| flat `Exercise` record                             | compositional `Exercise`                                                       |
| discrete acquisition/development/maintenance state | derived Fluency Profile language                                               |
| `PRIMARY`/`SECONDARY` Q entries                    | `Q`, predictor loading `q`, and attempt evidence `w`                           |
| `ReportedResult`                                   | a termination reason beside the outcome                                        |
