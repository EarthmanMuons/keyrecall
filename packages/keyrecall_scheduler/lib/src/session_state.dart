import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'config/scheduler_config.dart';
import 'realization_family_pacing.dart';

/// Short-lived scheduling context for one practice sitting.
///
/// Deliberately separate from persistent learner state, so a temporary
/// session condition is never stored as ability. It drives the attempt cap,
/// the diversity window, the repetition guard, and recovery.
class SessionState {
  /// Attempt slots consumed so far in this session.
  ///
  /// A slot is a decision opportunity; it is counted even when the decision
  /// admits nothing, so a session that keeps finding nothing to present still
  /// ends.
  int attemptsThisSession;

  /// Material ids of recent selections, oldest first.
  final List<String> recentMaterialIds;

  /// The exercise whose factual retrieval just failed, or null.
  ///
  /// The exercise itself rather than a bare flag, so recovery can target its
  /// exact one-step-more-guidance sibling rather than any easier candidate.
  Exercise? lastFailedExercise;

  /// The harder exercise to ask for after one that was clearly too easy, or
  /// null.
  ///
  /// The target itself for the same reason recovery holds one: the point is a
  /// specific harder question, not a general licence to pick something harder.
  Exercise? tempoProbe;

  /// Attempts in a row under support, without retrieval being observed at all.
  ///
  /// Continuous cueing never observes retrieval, so practice under it produces
  /// no evidence about whether the support is still needed.
  ///
  /// Counted across the sitting rather than per material, because what starves
  /// is the scheduler's knowledge of whether support is still needed, and that
  /// starves whether or not the same scale keeps coming back. Cueing spreads
  /// itself across materials, so a per-material count would rarely reach two.
  int supportedAttemptsSinceObservation;

  /// Selection opportunities that passed with an independence probe available
  /// and something else chosen.
  ///
  /// Opportunities rather than offers. What matters is how many times the
  /// question could have been asked and was not, so a slot narrowed to one
  /// candidate by recovery or a tempo probe does not count: the question was
  /// not in the contest to lose it.
  int unservedGuidanceProbeSelections;

  /// What the realization families of recent selections yielded, oldest first.
  ///
  /// Held beside [recentMaterialIds] rather than derived from it: pacing reads
  /// how productive the work was, which a material id does not carry.
  final List<FamilyObservation> recentFamilies;

  SessionState({
    this.attemptsThisSession = 0,
    List<String>? recentMaterialIds,
    this.lastFailedExercise,
    this.tempoProbe,
    this.supportedAttemptsSinceObservation = 0,
    this.unservedGuidanceProbeSelections = 0,
    List<FamilyObservation>? recentFamilies,
  }) : recentMaterialIds = recentMaterialIds ?? [],
       recentFamilies = recentFamilies ?? [];

  /// Whether a recovery context is currently active.
  bool get isRecovering => lastFailedExercise != null;

  /// Records that [exercise] was presented and how its retrieval went.
  ///
  /// A recovery context opens only on a genuine tested failure. An attempt
  /// that never tested retrieval is not a failure to recover from, so it
  /// clears the context like a success does.
  ///
  /// [tempoProbe] is the harder exercise to ask for next when this one was
  /// clearly too easy, and null otherwise. Like the recovery context it lasts
  /// exactly one decision.
  ///
  /// [retrievalObserved] says whether the attempt was at a rung that could have
  /// shown retrieval succeeding or failing, whichever it did.
  void recordSelection(
    Exercise exercise, {
    required bool retrievalFailed,
    required bool retrievalObserved,
    Exercise? tempoProbe,
    required DiversityConfig config,
  }) {
    supportedAttemptsSinceObservation = retrievalObserved
        ? 0
        : supportedAttemptsSinceObservation + 1;
    lastFailedExercise = retrievalFailed ? exercise : null;
    this.tempoProbe = tempoProbe;
    recentMaterialIds.add(exercise.material.materialId);
    while (recentMaterialIds.length > config.recentWindow) {
      recentMaterialIds.removeAt(0);
    }
  }

  /// Records what the families [exercise] consumed yielded.
  ///
  /// [productive] is the yield signal pressure reads: managed execution, which
  /// is deliberately demanding, so a family only stops accumulating pressure
  /// once it produces work the learner can actually execute.
  void recordFamilySelection(
    Exercise exercise, {
    required bool productive,
    required PacingConfig config,
    RealizationFamilyResolver families = handMotionFamilies,
  }) {
    recentFamilies.add(
      FamilyObservation(families: families(exercise), productive: productive),
    );
    while (recentFamilies.length > config.window) {
      recentFamilies.removeAt(0);
    }
  }

  /// Records what one selection did with a waiting independence question.
  ///
  /// Called at selection rather than at commit, because the question is about
  /// what was on the table and only the selection knows that.
  void recordSelectionOpportunity({
    required bool guidanceProbeAvailable,
    required bool guidanceProbeSelected,
  }) {
    if (guidanceProbeSelected) {
      unservedGuidanceProbeSelections = 0;
      return;
    }
    // A slot the recovery or tempo context narrowed to one candidate was never
    // a contest, so nothing lost it.
    if (isRecovering || tempoProbe != null) return;
    if (!guidanceProbeAvailable) return;
    unservedGuidanceProbeSelections++;
  }

  /// How many times [materialId] was selected in an unbroken run ending now.
  int consecutiveAttemptsOf(String materialId) {
    var count = 0;
    for (final id in recentMaterialIds.reversed) {
      if (id != materialId) break;
      count++;
    }
    return count;
  }

  /// How many of the recent selections used [materialId].
  int recentAttemptsOf(String materialId) =>
      recentMaterialIds.where((id) => id == materialId).length;

  @override
  String toString() =>
      'SessionState(attempts: $attemptsThisSession, '
      'recent: ${recentMaterialIds.length}, recovering: $isRecovering)';
}
