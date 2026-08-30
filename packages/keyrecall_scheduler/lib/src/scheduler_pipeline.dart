import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';
import 'execution_progression.dart';
import 'priority.dart';
import 'recovery.dart';
import 'session_state.dart';
import 'tempo_probe.dart';

/// What one admission exception has to say about one candidate.
///
/// Three answers rather than two. An exception that refuses a candidate has
/// answered, and nothing after it may answer instead; an exception with
/// nothing to say has not. Collapsing those into a nullable bypass is what let
/// a later exception become unreachable without any signal.
sealed class _Verdict {
  const _Verdict();
}

/// This exception admits the candidate, under this name.
class _Admits extends _Verdict {
  final ChallengeBypass bypass;

  const _Admits(this.bypass);
}

/// This exception owns the question for this candidate, and the answer is no.
class _Refuses extends _Verdict {
  const _Refuses();
}

/// This exception has nothing to say; the next one decides.
class _Silent extends _Verdict {
  const _Silent();
}

/// The candidates considered and the selection made for one attempt slot.
class SelectionResult {
  final List<CandidateTrace> traces;
  final List<CandidateTrace> selectable;
  final CandidateTrace? selected;

  const SelectionResult({
    required this.traces,
    required this.selectable,
    required this.selected,
  });
}

/// The staged decision pipeline that chooses what to practice next.
///
/// Four stages, each answering one question with an explicit information
/// boundary: candidate generation (which lives outside this class, because it
/// may not read learner state at all), eligibility and safety, challenge
/// admission, and priority ranking with selection.
///
/// [evaluate] traces every candidate through every stage; [selectChoice] is
/// the canonical V1 answer for what to present.
class SchedulerPipeline {
  /// The learner model supplying predictions and uncertainty.
  final LearnerModel learner;

  /// The versioned policy constants this pipeline applies.
  final SchedulerConfig config;

  const SchedulerPipeline({
    required this.learner,
    this.config = v1SchedulerConfig,
  });

  /// Evaluates and selects one attempt slot, updating its session bookkeeping.
  SelectionResult decide({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
  }) {
    final traces = evaluate(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
    );
    final available = selectable(traces, session);
    final selected = chooseFrom(available, session);
    session.recordSelectionOpportunity(
      guidanceProbeAvailable: available.any(
        (trace) => trace.challengeBypass == ChallengeBypass.guidanceProbe,
      ),
      guidanceProbeSelected:
          selected?.challengeBypass == ChallengeBypass.guidanceProbe,
    );
    session.attemptsThisSession++;
    return SelectionResult(
      traces: traces,
      selectable: available,
      selected: selected,
    );
  }

  /// Records how a presented exercise ended in the current session.
  void recordOutcome(
    SessionState session,
    Exercise exercise,
    Outcome? outcome,
  ) {
    session.recordSelection(
      exercise,
      retrievalFailed: outcome?.retrieval == FactualRetrieval.failed,
      retrievalObserved: exercise.guidance.isRetrievalObserved,
      tempoProbe: outcome == null
          ? null
          : tempoProbeTarget(
              exercise: exercise,
              outcome: outcome,
              config: config.probe,
            ),
      config: config.diversity,
    );
  }

  /// Stage 2a: the `REQUIRES` prerequisite gate.
  ///
  /// Two questions, both about the learner rather than about the exercise:
  /// whether both hands are capable before they play together, and whether
  /// this material is appropriate to introduce yet. Foundation material has no
  /// prerequisite of the second kind, which is not the same as being fully
  /// eligible however it is played: C major hands together still waits for
  /// both hands.
  ///
  /// Material admission uses what the learner model actually observes:
  /// per-hand execution, and topology competence per scale form. It cannot ask
  /// whether a hand pattern is already established, because nothing measures
  /// that, so the admission band stands in for it as a curriculum-derived
  /// prior. Two materials in one band are treated identically even when one
  /// introduces a new hand pattern and the other reuses a familiar one, and
  /// that approximation is the reason `EligibilityReason` is coded: stalls
  /// clustering at a band that introduces a new pattern are what would justify
  /// measuring the motor axis directly.
  ///
  /// Provisional rather than forbidden, in every case. A provisional candidate
  /// is outranked by anything fully eligible and is still reachable when
  /// nothing else is, which is what stops a strict prior from leaving a
  /// learner with nothing to play.
  EligibilityDecision eligibilityFor(LearnerState state, Exercise exercise) {
    final material = exercise.material;
    final band = admissionBandOf(material);
    final hands = exercise.conditions.hands;

    // Nothing here has ever been observed about this material, so an unguided
    // attempt would be testing a memory this app has never seen formed. The
    // material is still admissible; it enters through a rung that supplies it.
    if (!state.materialMemory.containsKey(material.materialId) &&
        !exercise.guidance.isMaterialSupplied) {
      return const EligibilityDecision(
        EligibilityTier.provisionallyEligible,
        'no history for this material, so its first encounter is cued',
        code: EligibilityReason.unseenMaterialRequiresCue,
      );
    }

    // An altered minor form is a new idea rather than a new key: harmonic
    // minor raises the seventh against natural minor, and melodic minor
    // raises the sixth as well, in a fixed form the classical convention does
    // not use. Meeting one while the ordinary scales are still unsettled
    // enlarges the vocabulary faster than the base under it, whatever the
    // keyboard geography says, which is why this is not a band question.
    if (!coreForms.contains(material.form)) {
      final breadth = _alteredFormDecisionFor(state, material.form, hands);
      if (breadth != null) return breadth;
    }

    // Both hands knowing this material at this span. Evidence about the work
    // in front of the learner rather than a general verdict on their hands,
    // and about the notes rather than the polish: see [supportsHandsTogether].
    //
    // This was a floor on the two hand-execution means, and it made playing
    // together a reward for fluency rather than an early coordination skill.
    // A beginner who played forty scales almost perfectly was still at -0.46
    // and -0.27 against a floor of zero, so every hands-together candidate sat
    // provisional, execution progression could not admit one, and the altered
    // minor phase gate that requires hands-together exposure was unreachable
    // behind it. The means still shape the prediction, which is where a
    // general estimate belongs; what they no longer do is veto the attempt.
    //
    // Once hands-together has a record of its own here it goes on through
    // that, like any other execution context.
    if (hands == HandConfiguration.together) {
      final span = exercise.conditions.octaves;
      final together = state.materialExecution[(material.materialId, hands)];
      final established =
          (together?.demonstratedTempoAt(span) ?? 0) > 0 ||
          (together?.demonstratedTempoAt(span - 1) ?? 0) > 0;
      if (!established &&
          !supportsHandsTogether(state, material.materialId, span)) {
        return const EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          'each hand has still to learn this alone at this span',
          code: EligibilityReason.handsTogetherPrerequisite,
        );
      }
    }

