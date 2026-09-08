import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

void main() {
  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final at = DateTime.utc(2026);
  final exercise = Exercise.linear(
    material: v1ScaleCatalog.first,
    hands: HandConfiguration.right,
    tempoBpm: 60,
  );

  for (final introduction in [true, false]) {
    test(
      '${introduction ? 'introduction' : 'bootstrap'} floor survives export',
      () {
        final state = learner.placementState(
          PlacementTier.someExperience,
          at: at,
        );
        if (!introduction) {
          state
                  .materialExecutionFor(
                    executionContextOf(exercise),
                    at,
                    learner.params,
                    familyId: exercise.material.familyId,
                  )
                  .lastEvidenceAt =
              at;
        }
        final offered = introduction
            ? exercise
            : exercise.withGuidance(GuidanceContext.continuouslyCued);
        final trace = pipeline
            .evaluate(
              state: state,
              session: SessionState(),
              candidates: [offered],
              at: at,
            )
            .singleWhere((trace) => trace.exercise == offered);
        expect(trace.isRanked, isTrue);
        expect(
          trace.prediction.overallP,
          inExclusiveRange(
            pipeline.config.challenge.pIntroductionMin,
            pipeline.config.challenge.pMin,
          ),
        );
        expect(
          trace.challengeFloor,
          pipeline.config.challenge.pIntroductionMin,
        );
        expect(
          trace.challengeFloorReason,
          introduction
              ? ChallengeFloorReason.introduction
              : ChallengeFloorReason.executionBootstrap,
        );
        expect(trace.isWithinChallengeBand, isTrue);
        final decision = SchedulerDecision.fromTrace(trace, pipeline.config);
        final json = encodeDecision(decision, encodePrediction);
        final restored = decodeDecision(json, decodePrediction);
        expect(restored.challengeBandMin, trace.challengeFloor);
        expect(restored.challengeFloorReason, trace.challengeFloorReason);
        expect(restored.withinChallengeBand, isTrue);
        json.remove('challenge_floor_reason');
        expect(
          decodeDecision(json, decodePrediction).challengeFloorReason,
          isNull,
        );
        json['challenge_floor_reason'] = 'invented';
        expect(
          () => decodeDecision(json, decodePrediction),
          throwsA(isA<JournalFormatException>()),
        );
      },
    );
  }
}
