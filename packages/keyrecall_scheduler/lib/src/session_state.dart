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
  /// specific harder question, not a general license to pick something harder.
  Exercise? tempoProbe;

  /// Whether [tempoProbe] was opened by the attempt just recorded.
  ///
  /// A fresh probe is the same exercise the learner has this second finished,
  /// one rung faster. Asking for it immediately is the echo a sitting notices:
  /// it reads as the app repeating itself rather than as verification. The
  /// slot after holds it back unconditionally, and the slot
  /// after that lets it compete like any other candidate.
  bool tempoProbeIsFresh;

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

  /// The acquisition parent the slot just before this one offered, or null.
  ///
  /// Supported work is an intervention inside ordinary practice rather than an
  /// alternative to it, so the thing a learner meets after one is ordinary
  /// work. Any other selection clears this, which makes it one opportunity
  /// rather than a wait.
  ///
  /// Skipping only the parent just offered was not enough. Six declared floors
  /// stuck at once rotated among themselves and filled most of a sitting while
  /// never repeating a parent twice running.
  Exercise? lastAcquisitionParent;

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
    this.tempoProbeIsFresh = false,
    this.supportedAttemptsSinceObservation = 0,
    this.unservedGuidanceProbeSelections = 0,
    List<FamilyObservation>? recentFamilies,
  }) : recentMaterialIds = recentMaterialIds ?? [],
       recentFamilies = recentFamilies ?? [];

  /// The state a sitting starts from when [history] came before it.
  ///
  /// The recency and pacing windows carry over from the tail of the history,
  /// and nothing else does. The attempt cap, the recovery context, the waiting
  /// tempo probe and the guidance counters are all conditions of the sitting
  /// they arose in: a new sitting is not owed a probe opened before a break,
  /// and a recovery context that outlived the failure it answered would answer
  /// a question nobody is still asking.
  ///
  /// Allocation is a question about the recent past rather than about the last
  /// attempt, so returning must not clear the pressure the work before it
  /// built up.
  factory SessionState.resuming(
    List<PriorSelection> history, {
    required SchedulerConfig config,
    RealizationFamilyResolver families = handMotionFamilies,
  }) {
    final window = config.diversity.recentWindow;
    final recent = [
      for (final prior in history) prior.exercise.material.materialId,
    ];
    final session = SessionState(
      recentMaterialIds: recent.length <= window
          ? recent
          : recent.sublist(recent.length - window),
    );
    final familyWindow = config.familyWindow;
    if (familyWindow > 0) {
      final paced = history.length <= familyWindow
          ? history
          : history.sublist(history.length - familyWindow);
      for (final prior in paced) {
        session.recordFamilySelection(
          prior.exercise,
          productive: prior.productive,
          window: familyWindow,
          at: prior.at,
          families: families,
        );
      }
    }
    return session;
  }

  /// Whether a recovery context is currently active.
  bool get isRecovering => lastFailedExercise != null;

  /// Records that [exercise] was presented and how its retrieval went.
  ///
  /// A recovery context opens only on a genuine tested failure. An attempt
  /// that never tested retrieval is not a failure to recover from, so it
  /// clears the context like a success does.
  ///
  /// [tempoProbe] is the harder exercise to ask for next when this one was
  /// clearly too easy, and null otherwise. It lasts one decision it could win:
  /// a probe held back from the slot right after the attempt that opened it
  /// survives into the next one, where nothing holds it back. One waiting to
  /// compete keeps its place against a newer one, so that a sitting in which
  /// every attempt is too easy still asks for a faster tempo every other slot.
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
    if (tempoProbeIsFresh && exercise != this.tempoProbe) {
      // Held back rather than taken, so it is no longer an echo of the attempt
      // that has just been played and competes from here. A probe opened by
      // that attempt is dropped rather than taking its place: a learner who is
      // underchallenged every time opens one every time, and letting each new
      // one displace the last would hold every probe forever and ask for none
      // of them. What a dropped probe costs is the explicit verification, not
      // the pace, which the outcome recorded either way.
      tempoProbeIsFresh = false;
    } else {
      this.tempoProbe = tempoProbe;
      tempoProbeIsFresh = tempoProbe != null;
    }
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
    required int window,
    required DateTime at,
    RealizationFamilyResolver families = handMotionFamilies,
  }) {
    recentFamilies.add(
      FamilyObservation(
        families: families(exercise),
        productive: productive,
        at: at,
      ),
    );
    while (recentFamilies.length > window) {
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
    if (isRecovering || (tempoProbe != null && !tempoProbeIsFresh)) return;
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

/// A selection a resumed sitting reads back out of its history.
///
/// [productive] is the yield signal pacing reads, which the exercise alone
/// does not carry.
class PriorSelection {
  final Exercise exercise;
  final bool productive;
  final DateTime at;

  const PriorSelection(
    this.exercise, {
    required this.productive,
    required this.at,
  });
}
