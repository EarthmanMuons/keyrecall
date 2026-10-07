import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Information counts only the uncertainty a candidate's evidence can reduce.
///
/// An attempt too short to time leaves the motor competencies and the
/// execution residual untouched, so a candidate that can only produce such an
/// attempt must not be credited with their uncertainty.
void main() {
  final arpeggio = allRootPositionArpeggios.firstWhere(
    (material) => material.materialId == 'C_MAJOR_ROOT_ARPEGGIO',
  );

  Exercise arpeggioExercise({
    ExerciseDirection direction = ExerciseDirection.up,
    int octaves = 1,
  }) => Exercise.linear(
    material: arpeggio,
    hands: HandConfiguration.right,
    octaves: octaves,
    direction: direction,
    guidance: GuidanceContext.unguided,
  );

  test('a traversal too short to time claims no motor uncertainty', () {
    final short = arpeggioExercise();
    expect(motorEvidenceOpportunity(short), 0.0);
    expect(motorEvidenceOpportunity(arpeggioExercise(octaves: 2)), 1.0);

    final state = stateAt(PlacementTier.beginner);
    final before = information(state, short, learnerParams);
    for (final competency in motorCompetencies) {
      state.competency(competency).variance *= 10;
    }
    state
            .materialExecutionFor(
              executionContextOf(short),
              t0,
              learnerParams,
              familyId: arpeggio.familyId,
            )
            .residualVariance =
        5.0;

    expect(
      information(state, short, learnerParams),
      before,
      reason: 'uncertainty this candidate cannot reduce is not its to claim',
    );
  });

  test('topology and memory uncertainty still count when it is short', () {
    final short = arpeggioExercise();
    final state = stateAt(PlacementTier.beginner);
    final before = information(state, short, learnerParams);
    state.competency(arpeggio.topologyCompetency).variance *= 10;
    expect(information(state, short, learnerParams), greaterThan(before));
  });

  test('a measurable traversal still counts its motor uncertainty', () {
    final measurable = arpeggioExercise(direction: ExerciseDirection.upDown);
    final state = stateAt(PlacementTier.beginner);
    final before = information(state, measurable, learnerParams);
    for (final competency in motorCompetencies) {
      state.competency(competency).variance *= 10;
    }
    expect(information(state, measurable, learnerParams), greaterThan(before));
  });
}
