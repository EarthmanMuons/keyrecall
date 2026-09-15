import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

final _material = fixtureMaterials.first;

/// What [Outcome] records when an attempt established no pace.
///
/// Zero rather than null: the ratio is the one channel that says absence with
/// a sentinel, which [Outcome.measuredTempoRatio] is the one reading of.
const double _noPaceEstablished = 0;

void main() {
  group('tempo', () {
    test('a clean performance below the required pace does not cover', () {
      final assessment = _assess(
        requirement: _requirement(minimumTempoBpm: 120),
        exercise: _exercise(tempoBpm: 60),
        outcome: _outcome(),
      );

      expect(assessment.structureMatches, isTrue);
      expect(assessment.tempo, CompletionCriterion.notSatisfied);
      expect(assessment.isCovered, isFalse);
    });

    test('the pace played is what counts, not the pace requested', () {
      final assessment = _assess(
        requirement: _requirement(minimumTempoBpm: 120),
        exercise: _exercise(tempoBpm: 100),
        outcome: _outcome(tempoRatio: 1.25),
      );

      expect(assessment.tempo, CompletionCriterion.satisfied);
      expect(
        assessment.isCovered,
        isTrue,
        reason: '125 played under a request for 100 reaches a 120 requirement',
      );
    });

    test('an attempt that established no pace leaves tempo unknown', () {
      final outcome = _outcome(tempoRatio: _noPaceEstablished);
      expect(
        outcome.measuredTempoRatio,
        isNull,
        reason: 'the sentinel is the absence of a pace, not a slow one',
      );

      final assessment = _assess(
        requirement: _requirement(minimumTempoBpm: 120),
        exercise: _exercise(tempoBpm: 120),
        outcome: outcome,
      );

      expect(assessment.tempo, CompletionCriterion.unknown);
      expect(assessment.unknownCriteria, contains('tempo'));
      expect(assessment.isCovered, isFalse);
    });

    test('a requirement naming no tempo is not assessed for one', () {
      final assessment = _assess(
        requirement: _requirement(),
        exercise: _exercise(tempoBpm: 60),
        outcome: _outcome(tempoRatio: 0.5),
      );

      expect(assessment.tempo, CompletionCriterion.notApplicable);
      expect(assessment.isCovered, isTrue);
    });
  });

  group('execution', () {
    test('octave errors at full tempo do not cover', () {
      final assessment = _assess(
        requirement: _requirement(minimumTempoBpm: 120),
        exercise: _exercise(tempoBpm: 120),
        outcome: _outcome(pitchIntegrity: 0.5),
      );

      expect(assessment.tempo, CompletionCriterion.satisfied);
      expect(
        assessment.retrieval,
        CompletionCriterion.satisfied,
        reason: 'retrieval tolerates the register the degrees were played in',
      );
      expect(assessment.pitch, CompletionCriterion.notSatisfied);
      expect(assessment.isCovered, isFalse);
    });

    test('hands that were not together do not cover a two-hand attempt', () {
      final assessment = _assess(
        requirement: _requirement(hands: HandConfiguration.together),
        exercise: _exercise(hands: HandConfiguration.together),
        outcome: _outcome(coordination: 0.2),
      );

      expect(assessment.pitch, CompletionCriterion.satisfied);
      expect(assessment.timing, CompletionCriterion.satisfied);
      expect(assessment.coordination, CompletionCriterion.notSatisfied);
      expect(assessment.isCovered, isFalse);
    });

    test('a one-hand attempt is not assessed for coordination', () {
      final assessment = _assess(
        requirement: _requirement(),
        exercise: _exercise(),
        outcome: _outcome(),
      );

      expect(assessment.coordination, CompletionCriterion.notApplicable);
      expect(assessment.isCovered, isTrue);
    });

    test('unmeasured timing leaves the criterion unknown', () {
      final assessment = _assess(
        requirement: _requirement(),
        exercise: _exercise(),
        outcome: _outcome(continuity: null, temporalStability: null),
      );

      expect(assessment.timing, CompletionCriterion.unknown);
      expect(assessment.isCovered, isFalse);
    });

    test('cued material was never retrieved, so it never covers', () {
      final assessment = _assess(
        requirement: _requirement(),
        exercise: _exercise(guidance: GuidanceContext.continuouslyCued),
        outcome: _outcome(retrieval: FactualRetrieval.notTested),
      );

      expect(assessment.retrieval, CompletionCriterion.unknown);
      expect(assessment.isCovered, isFalse);
    });

    test('an attempt nothing measured demonstrates nothing', () {
      final assessment = assessRequirementAttempt(
        requirement: _requirement(),
        material: _material,
        record: recordOf(
          _exercise(),
          unmeasured: MeasurementUnavailableReason.nothingPlayed,
          termination: AttemptTermination.inactivityTimeout,
        ),
      );

      expect(assessment.structureMatches, isTrue);
      expect(assessment.isCovered, isFalse);
    });
  });

  group('structure', () {
    test('an attempt at another shape demonstrates nothing', () {
      final assessment = _assess(
        requirement: _requirement(hands: HandConfiguration.together),
        exercise: _exercise(),
        outcome: _outcome(),
      );

      expect(assessment.structureMatches, isFalse);
      expect(assessment.isCovered, isFalse);
    });

    test('an attempt at other material demonstrates nothing', () {
      final assessment = assessRequirementAttempt(
        requirement: _requirement(),
        material: fixtureMaterials[1],
        record: recordOf(_exercise(), outcome: _outcome()),
      );

      expect(assessment.structureMatches, isFalse);
      expect(assessment.isCovered, isFalse);
    });
  });
}

RequirementAssessment _assess({
  required CurriculumRequirement requirement,
  required Exercise exercise,
  required Outcome outcome,
}) => assessRequirementAttempt(
  requirement: requirement,
  material: _material,
  record: recordOf(exercise, outcome: outcome),
);

CurriculumRequirement _requirement({
  double? minimumTempoBpm,
  HandConfiguration? hands,
}) => CurriculumRequirement(
  id: 'REQUIREMENT',
  familyId: _material.familyId,
  materialId: _material.materialId,
  constraints: ExerciseConstraints(
    hands: hands,
    minimumTempoBpm: minimumTempoBpm,
  ),
);

Exercise _exercise({
  double tempoBpm = 120,
  HandConfiguration hands = HandConfiguration.right,
  GuidanceContext guidance = GuidanceContext.unguided,
}) => Exercise.linear(
  material: _material,
  hands: hands,
  tempoBpm: tempoBpm,
  guidance: guidance,
);

Outcome _outcome({
  FactualRetrieval retrieval = FactualRetrieval.succeeded,
  double pitchIntegrity = 0.95,
  double? continuity = 0.9,
  double? temporalStability = 0.9,
  double tempoRatio = 1,
  double? coordination,
}) => Outcome(
  started: true,
  retrieval: retrieval,
  completed: true,
  materialRetrieval: 1,
  pitchIntegrity: pitchIntegrity,
  continuity: continuity,
  temporalStability: temporalStability,
  achievedTempoRatio: tempoRatio,
  topologyAccuracy: 1,
  coordination: coordination,
);
