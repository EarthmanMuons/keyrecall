import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

/// A first meeting too short to time borrows information only from work the
/// resolved scope actually offers.
void main() {
  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final at = DateTime.utc(2026);
  final arpeggio = allRootPositionArpeggios.first;

  List<Exercise> envelopeOf(ExerciseDirection direction) {
    final curriculum = Curriculum(
      id: 'ONE_OCTAVE_${direction.name.toUpperCase()}',
      version: '1',
      requirements: [
        CurriculumRequirement(
          id: '${arpeggio.materialId}:1',
          familyId: arpeggio.familyId,
          materialId: arpeggio.materialId,
          constraints: ExerciseConstraints(
            hands: HandConfiguration.right,
            octaves: 1,
            direction: direction,
          ),
        ),
      ],
    );
    final resolution = PracticeScopeResolver().resolve(
      goal: PracticeGoal(id: curriculum.id, curriculum: curriculum),
      focus: PracticeFocus.unrestricted,
      catalog: [arpeggio],
      instrument: InstrumentProfile(),
    );
    return [
      for (final requirement
          in (resolution as ValidPracticeScope).scope.requirements)
        ...requirement.candidates,
    ];
  }

  /// The ranked information of the ascending first meeting, and what that
  /// meeting would read as itself and as its up and down.
  ({double ranked, double literal, double opened}) readingsIn(
    List<Exercise> envelope,
  ) {
    final state = learner.placementState(PlacementTier.beginner, at: at);
    final trace = pipeline
        .evaluate(
          state: state,
          session: SessionState(),
          candidates: envelope,
          at: at,
          history: AttemptHistory.empty,
        )
        .firstWhere(
          (trace) =>
              trace.rankKey != null &&
              trace.exercise.conditions.direction == ExerciseDirection.up,
        );
    final conditions = trace.exercise.conditions;
    final opened = Exercise.linear(
      material: arpeggio,
      hands: conditions.hands,
      octaves: conditions.octaves,
      direction: ExerciseDirection.upDown,
      tempoBpm: conditions.tempoBpm,
      guidance: trace.exercise.guidance,
    );
    double of(Exercise exercise) =>
        canonicalRankValue(information(state, exercise, learner.params));
    return (
      ranked: trace.rankKey!.information,
      literal: of(trace.exercise),
      opened: of(opened),
    );
  }

  test('an ascending-only scope ranks the meeting as itself', () {
    final envelope = envelopeOf(ExerciseDirection.up);
    expect(envelope.map((exercise) => exercise.conditions.direction).toSet(), {
      ExerciseDirection.up,
    });

    final readings = readingsIn(envelope);
    expect(readings.opened, greaterThan(readings.literal));
    expect(
      readings.ranked,
      readings.literal,
      reason: 'the scope offers no up and down for the meeting to open',
    );
  });

  test('a scope that offers up and down ranks the meeting as it', () {
    final readings = readingsIn(envelopeOf(ExerciseDirection.upDown));
    expect(readings.ranked, readings.opened);
  });
}
