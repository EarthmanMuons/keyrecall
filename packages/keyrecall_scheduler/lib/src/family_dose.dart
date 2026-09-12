import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';
import 'realization_family_pacing.dart';

/// What other work counts as evidence that a family is becoming reachable.
///
/// Declared rather than inferred. Separate-hand work is evidence for playing
/// hands together because the coordination prerequisite is stated in those
/// terms; nothing establishes parallel motion as evidence for contrary, so
/// contrary is deliberately absent rather than guessed at.
const Map<String, Set<String>> familyPrerequisites = {
  'hands:together': {'hands:right', 'hands:left'},
};

/// How much a family's dose should contract, in `[0, 1]`.
///
/// **Yield, not share.** Pacing asks whether a family is crowding a sitting and
/// cannot see one that holds a third of it while yielding nothing. This asks
/// only what the last several attempts produced.
///
/// Evidence is required before contracting: a family with fewer than
/// [DoseConfig.minAttempts] in the window is left alone, so one or two failed
/// introductions cannot throttle it.
///
/// Productive prerequisite work relaxes the contraction rather than clearing
/// it, by [DoseConfig.prerequisiteReliefFactor], which is a multiplier and so
/// relieves more the lower it is. Somebody whose hands are improving separately
/// is worth asking for coordination sooner.
///
/// Time relaxes it too, through [at]. **What ages is the confidence that the
/// family is still over its cadence, not the record of what it produced.** The
/// attempts stay unproductive however long ago they were.
double familyDose(
  String family, {
  required List<FamilyObservation> window,
  required DoseConfig config,
  required DateTime at,
}) {
  final held = window.where(
    (observation) => observation.families.contains(family),
  );
  if (held.length < config.minAttempts) return 0;
  final produced = held.where((observation) => observation.productive).length;
  final yielded = produced / held.length;
  if (yielded >= config.yieldFloor) return 0;

  final contraction = (config.yieldFloor - yielded) / config.yieldFloor;
  final prerequisites = familyPrerequisites[family] ?? const <String>{};
  final supported = window.any(
    (observation) =>
        observation.productive &&
        observation.families.any(prerequisites.contains),
  );
  final relieved = supported
      ? contraction * config.prerequisiteReliefFactor
      : contraction;
  return relieved * _confidence(held.last.at, at, config);
}

/// How much a contraction from evidence last seen at [seen] still counts at
/// [at].
///
/// A half-life rather than an expiry, so evidence weakens instead of being
/// discarded on a boundary, and never reaches zero. What takes a family out of
/// contention is [doseGap] rounding a weak contraction back to no gap at all.
///
/// Time before the evidence is not relief: a window rebuilt at a sitting that
/// starts before its own history is a corrupt clock.
double _confidence(DateTime seen, DateTime at, DoseConfig config) {
  final elapsed = at.difference(seen);
  if (elapsed <= Duration.zero) return 1;
  final days = elapsed.inMinutes / Duration.minutesPerDay;
  return math.pow(0.5, days / config.evidenceHalfLifeDays).toDouble();
}

/// The slots a family must leave between attempts at this contraction.
///
/// One is no contraction at all. The scale is coarse because the evidence
/// supports only that a failing family should be asked for less often, not that
/// any particular cadence is correct.
int doseGap(double contraction, DoseConfig config) =>
    1 + ((config.maximumGap - 1) * contraction).round();

/// Selections since [family] was last chosen, or null when it is not in
/// [window] at all.
int? attemptsSince(String family, List<FamilyObservation> window) {
  for (var since = 0; since < window.length; since++) {
    final observation = window[window.length - 1 - since];
    if (observation.families.contains(family)) return since;
  }
  return null;
}

/// How dose control read the slot.
enum DoseDisposition {
  /// No family had both the evidence and the yield to be contracted.
  inactive('inactive'),

  /// A contracted family was held back and other work remained.
  contracted('contracted'),

  /// Every candidate belonged to a contracted family, so none was held back.
  ///
  /// Contraction lowers how often a family is asked for; it never empties a
  /// slot. A learner with nothing else useful to do keeps being offered the
  /// hard thing.
  unrelieved('unrelieved');

  const DoseDisposition(this.id);

  final String id;
}

/// What dose control did to the available set.
class DoseDecision {
  final List<CandidateTrace> selectable;
  final DoseDisposition disposition;

  /// The contraction of each family that was over its cadence, for reports.
  final Map<String, double> contracted;

  const DoseDecision.inactive(this.selectable)
    : disposition = DoseDisposition.inactive,
      contracted = const {};

  const DoseDecision.unrelieved(this.selectable, this.contracted)
    : disposition = DoseDisposition.unrelieved;

  const DoseDecision.contracted(this.selectable, this.contracted)
    : disposition = DoseDisposition.contracted;
}

/// The families whose cadence [window] says they are over, with how far.
///
/// A family is over its cadence when it has been chosen more recently than its
/// contraction allows. Everything else about it is unchanged: it stays
/// eligible, ranked and selectable.
Map<String, double> familiesOverDose({
  required List<FamilyObservation> window,
  required DoseConfig config,
  required DateTime at,
}) {
  final families = {for (final observation in window) ...observation.families};
  final over = <String, double>{};
  for (final family in families) {
    final contraction = familyDose(
      family,
      window: window,
      config: config,
      at: at,
    );
    if (contraction <= 0) continue;
    final since = attemptsSince(family, window);
    if (since == null || since >= doseGap(contraction, config) - 1) continue;
    over[family] = contraction;
  }
  return over;
}

/// Whether [exercise] belongs to any family in [contracted].
bool isOverDosed(
  Exercise exercise,
  Map<String, double> contracted, {
  RealizationFamilyResolver families = handMotionFamilies,
}) => families(exercise).any(contracted.containsKey);
