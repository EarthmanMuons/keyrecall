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

  /// How many probes of the parent this history has already been served.
  final int probesServed;

  /// Criterion successes covered by the most recent presentation.
  final int criterionSuccessesServed;

  /// When the last attempt was recorded.
  final DateTime lastAttemptAt;

  /// When the last criterion success happened, or null if none has.
  final DateTime? lastCriterionSuccessAt;

  /// When a probe of the parent was last presented, or null if none has been.
  final DateTime? lastProbeServedAt;

  const AcquisitionRecord({
    required this.attempts,
    required this.completions,
    required this.criterionSuccesses,
    required this.lastAttemptAt,
    this.probesServed = 0,
    this.criterionSuccessesServed = 0,
    this.lastCriterionSuccessAt,
    this.lastProbeServedAt,
  });

  /// Whether a criterion success here has earned a probe of the parent.
  ///
  /// Deliberately binary. Whether one criterion success should be enough is a
  /// policy question the simulation has not been asked yet, and answering it
  /// early would put a threshold where the evidence is not.
  ///
  /// A fact about the past, and not the scheduler's condition. It stays true
  /// once it is true, which is why [probeOwed] exists.
  bool get earnsParentProbe => criterionSuccesses > 0;

  /// Whether a success arrived after the last presentation in event order.
  ///
  /// One presentation covers every success preceding it, even at equal times.
  bool get probeOwed => criterionSuccesses > criterionSuccessesServed;

  @override
  bool operator ==(Object other) =>
      other is AcquisitionRecord &&
      other.attempts == attempts &&
      other.completions == completions &&
      other.criterionSuccesses == criterionSuccesses &&
      other.probesServed == probesServed &&
      other.criterionSuccessesServed == criterionSuccessesServed &&
      other.lastAttemptAt == lastAttemptAt &&
      other.lastCriterionSuccessAt == lastCriterionSuccessAt &&
      other.lastProbeServedAt == lastProbeServedAt;

  @override
  int get hashCode => Object.hash(
    attempts,
    completions,
    criterionSuccesses,
    probesServed,
    criterionSuccessesServed,
    lastAttemptAt,
    lastCriterionSuccessAt,
    lastProbeServedAt,
  );

  @override
  String toString() =>
      'AcquisitionRecord($attempts attempts, $completions complete, '
      '$criterionSuccesses criterion, $probesServed served)';
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

  /// Whether acquisition work on [parent] has ever earned a probe.
  bool earnsParentProbe(Exercise parent) =>
      _byParent[parent]?.earnsParentProbe ?? false;

  /// Whether [parent] is owed a probe that has not been asked yet.
  ///
  /// What the scheduler reads. Acquisition is not offered while a probe is
  /// owed, because what the learner is owed is the ordinary question; once it
  /// has been asked, a parent that is still stuck may acquire again.
  bool probeOwed(Exercise parent) => _byParent[parent]?.probeOwed ?? false;

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
        probesServed: previous?.probesServed ?? 0,
        criterionSuccessesServed: previous?.criterionSuccessesServed ?? 0,
        lastAttemptAt: at,
        lastCriterionSuccessAt: earnedProbe
            ? at
            : previous?.lastCriterionSuccessAt,
        lastProbeServedAt: previous?.lastProbeServedAt,
      ),
    });
  }

  /// This progress with a probe of [parent] recorded as asked.
  ///
  /// Service is presentation, not success. What acquisition earned is the
  /// ordinary question; what the answer to it means is the ordinary path's to
  /// decide, and a probe that fails leaves the parent stuck rather than owed
  /// again.
  ///
  /// Recorded even when nothing was owed. A parent presented by ordinary
  /// ranking has been asked the same question, and pretending otherwise would
  /// leave an obligation open that the learner has already answered.
  ///
  /// Throws [ArgumentError] for a parent with no acquisition history, which
  /// would be service of an obligation that never existed.
  AcquisitionProgress serving({
    required Exercise parent,
    required DateTime at,
  }) {
    final previous = _byParent[parent];
    if (previous == null) {
      throw ArgumentError.value(
        parent,
        'parent',
        'no acquisition history to serve a probe for',
      );
    }
    return AcquisitionProgress({
      ..._byParent,
      parent: AcquisitionRecord(
        attempts: previous.attempts,
        completions: previous.completions,
        criterionSuccesses: previous.criterionSuccesses,
        probesServed: previous.probesServed + 1,
        criterionSuccessesServed: previous.criterionSuccesses,
        lastAttemptAt: previous.lastAttemptAt,
        lastCriterionSuccessAt: previous.lastCriterionSuccessAt,
        lastProbeServedAt: at,
      ),
    });
  }

  @override
  String toString() => 'AcquisitionProgress(${_byParent.length} parents)';
}
