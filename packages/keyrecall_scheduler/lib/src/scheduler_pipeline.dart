import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'acquisition_floor.dart';
import 'candidate_trace.dart';
import 'config/scheduler_config.dart';
import 'execution_progression.dart';
import 'priority.dart';
import 'practice_entry_policy.dart';
import 'realization_family_pacing.dart';
import 'recovery.dart';
import 'session_state.dart';
import 'tempo_probe.dart';

/// What one admission exception has to say about one candidate.
///
/// A refusal ends the question; silence lets the next exception answer.
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

/// Answers about a learner that every candidate in one decision shares.
///
/// [SchedulerPipeline.eligibilityFor] asks several questions of learner state
/// alone: how broad a hand's ordinary repertoire is, where its execution mean
/// sits, whether coordination is fluent. Those do not vary across the ten
/// thousand candidates a slot evaluates, and the repertoire question walks the
/// whole catalog, so asking them per candidate was most of what a decision
/// cost for a learner whose material sits behind the altered-form gate.
///
/// Scoped to one decision and holding the state it answers about, so nothing
/// has to invalidate it: it is discarded before that state moves. Passing none
/// computes everything fresh, which is what a caller asking a single question
/// wants.
class DecisionFacts {
  /// The state every answer here is about.
  final LearnerState state;

  final Map<HandConfiguration, (int, int)> _breadth = {};
  final Map<(String, HandConfiguration), double> _executionMean = {};
  final Map<ScaleForm, double> _minorTopology = {};
  bool? _fluentHandsTogether;

  DecisionFacts(this.state);
}

/// The candidates considered and the reasoned outcome of one attempt slot.
///
/// This layer cannot report that a curriculum is caught up: it sees exercises,
/// not curriculum requirements or whether any work is due. An empty ordinary
/// path is therefore [SelectionBlocked], never a successful absence.
sealed class SelectionResult {
  final List<CandidateTrace> traces;
  final List<CandidateTrace> selectable;

  /// What realization-family pacing did to the available set.
  final PacingDecision pacing;

  const SelectionResult({
    required this.traces,
    required this.selectable,
    required this.pacing,
  });
}

/// The scheduler selected one candidate to present.
final class CandidateSelected extends SelectionResult {
  final CandidateTrace candidate;

  const CandidateSelected({
    required super.traces,
    required super.selectable,
    required super.pacing,
    required this.candidate,
  });
}

/// Why an unresolved scheduling request produced no usable candidate.
enum BlockedReason {
  /// No candidate survived ordinary challenge admission.
  admissionExhausted,

  /// The unresolved requirements supplied no valid entry realization.
  noSafeEntryRealization,

  /// A supplied entry realization could not pass the remaining stages.
  safeEntryRejected,
}

/// Useful work was requested, but the scheduler could not produce it.
final class SelectionBlocked extends SelectionResult {
  final BlockedReason reason;

  const SelectionBlocked({
    required super.traces,
    required super.selectable,
    required super.pacing,
    required this.reason,
  });
}

