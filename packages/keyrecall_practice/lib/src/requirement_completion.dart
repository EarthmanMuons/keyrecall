import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

/// Whether one attempt met one completion criterion.
///
/// [unknown] is not a failure and not a pass: the attempt carried no evidence
/// either way. Coverage requires [satisfied], but the distinction survives the
/// verdict, because an attempt that could not be judged and one that was
/// judged and fell short are different things to say to a learner.
enum CompletionCriterion { satisfied, notSatisfied, unknown, notApplicable }

extension on CompletionCriterion {
  bool get isMet =>
      this == CompletionCriterion.satisfied ||
      this == CompletionCriterion.notApplicable;
}

/// What a performance has to show before a requirement counts as covered.
///
/// The curriculum's own policy, deliberately not the learner model's evidence
/// predicates. The learner asks what a performance says about the learner;
/// this asks whether the performance demonstrated the requirement, so it names
/// pitch accuracy and coordination that the execution channel excludes on
/// purpose.
@immutable
class RequirementCompletionPolicy {
  /// Pitch accuracy a covering performance has to reach.
  ///
  /// Sounded notes over notes played, so one slip in a two-octave traversal
  /// still covers and alternating octave errors do not.
  final double minimumPitchIntegrity;

  /// Timing quality a covering performance has to reach.
  ///
  /// The same value the learner's execution channel calls demonstrated today,
  /// held separately so either can move without moving the other.
  final double minimumMotorScore;

  /// Hand coordination a hands-together performance has to reach.
  final double minimumCoordination;

  const RequirementCompletionPolicy({
    this.minimumPitchIntegrity = 0.9,
    this.minimumMotorScore = 0.5,
    this.minimumCoordination = 0.75,
  });

  static const RequirementCompletionPolicy standard =
      RequirementCompletionPolicy();
}

/// One attempt read against one requirement, criterion by criterion.
@immutable
class RequirementAssessment {
  /// Whether the attempt realized the shape the requirement names.
  ///
  /// Tempo is not part of it: the requested pace says what was asked for and
  /// [tempo] says what was played.
  final bool structureMatches;

  /// Whether the exercise was started and played through.
  final CompletionCriterion completion;

  /// Whether the measured pace reached the requirement's tempo.
  final CompletionCriterion tempo;

  /// Whether the sounded pitches were correct.
  final CompletionCriterion pitch;

  /// Whether the material was retrieved independently.
  final CompletionCriterion retrieval;

  /// Whether the playing was continuous and steady.
  final CompletionCriterion timing;

  /// Whether the hands were together, where both played.
  final CompletionCriterion coordination;

  const RequirementAssessment({
    required this.structureMatches,
    required this.completion,
    required this.tempo,
    required this.pitch,
    required this.retrieval,
    required this.timing,
    required this.coordination,
  });

  /// An attempt at something else, or one that measured nothing.
  const RequirementAssessment.notDemonstrated({this.structureMatches = false})
    : completion = CompletionCriterion.unknown,
      tempo = CompletionCriterion.unknown,
      pitch = CompletionCriterion.unknown,
      retrieval = CompletionCriterion.unknown,
      timing = CompletionCriterion.unknown,
      coordination = CompletionCriterion.unknown;

  /// Whether this attempt demonstrated the requirement.
  bool get isCovered =>
      structureMatches &&
      completion.isMet &&
      tempo.isMet &&
      pitch.isMet &&
      retrieval.isMet &&
      timing.isMet &&
      coordination.isMet;

  /// The criteria this attempt carried no evidence about.
  List<String> get unknownCriteria => [
    for (final entry in {
      'completion': completion,
      'tempo': tempo,
      'pitch': pitch,
      'retrieval': retrieval,
      'timing': timing,
      'coordination': coordination,
    }.entries)
      if (entry.value == CompletionCriterion.unknown) entry.key,
  ];
}

/// Reads [record] against [requirement] under [policy].
RequirementAssessment assessRequirementAttempt({
  required CurriculumRequirement requirement,
  required TechnicalMaterial material,
  required AttemptRecord record,
  RequirementCompletionPolicy policy = RequirementCompletionPolicy.standard,
}) {
  final structureMatches =
      record.exercise.material == material &&
      requirement.constraints.matchesStructure(record.exercise);
  if (record.closure.measurement case Measured(:final outcome)) {
    return RequirementAssessment(
      structureMatches: structureMatches,
      completion: _met(outcome.started && outcome.completed),
      tempo: _assessTempo(requirement, record.exercise, outcome),
      pitch: _atLeast(outcome.pitchIntegrity, policy.minimumPitchIntegrity),
      retrieval: switch (outcome.retrieval) {
        FactualRetrieval.succeeded => CompletionCriterion.satisfied,
        FactualRetrieval.failed => CompletionCriterion.notSatisfied,
        FactualRetrieval.notTested => CompletionCriterion.unknown,
      },
      timing: _atLeast(outcome.motorScore, policy.minimumMotorScore),
      coordination:
          record.exercise.conditions.hands == HandConfiguration.together
          ? _atLeast(outcome.coordination, policy.minimumCoordination)
          : CompletionCriterion.notApplicable,
    );
  }
  return RequirementAssessment.notDemonstrated(
    structureMatches: structureMatches,
  );
}

/// The pace [outcome] established, against the pace [requirement] asks for.
///
/// The requested tempo is what was asked for and the ratio is what came of it,
/// so the product is the pace actually played; an attempt that established no
/// pace leaves the criterion unknown rather than failed.
CompletionCriterion _assessTempo(
  CurriculumRequirement requirement,
  Exercise exercise,
  Outcome outcome,
) {
  final wanted = requirement.constraints.minimumTempoBpm;
  if (wanted == null) return CompletionCriterion.notApplicable;
  final ratio = outcome.measuredTempoRatio;
  if (ratio == null) return CompletionCriterion.unknown;
  return _met(exercise.conditions.tempoBpm * ratio >= wanted);
}

CompletionCriterion _met(bool value) =>
    value ? CompletionCriterion.satisfied : CompletionCriterion.notSatisfied;

CompletionCriterion _atLeast(double? value, double floor) =>
    value == null ? CompletionCriterion.unknown : _met(value >= floor);
