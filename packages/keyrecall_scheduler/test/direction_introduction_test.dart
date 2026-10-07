import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Up before up and down, for any material that can be traversed either way.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());

  for (final material in [
    TechnicalMaterial('C', ScaleForm.major),
    ArpeggioMaterial('C', ArpeggioQuality.major),
  ]) {
    group(material.familyId.toLowerCase(), () {
      Exercise traversal(
        ExerciseDirection direction,
        HandConfiguration hands,
      ) => Exercise.linear(
        material: material,
        hands: hands,
        octaves: 1,
        direction: direction,
        guidance: GuidanceContext.notesPreviewedOnly,
      );

      EligibilityReason reasonAfter(
        Set<Exercise> attempted, {
        HandConfiguration hands = HandConfiguration.right,
      }) {
        final state = LearnerState.cold(learnerParams, at: t0);
        return pipeline
            .eligibilityFor(
              state,
              traversal(ExerciseDirection.upDown, hands),
              facts: DecisionFacts(state, startedExercises: attempted),
            )
            .code;
      }

      test('is not met up and down before it has been met going up', () {
        expect(reasonAfter(const {}), EligibilityReason.directionPrerequisite);
      });

      test('and is once that hand has gone up', () {
        expect(
          reasonAfter({
            traversal(ExerciseDirection.up, HandConfiguration.right),
          }),
          isNot(EligibilityReason.directionPrerequisite),
        );
      });

      test('the other hand going up does not count', () {
        expect(
          reasonAfter({
            traversal(ExerciseDirection.up, HandConfiguration.right),
          }, hands: HandConfiguration.left),
          EligibilityReason.directionPrerequisite,
        );
      });
    });
  }
}
