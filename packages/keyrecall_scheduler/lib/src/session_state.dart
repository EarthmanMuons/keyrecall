import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'config/scheduler_config.dart';

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

  SessionState({
    this.attemptsThisSession = 0,
    List<String>? recentMaterialIds,
    this.lastFailedExercise,
    this.tempoProbe,
  }) : recentMaterialIds = recentMaterialIds ?? [];

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
  /// exactly one decision: a probe that outlived its answer would keep asking
  /// a question that has been answered.
  void recordSelection(
    Exercise exercise, {
    required bool retrievalFailed,
    Exercise? tempoProbe,
    required DiversityConfig config,
  }) {
    lastFailedExercise = retrievalFailed ? exercise : null;
    this.tempoProbe = tempoProbe;
    recentMaterialIds.add(exercise.material.materialId);
    while (recentMaterialIds.length > config.recentWindow) {
      recentMaterialIds.removeAt(0);
    }
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
