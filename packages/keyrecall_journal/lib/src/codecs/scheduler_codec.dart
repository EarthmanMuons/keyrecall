import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import '../canonical_json.dart';
import '../schema.dart';

/// Why the scheduler chose what it chose.
///
/// The selected candidate's trace, kept because a later catalog or generator
/// must not be able to reinterpret a historical decision. The full candidate
/// set is deliberately not stored: it is regenerable from the recorded state,
/// session context, and configuration, and a developer-diagnostics mode can
/// retain the near misses separately when it needs them.
@immutable
class SchedulerDecision {
  /// The four predicted channels for the selected exercise.
  final Prediction prediction;

  /// Which prerequisite tier it competed in.
  final EligibilityTier eligibilityTier;

  /// Which prerequisite rule decided that tier, when one did.
  ///
  /// The tier says a candidate was outranked; this says what outranked it.
  /// They are different questions, and only the second one groups stalls,
  /// which is the whole reason the reasons are coded rather than described.
  final EligibilityReason? eligibilityReason;

  /// Why the safety gate allowed this decision opportunity.
  final String safetyReason;

  /// Whether predicted success fell inside the ordinary band.
  final bool withinChallengeBand;

  /// The band in force at the time, so a later configuration change cannot
  /// make a past admission look wrong.
  final double challengeBandMin;

  /// The upper edge of that band.
  final double challengeBandMax;

  /// Which named exception admitted it, if any.
  final ChallengeBypass? challengeBypass;

  /// The lexicographic key it won on.
  final RankKey rankKey;

  const SchedulerDecision({
    required this.prediction,
    required this.eligibilityTier,
    required this.eligibilityReason,
    required this.safetyReason,
    required this.withinChallengeBand,
    required this.challengeBandMin,
    required this.challengeBandMax,
    required this.challengeBypass,
    required this.rankKey,
  });

  /// The decision behind a selected [trace], under [config].
  factory SchedulerDecision.fromTrace(
    CandidateTrace trace,
    SchedulerConfig config,
  ) {
    final rankKey = trace.rankKey;
    if (rankKey == null) {
      throw ArgumentError.value(
        trace,
        'trace',
        'only a candidate that reached priority ranking can be journaled as a '
            'decision',
      );
    }
    return SchedulerDecision(
      prediction: trace.prediction,
      eligibilityTier: trace.eligibility.tier,
      eligibilityReason: trace.eligibility.code,
      safetyReason: trace.safety.reason,
      withinChallengeBand: trace.isWithinChallengeBand,
      challengeBandMin: config.challenge.pMin,
      challengeBandMax: config.challenge.pMax,
      challengeBypass: trace.challengeBypass,
      rankKey: rankKey,
    );
  }

  @override
  String toString() =>
      'SchedulerDecision(${eligibilityTier.id}, '
      'p: ${prediction.overallP.toStringAsFixed(3)}, '
      'bypass: ${challengeBypass?.id ?? 'none'})';
}

/// Writes a scheduler decision.
Map<String, Object?> encodeDecision(
  SchedulerDecision decision,
  Map<String, Object?> Function(Prediction) encodePrediction,
) => {
  'prediction': encodePrediction(decision.prediction),
  'eligibility_tier': decision.eligibilityTier.id,
  'eligibility_reason': decision.eligibilityReason?.id,
  'safety_reason': decision.safetyReason,
  'within_challenge_band': decision.withinChallengeBand,
  'challenge_band_min': decision.challengeBandMin,
  'challenge_band_max': decision.challengeBandMax,
  'challenge_bypass': decision.challengeBypass?.id,
  'rank_key': {
    'tier': decision.rankKey.tier.id,
    'coordination_transition': decision.rankKey.coordinationTransition,
    'retention': decision.rankKey.retention,
    'information': decision.rankKey.information,
    'diversity': decision.rankKey.diversity,
    'goals': decision.rankKey.goals,
    'realization': decision.rankKey.realization.id,
    'realization_fit': decision.rankKey.realizationFit,
  },
};

/// Reads a scheduler decision back.
SchedulerDecision decodeDecision(
  Map<String, Object?> json,
  Prediction Function(Map<String, Object?>) decodePrediction, {
  String? location,
}) {
  final rankKeyJson = requireMap(json, 'rank_key', location: location);
  final tier = _tierFromId(
    requireString(json, 'eligibility_tier', location: location),
    location: location,
  );
  final bypassId = json['challenge_bypass'];

  return SchedulerDecision(
    prediction: decodePrediction(
      requireMap(json, 'prediction', location: location),
    ),
    eligibilityTier: tier,
    eligibilityReason: switch (json['eligibility_reason']) {
      final String id => _reasonFromId(id, location: location),
      _ => null,
    },
    safetyReason: requireString(json, 'safety_reason', location: location),
    withinChallengeBand: requireBool(
      json,
      'within_challenge_band',
      location: location,
    ),
    challengeBandMin: requireDouble(
      json,
      'challenge_band_min',
      location: location,
    ),
    challengeBandMax: requireDouble(
      json,
      'challenge_band_max',
      location: location,
    ),
    challengeBypass: bypassId == null
        ? null
        : _bypassFromId(
            asString(bypassId, 'challenge_bypass', location: location),
            location: location,
          ),
    rankKey: RankKey(
      tier: _tierFromId(
        requireString(rankKeyJson, 'tier', location: location),
        location: location,
      ),
      coordinationTransition: requireBool(
        rankKeyJson,
        'coordination_transition',
        location: location,
      ),
      retention: requireDouble(rankKeyJson, 'retention', location: location),
      information: requireDouble(
        rankKeyJson,
        'information',
        location: location,
      ),
      diversity: requireDouble(rankKeyJson, 'diversity', location: location),
      goals: requireDouble(rankKeyJson, 'goals', location: location),
      realization: _realizationFromId(
        requireString(rankKeyJson, 'realization', location: location),
        location: location,
      ),
      realizationFit: requireDouble(
        rankKeyJson,
        'realization_fit',
        location: location,
      ),
    ),
  );
}

RealizationRank _realizationFromId(String id, {String? location}) =>
    RealizationRank.values.firstWhere(
      (rank) => rank.id == id,
      orElse: () => throw JournalFormatException(
        'unknown realization rank: $id',
        location: location,
      ),
    );

EligibilityTier _tierFromId(String id, {String? location}) =>
    EligibilityTier.values.firstWhere(
      (tier) => tier.id == id,
      orElse: () => throw JournalFormatException(
        'unknown eligibility tier "$id"',
        location: location,
      ),
    );

EligibilityReason _reasonFromId(String id, {String? location}) =>
    EligibilityReason.values.firstWhere(
      (reason) => reason.id == id,
      orElse: () => throw JournalFormatException(
        'unknown eligibility reason "$id"',
        location: location,
      ),
    );

ChallengeBypass _bypassFromId(String id, {String? location}) =>
    ChallengeBypass.values.firstWhere(
      (bypass) => bypass.id == id,
      orElse: () => throw JournalFormatException(
        'unknown challenge bypass "$id"',
        location: location,
      ),
    );
