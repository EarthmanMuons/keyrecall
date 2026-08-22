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

  SessionState({
    this.attemptsThisSession = 0,
    List<String>? recentMaterialIds,
    this.lastFailedExercise,
  }) : recentMaterialIds = recentMaterialIds ?? [];

  /// Whether a recovery context is currently active.
  bool get isRecovering => lastFailedExercise != null;

  /// Records that [exercise] was presented and how its retrieval went.
  ///
  /// A recovery context opens only on a genuine tested failure. An attempt
  /// that never tested retrieval is not a failure to recover from, so it
  /// clears the context like a success does.
  void recordSelection(
    Exercise exercise, {
    required bool retrievalFailed,
    required DiversityConfig config,
  }) {
    lastFailedExercise = retrievalFailed ? exercise : null;
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
