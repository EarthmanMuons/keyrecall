import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

void main() {
  final at = DateTime.utc(2026);
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.together,
  );

  for (final (name, model) in [
    ('production', const LearnerModel()),
    ('prototype', const LearnerModel.v1Prototype()),
  ]) {
    test('the scheduler uses $name prediction semantics', () {
      final state = model.placementState(PlacementTier.someExperience, at: at);
      final trace = SchedulerPipeline(learner: model)
          .evaluate(
            state: state,
            session: SessionState(),
            candidates: [exercise],
            at: at,
          )
          .firstWhere((candidate) => candidate.exercise == exercise);

      expect(trace.prediction, model.predict(state, exercise, at: at));
    });
  }
}
