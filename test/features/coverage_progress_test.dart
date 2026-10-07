import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/goal_progress.dart';
import 'package:keyrecall/features/practice/goal_feedback.dart';

void main() {
  final cMajor = ScaleMaterial('C', ScaleForm.major);
  final gMajor = ScaleMaterial('G', ScaleForm.major);

  GoalTarget target(
    ScaleMaterial material,
    HandConfiguration hands, {
    CoverageRetrieval retrieval = CoverageRetrieval.unguided,
  }) => GoalTarget(
    requirement: CurriculumRequirement(
      id: '${material.materialId}-${hands.name}',
      familyId: TechnicalMaterial.scaleFamilyId,
      materialId: material.materialId,
      constraints: ExerciseConstraints(hands: hands),
      retrieval: retrieval,
    ),
    material: material,
  );

  final cRight = target(cMajor, HandConfiguration.right);
  final cLeft = target(cMajor, HandConfiguration.left);
  final gRight = target(gMajor, HandConfiguration.right);
  final targets = [cRight, cLeft, gRight];

  AttemptRecord played(
    int index,
    ScaleMaterial material,
    HandConfiguration hands, {
    GuidanceContext guidance = GuidanceContext.unguided,
  }) {
    final exercise = Exercise.linear(
      material: material,
      hands: hands,
      guidance: guidance,
    );
    final outcome = Outcome(
      pulseMaintenance: PulseMaintenance.tested,
      started: true,
      retrieval: FactualRetrieval.succeeded,
      completed: true,
      materialRetrieval: 1,
      pitchIntegrity: 1,
      continuity: 1,
      temporalStability: 1,
      achievedTempoRatio: 1,
      topologyAccuracy: 1,
    );
    return AttemptRecord(
      journalSequence: index,
      identity: AttemptIdentity(
        profileId: 'profile',
        attemptId: 'attempt-$index',
        sessionId: 'session',
        indexInSession: index,
        occurredAt: DateTime.utc(2026, 1, 1, 12, index),
      ),
      provenance: const ModelProvenance(
        learnerModelVersion: 'learner',
        schedulerModelVersion: 'scheduler',
      ),
      exercise: exercise,
      closure: AttemptClosure.measured(
        termination: AttemptTermination.traversalCompleted,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        memoryUpdate: MemoryUpdateDiagnostics(),
      ),
    );
  }

  CoverageProgress? progressAfter(
    List<AttemptRecord> history, {
    bool focused = false,
  }) => coverageProgressFor(
    history.last,
    history: history,
    targets: targets,
    focused: focused,
  );

  test('a target demonstrated for the first time is named and counted', () {
    final progress = progressAfter([
      played(0, cMajor, HandConfiguration.right),
    ])!;

    expect(progress.newlyCovered, [cRight]);
    expect(progress.coveredBefore, 0);
    expect(progress.covered, 1);
    expect(progress.events.map((event) => event.type), [
      ProgressEventKind.targetCovered,
    ]);
    expect(coverageHeading(progress), 'Goal progress');
    expect(
      coverageStatement(progress),
      'C major, right hand, from memory. 1 of 3 demonstrated.',
    );
  });

  test('a target already demonstrated is not news', () {
    expect(
      progressAfter([
        played(0, cMajor, HandConfiguration.right),
        played(1, cMajor, HandConfiguration.right),
      ]),
      isNull,
    );
  });

  test('only what came before counts as already demonstrated', () {
    final first = played(0, cMajor, HandConfiguration.right);
    final later = played(1, cMajor, HandConfiguration.right);

    expect(
      coverageProgressFor(
        first,
        history: [first, later],
        targets: targets,
        focused: false,
      )?.newlyCovered,
      [cRight],
    );
  });

  test('playing with the notes shown covers nothing asked from memory', () {
    expect(
      progressAfter([
        played(
          0,
          cMajor,
          HandConfiguration.right,
          guidance: GuidanceContext.continuouslyCued,
        ),
      ]),
      isNull,
    );
  });

  test('the last target completes the goal and is named as the last', () {
    final progress = progressAfter([
      played(0, cMajor, HandConfiguration.right),
      played(1, cMajor, HandConfiguration.left),
      played(2, gMajor, HandConfiguration.right),
    ])!;

    expect(progress.completes, isTrue);
    expect(progress.events.map((event) => event.type), [
      ProgressEventKind.targetCovered,
      ProgressEventKind.scopeCovered,
    ]);
    expect(coverageHeading(progress), 'Goal complete');
    expect(
      coverageStatement(progress),
      'All 3 demonstrated from memory. The last was G major.',
    );
  });

  test('an exclusive focus is named as the focus, not the goal', () {
    final progress = progressAfter([
      played(0, cMajor, HandConfiguration.right),
    ], focused: true)!;

    expect(coverageHeading(progress), 'Focus progress');
  });

  test('a target is named only as far as its material needs', () {
    expect(coveredTargetName(gRight, targets), 'G major');
    expect(coveredTargetName(cLeft, targets), 'C major, left hand');
  });
}
