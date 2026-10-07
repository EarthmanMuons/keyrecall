import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The production pipeline, keeping the history each slot was decided with.
class _HistoryRecorder extends SchedulerPipeline {
  final List<AttemptHistory?> histories = [];

  _HistoryRecorder() : super(learner: const LearnerModel());

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    bool diagnose = true,
  }) {
    histories.add(history);
    return super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      diagnose: diagnose,
    );
  }
}

/// A simulated slot is decided with the history the app would rebuild from
/// the same attempts, so rules that read history apply in both.
void main() {
  test('every slot is decided with the history of the slots before it', () {
    final pipeline = _HistoryRecorder();
    final trajectory = runTrajectorySessions(
      player: PlayerArchetypes.developing,
      seed: 0,
      materials: [...v1ScaleCatalog, ...allRootPositionArpeggios],
      sessions: sessionsOnDays([0, 2], slots: 8),
      pipeline: pipeline,
    );
    final slots = trajectory.slots;
    expect(pipeline.histories, hasLength(slots.length));

    for (final (index, history) in pipeline.histories.indexed) {
      final expected = attemptHistoryOf([
        for (final slot in slots.take(index))
          (
            exercise: slot.chosen,
            outcome: slot.outcome,
            weights: evidenceWeightsFor(slot.chosen, slot.outcome),
          ),
      ]);
      expect(history, isNotNull, reason: 'slot $index decided without one');
      expect(history!.attemptedExercises, expected.attemptedExercises);
      expect(history.retrievedMaterialHands, expected.retrievedMaterialHands);
      expect(
        history.executionEvidenceRevisions,
        expected.executionEvidenceRevisions,
      );
      expect(history.demonstratedShapes, expected.demonstratedShapes);
    }
    expect(
      pipeline.histories.last!.attemptedExercises,
      isNotEmpty,
      reason: 'the run accumulated a history to read',
    );
  });
}
