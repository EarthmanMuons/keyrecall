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

  /// The material's band asks for more single-hand execution than the learner
  /// has shown.
  bandExecutionFloor('BAND_EXECUTION_FLOOR'),

  /// A minor form asks for some familiarity with minor topology first.
  minorTopologyPrerequisite('MINOR_TOPOLOGY_PREREQUISITE'),

  /// Fixed-form melodic minor asks for another minor form first.
  melodicFormPrerequisite('MELODIC_FORM_PREREQUISITE'),

  /// Hands-together work asks for both hands first.
  handsTogetherPrerequisite('HANDS_TOGETHER_PREREQUISITE'),

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

  /// Material with no history, admitted over a lower floor.
  newMaterial,

  /// One rung less support than the one that is working.
  guidanceProbe,

  /// A retrieval test where no rung is established at all.
  bootstrapProbe,
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

/// The lexicographic priority key: eligibility tier, then retention,
/// information, diversity, and goals.
///
/// Compared like alphabetizing a dictionary. The tier always decides first, so
/// no amount of retention, information, or diversity advantage lets a
/// provisional candidate outrank a fully eligible one. There is no hidden
/// weighted sum.
@immutable
class RankKey implements Comparable<RankKey> {
  /// Primary key: the eligibility tier.
  final EligibilityTier tier;

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

  const RankKey({
    required this.tier,
    required this.retention,
    required this.information,
    required this.diversity,
    required this.goals,
  });

  @override
  int compareTo(RankKey other) {
    final byTier = tier.index.compareTo(other.tier.index);
    if (byTier != 0) return byTier;
    final byRetention = retention.compareTo(other.retention);
    if (byRetention != 0) return byRetention;
    final byInformation = information.compareTo(other.information);
    if (byInformation != 0) return byInformation;
    final byDiversity = diversity.compareTo(other.diversity);
    if (byDiversity != 0) return byDiversity;
    return goals.compareTo(other.goals);
  }

  @override
  bool operator ==(Object other) =>
      other is RankKey &&
      other.tier == tier &&
      other.retention == retention &&
      other.information == information &&
      other.diversity == diversity &&
      other.goals == goals;

  @override
  int get hashCode =>
      Object.hash(tier, retention, information, diversity, goals);

  @override
  String toString() =>
      'RankKey(${tier.id}, R: ${retention.toStringAsFixed(3)}, '
      'I: ${information.toStringAsFixed(3)}, '
      'V: ${diversity.toStringAsFixed(1)}, '
      'G: ${goals.toStringAsFixed(1)})';
}

/// Everything the pipeline computed about one candidate.
///
/// Stage values are always populated, including for candidates an earlier
/// stage already excluded, because a "why not that one?" question should be
/// answerable from the trace alone. [challengeStatus] and [priorityStatus] say
/// which of those values reflect a real decision, and [rankKey] is populated
/// only when priority ranking genuinely ran.
@immutable
class CandidateTrace {
  /// The candidate this trace describes.
  final Exercise exercise;

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

  /// Stage 4: the ranking terms, always computed for diagnostics.
  final RankKey terms;

  /// The key this candidate actually competed on, or null when priority
  /// ranking was never reached.
  final RankKey? rankKey;

  const CandidateTrace({
    required this.exercise,
    required this.eligibility,
    required this.safety,
    required this.challengeStatus,
    required this.prediction,
    required this.isWithinChallengeBand,
    required this.challengeBypass,
    required this.challengeSurvived,
    required this.priorityStatus,
    required this.terms,
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
