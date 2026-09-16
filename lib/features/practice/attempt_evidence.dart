import 'package:flutter/foundation.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

/// Whether one timing channel of an attempt can support a claim about it.
///
/// A null score is two different facts. Coordination in one hand is not a
/// question the exercise asks, while coordination nobody measured in two is a
/// question nobody answered, and only the first may be passed over.
enum ChannelEvidence {
  /// Measured, so its score says how the playing went.
  observed,

  /// Asked for, and nothing measured it.
  unobserved,

  /// Not a question this exercise asks.
  inapplicable,
}

/// What an attempt's timing channels can support.
///
/// A positive claim about steadiness, unbroken flow, or the hands being
/// together needs its channel [ChannelEvidence.observed]. Unobserved is never
/// a poor score either: it supports no claim in either direction.
@immutable
class AttemptEvidence {
  final ChannelEvidence continuity;
  final ChannelEvidence steadiness;
  final ChannelEvidence coordination;

  const AttemptEvidence({
    required this.continuity,
    required this.steadiness,
    required this.coordination,
  });

  factory AttemptEvidence.of(Exercise exercise, Outcome outcome) =>
      AttemptEvidence(
        continuity: _evidenceOf(outcome.continuity),
        steadiness: _evidenceOf(outcome.temporalStability),
        coordination: exercise.conditions.hands == HandConfiguration.together
            ? _evidenceOf(outcome.coordination)
            : ChannelEvidence.inapplicable,
      );

  static ChannelEvidence _evidenceOf(double? score) =>
      score == null ? ChannelEvidence.unobserved : ChannelEvidence.observed;
}
