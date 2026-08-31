import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

/// How far an exercise has cleared the `REQUIRES` prerequisite gate.
///
/// A soft pedagogical gate: a provisional candidate stays reachable, but can
/// never outrank a fully eligible one. Declaration order is rank order.
enum EligibilityTier {
  /// Reachable, but outranked by anything fully eligible.
  provisionallyEligible('PROVISIONALLY_ELIGIBLE'),

  /// Prerequisites met.
  fullyEligible('FULLY_ELIGIBLE');

  const EligibilityTier(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// Which prerequisite rule decided a candidate's eligibility.
///
/// Coded rather than only described, because the question these answer is
/// where admission is too conservative, and that needs failures grouped rather
/// than read. In particular, the fingering-family axis is approximated by the
/// band prior today, so stalls clustering at a band that introduces a new hand
/// pattern are the evidence that would justify measuring it directly.
enum EligibilityReason {
  /// No prerequisite relationship applies to this exercise.
  noPrerequisite('NO_PREREQUISITE'),

  /// Material every learner may practice from the start.
  foundationMaterial('FOUNDATION_MATERIAL'),

  /// The material's band is met by demonstrated single-hand execution.
  bandExecutionMet('BAND_EXECUTION_MET'),

  /// The learner has already played this material, in this hand, at this span,
  /// so the band's question about the key is settled by evidence.
  bandGeographyDemonstrated('BAND_GEOGRAPHY_DEMONSTRATED'),

  /// The material's band asks for more single-hand execution than the learner
  /// has shown.
  bandExecutionFloor('BAND_EXECUTION_FLOOR'),

  /// A minor form asks for some familiarity with minor topology first.
  minorTopologyPrerequisite('MINOR_TOPOLOGY_PREREQUISITE'),

  /// Fixed-form melodic minor asks for another minor form first.
  melodicFormPrerequisite('MELODIC_FORM_PREREQUISITE'),

  /// Hands-together work asks for both hands first.
  handsTogetherPrerequisite('HANDS_TOGETHER_PREREQUISITE'),

  /// A multi-octave traversal asks for one octave first.
  octaveSpanPrerequisite('OCTAVE_SPAN_PREREQUISITE'),

  /// An altered minor form asks for both hands to have been observed
  /// separately first.
  alteredFormHandsFoundation('ALTERED_FORM_HANDS_FOUNDATION'),

  /// An altered minor form asks for some hands-together work on ordinary
  /// material first.
  alteredFormHandsTogetherFoundation('ALTERED_FORM_HANDS_TOGETHER_FOUNDATION'),

  /// Harmonic minor asks for a broad base of ordinary scales first.
  harmonicMinorRepertoireBreadth('HARMONIC_MINOR_REPERTOIRE_BREADTH'),

  /// Melodic minor asks for a broader one still.
  melodicMinorRepertoireBreadth('MELODIC_MINOR_REPERTOIRE_BREADTH'),

  /// Material KeyRecall has no history for may be introduced, but not tested
  /// from memory first.
  ///
  /// A rung question rather than a material one: the material itself is
  /// admissible, and this says only that its first encounter here has to
  /// supply it. It makes no claim that the learner does not know the scale,
  /// which is exactly what an unguided first attempt would be assuming.
  unseenMaterialRequiresCue('UNSEEN_MATERIAL_REQUIRES_CUE');

  const EligibilityReason(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// Whether the real pipeline reached a stage for a candidate.
///
/// Every candidate carries a fully populated trace, because that traceability
/// is the point. But a computed value is not the same claim as "the pipeline
/// consulted this", and this distinction keeps that explicit rather than
/// leaving it implicit in whether a field happens to be populated.
enum StageStatus {
  /// The pipeline really evaluated this stage for this candidate.
  reached('reached'),

  /// An earlier stage already excluded this candidate; any value recorded
  /// alongside is diagnostic only.
  notReached('not_reached');

  const StageStatus(this.id);

  /// Stable identifier used in traces.
  final String id;

  /// Whether the pipeline reached this stage.
  bool get isReached => this == StageStatus.reached;
}

/// A named reason a candidate was admitted outside the ordinary challenge
/// band.
enum ChallengeBypass {
  /// Material already met and not yet retrieved, offered again rather than
  /// letting the slot reach for something new and less appropriate.
  consolidation('consolidation'),

  /// One adjacent execution step on material the learner already owns.
  executionProgression('execution_progression'),

  /// Never-practiced material, admitted through the introduction envelope.
  newMaterial('new_material'),

  /// The exact one-step-more-guidance sibling of what just failed.
  recovery('recovery'),

  /// A step back toward independence for anchored material.
  guidanceProbe('guidance_probe'),

  /// A retrieval test for material that has never succeeded.
  bootstrapProbe('bootstrap_probe'),

  /// The same task at a tempo the learner just played it at unasked.
  tempoProbe('tempo_probe'),

  /// A retrieval test for material that support has made invisible.
  observationProbe('observation_probe'),

  /// An explicit caller instruction, for diagnostics or a learner request.
  override('override');

  const ChallengeBypass(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// The admission exceptions, in the order they are consulted.
///
/// Declaration order is precedence order, the way it is for [EligibilityTier].
/// Which exception gets to answer first is a policy decision, and it was
/// previously expressed as the order of `if` statements, where an exception
/// that refused a candidate looked exactly like one that had nothing to say.
/// Adding a mechanism at the bottom of that chain made it unreachable for
/// every candidate an earlier one had quietly refused.
enum AdmissionException {
  /// An explicit caller instruction, which beats every inference.
  override,

  /// Something just went wrong, which matters more than anything going well.
  recovery,

  /// Something went too easily, and the harder question is worth the slot.
  tempoProbe,

  /// Nothing has observed retrieval for a while, whatever the odds say.
  observationProbe,

  /// Material already met that has not yet been produced from memory.
  consolidation,

  /// Material with no history, admitted over a lower floor.
  newMaterial,

  /// One rung less support than the one that is working.
  guidanceProbe,

  /// A retrieval test where no rung is established at all.
  bootstrapProbe,

  /// One adjacent execution step on material already owned.
  ///
  /// Last, so a probe keeps its own reason. A probe is answering a specific
  /// question and this is ordinary work, so where a candidate happens to be
  /// both, the question wins.
  executionProgression,
}

/// The `REQUIRES` gate's verdict for one candidate.
@immutable
class EligibilityDecision {
  /// Which tier the candidate landed in.
  final EligibilityTier tier;

  /// Why, in human-readable form, for diagnostics.
  final String reason;

  /// Which rule decided it.
  final EligibilityReason code;

  const EligibilityDecision(
    this.tier,
    this.reason, {
    this.code = EligibilityReason.noPrerequisite,
  });

  @override
  bool operator ==(Object other) =>
      other is EligibilityDecision &&
      other.tier == tier &&
      other.code == code &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(tier, code, reason);

  @override
  String toString() => 'EligibilityDecision(${tier.id}, ${code.id}: $reason)';
}

/// The safety gate's verdict for this decision opportunity.
@immutable
class SafetyDecision {
  /// Whether presenting anything at all is allowed right now.
  final bool isAllowed;

  /// Why, in human-readable form, for diagnostics.
  final String reason;

  const SafetyDecision(this.isAllowed, this.reason);

  @override
  bool operator ==(Object other) =>
      other is SafetyDecision &&
      other.isAllowed == isAllowed &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(isAllowed, reason);

  @override
  String toString() =>
      'SafetyDecision(${isAllowed ? 'allowed' : 'suppressed'}: $reason)';
}

/// Where a realization sits against what the learner has already demonstrated
/// on that material and hand.
///
/// Ordered by how much a slot spent on it is worth, best first when compared
/// as a rank: a step forward, then holding where they are, then work they have
/// already surpassed.
///
/// The material-level terms cannot tell realizations apart: retention and
/// diversity are facts about a material and information reads competencies, so
/// every tempo, span and hand configuration of one scale can carry identical
/// keys. An axis nothing ranks is not neutral; it is decided by the order of a
/// constant.
enum RealizationRank {
  /// Slower, narrower, or fewer hands than this learner has already managed
  /// here. Reachable, and last: they have been past this.
  surpassed('SURPASSED'),

  /// No frontier to sit against, which is every first encounter. Between the
  /// other two deliberately: meeting material is ordinary work, and neither a
  /// step on from something nor a step back to it.
  unmeasured('UNMEASURED'),

  /// Where this learner is: the tempo and span they have demonstrated.
  /// Practising what you have just reached is real work.
  holding('HOLDING'),

  /// One adjacent step past the frontier, which is the thing this whole
  /// progression exists to offer.
  advancing('ADVANCING');

  const RealizationRank(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// The lexicographic priority key: eligibility tier, then retention,
/// information, diversity, goals, and finally the realization.
///
/// Compared like alphabetizing a dictionary. The tier always decides first, so
/// no amount of retention, information, or diversity advantage lets a
/// provisional candidate outrank a fully eligible one. There is no hidden
/// weighted sum.
///
/// The terms before [realization] choose between candidate evidence
/// opportunities. Some are material-level; coordination transition and
/// information may differ between realizations of the same material.
@immutable
class RankKey implements Comparable<RankKey> {
  /// Primary key: the eligibility tier.
  final EligibilityTier tier;

  /// Whether this candidate is the learner's first chance to play its material
  /// with both hands, having just earned it.
  ///
  /// **Must precede retention and information, or it is inert.** Those are the
  /// terms that separate a waiting hands-together candidate from the winner, so
  /// below either of them this term never decides anything.
  ///
  /// It therefore overrides genuine retention urgency, which it is allowed to
  /// do because it cannot persist: the first hands-together attempt on the
  /// material ends it, so the cost is one slot per scale, once.
  ///
  /// **Must follow the tier**, so it cannot pull a provisionally eligible
  /// candidate past a fully eligible one.
  final bool coordinationTransition;

  /// Whether this candidate spends the coordination transition on contrary
  /// motion.
  ///
  /// Common piano pedagogy introduces hands-together work through contrary
  /// motion: the hands mirror, the same fingers align, and the thumb crossings
  /// happen together, where parallel motion pairs non-homologous fingers. See
  /// `docs/design/coordination-transition-policy.md`.
  ///
  /// **A claim about which introduction is better, not about which exercise is
  /// easier.** Prediction scores the two identically, because nothing measured
  /// supports a quantitative difference; this says only that where the two are
  /// otherwise tied, coordination is introduced through the mirrored one.
  ///
  /// **Must follow [coordinationTransition] and precede retention**, and is
  /// false whenever the transition is: outside it the two motions are ordinary
  /// realizations of the same material and this must not order them.
  ///
  /// Without it the choice is still made, by the order `HandMotion.values`
  /// happens to list. Measured across every archetype, contrary motion won
  /// none of 710 transition slots for exactly that reason.
  final bool contraryCoordination;

  /// `R(e)`: how urgent it is to test this material, weighted by whether this
  /// candidate can actually produce retrieval evidence.
  final double retention;

  /// `I(e)`: the uncertainty this candidate's evidence opportunities expose.
  final double information;

  /// `V(e)`: negative count of this material in the recent window.
  final double diversity;

  /// `G(e)`: learner-goal relevance, explicitly zero until a goal data model
  /// exists.
  final double goals;

  /// Where this realization sits against the learner's frontier for its
  /// material and hand.
  final RealizationRank realization;

  /// How near an unmeasured realization is to the one this learner should be
  /// entering at, as a negative rung distance. Zero for everything else.
  ///
  /// The last term, and the smallest. [RealizationRank.unmeasured] is true of
  /// every tempo at an unreached span at once, so without this the tempi there
  /// tie and generation order decides between them.
  ///
  /// A distance rather than more ordinal categories, because what is being
  /// compared is a distance: splitting `unmeasured` into near and far would
  /// need a boundary nobody can defend.
  final double realizationFit;

  const RankKey({
    required this.tier,
    required this.retention,
    this.coordinationTransition = false,
    this.contraryCoordination = false,
    required this.information,
    required this.diversity,
    required this.goals,
    this.realization = RealizationRank.unmeasured,
    this.realizationFit = 0,
  });

  @override
  int compareTo(RankKey other) {
    final byTier = tier.index.compareTo(other.tier.index);
    if (byTier != 0) return byTier;
    final byTransition = _order(
      coordinationTransition,
    ).compareTo(_order(other.coordinationTransition));
    if (byTransition != 0) return byTransition;
    final byContrary = _order(
      contraryCoordination,
    ).compareTo(_order(other.contraryCoordination));
    if (byContrary != 0) return byContrary;
    final byRetention = retention.compareTo(other.retention);
    if (byRetention != 0) return byRetention;
    final byInformation = information.compareTo(other.information);
    if (byInformation != 0) return byInformation;
    final byDiversity = diversity.compareTo(other.diversity);
    if (byDiversity != 0) return byDiversity;
    final byGoals = goals.compareTo(other.goals);
    if (byGoals != 0) return byGoals;
    final byRealization = realization.index.compareTo(other.realization.index);
    if (byRealization != 0) return byRealization;
    return realizationFit.compareTo(other.realizationFit);
  }

  @override
  bool operator ==(Object other) =>
      other is RankKey &&
      other.tier == tier &&
      other.coordinationTransition == coordinationTransition &&
      other.contraryCoordination == contraryCoordination &&
      other.retention == retention &&
      other.information == information &&
      other.diversity == diversity &&
      other.goals == goals &&
      other.realization == realization &&
      other.realizationFit == realizationFit;

  @override
  int get hashCode => Object.hash(
    tier,
    coordinationTransition,
    contraryCoordination,
    retention,
    information,
    diversity,
    goals,
    realization,
    realizationFit,
  );

  @override
  String toString() =>
      'RankKey(${tier.id}, '
      '${coordinationTransition ? 'TRANSITION, ' : ''}'
      '${contraryCoordination ? 'CONTRARY, ' : ''}'
      'R: ${retention.toStringAsFixed(3)}, '
      'I: ${information.toStringAsFixed(3)}, '
      'V: ${diversity.toStringAsFixed(1)}, '
      'G: ${goals.toStringAsFixed(1)}, '
      '${realization.id}'
      '${realizationFit == 0 ? '' : ' ${realizationFit.toStringAsFixed(0)}'})';
}

/// Everything the pipeline computed about one candidate.
///
/// Qualification values are always populated, including for candidates an
/// earlier stage already excluded, because a "why not that one?" question
/// should be answerable from the trace alone. [challengeStatus] says which of
/// those reflect a real decision.
///
/// **Ranking is different: its values are absent rather than computed.** A
/// candidate that never reached ranking has no [rankKey], because it never
/// competed on one and a key it could not use is a number presented as though
/// it meant something. Most candidates are in that position, so this is also
/// what keeps a slot from computing ranking terms for the ninety-five per cent
/// of candidates that cannot consume them.
@immutable
class CandidateTrace {
  /// The candidate this trace describes.
  final Exercise exercise;

  /// Whether the hands-together prerequisite passed for this candidate.
  final bool? handsTogetherPrerequisiteSatisfied;

  /// Whether this is the learner's first chance to play this material with
  /// both hands, having just earned it.
  ///
  /// A fact about the candidate rather than a ranking term, so it is recorded
  /// for every candidate and not only for the ones that reached ranking. The
  /// question a diagnostic asks is which candidates were transitions and what
  /// became of them, which is unanswerable if refusing one erases the fact.
  final bool coordinationTransition;

  /// Stage 2a: the prerequisite verdict.
  final EligibilityDecision eligibility;

  /// Stage 2b: the workload verdict for this decision opportunity.
  final SafetyDecision safety;

  /// Whether the pipeline really reached challenge admission for this
  /// candidate.
  final StageStatus challengeStatus;

  /// Stage 3 input: all four predicted channels.
  final Prediction prediction;

  /// Whether predicted success landed inside the ordinary band.
  final bool isWithinChallengeBand;

  /// Which named exception admitted this candidate, if any.
  final ChallengeBypass? challengeBypass;

  /// Whether the candidate survived challenge admission at all.
  final bool challengeSurvived;

  /// Whether the pipeline really reached priority ranking for this candidate.
  final StageStatus priorityStatus;

  /// Stage 4: the key this candidate competed on, or null when priority
  /// ranking was never reached and no ranking term was computed.
  final RankKey? rankKey;

  const CandidateTrace({
    required this.exercise,
    this.handsTogetherPrerequisiteSatisfied,
    this.coordinationTransition = false,
    required this.eligibility,
    required this.safety,
    required this.challengeStatus,
    required this.prediction,
    required this.isWithinChallengeBand,
    required this.challengeBypass,
    required this.challengeSurvived,
    required this.priorityStatus,
    required this.rankKey,
  });

  /// Whether this candidate is a real contender for selection.
  bool get isRanked => priorityStatus.isReached && rankKey != null;

  @override
  String toString() =>
      'CandidateTrace($exercise, ${eligibility.tier.id}, '
      'p: ${prediction.overallP.toStringAsFixed(3)}, '
      'bypass: ${challengeBypass?.id ?? 'none'}, '
      'ranked: $isRanked)';
}

int _order(bool flag) => flag ? 1 : 0;
