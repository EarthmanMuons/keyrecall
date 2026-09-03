import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

void main() {
  const learner = LearnerModel();
  final at = DateTime.utc(2026);
  final exercise = Exercise.linear(
    material: ArpeggioMaterial('C', ArpeggioQuality.major),
    hands: HandConfiguration.right,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );

  test('scale execution transfers without implying arpeggio mastery', () {
    final baseline = learner.newState(at: at);
    final experienced = learner.newState(at: at);
    experienced.competency(Competency.rhScaleExecution).mean = 2;

    final baselineP = learner.executionProbability(baseline, exercise);
    final transferredP = learner.executionProbability(experienced, exercise);

    expect(transferredP, greaterThan(baselineP));
    expect(
      learner.effectiveCompetencyMean(
        experienced,
        Competency.rhArpeggioExecution,
      ),
      lessThan(experienced.competency(Competency.rhScaleExecution).mean),
    );
    expect(
      experienced.competency(Competency.rhArpeggioExecution).mean,
      baseline.competency(Competency.rhArpeggioExecution).mean,
    );
  });
}
