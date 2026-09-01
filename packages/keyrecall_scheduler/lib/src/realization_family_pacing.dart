import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';

/// The pacing families whose allocation [exercise] consumes.
///
/// Families are declared keys rather than an enum so a realization the
/// scheduler does not know about can join the same allocation accounting by
/// naming the strands it belongs to.
typedef RealizationFamilyResolver = Set<String> Function(Exercise exercise);

/// Hand configuration, plus motion as its own strand for hands together.
///
/// Two keys rather than one for hands together, so rotating between parallel
/// and contrary still accumulates pressure on the shared strand while each
/// motion is paced separately.
Set<String> handMotionFamilies(Exercise exercise) =>
    switch (exercise.conditions.hands) {
      HandConfiguration.right => {'hands:right'},
      HandConfiguration.left => {'hands:left'},
      HandConfiguration.together => {
        'hands:together',
        'motion:${exercise.conditions.handMotion.name}',
      },
    };

/// The families one recent selection consumed, and what it yielded.
@immutable
class FamilyObservation {
  final Set<String> families;
  final bool productive;

  const FamilyObservation({required this.families, required this.productive});
}

/// `share above the floor x unproductive fraction`, in `[0, 1]`.
///
/// Pressure rises when a family holds much of [window] and little of that work
/// was productive; it falls as the family produces managed execution and as
/// the window fills with other families.
double familyPressure(
  String family, {
  required List<FamilyObservation> window,
  required PacingConfig config,
}) {
  if (window.length < config.window) return 0;
  final held = window.where((o) => o.families.contains(family));
  if (held.length < config.minFamilyAttempts) return 0;
  final excess = held.length / window.length - config.shareFloor;
  if (excess <= 0) return 0;
  final yield = held.where((o) => o.productive).length / held.length;
  return excess * (1 - yield);
}

/// Every family in [window] at or over [PacingConfig.setAsideAt].
Set<String> pressuredFamilies({
  required List<FamilyObservation> window,
  required PacingConfig config,
}) {
  final families = {for (final observation in window) ...observation.families};
  return families
      .where(
        (family) =>
            familyPressure(family, window: window, config: config) >=
            config.setAsideAt,
      )
      .toSet();
}

/// Whether [exercise] consumes any family in [pressured].
bool isPressured(
  Exercise exercise,
  Set<String> pressured, {
  RealizationFamilyResolver families = handMotionFamilies,
}) => families(exercise).any(pressured.contains);

/// One slot where pressure removed candidates and others survived.
///
/// Both sides of the substitution: the best candidate removed and the best
/// candidate that replaced it, so a diagnostic can ask how much better
/// prepared the relieving family actually was.
@immutable
class FamilySetAside {
  final int slot;
  final Set<String> pressuredFamilies;
  final CandidateTrace pressured;
  final CandidateTrace relieving;

  const FamilySetAside({
    required this.slot,
    required this.pressuredFamilies,
    required this.pressured,
    required this.relieving,
  });

  /// Whether the relieving family is a credible substitute.
  ///
  /// Predicted success alone, which is the scheduler's existing generic
  /// readiness measure. It is a coarse safeguard against reallocating practice
  /// toward a generally less prepared strand, not a prediction that this
  /// particular replacement will succeed.
  bool get isRelievable =>
      relieving.prediction.overallP >= pressured.prediction.overallP;
}

/// What pacing did to one slot's available set.
enum PacingDisposition {
  /// No policy is configured, or no family reached the set-aside pressure.
  inactive,

  /// Pressure held because every admitted candidate was pressured.
  unrelieved,

  /// Pressure held because no alternative family was as ready.
  unready,

  /// Pressured candidates were set aside in favor of another family.
  relieved,
}

/// The available set after pacing, and what pacing did to reach it.
@immutable
class PacingDecision {
  final List<CandidateTrace> selectable;
  final PacingDisposition disposition;

  /// The substitution made, present only when pressure relieved the slot.
  final FamilySetAside? setAside;

  const PacingDecision.inactive(this.selectable)
    : disposition = PacingDisposition.inactive,
      setAside = null;

  const PacingDecision.unrelieved(this.selectable)
    : disposition = PacingDisposition.unrelieved,
      setAside = null;

  const PacingDecision.unready(this.selectable)
    : disposition = PacingDisposition.unready,
      setAside = null;

  const PacingDecision.relieved(this.selectable, FamilySetAside this.setAside)
    : disposition = PacingDisposition.relieved;
}
