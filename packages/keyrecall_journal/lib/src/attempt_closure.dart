import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

/// How an attempt ended.
///
/// Lifecycle data, not evidence. Which of these happened says nothing about how
/// the performance went, and reading a failure out of one would be inventing
/// evidence nobody observed. See `docs/domain-model/attempt-termination.md`.
enum AttemptTermination {
  /// The learner ended it. The only path that exists today.
  ///
  /// Deliberately not `learnerCompleted`: nothing can establish completion
  /// until measurement does, and tapping Done is the weaker claim.
  learnerStopped('LEARNER_STOPPED'),

  /// Nothing arrived for long enough that the attempt was closed.
  inactivityTimeout('INACTIVITY_TIMEOUT'),

  /// The attempt ran past the time allowed for it.
  durationLimit('DURATION_LIMIT'),

  /// The learner said they could not retrieve the material, before playing.
  ///
  /// Evidence, not an escape hatch: it is a retrieval failure the learner is
  /// in a position to report, and it says nothing about execution because
  /// there was none. Only available while nothing has been played, since after
  /// that what happened is a question for the performance rather than for the
  /// learner.
  learnerDeclined('LEARNER_DECLINED'),

  /// The app stopped it because of how it was going. Only legitimate where the
  /// attempt's presentation already permits evaluative feedback.
  evaluativeCutoff('EVALUATIVE_CUTOFF');

  const AttemptTermination(this.id);

  /// Stable identifier used in persisted records and traces.
  final String id;

  /// The termination with the given [id].
  ///
  /// Throws [ArgumentError] when no termination matches.
  static AttemptTermination fromId(String id) => values.firstWhere(
    (termination) => termination.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown termination'),
  );
}

/// Why an attempt has no measured outcome.
///
/// Structural, always. A reason names a capability the observation model is
/// missing, never a performance it disliked: fifty wrong notes measure fine,
/// and if bad attempts could go unmeasured the evidence would go missing
/// exactly where it is strongest.
enum MeasurementUnavailableReason {
  /// Nothing can measure a performance yet.
  notAvailable('NOT_AVAILABLE'),

  /// The exercise used both hands, and relating two hands' notes to the
  /// moments they belong to needed observation grouping. Written by builds
  /// before that existed, and read back rather than produced.
  handsTogetherCorrespondence('HANDS_TOGETHER_CORRESPONDENCE');

  const MeasurementUnavailableReason(this.id);

  /// Stable identifier used in persisted records and traces.
  final String id;

  /// The reason with the given [id].
  ///
  /// Throws [ArgumentError] when no reason matches.
  static MeasurementUnavailableReason fromId(String id) => values.firstWhere(
    (reason) => reason.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown reason'),
  );
}

/// What was established about a performance, if anything.
///
/// A sum rather than a nullable outcome. "Nothing measured this attempt, and
/// here is why" is known information; a missing field is what an incomplete
/// write looks like, and replay has to tell those apart without guessing.
///
/// Making it a sum also keeps [MeasurementUnavailable] from reaching code that
/// was built on an outcome always existing: the evidence a measurement produces
/// lives inside [Measured], so there is nothing to null-check and nothing to
/// defensively skip.
@immutable
sealed class MeasurementResult {
  const MeasurementResult();
}

/// A performance was measured, with everything derived from it.
///
/// Or, for [AttemptTermination.learnerDeclined], established without one: the
/// learner reporting that they could not retrieve the material is an outcome
/// in its own right, and it carries the same evidence a measured attempt does.
@immutable
final class Measured extends MeasurementResult {
  /// What was observed.
  final Outcome outcome;

  /// How informative it was, per layer.
  final EvidenceWeights weights;

  /// Where its consolidation change came from.
  final MemoryUpdateDiagnostics memoryUpdate;

  const Measured({
    required this.outcome,
    required this.weights,
    required this.memoryUpdate,
  });

  @override
  bool operator ==(Object other) =>
      other is Measured &&
      other.outcome == outcome &&
      other.weights == weights &&
      other.memoryUpdate == memoryUpdate;

  @override
  int get hashCode => Object.hash(outcome, weights, memoryUpdate);

  @override
  String toString() => 'Measured(${outcome.retrieval.name})';
}

/// Nothing was measured, and this is why.
@immutable
final class MeasurementUnavailable extends MeasurementResult {
  /// Why there is no outcome.
  final MeasurementUnavailableReason reason;

  const MeasurementUnavailable(this.reason);

  @override
  bool operator ==(Object other) =>
      other is MeasurementUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'MeasurementUnavailable(${reason.id})';
}

/// Everything known about an attempt at the moment it ended.
///
/// Termination is mandatory, because an attempt that ended did so somehow.
/// Measurement is independent evidence beside it, and its absence is a state
/// rather than a gap.
@immutable
class AttemptClosure {
  /// How the attempt ended.
  final AttemptTermination termination;

  /// What was established about the performance.
  final MeasurementResult measurement;

  const AttemptClosure({required this.termination, required this.measurement});

  /// A closure carrying a measured performance.
  factory AttemptClosure.measured({
    required AttemptTermination termination,
    required Outcome outcome,
    required EvidenceWeights weights,
    required MemoryUpdateDiagnostics memoryUpdate,
  }) => AttemptClosure(
    termination: termination,
    measurement: Measured(
      outcome: outcome,
      weights: weights,
      memoryUpdate: memoryUpdate,
    ),
  );

  /// A closure with nothing measured.
  factory AttemptClosure.unmeasured({
    required AttemptTermination termination,
    MeasurementUnavailableReason reason =
        MeasurementUnavailableReason.notAvailable,
  }) => AttemptClosure(
    termination: termination,
    measurement: MeasurementUnavailable(reason),
  );

  @override
  bool operator ==(Object other) =>
      other is AttemptClosure &&
      other.termination == termination &&
      other.measurement == measurement;

  @override
  int get hashCode => Object.hash(termination, measurement);

  @override
  String toString() => 'AttemptClosure(${termination.id}, $measurement)';
}