/// The staged decision pipeline that chooses what to practice next.
///
/// Eligibility and safety, then challenge admission, then priority ranking and
/// selection. Candidate generation lives outside this class because it may not
/// read learner state at all.
///
/// [evaluate] traces every candidate through every stage; [decide] performs a
/// complete decision-slot transition.
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
    AcquisitionFloor? acquisitionFloor,
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    final entryPolicy =
        practiceEntryPolicy ??
        PracticeEntryPolicy.uniform(config.eligibility.gentleTempoBpm);
    var traces = evaluate(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      practiceEntryPolicy: entryPolicy,
    );
    var pacing = pace(applyRepetitionGuard(traces, session), session);
    var available = pacing.selectable;
    var selected = chooseFrom(available, session);
    var blockedReason = BlockedReason.admissionExhausted;

    if (selected == null && acquisitionFloor != null) {
      final floorOverrides = <Exercise, ChallengeBypass>{};
      var everyEntryIsInScope = true;
      for (final entry in acquisitionFloor.entries) {
        if (candidates.contains(entry.exercise)) {
          floorOverrides[entry.exercise] = ChallengeBypass.acquisitionFloor;
        } else {
          everyEntryIsInScope = false;
        }
      }

      if (acquisitionFloor.entries.isEmpty) {
        blockedReason = BlockedReason.noSafeEntryRealization;
      } else if (!everyEntryIsInScope) {
        blockedReason = BlockedReason.safeEntryRejected;
      } else {
        traces = evaluate(
          state: state,
          session: session,
          candidates: candidates,
          at: at,
          overrides: {...overrides, ...floorOverrides},
          practiceEntryPolicy: entryPolicy,
        );
        pacing = pace(applyRepetitionGuard(traces, session), session);
        available = pacing.selectable;
        selected = chooseFrom(available, session);
        blockedReason = BlockedReason.safeEntryRejected;
      }
    }

    session.recordSelectionOpportunity(
      guidanceProbeAvailable: available.any(
        (trace) => trace.challengeBypass == ChallengeBypass.guidanceProbe,
      ),
      guidanceProbeSelected:
          selected?.challengeBypass == ChallengeBypass.guidanceProbe,
    );
    session.attemptsThisSession++;
    return selected == null
        ? SelectionBlocked(
            traces: traces,
            selectable: available,
            pacing: pacing,
            reason: blockedReason,
          )
        : CandidateSelected(
            traces: traces,
            selectable: available,
            pacing: pacing,
            candidate: selected,
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
    if (config.pacing case final pacing?) {
      session.recordFamilySelection(
        exercise,
        productive: outcome != null && learner.executionWasManaged(outcome),
        config: pacing,
      );
    }
  }

  /// Stage 2a: the `REQUIRES` prerequisite gate.
  ///
  /// Two questions, both about the learner rather than the exercise: whether
  /// both hands are capable before they play together, and whether this
  /// material is appropriate to introduce yet. Foundation material has no
  /// prerequisite of the second kind, which is not the same as being fully
  /// eligible however it is played.
  ///
  /// Nothing measures whether a hand pattern is established, so the admission
  /// band stands in for it as a curriculum-derived prior. `EligibilityReason`
  /// is coded so that stalls clustering at one band remain visible.
  ///
  /// Provisional rather than forbidden, in every case: a provisional candidate
  /// is outranked by anything fully eligible and stays reachable when nothing
  /// else is.
  EligibilityDecision eligibilityFor(
    LearnerState state,
    Exercise exercise, {
    DecisionFacts? facts,
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    final entryPolicy =
        practiceEntryPolicy ??
        PracticeEntryPolicy.uniform(config.eligibility.gentleTempoBpm);
    final material = exercise.material;
    final scaleForm = material.scaleForm;
    final band = admissionBandOf(material);
    final hands = exercise.conditions.hands;

    // An unguided attempt would test a memory this app has never seen formed.
    // The material is still admissible, through a rung that supplies it.
    if (!state.materialMemory.containsKey(material.materialId) &&
        !exercise.guidance.isMaterialSupplied) {
      return const EligibilityDecision(
        EligibilityTier.provisionallyEligible,
        'no history for this material, so its first encounter is cued',
        code: EligibilityReason.unseenMaterialRequiresCue,
      );
    }

    // An altered minor form is a new idea rather than a new key, so its
    // prerequisite is a curriculum phase rather than keyboard geography.
    if (scaleForm != null && !coreForms.contains(scaleForm)) {
      final breadth = _alteredFormDecisionFor(state, scaleForm, hands, facts);
      if (breadth != null) return breadth;
    }

    if (!_materialPrerequisitesSatisfied(state, exercise)) {
      return EligibilityDecision(
        EligibilityTier.provisionallyEligible,
        '${material.materialId} requires demonstrated work on '
        '${material.progression.prerequisiteMaterialIds.join(', ')}',
        code: EligibilityReason.materialProgressionPrerequisite,
      );
    }

    // Each hand having separately demonstrated this material at this span:
    // evidence about the work in front of the learner rather than a general
    // verdict on their hands, and about the pitches rather than the polish.
    // See [supportsHandsTogether].
    if (hands == HandConfiguration.together &&
        material.progression.requiresSeparateHandsBeforeTogether) {
      if (!handsTogetherPrerequisiteSatisfied(state, exercise)) {
        return const EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          'each hand has still to learn this alone at this span',
          code: EligibilityReason.handsTogetherPrerequisite,
        );
      }
    }

    // One octave before two is the one execution ordering every source agrees
    // on, and the information term otherwise reaches for the span nobody has
    // attempted precisely because nobody has. One octave stays fully eligible.
    if (exercise.conditions.octaves > 1) {
      if (material.progression.requiresPreviousSpanEvidence &&
          !_previousSpanPrerequisiteSatisfied(state, exercise)) {
        final previous = material.progression.previousSpan(
          exercise.conditions.octaves,
        );
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          '${exercise.conditions.octaves} octaves require demonstrated '
          '$previous-octave work in this realization',
          code: EligibilityReason.octaveSpanPrerequisite,
        );
      }
      final floor = config.eligibility.multiOctaveExecutionFloor;
      final execution = _executionMeanFor(state, material, hands, facts);
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
    // so gating it on minor familiarity would outrank every minor scale
    // forever.
    if (scaleForm == ScaleForm.harmonicMinor ||
        scaleForm == ScaleForm.melodicMinor) {
      final floor = config.eligibility.minorTopologyFloor;
      final familiar = _bestMinorTopology(state, scaleForm!, facts);
      if (familiar < floor) {
        return EligibilityDecision(
          EligibilityTier.provisionallyEligible,
          'another minor form is at ${familiar.toStringAsFixed(2)}, '
          'floor ${floor.toStringAsFixed(2)}',
          code: scaleForm == ScaleForm.melodicMinor
              // Fixed-form melodic minor is the least familiar of the three
              // and waits for either of the others.
              ? EligibilityReason.melodicFormPrerequisite
              : EligibilityReason.minorTopologyPrerequisite,
        );
      }
    }

    if (band != AdmissionBand.foundation) {
      // The material's own record is a stronger claim than a general execution
      // mean: a learner who has played this key, in this hand, at this span
      // has already answered what the floor asks. At this span rather than any
      // span, because two octaves of a key is a geography one octave has not
      // shown.
      //
      // Difficulty is compositional, so the floor below discounts by one band
      // when the key is met at the gentlest conditions the catalog offers.
      // Unfamiliar geography and a harder way of playing are separate asks,
      // and the floor protects against taking both at once.
      final demonstrated =
          state.materialExecution[executionContextOf(exercise)]
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

      final asked = _isGentlest(exercise, entryPolicy)
          ? _bandBefore(band)
          : band;
      final floor = config.eligibility.executionFloorFor(asked);
      final execution = _executionMeanFor(state, material, hands, facts);
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

    // Foundation means no *material* prerequisite. An execution condition
    // checked above may still hold the exercise back.
    return const EligibilityDecision(
      EligibilityTier.fullyEligible,
      'foundation material, and no material prerequisite applies',
      code: EligibilityReason.foundationMaterial,
    );
  }

  /// Whether [exercise] would be this hand's first encounter with its
  /// material.
  ///
  /// Per hand rather than per material. Knowing the notes travels with the
  /// learner, but playing them with the other hand is a fingering nobody has
  /// attempted, and material memory alone cannot tell the two apart.
  ///
  /// Hands together is not an introduction. It is a transition off two
  /// frontiers that already exist, with its own prerequisite and entry tempo,
  /// which execution progression offers instead.
  bool isIntroduction(LearnerState state, Exercise exercise) =>
      exercise.conditions.hands != HandConfiguration.together &&
      !state.hasPlayed(exercise.material.materialId, exercise.conditions.hands);

  /// Whether [exercise] may be met for the first time at all.
  ///
  /// The only place this comes apart from eligibility, which merely orders
  /// candidates: provisional means deferred while something better exists,
  /// which is right for an execution condition and wrong for a curriculum
  /// phase. The altered forms are therefore a barrier rather than a
  /// disadvantage, and only against meeting one for the first time. Recovery
  /// of one already introduced is a separate question.
  ///
  /// Asked directly rather than read off the eligibility reason, which is
  /// whichever rule refused first.
  bool isIntroducible(
    LearnerState state,
    Exercise exercise, {
    DecisionFacts? facts,
  }) {
    final form = exercise.material.scaleForm;
    return form == null ||
        _alteredFormDecisionFor(
              state,
              form,
              exercise.conditions.hands,
              facts,
            ) ==
            null;
  }

  /// Whether an altered minor form has to wait for a foundation under it, or
  /// null when it does not and the ordinary rules decide.
  ///
  /// A curriculum phase transition rather than a threshold, so it asks for
  /// three observable markers of the phase, none of which harmonic minor needs
  /// mechanically. `docs/domain-model/material-admission.md` carries the
  /// curriculum rationale for each.
  ///
  /// - both hands observed separately;
  /// - some hands-together exposure on ordinary material, which applies to
  ///   one-hand candidates too because it marks the phase rather than a need
  ///   for two hands;
  /// - retrieval breadth across major and natural minor, counted per hand.
  ///
  /// Each asks whether a channel has been *observed* rather than where its mean
  /// sits, because placement seeds means from what the learner said about
  /// themselves. Waived by observed fluent hands-together coordination, and
  /// only by that; see [_hasFluentHandsTogether].
  EligibilityDecision? _alteredFormDecisionFor(
    LearnerState state,
    ScaleForm form,
    HandConfiguration hands,
    DecisionFacts? facts,
  ) {
    final required = switch (form) {
      ScaleForm.harmonicMinor => config.eligibility.harmonicMinorCoreRetrievals,
      ScaleForm.melodicMinor => config.eligibility.melodicMinorCoreRetrievals,
      _ => 0,
    };
    if (required == 0) return null;

    if (_hasFluentHandsTogether(state, facts)) return null;

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
      final (retrieved, spread) = _ordinaryBreadthFor(state, hand, facts);
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
  /// Memory knows a scale was retrieved without knowing which hand played;
  /// execution residuals know a hand played it without knowing whether
  /// anything was remembered. Requiring both is the closest this state comes to
  /// "this hand has this scale", and it is a projection rather than a record: a
  /// scale retrieved by one hand and merely played by the other counts for
  /// both.
  (int, int) _ordinaryBreadthFor(
    LearnerState state,
    HandConfiguration hand,
    DecisionFacts? facts,
  ) {
    final memo = facts?._breadth[hand];
    if (memo != null) return memo;
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
    final breadth = (retrieved, spread.length);
    facts?._breadth[hand] = breadth;
    return breadth;
  }

  /// Whether hands-together playing has been observed and is fluent.
  ///
  /// The only escape hatch from the phase graph. The ordinary path establishes
  /// the phase developmentally; this establishes that the learner is already
  /// past it, so it asks about the dimension that defines the phase rather than
  /// about either hand separately.
  ///
  /// Observed and fluent, both. Placement seeds this mean from the onboarding
  /// answer, so the mean alone would let a self-report skip the phase, and
  /// exposure alone would let one ragged first attempt do it.
  bool _hasFluentHandsTogether(LearnerState state, DecisionFacts? facts) {
    final memo = facts?._fluentHandsTogether;
    if (memo != null) return memo;
    final fluent =
        state.isObserved(Competency.handsTogetherCoordination) &&
        state.competency(Competency.handsTogetherCoordination).mean >=
            config.eligibility.fluentHandsTogetherFloor;
    facts?._fluentHandsTogether = fluent;
    return fluent;
  }

  static Competency _executionCompetencyOf(HandConfiguration hand) =>
      hand == HandConfiguration.right
      ? Competency.rhScaleExecution
      : Competency.lhScaleExecution;

  bool _materialPrerequisitesSatisfied(LearnerState state, Exercise exercise) {
    final prerequisites = exercise.material.progression.prerequisiteMaterialIds;
    if (prerequisites.isEmpty) return true;
    final hands = [
      if (exercise.conditions.hands.usesRightHand) HandConfiguration.right,
      if (exercise.conditions.hands.usesLeftHand) HandConfiguration.left,
    ];
    return prerequisites.every(
      (materialId) => hands.every(
        (hand) => state.materialExecution.entries.any(
          (entry) =>
              entry.key.$1 == materialId &&
              entry.key.$2 == hand &&
              entry.value.demonstratedTempoByOctaves.isNotEmpty,
        ),
      ),
    );
  }

  bool _previousSpanPrerequisiteSatisfied(
    LearnerState state,
    Exercise exercise,
  ) {
    final span = exercise.conditions.octaves;
    final previous = exercise.material.progression.previousSpan(span);
    if (previous == null) return false;
    final demonstrated =
        state.materialExecution[executionContextOf(exercise)]
            ?.demonstratedTempoAt(previous) ??
        0;
    if (demonstrated > 0) return true;
    return exercise.conditions.hands == HandConfiguration.together &&
        supportsHandsTogether(state, exercise.material.materialId, span);
  }

  /// The tempo [exercise]'s material is introduced at.
  ///
  /// What this learner's playing hand has shown on material they already own,
  /// or the slow end of ordinary practice when they have shown nothing, so that
  /// a working pace is not walked back every time the catalog opens wider.
  ///
  /// Held back one rung for the later bands. Transfer across fingering families
  /// is what nothing here measures yet, so a key whose geography is new is met
  /// unhurried whatever the hand has managed on keys it knows.
  double entryTempoFor(
    LearnerState state,
    Exercise exercise, {
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    final entryPolicy =
        practiceEntryPolicy ??
        PracticeEntryPolicy.uniform(config.eligibility.gentleTempoBpm);
    final transferable = transferableTempoFor(
      state,
      exercise.conditions.hands,
      exercise.conditions.octaves,
    );
    // Nobody has seen this learner play, so there is no evidence to be
    // conservative about. The gentle tempo is the only honest default.
    if (transferable <= 0) return entryPolicy.tempoFor(exercise.material);

    // One rung, and exactly one. An unfamiliar fingering is a real additional
    // ask, so the full pace is overconfident; the learner's own pace is direct
    // behavioral evidence, so the bottom of the ladder discards it.
    return admissionBandOf(
          exercise.material,
        ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer)
        ? transferable
        : tempoBefore(transferable);
  }

  /// Whether these are the gentlest conditions the family offers.
  ///
  /// One octave, one hand, at the slow end of ordinary practice. Not the
  /// guidance rung, which is a separate ladder with its own rules about first
  /// encounters and about what independence has to be earned.
  bool _isGentlest(Exercise exercise, PracticeEntryPolicy entryPolicy) =>
      exercise.conditions.octaves == 1 &&
      exercise.conditions.hands != HandConfiguration.together &&
      exercise.conditions.tempoBpm <= entryPolicy.tempoFor(exercise.material);

  /// The band before [band], or [band] itself when it is the first.
  static AdmissionBand _bandBefore(AdmissionBand band) =>
      band == AdmissionBand.foundation
      ? band
      : AdmissionBand.values[band.index - 1];

  /// The weaker hand's execution when both play, otherwise the playing hand's.
  double _executionMeanFor(
    LearnerState state,
    TechnicalMaterial material,
    HandConfiguration hands, [
    DecisionFacts? facts,
  ]) {
    final cacheKey = (material.familyId, hands);
    final memo = facts?._executionMean[cacheKey];
    if (memo != null) return memo;
    final rhCompetency = material
        .executionCompetenciesFor(HandConfiguration.right)
        .single;
    final lhCompetency = material
        .executionCompetenciesFor(HandConfiguration.left)
        .single;
    final rh = state.competency(rhCompetency).mean;
    final lh = state.competency(lhCompetency).mean;
    final mean = switch (hands) {
      HandConfiguration.right => rh,
      HandConfiguration.left => lh,
      HandConfiguration.together => rh < lh ? rh : lh,
    };
    facts?._executionMean[cacheKey] = mean;
    return mean;
  }

  /// The best minor topology the learner has, ignoring [exclude].
  ///
  /// Ignoring the form being admitted is what makes this a transfer rule
  /// rather than a self-referential one: A harmonic minor is admitted on the
  /// strength of A natural minor, not of itself. Note that it is any minor
  /// topology rather than the same tonic's, since the curricula give no
  /// support for a per-key ladder either.
  double _bestMinorTopology(
    LearnerState state,
    ScaleForm exclude,
    DecisionFacts? facts,
  ) {
    final memo = facts?._minorTopology[exclude];
    if (memo != null) return memo;
    var best = double.negativeInfinity;
    for (final form in ScaleForm.values) {
      if (form == ScaleForm.major || form == exclude) continue;
      final mean = state.competency(form.topologyCompetency).mean;
      if (mean > best) best = mean;
    }
    facts?._minorTopology[exclude] = best;
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

  /// The one tempo a probe about guidance is asked at.
  ///
  /// **A probe holds every condition but the axis it asks about.** A probe that
  /// moves two axes has asked two questions and can answer neither, because
  /// nothing in the outcome says which one the learner responded to. Holding
  /// has to be explicit here: these are predicates over generated candidates
  /// rather than constructed exercises, and the ranking key reads none of the
  /// execution conditions, so an unconstrained axis is chosen by the order of a
  /// constant.
  ///
  /// The frontier for this material, hand and span, which is where the learner
  /// already is, or [entryTempoFor] when that span has never been managed.
  double heldTempoFor(
    LearnerState state,
    Exercise exercise, {
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    final frontier =
        state.materialExecution[executionContextOf(exercise)]
            ?.demonstratedTempoAt(exercise.conditions.octaves) ??
        0;
    return frontier > 0
        ? frontier
        : entryTempoFor(
            state,
            exercise,
            practiceEntryPolicy: practiceEntryPolicy,
          );
  }

  /// Whether [exercise] is a proactive step back toward independence.
  ///
  /// The mirror of recovery: the same task at exactly one rung less support
  /// than the one the learner last succeeded under, where recovery is the same
  /// task at one rung more. That makes the ladder traversable in both
  /// directions and gives it a top, since a material established unguided has
  /// no less supportive rung to be probed toward.
  ///
  /// Paced by how long the rung has been established rather than by how long
  /// ago retrieval last happened. Sharing the retrieval clock would make every
  /// success at the established rung push the next step away. Producing a scale
  /// seconds after being shown it still proves little, so the establishment
  /// clock is short rather than absent.
  bool isGuidanceProbe(
    LearnerState state,
    Exercise exercise,
    DateTime at, {
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    final memory = state.materialMemory[exercise.material.materialId];
    final established = memory?.establishedIndependence;
    final since = memory?.establishedIndependenceAt;
    if (established == null || since == null) return false;
    if (exercise.guidance.independence != established + 1) return false;
    if (exercise.conditions.tempoBpm !=
        heldTempoFor(
          state,
          exercise,
          practiceEntryPolicy: practiceEntryPolicy,
        )) {
      return false;
    }
    return since.daysUntil(at) >= config.probe.minDaysSinceSupportEstablished;
  }

  /// Whether [exercise] is a retrieval test for material with no rung
  /// currently established.
  ///
  /// The counterpart to [isGuidanceProbe], which climbs from an established
  /// rung and so cannot help where there is none: the material has never been
  /// retrieved, or it failed and unsettled the rung. Recovery can otherwise
  /// walk a material down to full cueing, where retrieval is never observed and
  /// nothing re-establishes anything.
  ///
  /// Its clock is the last factual attempt of any kind rather than the last
  /// success, since after a failure there may be no success to count from, and
  /// the wait is the long one: returning to something that just went wrong is a
  /// question about retention.
  bool isBootstrapProbe(
    LearnerState state,
    Exercise exercise,
    DateTime at, {
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    if (exercise.guidance != GuidanceContext.notesPreviewedOnly) return false;
    final memory = state.materialMemory[exercise.material.materialId];
    if (memory == null || memory.establishedIndependence != null) return false;
    final lastAttempt = memory.lastRetrievalAttemptAt;
    if (lastAttempt == null) return false;
    if (exercise.conditions.tempoBpm !=
        heldTempoFor(
          state,
          exercise,
          practiceEntryPolicy: practiceEntryPolicy,
        )) {
      return false;
    }
    return lastAttempt.daysUntil(at) >= config.probe.minDaysSinceLastRetrieval;
  }

  /// Whether [exercise] is a deliberate retrieval test for material that has
  /// been practised under support without retrieval being observed.
  ///
  /// Support raises predicted success, so as memory weakens the ordinary band
  /// comes to prefer continuous cueing. Cueing observes no retrieval, so the
  /// preference then persists on evidence that can never be collected. After
  /// enough supported attempts, one retrieval-observing question is asked
  /// whatever its predicted success.
  bool isObservationProbe(
    LearnerState state,
    Exercise exercise,
    int supportedAttempts, {
    PracticeEntryPolicy? practiceEntryPolicy,
  }) =>
      exercise.guidance == GuidanceContext.notesPreviewedOnly &&
      exercise.conditions.tempoBpm ==
          heldTempoFor(
            state,
            exercise,
            practiceEntryPolicy: practiceEntryPolicy,
          ) &&
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
    List<Exercise> candidates, {
    DecisionFacts? facts,
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    EligibilityTier? best;
    for (final exercise in candidates) {
      if (!isIntroduction(state, exercise)) continue;
      if (!isIntroducible(state, exercise, facts: facts)) continue;
      final tier = eligibilityFor(
        state,
        exercise,
        facts: facts,
        practiceEntryPolicy: practiceEntryPolicy,
      ).tier;
      if (best == null || tier.index > best.index) best = tier;
      if (best == EligibilityTier.fullyEligible) break;
    }
    return best;
  }

  /// Which named exception, if any, admits [exercise] outside the ordinary
  /// band.
  ///
  /// Precedence is [AdmissionException]'s declaration order, consulted until
  /// one of them answers. The order is policy rather than an accident of
  /// layout: an override is an explicit instruction and beats every inference;
  /// recovery beats the tempo probe because something that just went wrong
  /// matters more than something that went too easily; the observation probe
  /// comes before the introduction floor because a drought is a drought
  /// whether the candidate that ends it is new or familiar.
  ///
  /// Some exceptions answer for a candidate they do not admit, which is why
  /// [_Verdict] distinguishes refusing from having nothing to say: a recovery
  /// context refuses everything but its target, and material below the
  /// introduction floor is refused rather than passed along.
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
    DecisionFacts? facts,
    PracticeEntryPolicy? practiceEntryPolicy,
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
          isObservationProbe(
                state,
                exercise,
                supportedAttempts,
                practiceEntryPolicy: practiceEntryPolicy,
              )
              ? const _Admits(ChallengeBypass.observationProbe)
              : const _Silent(),
        // The slot has nothing appropriate left to introduce, and something
        // already met that has never been produced from memory. Offering it
        // again is better work than reaching for material the learner has not
        // earned.
        //
        // The previewed rung, and only that one, for the reason the bootstrap
        // probe uses it: where no rung is established, that is the retrieval
        // test to offer. A cued repeat cannot turn a scale that has been shown
        // into one that has been produced, and an unguided one hands out
        // independence that is supposed to be earned.
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

        // Difficulty is what an introduction may bypass, and only that. A
        // prerequisite says the material is inappropriate for a separate
        // reason, so while the slot has an introducible candidate in a higher
        // tier, a lower one is unreachable here.
        //
        // Tier is checked before the probability floor: reversing them would
        // let a provisional candidate that clears the introduction minimum beat
        // a fully eligible one that does not.
        AdmissionException.newMaterial =>
          !isIntroduction(state, exercise)
              ? const _Silent()
              : !isIntroducible(state, exercise, facts: facts)
              ? const _Refuses()
              : eligibility != introducibleTier
              ? const _Refuses()
              // One tempo, and a chosen one: nothing in the ranking key reads
              // tempo, so an unconstrained introduction meets whichever tempo
              // generation happened to list first.
              : exercise.conditions.tempoBpm !=
                    entryTempoFor(
                      state,
                      exercise,
                      practiceEntryPolicy: practiceEntryPolicy,
                    )
              ? const _Refuses()
              : prediction.overallP >= config.challenge.pIntroductionMin
              ? const _Admits(ChallengeBypass.newMaterial)
              : const _Refuses(),
        AdmissionException.guidanceProbe =>
          isGuidanceProbe(
                state,
                exercise,
                at,
                practiceEntryPolicy: practiceEntryPolicy,
              )
              ? const _Admits(ChallengeBypass.guidanceProbe)
              : const _Silent(),
        AdmissionException.bootstrapProbe =>
          isBootstrapProbe(
                state,
                exercise,
                at,
                practiceEntryPolicy: practiceEntryPolicy,
              )
              ? const _Admits(ChallengeBypass.bootstrapProbe)
              : const _Silent(),

        // Deepening material the learner owns rather than has been shown:
        // playing a scale perfectly while it is in front of them demonstrates
        // the motor conditions and not the scale, so a faster one would race
        // execution ahead of what they know. Establishing the material is
        // consolidation's job, and this begins where that ends.
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
    PracticeEntryPolicy? practiceEntryPolicy,
  }) {
    final entryPolicy =
        practiceEntryPolicy ??
        PracticeEntryPolicy.uniform(config.eligibility.gentleTempoBpm);
    final failed = session.lastFailedExercise;
    final target = failed == null ? null : recoveryTarget(failed);
    final probe = target == null ? session.tempoProbe : null;
    final safety = safetyFor(session);
    // Refined once here, so that every set-level fact below reads the same
    // universe the candidate loop evaluates.
    //
    // An exclusive target has to be in the set it narrows: recovery and the
    // tempo probe both refuse everything but one exact exercise, so a target
    // the candidates do not contain would leave the slot admitting nothing.
    final neighbours = withExecutionNeighbours(state, candidates);
    final refined = [
      ...neighbours,
      for (final exclusive in [target, probe])
        if (exclusive != null && !neighbours.contains(exclusive)) exclusive,
    ];
    // One memo for the slot, so the questions eligibility asks of state alone
    // are answered once rather than once per candidate.
    final facts = DecisionFacts(state);
    final introducible = introducibleTier(
      state,
      refined,
      facts: facts,
      practiceEntryPolicy: entryPolicy,
    );

    // Guidance changes material availability, but not independent retrieval,
    // execution, coordination, or topology. Generation emits each realization under all
    // three guidance levels, so those channels are computed once per
    // realization, keyed by the same exercise with guidance normalized away.
    final retrievalCache = <String, double>{};
    final executionCache = <Exercise, double>{};
    final coordinationCache = <Exercise, double>{};
    final topologyCache = <Exercise, double>{};
    final informationCache = <InformationKey, double>{};

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
          facts: facts,
          retrievalCache: retrievalCache,
          executionCache: executionCache,
          coordinationCache: coordinationCache,
          topologyCache: topologyCache,
          informationCache: informationCache,
          practiceEntryPolicy: entryPolicy,
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
    required DecisionFacts facts,
    required Map<String, double> retrievalCache,
    required Map<Exercise, double> executionCache,
    required Map<Exercise, double> coordinationCache,
    required Map<Exercise, double> topologyCache,
    required Map<InformationKey, double> informationCache,
    required PracticeEntryPolicy practiceEntryPolicy,
  }) {
    final realization = exercise.withGuidance(GuidanceContext.unguided);
    final independentRetrievalP = retrievalCache.putIfAbsent(
      exercise.material.materialId,
      () => learner.independentRetrievalProbability(state, exercise, at),
    );
    final prediction = learner.predictionFromChannels(
      guidance: exercise.guidance,
      independentRetrievalP: independentRetrievalP,
      executionP: executionCache.putIfAbsent(
        realization,
        () => learner.executionProbability(state, exercise),
      ),
      coordinationP: coordinationCache.putIfAbsent(
        realization,
        () => learner.coordinationProbability(state, exercise),
      ),
      topologyP: topologyCache.putIfAbsent(
        realization,
        () => learner.topologyProbability(state, exercise),
      ),
    );

    // Ahead of admission rather than beside ranking: the introduction
    // exception reads the tier, so eligibility now decides what may be
    // admitted as well as how admitted candidates are ordered.
    final eligibility = eligibilityFor(
      state,
      exercise,
      facts: facts,
      practiceEntryPolicy: practiceEntryPolicy,
    );
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
      facts: facts,
      practiceEntryPolicy: practiceEntryPolicy,
    );
    // A recovery context is exclusive: a candidate that happens to fall in the
    // ordinary band or qualify as new material must not survive alongside the
    // target. Something went wrong, and the next thing asked for answers it.
    //
    // A tempo probe is not exclusive. Pace is recorded on the frontier, so the
    // probe competes as an ordinary exception: it wins a slot when it is the
    // most useful thing there and loses one to a scale nobody has played.
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

    final transition = isCoordinationTransition(state, exercise);

    // Ranking terms only for candidates that reached ranking. Nothing here
    // participates in deciding whether ranking is reached, which is what makes
    // this a computation the pipeline declines rather than a decision it
    // changes: everything above is already settled.
    //
    // Most candidates never get here. A slot evaluates ten thousand and for
    // most learners fewer than one in twenty survives admission.
    final rankKey = priorityStatus.isReached
        ? RankKey(
            tier: eligibility.tier,
            coordinationTransition: transition,
            contraryCoordination:
                transition &&
                exercise.conditions.handMotion == HandMotion.contrary,
            retention: retention(prediction, exercise),
            information: informationCache.putIfAbsent(
              informationKeyFor(exercise),
              () => information(state, exercise, learner.params),
            ),
            diversity: diversity(exercise, session),
            goals: goals(exercise),
            realization: realizationRankFor(state, exercise),
            realizationFit: realizationFitFor(
              state,
              exercise,
              practiceEntryPolicy: practiceEntryPolicy,
            ),
          )
        : null;

    return CandidateTrace(
      exercise: exercise,
      handsTogetherPrerequisiteSatisfied:
          exercise.conditions.hands == HandConfiguration.together
          ? handsTogetherPrerequisiteSatisfied(state, exercise)
          : null,
      coordinationTransition: transition,
      eligibility: eligibility,
      safety: safety,
      challengeStatus: challengeStatus,
      prediction: prediction,
      isWithinChallengeBand: withinBand,
      challengeBypass: bypass,
      challengeSurvived: survived,
      priorityStatus: priorityStatus,
      rankKey: rankKey,
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
    if (ranked.isEmpty) return ranked;

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
  /// A selection-stage rule rather than a rank term or another bypass. Ranking
  /// is strictly lexicographic, so an urgency term would dominate everything
  /// below it the instant it differed, and a bypass would not help because the
  /// probe is already admitted and ranked. It is losing the contest, not
  /// missing from it.
  ///
  /// The highest-ranked probe rather than whichever has waited longest:
  /// admission and ranking still choose which independence question to ask,
  /// and this only guarantees that the kind of question eventually gets asked.
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
  ) => pace(applyRepetitionGuard(traces, session), session).selectable;

  /// Realization-family pacing applied to an already-guarded set.
  ///
  /// A selection-stage filter beside the repetition guard, not an admission
  /// rule: a pressured candidate stays eligible and ranked, and wins the slot
  /// whenever nothing from another family is admitted. Under lexicographic
  /// ranking a penalty term could only break exact ties, so pressure has to
  /// act on the available set to act at all.
  ///
  /// What it claims is a trajectory-level proposition: over a trajectory,
  /// periodically making room for another reasonably ready technical strand
  /// improves practice allocation. It does not claim that any particular
  /// substitution teaches more than the candidate it displaced, which is why
  /// relief asks only that the alternative is not a step backward.
  PacingDecision pace(List<CandidateTrace> guarded, SessionState session) {
    final policy = config.pacing;
    if (policy == null) return PacingDecision.inactive(guarded);
    final pressured = pressuredFamilies(
      window: session.recentFamilies,
      config: policy,
    );
    if (pressured.isEmpty) return PacingDecision.inactive(guarded);

    final relieved = [
      for (final trace in guarded)
        if (!isPressured(trace.exercise, pressured)) trace,
    ];
    if (relieved.isEmpty) return PacingDecision.unrelieved(guarded);
    if (relieved.length == guarded.length) {
      return PacingDecision.inactive(guarded);
    }

    final setAside = FamilySetAside(
      slot: session.attemptsThisSession,
      pressuredFamilies: pressured,
      pressured: selectBest([
        for (final trace in guarded)
          if (isPressured(trace.exercise, pressured)) trace,
      ])!,
      relieving: selectBest(relieved)!,
    );
    if (policy.requireReadyAlternative && !setAside.isRelievable) {
      return PacingDecision.unready(guarded);
    }
    return PacingDecision.relieved(relieved, setAside);
  }

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