    // Two octaves before one is the one ordering on the execution axis every
    // source agrees on, and the information term will otherwise reach for the
    // span nobody has attempted precisely because nobody has. The material is
    // untouched: one octave of it stays fully eligible.
    if (exercise.conditions.octaves > 1) {
      final floor = config.eligibility.multiOctaveExecutionFloor;
      final execution = _executionMeanFor(state, hands);
      if (execution < floor) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          '${exercise.conditions.octaves} octaves ask for execution '
          '${floor.toStringAsFixed(2)}, learner is at '
          '${execution.toStringAsFixed(2)}',
          code: EligibilityReason.octaveSpanPrerequisite,
        );
      }
    }

    // Natural minor asks for nothing: it is where minor topology comes from,
    // and requiring familiarity to earn the only material that produces it
    // would keep every minor scale outranked forever.
    if (material.form == ScaleForm.harmonicMinor ||
        material.form == ScaleForm.melodicMinor) {
      final floor = config.eligibility.minorTopologyFloor;
      final familiar = _bestMinorTopology(state, exclude: material.form);
      if (familiar < floor) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          'another minor form is at ${familiar.toStringAsFixed(2)}, '
          'floor ${floor.toStringAsFixed(2)}',
          code: material.form == ScaleForm.melodicMinor
              // Fixed-form melodic minor is the least familiar of the three
              // and waits for either of the others.
              ? EligibilityReason.melodicFormPrerequisite
              : EligibilityReason.minorTopologyPrerequisite,
        );
      }
    }

    if (band != AdmissionBand.foundation) {
      // Difficulty is compositional, and the floor was reading only half of
      // it. New keyboard geography is one thing to take on; a harder way of
      // playing is another, and asking for both at once is what the floor is
      // protecting against. Met at the gentlest conditions the catalog
      // offers, a key is a smaller ask than the band alone suggests, so it is
      // judged against the band before it.
      //
      // One band, not a waiver. It puts D major in front of a beginner at one
      // octave in one hand, which is where the next scales after the
      // foundation ought to come from, and leaves D flat major where it was.
      // Already played, in this hand, at this span. The floor asks whether a
      // learner is fluent enough for an unfamiliar key geography, and somebody
      // who has got through this one has answered that about this one: a
      // general execution mean is a weaker claim than the material's own
      // record, exactly as it was for hands together.
      //
      // Without this the floor left the learner's own frontier ineligible. A
      // device sitting demonstrated C natural minor left hand at a hundred and
      // twenty-six, and every candidate at that tempo stayed provisional while
      // the sixty-beat one was fully eligible through the gentleness discount
      // below. Tier decides before anything else, so eleven consecutive slots
      // went to work the learner was two rungs past.
      //
      // At this span, not at any span: two octaves of a key is a geography one
      // octave of it has not shown.
      final demonstrated =
          state.materialExecution[(material.materialId, hands)]
              ?.demonstratedTempoAt(exercise.conditions.octaves) ??
          0;
      if (demonstrated > 0) {
        return EligibilityDecision(
          EligibilityTier.fullyEligible,
          '${band.id} already played at '
          '${demonstrated.toStringAsFixed(0)} bpm',
          code: EligibilityReason.bandGeographyDemonstrated,
        );
      }

      final asked = _isGentlest(exercise.conditions) ? _bandBefore(band) : band;
      final floor = config.eligibility.executionFloorFor(asked);
      final execution = _executionMeanFor(state, hands);
      if (execution < floor) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          '${band.id} asks for execution ${floor.toStringAsFixed(2)}, '
          'learner is at ${execution.toStringAsFixed(2)}',
          code: EligibilityReason.bandExecutionFloor,
        );
      }
      return EligibilityDecision(
        EligibilityTier.fullyEligible,
        '${band.id} met at execution ${execution.toStringAsFixed(2)}',
        code: EligibilityReason.bandExecutionMet,
      );
    }

    // Foundation means no *material* prerequisite. An execution condition can
    // still hold it back: hands-together work on C major is checked above and
    // may be provisional, which is the decomposition working rather than a
    // contradiction.
    return const EligibilityDecision(
      EligibilityTier.fullyEligible,
      'foundation material, and no material prerequisite applies',
      code: EligibilityReason.foundationMaterial,
    );
  }

  /// Whether [exercise] would be this hand's first encounter with its
  /// material.
  ///
  /// Per hand, not per material. Knowing the notes of a scale is a fact about
  /// the material and travels with the learner; playing it under the other
  /// hand is a fingering nobody has attempted, and material memory alone
  /// cannot tell the two apart. Read per material, the second hand had no
  /// admission path at all: introduction was silent because the scale was
  /// known, consolidation because it had been retrieved, and execution
  /// progression because that hand had no frontier to step from. A device
  /// sitting kept every scale on the hand that met it first, for thirty
  /// attempts.
  ///
  /// Hands-together is not an introduction. Both hands at once is a transition
  /// off two frontiers that already exist, with its own prerequisite and its
  /// own conservative entry tempo, which is execution progression's step to
  /// offer rather than this one's.
  bool isIntroduction(LearnerState state, Exercise exercise) =>
      exercise.conditions.hands != HandConfiguration.together &&
      !state.hasPlayed(exercise.material.materialId, exercise.conditions.hands);

  /// Whether [exercise] may be met for the first time at all.
  ///
  /// A different question from eligibility, and the only place the two come
  /// apart. Eligibility orders candidates: provisional means deferred while
  /// something better exists, which is right for an execution condition like
  /// octave span, where the material is appropriate and one way of playing it
  /// is not. It is wrong for a curriculum phase. A device sitting introduced
  /// harmonic and melodic minor six times before hands-together work appeared
  /// once, each time through the introduction exception, because "not fully
  /// eligible" was never the same claim as "not to be introduced".
  ///
  /// So the altered forms are a barrier rather than a disadvantage. Recovery
  /// of one already introduced is a separate question and is left alone; what
  /// this forbids is meeting one for the first time.
  ///
  /// Asked directly rather than read off the eligibility reason, because that
  /// reason is whichever rule refused first and a two-octave harmonic minor
  /// reports the span. Deciding a barrier from a diagnostic that stops at the
  /// first answer is how this went wrong once already.
  bool isIntroducible(LearnerState state, Exercise exercise) =>
      _alteredFormDecisionFor(
        state,
        exercise.material.form,
        exercise.conditions.hands,
      ) ==
      null;

  /// Whether an altered minor form has to wait for a foundation under it.
  ///
  /// Returns null when it does not, so the ordinary rules decide.
  ///
  /// Harmonic minor is not another unseen scale; it is a new idea about what
  /// minor means, layered on a major and natural-minor foundation. So this is
  /// a curriculum phase transition rather than a threshold, and it asks for
  /// the evidence that a phase has actually been reached:
  ///
  /// - both hands observed separately, because a scale learned in one hand is
  ///   not a scale learned;
  /// - some hands-together work on ordinary material, which is what marks the
  ///   move from having met some shapes to studying scales;
  /// - retrieval breadth across major and natural minor, counted per hand.
  ///
  /// The hands-together condition applies to one-hand candidates too, and
  /// deliberately. Nothing about harmonic minor mechanically needs two hands.
  /// It is being used as the marker of the phase, and a phase the learner has
  /// not reached is not reached for right-hand work either.
  ///
  /// Every one of these asks whether a channel has been *observed* rather than
  /// where its mean sits. Placement seeds means from what somebody said about
  /// themselves, so a mean test would let the onboarding answer masquerade as
  /// demonstrated musicianship, which is the trap natural minor already taught
  /// in a different form.
  ///
  /// Waived by observed fluent hands-together coordination, and only by that;
  /// see [_hasFluentHandsTogether]. Making somebody who arrived playing scales
  /// demonstrate half a curriculum first would be an artificial path through
  /// material they know, and making them play it once to show it is not.
  EligibilityDecision? _alteredFormDecisionFor(
    LearnerState state,
    ScaleForm form,
    HandConfiguration hands,
  ) {
    final required = switch (form) {
      ScaleForm.harmonicMinor => config.eligibility.harmonicMinorCoreRetrievals,
      ScaleForm.melodicMinor => config.eligibility.melodicMinorCoreRetrievals,
      _ => 0,
    };
    if (required == 0) return null;

    if (_hasFluentHandsTogether(state)) return null;

    for (final hand in HandConfiguration.values) {
      if (hand == HandConfiguration.together) continue;
      if (state.isObserved(_executionCompetencyOf(hand))) continue;
      return EligibilityDecision(
        EligibilityTier.provisionallyEligible,
        'the ${hand.id.toLowerCase()} hand has never been observed, and '
        '${form.id} asks for a foundation in both',
        code: EligibilityReason.alteredFormHandsFoundation,
      );
    }

    if (!state.isObserved(Competency.handsTogetherCoordination)) {
      return EligibilityDecision(
        EligibilityTier.provisionallyEligible,
        'no hands-together work yet, and ${form.id} asks for some on ordinary '
        'material first',
        code: EligibilityReason.alteredFormHandsTogetherFoundation,
      );
    }

    final bands = config.eligibility.coreRetrievalBands;
    for (final hand in HandConfiguration.values) {
      if (hand == HandConfiguration.together) continue;
      final (retrieved, spread) = _ordinaryBreadthFor(state, hand);
      if (retrieved >= required && spread >= bands) continue;
      return EligibilityDecision(
        EligibilityTier.provisionallyEligible,
        'the ${hand.id.toLowerCase()} hand has $retrieved major and '
        'natural-minor scales retrieved across $spread bands, and ${form.id} '
        'asks for $required across $bands',
        code: form == ScaleForm.melodicMinor
            ? EligibilityReason.melodicMinorRepertoireBreadth
            : EligibilityReason.harmonicMinorRepertoireBreadth,
      );
    }
    return null;
  }

  /// How many ordinary-form scales [hand] has played and had retrieved, and
  /// how many admission bands they span.
  ///
  /// Two facts joined because neither is enough alone. Memory is keyed by
  /// material and knows a scale was retrieved without knowing which hand was
  /// playing; execution residuals are keyed by material and hand and know a
  /// hand played it without knowing whether anything was remembered. Requiring
  /// both is the closest this state can come to "this hand has this scale",
  /// and it is a projection rather than a record: a scale retrieved by one
  /// hand and merely played by the other counts for both.
  (int, int) _ordinaryBreadthFor(LearnerState state, HandConfiguration hand) {
    final spread = <AdmissionBand>{};
    var retrieved = 0;
    for (final material in allScales) {
      if (!coreForms.contains(material.form)) continue;
      final memory = state.materialMemory[material.materialId];
      if (memory?.hasFactualRetrieval != true) continue;
      if (!state.hasPlayed(material.materialId, hand)) continue;
      retrieved++;
      spread.add(admissionBandOf(material));
    }
    return (retrieved, spread.length);
  }

  /// Whether hands-together playing has been observed and is fluent.
  ///
  /// The escape hatch from the phase graph, and the only one. The ordinary
  /// path establishes the phase developmentally; this establishes that the
  /// learner is already past it, so it asks about the dimension that defines
  /// the phase rather than about one hand.
  ///
  /// A scale played hands together well enough to produce competent
  /// coordination evidence is a scale played with two hands that each work, so
  /// this does not need to check them separately. Strictly it does not prove
  /// high single-hand execution, since two mediocre hands can be well
  /// synchronized; a curriculum waiver does not need that proof, only evidence
  /// strong enough that marching the learner through the prerequisites would
  /// be artificial.
  ///
  /// Observed and fluent, both. Placement seeds this mean from the onboarding
  /// answer, so the mean alone would let a self-report skip the phase, and
  /// exposure alone would let one ragged first attempt do it.
  bool _hasFluentHandsTogether(LearnerState state) =>
      state.isObserved(Competency.handsTogetherCoordination) &&
      state.competency(Competency.handsTogetherCoordination).mean >=
          config.eligibility.fluentHandsTogetherFloor;

  static Competency _executionCompetencyOf(HandConfiguration hand) =>
      hand == HandConfiguration.right
      ? Competency.rhScaleExecution
      : Competency.lhScaleExecution;

  /// The tempo [exercise]'s material is introduced at.
  ///
  /// What this learner's playing hand has shown on material they already own,
  /// or the slow end of ordinary practice when they have shown nothing. So a
  /// beginner still meets their first scale at sixty, and somebody who has
  /// been working in the seventies meets their next one there rather than
  /// being walked back to sixty every time the catalog opens a little wider.
  ///
  /// Capped for the later bands. Transfer across fingering families is exactly
  /// what nothing here measures yet, so a key whose geography is new is met
  /// unhurried whatever the hand has managed on keys it knows: a new shape and
  /// a new speed at once is the compounding this has been avoiding everywhere
  /// else.
  double entryTempoFor(LearnerState state, Exercise exercise) {
    final gentle = config.eligibility.gentleTempoBpm;
    final transferable = transferableTempoFor(
      state,
      exercise.conditions.hands,
      exercise.conditions.octaves,
    );
    // Nobody has seen this learner play, so there is no evidence to be
    // conservative about. The gentle tempo is the only honest default.
    if (transferable <= 0) return gentle;

    // One rung, and exactly one. Geography and speed are different axes: an
    // unfamiliar fingering is a real additional ask, so the full pace is
    // overconfident, and the learner's own pace is direct behavioral evidence,
    // so dropping to the bottom of the ladder treats it as though it barely
    // existed. This used to be `min(transferable, gentle)`, which took a
    // learner playing at a hundred and twenty down to sixty for anything past
    // early transfer, and made the same sitting meet one scale at the pace and
    // the next at the floor.
    return admissionBandOf(
          exercise.material,
        ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer)
        ? transferable
        : tempoBefore(transferable);
  }

  /// Whether these are the gentlest conditions the catalog offers a scale
  /// under.
  ///
  /// One octave, one hand, at the slow end of ordinary practice. Not the
  /// guidance rung, which is a separate ladder with its own rules about first
  /// encounters and about what independence has to be earned.
  bool _isGentlest(ExecutionConditions conditions) =>
      conditions.octaves == 1 &&
      conditions.hands != HandConfiguration.together &&
      conditions.tempoBpm <= config.eligibility.gentleTempoBpm;

  /// The band before [band], or [band] itself when it is the first.
  static AdmissionBand _bandBefore(AdmissionBand band) =>
      band == AdmissionBand.foundation
      ? band
      : AdmissionBand.values[band.index - 1];

  /// The weaker hand's execution when both play, otherwise the playing hand's.
  double _executionMeanFor(LearnerState state, HandConfiguration hands) {
    final rh = state.competency(Competency.rhScaleExecution).mean;
    final lh = state.competency(Competency.lhScaleExecution).mean;
    return switch (hands) {
      HandConfiguration.right => rh,
      HandConfiguration.left => lh,
      HandConfiguration.together => rh < lh ? rh : lh,
    };
  }

  /// The best minor topology the learner has, ignoring [exclude].
  ///
  /// Ignoring the form being admitted is what makes this a transfer rule
  /// rather than a self-referential one: A harmonic minor is admitted on the
  /// strength of A natural minor, not of itself. Note that it is any minor
  /// topology rather than the same tonic's, since the curricula give no
  /// support for a per-key ladder either.
  double _bestMinorTopology(LearnerState state, {required ScaleForm exclude}) {
    var best = double.negativeInfinity;
    for (final form in ScaleForm.values) {
      if (form == ScaleForm.major || form == exclude) continue;
      final mean = state.competency(form.topologyCompetency).mean;
      if (mean > best) best = mean;
    }
    return best;
  }

  /// Stage 2b: the workload gate.
  ///
  /// Reads session state only. A hard gate, unlike eligibility, but a narrow
  /// one: it bounds session length where a bound is configured and does not
  /// try to diagnose fatigue or injury from playing behavior.
  SafetyDecision safetyFor(SessionState session) {
    final cap = config.safety.maxSessionAttempts;
    final attempts = session.attemptsThisSession;
    if (cap == null) {
      return SafetyDecision(true, 'sittings are not bounded by attempt count');
    }
    if (attempts >= cap) {
      return SafetyDecision(
        false,
        'session attempt cap reached ($attempts/$cap)',
      );
    }
    return SafetyDecision(true, 'within session attempt cap ($attempts/$cap)');
  }

  /// Stage 3: whether predicted success lands in the "not too easy, not too
  /// hard" band.
  bool isWithinChallengeBand(Prediction prediction) =>
      config.challenge.pMin <= prediction.overallP &&
      prediction.overallP <= config.challenge.pMax;

  /// Whether [exercise] is a proactive step back toward independence.
  ///
  /// The mirror of recovery: the same task at exactly one rung less support
  /// than the one the learner last succeeded under, where recovery is the same
  /// task at one rung more. That makes the ladder traversable in both
  /// directions and gives it a top, since a material established unguided has
  /// no less supportive rung to be probed toward.
  ///
  /// It used to name one fixed rung, on the reasoning that a successful probe
  /// re-anchors the clock and ordinary admission takes it from there.
  /// Simulating three learners showed ordinary admission never gets there:
  /// every winning slot across all three carried a bypass, so nothing ever
  /// climbed past previewed and no profile played anything from memory
  /// unaided. The step from previewed to unguided is a real question in its
  /// own right anyway. Producing a scale moments after being shown it and
  /// producing it cold are different achievements, whatever they share as a
  /// retrieval channel.
  ///
  /// Paced by how long the rung has been established rather than by how long
  /// ago retrieval last happened. Those are different questions, and sharing
  /// the retrieval clock made every success at the established rung push the
  /// next step away: a learner who never missed a note waited longer for
  /// independence the more they practised. Producing a scale seconds after
  /// being shown it still proves little, so the establishment clock is short
  /// rather than absent.
  /// The one tempo a probe about guidance is asked at.
  ///
  /// **A probe holds every condition but the axis it asks about.** That is the
  /// rule this implements for tempo, and it is the rule a probe on any other
  /// axis has to implement in its own direction: a probe testing span holds
  /// guidance and tempo, one testing hands holds span and tempo. A probe that
  /// moves two axes has asked two questions and can answer neither, because
  /// nothing in the outcome says which one the learner responded to.
  ///
  /// It is not enough to leave the other axes alone in the construction, since
  /// nothing constructs a probe here: these are predicates over generated
  /// candidates, and the ranking key reads none of the execution conditions.
  /// An unconstrained axis is therefore not held, it is chosen by the order of
  /// a constant. A guidance probe dropped a learner from a hundred and twenty
  /// six to sixty for exactly that reason, and the slower exercise then read as
  /// underchallenged and drew a tempo probe along behind it: a mechanism
  /// undoing its own question a slot later.
  ///
  /// The frontier for this material, hand and span, which is where the learner
  /// already is. [entryTempoFor] when that span has never been managed: a
  /// material can have an established guidance rung without having been played
  /// this wide, and the learner's pace is the best answer there.
  double heldTempoFor(LearnerState state, Exercise exercise) {
    final frontier =
        state
            .materialExecution[(
              exercise.material.materialId,
              exercise.conditions.hands,
            )]
            ?.demonstratedTempoAt(exercise.conditions.octaves) ??
        0;
    return frontier > 0 ? frontier : entryTempoFor(state, exercise);
  }

  bool isGuidanceProbe(LearnerState state, Exercise exercise, DateTime at) {
    final memory = state.materialMemory[exercise.material.materialId];
    final established = memory?.establishedIndependence;
    final since = memory?.establishedIndependenceAt;
    if (established == null || since == null) return false;
    if (exercise.guidance.independence != established + 1) return false;
    if (exercise.conditions.tempoBpm != heldTempoFor(state, exercise)) {
      return false;
    }
    return since.daysUntil(at) >= config.probe.minDaysSinceSupportEstablished;
  }

  /// Whether [exercise] is a retrieval test for material with no rung
  /// currently established.
  ///
  /// The counterpart to [isGuidanceProbe], which climbs from an established
  /// rung and so cannot help where there is none. Two ways to have none: the
  /// material has never been retrieved at all, or it was retrieved and then
  /// failed, which unsettles the rung. Recovery answers a failure by adding
  /// support and can walk a material down to full cueing, where retrieval is
  /// never observed and nothing can re-establish anything. This is what keeps
  /// offering a retrieval-observing candidate instead of settling there
  /// permanently.
  ///
  /// Its clock is the last factual attempt of any kind rather than the last
  /// success, since after a failure there may be no success to count from, and
  /// the wait is the long one: coming back to something that just went wrong
  /// is a question about retention, unlike stepping up from a rung that is
  /// working.
  bool isBootstrapProbe(LearnerState state, Exercise exercise, DateTime at) {
    if (exercise.guidance != GuidanceContext.notesPreviewedOnly) return false;
    final memory = state.materialMemory[exercise.material.materialId];
    if (memory == null || memory.establishedIndependence != null) return false;
    final lastAttempt = memory.lastRetrievalAttemptAt;
    if (lastAttempt == null) return false;
    if (exercise.conditions.tempoBpm != heldTempoFor(state, exercise)) {
      return false;
    }
    return lastAttempt.daysUntil(at) >= config.probe.minDaysSinceLastRetrieval;
  }

  /// Whether [exercise] is a deliberate retrieval test for material that has
  /// been practised under support without retrieval being observed.
  ///
  /// Support raises predicted success, so as memory weakens the ordinary band
  /// comes to prefer continuous cueing. Cueing observes no retrieval, so
  /// nothing arrives to say whether the support is still needed, and the
  /// preference persists on evidence that can never be collected. A whole
  /// sitting can go by teaching the scheduler nothing about the question it is
  /// implicitly answering.
  ///
  /// So after enough supported attempts on a material, one retrieval-observing
  /// question is asked whatever its predicted success. The band optimises for
  /// an appropriate challenge; this is the exception that keeps it answerable.
  bool isObservationProbe(
    LearnerState state,
    Exercise exercise,
    int supportedAttempts,
  ) =>
      exercise.guidance == GuidanceContext.notesPreviewedOnly &&
      exercise.conditions.tempoBpm == heldTempoFor(state, exercise) &&
      supportedAttempts >= config.probe.supportedAttemptsBeforeObservation;

  /// The highest eligibility tier that has anything left to introduce, or null
  /// when no material is unseen.
  ///
  /// A set-level fact, which is why it is computed once for a slot rather than
  /// asked of a candidate. The introduction exception is the only admission
  /// path a cold-start learner has, and a candidate cannot tell on its own
  /// whether something more appropriate is also waiting to be introduced.
  EligibilityTier? introducibleTier(
    LearnerState state,
    List<Exercise> candidates,
  ) {
    EligibilityTier? best;
    for (final exercise in candidates) {
      if (!isIntroduction(state, exercise)) continue;
      if (!isIntroducible(state, exercise)) continue;
      final tier = eligibilityFor(state, exercise).tier;
      if (best == null || tier.index > best.index) best = tier;
      if (best == EligibilityTier.fullyEligible) break;
    }
    return best;
  }

  /// Which named exception, if any, admits [exercise] outside the ordinary
  /// band.
  ///
  /// Precedence is [AdmissionException]'s declaration order, consulted until
  /// one of them answers. The order is policy and not an accident of layout:
  /// an override is an explicit instruction and beats every inference;
  /// recovery beats the tempo probe because something that just went wrong
  /// matters more than something that went too easily; the observation probe
  /// comes before the introduction floor because a drought is a drought
  /// whether the candidate that ends it is new or familiar.
  ///
  /// Some exceptions answer for a candidate they do not admit, which is why
  /// [_Verdict] distinguishes refusing from having nothing to say. A recovery
  /// context refuses everything but its target, and material below the
  /// introduction floor is refused rather than passed along. Writing those as
  /// a bare `return null` in a chain of ifs is what made this a list: a null
  /// reads as "nothing applied", so moving a clause below one silently made it
  /// unreachable, which is a bug this code has already had once.
  ChallengeBypass? challengeBypassFor({
    required LearnerState state,
    required Exercise exercise,
    required Prediction prediction,
    required DateTime at,
    required ChallengeBypass? override,
    required Exercise? recoveryTarget,
    required Exercise? tempoProbe,
    required int supportedAttempts,
    required EligibilityTier eligibility,
    required EligibilityTier? introducibleTier,
  }) {
    for (final exception in AdmissionException.values) {
      final verdict = switch (exception) {
        AdmissionException.override =>
          override == null ? const _Silent() : _Admits(override),
        AdmissionException.recovery => _exactly(
          recoveryTarget,
          exercise,
          ChallengeBypass.recovery,
        ),
        AdmissionException.tempoProbe => _exactly(
          tempoProbe,
          exercise,
          ChallengeBypass.tempoProbe,
        ),
        AdmissionException.observationProbe =>
          isObservationProbe(state, exercise, supportedAttempts)
              ? const _Admits(ChallengeBypass.observationProbe)
              : const _Silent(),
        // The slot has nothing appropriate left to introduce, and something
        // already met that has never been produced from memory. Offering it
        // again is better work than reaching for material a learner has not
        // earned, and without this there is nothing else the slot can do: for
        // a beginner in a first sitting every other path to seen material is
        // shut. It is out of the ordinary band, no rung is established so the
        // guidance probe cannot climb, the bootstrap probe is days away, and
        // the observation probe counts supported attempts that a previewed
        // introduction resets. Introducing was the only move available, which
        // is why introductions kept happening.
        //
        // No refusal is needed against the introduction below. This admits
        // fully eligible work, that one admits provisional work, and the tier
        // leads the ranking key, so consolidation wins where it applies and
        // steps aside where it does not.
        //
        // The previewed rung, and only that one, for the reason the bootstrap
        // probe uses it: where no rung is established, that is the retrieval
        // test to offer. A cued repeat cannot turn a scale that has been shown
        // into one that has been produced however often it is offered, and an
        // unguided one hands out independence that is supposed to be earned,
        // which would make failing every retrieval a way to be asked harder
        // questions.
        AdmissionException.consolidation =>
          introducibleTier == EligibilityTier.fullyEligible ||
                  eligibility != EligibilityTier.fullyEligible ||
                  exercise.guidance != GuidanceContext.notesPreviewedOnly
              ? const _Silent()
              : switch (state.materialMemory[exercise.material.materialId]) {
                  final memory? when !memory.hasFactualRetrieval =>
                    const _Admits(ChallengeBypass.consolidation),
                  _ => const _Silent(),
                },

        // Difficulty is what an introduction is allowed to bypass, and only
        // that. A prerequisite says the material is inappropriate for a
        // separate reason, so introducing something is never a licence to
        // introduce anything: while the slot has an introducible candidate in
        // a higher tier, a lower one is not reachable here at all.
        //
        // The tier is checked before the floor deliberately. Reversing them
        // would let a provisional candidate that clears the introduction
        // minimum beat a fully eligible one that does not, which is
        // probability leapfrogging a prerequisite. Nothing introduced is the
        // right answer there.
        AdmissionException.newMaterial =>
          !isIntroduction(state, exercise)
              ? const _Silent()
              : !isIntroducible(state, exercise)
              ? const _Refuses()
              : eligibility != introducibleTier
              ? const _Refuses()
              // One tempo, and a chosen one. An introduction used to be
              // offered at every tempo generation listed, and nothing in the
              // ranking key reads tempo, so which of them a learner met was
              // decided by the order of a constant. Sixty always won, and it
              // looked like a policy.
              : exercise.conditions.tempoBpm != entryTempoFor(state, exercise)
              ? const _Refuses()
              : prediction.overallP >= config.challenge.pIntroductionMin
              ? const _Admits(ChallengeBypass.newMaterial)
              : const _Refuses(),
        AdmissionException.guidanceProbe =>
          isGuidanceProbe(state, exercise, at)
              ? const _Admits(ChallengeBypass.guidanceProbe)
              : const _Silent(),
        AdmissionException.bootstrapProbe =>
          isBootstrapProbe(state, exercise, at)
              ? const _Admits(ChallengeBypass.bootstrapProbe)
              : const _Silent(),

        // Deepening material the learner owns. Owns, rather than has been
        // shown: somebody who played a scale perfectly while it was in front
        // of them has demonstrated the motor conditions and not the scale, and
        // answering that with a faster one races execution ahead of what they
        // know. Establishing the material is consolidation's job, and this
        // begins where that ends.
        //
        // Silent rather than refusing on every failure. It is an opportunity
        // to admit familiar work outside the ordinary band, not a policy that
        // should stop another exception having something to say.
        AdmissionException.executionProgression =>
          switch (state.materialMemory[exercise.material.materialId]) {
            final memory?
                when memory.hasFactualRetrieval &&
                    eligibility == EligibilityTier.fullyEligible &&
                    executionAdvanceFor(state, exercise).isAdjacentStep =>
              const _Admits(ChallengeBypass.executionProgression),
            _ => const _Silent(),
          },
      };

      if (verdict case _Admits(:final bypass)) return bypass;
      if (verdict is _Refuses) return null;
    }
    return null;
  }

  /// The verdict of an exception that admits exactly [target] and refuses
  /// every other candidate while it is open.
  static _Verdict _exactly(
    Exercise? target,
    Exercise exercise,
    ChallengeBypass bypass,
  ) {
    if (target == null) return const _Silent();
    return exercise == target ? _Admits(bypass) : const _Refuses();
  }

  /// Runs every candidate through every stage and returns the full traces.
  ///
  /// Diagnostic values are computed for all candidates, but the stage statuses
  /// follow the real upstream decisions, and a rank key is set only where
  /// priority ranking genuinely ran.
  ///
  /// Pass [overrides] to force admission for a specific candidate, which
  /// scripted diagnostics and explicit learner requests need because those
  /// reasons are not derivable from state.
  List<CandidateTrace> evaluate({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
  }) {
    final failed = session.lastFailedExercise;
    final target = failed == null ? null : recoveryTarget(failed);
    final probe = target == null ? session.tempoProbe : null;
    final safety = safetyFor(session);
    // Refined once, here, and every set-level fact below reads the refined
    // set. Computing one of them from the raw candidates while the loop
    // evaluates the refined ones would make two different universes out of
    // one slot.
    // An exclusive target has to be in the set it narrows. Recovery and the
    // tempo probe both refuse everything but one exact exercise, so a target
    // the candidates do not contain leaves the slot admitting nothing at all,
    // which is how the tempo probe reaching a metronome rung would otherwise
    // have broken it: generation has no candidate at a hundred and four.
    final neighbours = withExecutionNeighbours(state, candidates);
    final refined = [
      ...neighbours,
      for (final exclusive in [target, probe])
        if (exclusive != null && !neighbours.contains(exclusive)) exclusive,
    ];
    final introducible = introducibleTier(state, refined);

    // Guidance changes material availability, but not independent retrieval,
    // execution, or topology. Generation emits each realization under all
    // three guidance levels, so those channels are computed once per
    // realization, keyed by the same exercise with guidance normalized away.
    final retrievalCache = <String, double>{};
    final executionCache = <Exercise, double>{};
    final topologyCache = <Exercise, double>{};

    return [
      for (final exercise in refined)
        _evaluateCandidate(
          state: state,
          session: session,
          exercise: exercise,
          at: at,
          safety: safety,
          recoveryTarget: target,
          tempoProbe: probe,
          override: overrides[exercise],
          introducibleTier: introducible,
          retrievalCache: retrievalCache,
          executionCache: executionCache,
          topologyCache: topologyCache,
        ),
    ];
  }

  CandidateTrace _evaluateCandidate({
    required LearnerState state,
    required SessionState session,
    required Exercise exercise,
    required DateTime at,
    required SafetyDecision safety,
    required Exercise? recoveryTarget,
    required Exercise? tempoProbe,
    required ChallengeBypass? override,
    required EligibilityTier? introducibleTier,
    required Map<String, double> retrievalCache,
    required Map<Exercise, double> executionCache,
    required Map<Exercise, double> topologyCache,
  }) {
    final realization = exercise.withGuidance(GuidanceContext.unguided);
    final independentRetrievalP = retrievalCache.putIfAbsent(
      exercise.material.materialId,
      () => learner.independentRetrievalProbability(state, exercise, at),
    );
    final prediction = Prediction(
      independentRetrievalP: independentRetrievalP,
      materialAvailableP: materialAvailableProbability(
        independentRetrievalP,
        exercise.guidance,
      ),
      executionP: executionCache.putIfAbsent(
        realization,
        () => learner.executionProbability(state, exercise),
      ),
      topologyP: topologyCache.putIfAbsent(
        realization,
        () => learner.topologyProbability(state, exercise),
      ),
    );

    // Ahead of admission rather than beside ranking: the introduction
    // exception reads the tier, so eligibility now decides what may be
    // admitted as well as how admitted candidates are ordered.
    final eligibility = eligibilityFor(state, exercise);
    final withinBand = isWithinChallengeBand(prediction);
    final bypass = challengeBypassFor(
      state: state,
      exercise: exercise,
      prediction: prediction,
      at: at,
      override: override,
      recoveryTarget: recoveryTarget,
      tempoProbe: tempoProbe,
      supportedAttempts: session.supportedAttemptsSinceObservation,
      eligibility: eligibility.tier,
      introducibleTier: introducibleTier,
    );
    // A recovery context is exclusive: narrowing which candidate gets the
    // label is not enough, since a candidate that happens to fall in the
    // ordinary band or qualify as new material must not survive alongside the
    // target. Something went wrong and the next thing asked for is the answer
    // to that.
    //
    // A tempo probe is not. It used to be, and it made the same scale come
    // back immediately at the speed it was just played, nearly every time
    // something was met: play C major at sixty, play it again at a hundred and
    // twenty. That was the only way to learn a learner's pace when a frontier
    // could only record what was asked for. Pace is recorded now, so material
    // arrives near them and the probe has much less to do; leaving it as an
    // ordinary exception lets it win a slot when it is the most useful thing
    // there and lose one to a scale nobody has played.
    final narrowed = recoveryTarget;
    final survived = narrowed != null && override == null
        ? bypass == ChallengeBypass.recovery
        : withinBand || bypass != null;

    final challengeStatus = safety.isAllowed
        ? StageStatus.reached
        : StageStatus.notReached;
    final priorityStatus = challengeStatus.isReached && survived
        ? StageStatus.reached
        : StageStatus.notReached;

    final terms = RankKey(
      tier: eligibility.tier,
      coordinationTransition: isCoordinationTransition(state, exercise),
      retention: retention(prediction, exercise),
      information: information(state, exercise, learner.params),
      diversity: diversity(exercise, session),
      goals: goals(exercise),
      realization: realizationRankFor(state, exercise),
      realizationFit: realizationFitFor(
        state,
        exercise,
        gentleTempoBpm: config.eligibility.gentleTempoBpm,
      ),
    );

    return CandidateTrace(
      exercise: exercise,
      eligibility: eligibility,
      safety: safety,
      challengeStatus: challengeStatus,
      prediction: prediction,
      isWithinChallengeBand: withinBand,
      challengeBypass: bypass,
      challengeSurvived: survived,
      priorityStatus: priorityStatus,
      terms: terms,
      rankKey: priorityStatus.isReached ? terms : null,
    );
  }

  /// Excludes a material that has been selected too many times in a row, as
  /// long as another admitted material exists.
  ///
  /// A pre-selection filter rather than another ranking term: under
  /// lexicographic ranking the diversity term can only break exact ties, so no
  /// diversity penalty could stop a material whose retention score wins
  /// outright. It never removes the only admitted option, which would force a
  /// no-admission slot to avoid repetition.
  List<CandidateTrace> applyRepetitionGuard(
    List<CandidateTrace> traces,
    SessionState session,
  ) {
    final ranked = traces.where((trace) => trace.isRanked).toList();
    if (ranked.isEmpty) return traces;

    final cap = config.diversity.maxConsecutiveMaterialAttempts;
    final overRepeated = {
      for (final trace in ranked) trace.exercise.material.materialId,
    }.where((id) => session.consecutiveAttemptsOf(id) >= cap).toSet();

    final guarded = ranked
        .where(
          (trace) => !overRepeated.contains(trace.exercise.material.materialId),
        )
        .toList();
    return guarded.isEmpty ? ranked : guarded;
  }

  /// The highest-ranking candidate, or null when nothing was admitted.
  ///
  /// The bare lexicographic primitive, kept usable on its own for unit tests.
  /// Production callers want [selectChoice], which applies the repetition
  /// guard first. Ties resolve to the earliest candidate in [traces], so
  /// selection stays deterministic for replay.
  CandidateTrace? selectBest(List<CandidateTrace> traces) {
    CandidateTrace? best;
    for (final trace in traces) {
      if (!trace.isRanked) continue;
      if (best == null || trace.rankKey!.compareTo(best.rankKey!) > 0) {
        best = trace;
      }
    }
    return best;
  }

  /// The independence probe to service when one has waited long enough, or
  /// null.
  ///
  /// A selection-stage rule beside the repetition guard rather than a rank
  /// term or another bypass, and each of those was considered. Ranking is
  /// strictly lexicographic, so an urgency term would not age gracefully: it
  /// would dominate everything below it the instant it differed. And a bypass
  /// would not help, because the probe is already admitted and already ranked.
  /// It is losing the contest, not missing from it.
  ///
  /// The highest-ranked probe rather than whichever has waited longest.
  /// Admission and ranking still choose which independence question is the
  /// right one to ask; fairness only guarantees that the kind of question
  /// eventually gets asked.
  ///
  /// Inert whenever a probe would have won anyway, and silent when none is
  /// ranked: a learner who has established no rung has no independence
  /// question waiting, and this must never manufacture one.
  CandidateTrace? overdueGuidanceProbe(
    List<CandidateTrace> traces,
    SessionState session,
  ) {
    if (session.unservedGuidanceProbeSelections <
        config.probe.maxUnservedGuidanceProbes) {
      return null;
    }
    return selectBest([
      for (final trace in traces)
        if (trace.challengeBypass == ChallengeBypass.guidanceProbe) trace,
    ]);
  }

  /// The candidates genuinely available this slot.
  ///
  /// One answer to "what could have been chosen", so the choice and anything
  /// recording what happened to the choice are looking at the same set. A
  /// candidate the repetition guard removed was not passed over; it was not
  /// there.
  List<CandidateTrace> selectable(
    List<CandidateTrace> traces,
    SessionState session,
  ) => applyRepetitionGuard(traces, session);

  /// The canonical V1 choice from an already-narrowed set: the diagnostic
  /// fairness guard, then lexicographic ranking.
  CandidateTrace? chooseFrom(
    List<CandidateTrace> selectable,
    SessionState session,
  ) => overdueGuidanceProbe(selectable, session) ?? selectBest(selectable);

  /// The canonical V1 choice: repetition guard, then the diagnostic fairness
  /// guard, then lexicographic ranking.
  ///
  /// Every real caller should use this rather than [selectBest] alone, which
  /// silently omits both guards and can reproduce perseveration.
  CandidateTrace? selectChoice(
    List<CandidateTrace> traces,
    SessionState session,
  ) => chooseFrom(selectable(traces, session), session);
}
