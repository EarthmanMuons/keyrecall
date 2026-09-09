import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

class ObservedPipeline extends SchedulerPipeline {
  ObservedPipeline() : super(learner: const LearnerModel());

  late SessionState session;

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
    Set<Exercise> attemptedAcquisitionParents = const {},
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
  }) {
    this.session = session;
    return super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      attemptedAcquisitionParents: attemptedAcquisitionParents,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
    );
  }
}

void main() {
  test('guidance service follows the substituted winner', () {
    final pipeline = ObservedPipeline();
    var probesSelected = 0;
    var probesSkipped = 0;
    var checked = 0;
    int? expectedDebt;
    final run = runTrajectory(
      player: PlayerArchetypes.developing,
      seed: 3,
      materials: v1ScaleCatalog.take(4).toList(),
      slots: 80,
      pipeline: pipeline,
      observeState: (_, _) {
        if (expectedDebt case final debt?) {
          expect(pipeline.session.unservedGuidanceProbeSelections, debt);
          checked++;
        }
      },
      chooseInstead: (selection, _) {
        final selected = (selection as CandidateSelected).candidate;
        final wasProbe =
            selected.challengeBypass == ChallengeBypass.guidanceProbe;
        final opposite = selection.selectable
            .where(
              (trace) =>
                  (trace.challengeBypass == ChallengeBypass.guidanceProbe) !=
                  wasProbe,
            )
            .firstOrNull;
        final chosen = opposite ?? selected;
        expectedDebt = null;
        if (opposite != null) {
          if (chosen.challengeBypass == ChallengeBypass.guidanceProbe) {
            probesSelected++;
            expectedDebt = 0;
          } else {
            probesSkipped++;
            expectedDebt = pipeline.session.unservedGuidanceProbeSelections + 1;
          }
        }
        return opposite;
      },
    );
    expect(probesSelected, greaterThan(0));
    expect(probesSkipped, greaterThan(0));
    expect(checked, greaterThan(0));
    if (expectedDebt case final debt?) {
      expect(pipeline.session.unservedGuidanceProbeSelections, debt);
    }
    expect(
      pipeline.session.attemptsThisSession,
      run.slots.length + run.terminals.length,
    );
  });

  test('a replacement must be selectable in the current slot', () {
    CandidateTrace? previous;
    expect(
      () => runTrajectory(
        player: PlayerArchetypes.developing,
        seed: 3,
        materials: v1ScaleCatalog.take(4).toList(),
        slots: 2,
        chooseInstead: (selection, _) {
          final stale = previous;
          previous = (selection as CandidateSelected).candidate;
          return stale;
        },
      ),
      throwsArgumentError,
    );
  });
}
