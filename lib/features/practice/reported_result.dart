import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

/// A result a person reports, standing in for measurement.
///
/// Developer tooling, not a product path: the learner-facing screen closes an
/// attempt from what was played, and these exist so state transitions can be
/// driven by hand without an instrument. A self-report is not a second kind of
/// evidence running beside measurement, and this must not grow into a scoring
/// UX.
///
/// [brokeDown] says both how the attempt ended and how it went, which is only
/// tenable while tapping Done is the one way an attempt can end. See
/// `docs/domain-model/attempt-termination.md`.
enum ReportedResult {
  /// Played through accurately and steadily.
  clean('Clean', 'played it through accurately'),

  /// Played through, but unevenly.
  shaky('Shaky', 'got through it, not cleanly'),

  /// Played through with the wrong notes.
  wrongNotes('Wrong notes', 'played it, but not the right material'),

  /// Started and broke down partway.
  brokeDown('Broke down', 'started, could not finish'),

  /// Could not begin.
  blank('Blank', 'could not start at all');

  const ReportedResult(this.label, this.description);

  /// Short button text.
  final String label;

  /// What the button claims happened.
  final String description;

  /// The outcome this result stands for, given what [exercise] asked.
  ///
  /// Retrieval is forced to [FactualRetrieval.notTested] when the exercise
  /// supplied the material continuously, whatever the person reported.
  /// Succeeding at a fully cued attempt is not evidence of remembering, and
  /// recording it as such would manufacture exactly the false evidence the
  /// three-valued encoding exists to prevent.
  Outcome toOutcome(Exercise exercise) {
    final tested = exercise.guidance.isRetrievalObserved;
    FactualRetrieval retrievalWhen(bool succeeded) {
      if (!tested) return FactualRetrieval.notTested;
      return succeeded ? FactualRetrieval.succeeded : FactualRetrieval.failed;
    }

    return switch (this) {
      ReportedResult.clean => Outcome(
        started: true,
        retrieval: retrievalWhen(true),
        completed: true,
        materialRetrieval: 1.0,
        pitchIntegrity: 0.98,
        continuity: 0.95,
        temporalStability: 0.92,
        achievedTempoRatio: 1.0,
        topologyAccuracy: 1.0,
      ),
      ReportedResult.shaky => Outcome(
        started: true,
        retrieval: retrievalWhen(true),
        completed: true,
        materialRetrieval: 0.9,
        pitchIntegrity: 0.8,
        continuity: 0.6,
        temporalStability: 0.55,
        achievedTempoRatio: 0.85,
        topologyAccuracy: 0.9,
      ),
      ReportedResult.wrongNotes => Outcome(
        started: true,
        retrieval: retrievalWhen(false),
        completed: true,
        materialRetrieval: 0.45,
        pitchIntegrity: 0.4,
        continuity: 0.65,
        temporalStability: 0.6,
        achievedTempoRatio: 0.8,
        topologyAccuracy: 0.35,
      ),
      ReportedResult.brokeDown => Outcome(
        started: true,
        retrieval: retrievalWhen(false),
        completed: false,
        materialRetrieval: 0.3,
        pitchIntegrity: 0.5,
        continuity: 0.2,
        temporalStability: 0.3,
        achievedTempoRatio: 0.5,
        topologyAccuracy: 0.3,
      ),
      ReportedResult.blank => Outcome(
        started: false,
        retrieval: retrievalWhen(false),
        completed: false,
        materialRetrieval: 0.0,
        pitchIntegrity: 0.0,
        continuity: 0.0,
        temporalStability: 0.0,
        achievedTempoRatio: 0.0,
        topologyAccuracy: 0.0,
      ),
    };
  }
}
