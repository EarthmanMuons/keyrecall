import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// What acquisition work on one parent exercise has produced so far.
///
/// Counts rather than a verdict. The policy that reads this is binary today, a
/// single criterion success being enough to earn a probe, and the counts are
/// kept so that a rule wanting two of them is a change of policy rather than a
/// change of what was recorded. Representing the evidence first is the same
/// discipline the entry trigger follows.
///
/// [completions] counts attempts the sequence came out of at all, including
/// those reached through correction, because that is practice and the record
/// should say it happened.
@immutable
class AcquisitionRecord {
  /// Acquisition attempts recorded against this parent.
  final int attempts;

  /// How many of them produced the whole sequence, however it came out.
  final int completions;

  /// How many of them were a clean pass with no stall.
  final int criterionSuccesses;

  /// When the last attempt was recorded.
  final DateTime lastAttemptAt;

  /// When the last criterion success happened, or null if none has.
  final DateTime? lastCriterionSuccessAt;

  const AcquisitionRecord({
    required this.attempts,
    required this.completions,
    required this.criterionSuccesses,
    required this.lastAttemptAt,
    this.lastCriterionSuccessAt,
  });

  /// Whether anything here has earned a probe of the unchanged parent.
  ///
  /// Deliberately binary. Whether one criterion success should be enough is a
  /// policy question the simulation has not been asked yet, and answering it
  /// early would put a threshold where the evidence is not.
  bool get earnsParentProbe => criterionSuccesses > 0;

  @override
  bool operator ==(Object other) =>
      other is AcquisitionRecord &&
      other.attempts == attempts &&
      other.completions == completions &&
      other.criterionSuccesses == criterionSuccesses &&
      other.lastAttemptAt == lastAttemptAt &&
      other.lastCriterionSuccessAt == lastCriterionSuccessAt;

  @override
  int get hashCode => Object.hash(
    attempts,
    completions,
    criterionSuccesses,
    lastAttemptAt,
    lastCriterionSuccessAt,
  );

  @override
  String toString() =>
      'AcquisitionRecord($attempts attempts, $completions complete, '
      '$criterionSuccesses criterion)';
}

/// Acquisition history, keyed by the parent exercise it was work toward.
///
/// Durable by intent and separate from `LearnerState` by design. Nothing here
/// is evidence in the learner model's vocabulary, and keeping it out of that
/// state is what stops an acquisition attempt reaching a residual, a frontier,
/// or a memory clock through a shared container.
///
/// Keyed by the whole parent exercise rather than by its execution context,
/// because what a criterion success earns is a probe of that exact question.
/// Two parents in one context can be stuck for different reasons.
///
/// Progress has to outlive a sitting. A criterion success followed by a break
/// is still a criterion success, so none of this belongs in `SessionState`,
/// every field of which is deliberately a condition of the sitting it arose
/// in.
@immutable
class AcquisitionProgress {
  final Map<Exercise, AcquisitionRecord> _byParent;

  /// No acquisition work recorded.
  const AcquisitionProgress.empty() : _byParent = const {};

  /// Rehydrates persisted progress.
  AcquisitionProgress(Map<Exercise, AcquisitionRecord> byParent)
    : _byParent = Map.unmodifiable(byParent);

  /// Every parent with acquisition history, and what it says.
  Map<Exercise, AcquisitionRecord> get byParent => _byParent;

  /// What acquisition on [parent] has produced, or null if none is recorded.
  AcquisitionRecord? recordFor(Exercise parent) => _byParent[parent];

  /// Whether [parent] has been earned a probe by acquisition work.
  bool earnsParentProbe(Exercise parent) =>
      _byParent[parent]?.earnsParentProbe ?? false;

  /// This progress with one attempt at [parent] added.
  ///
  /// Takes the two facts rather than the observation that carried them, so
  /// nothing here depends on the measurement layer and no measurement can be
  /// mistaken for the evidence a learner-model update consumes.
  ///
  /// Throws [ArgumentError] when an attempt earns a probe without completing,
  /// which no observation produces and which would make the counts disagree.
  AcquisitionProgress recording({
    required Exercise parent,
    required bool completed,
    required bool earnedProbe,
    required DateTime at,
  }) {
    if (earnedProbe && !completed) {
      throw ArgumentError.value(
        earnedProbe,
        'earnedProbe',
        'a criterion success is a completion',
      );
    }
    final previous = _byParent[parent];
    return AcquisitionProgress({
      ..._byParent,
      parent: AcquisitionRecord(
        attempts: (previous?.attempts ?? 0) + 1,
        completions: (previous?.completions ?? 0) + (completed ? 1 : 0),
        criterionSuccesses:
            (previous?.criterionSuccesses ?? 0) + (earnedProbe ? 1 : 0),
        lastAttemptAt: at,
        lastCriterionSuccessAt: earnedProbe
            ? at
            : previous?.lastCriterionSuccessAt,
      ),
    });
  }

  @override
  String toString() => 'AcquisitionProgress(${_byParent.length} parents)';
}
