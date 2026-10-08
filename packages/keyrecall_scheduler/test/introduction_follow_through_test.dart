import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// One hand meeting a new arpeggio and following that meeting through.
///
/// A one-octave triad ascending cannot be timed, so the meeting leaves the
/// hand without the execution evidence ordinary eligibility reads. What it
/// opens at the entry tempo has to stay open until an attempt gives that
/// evidence, and then the hand's own record decides, well or badly.
void main() {
  const pipeline = SchedulerPipeline(learner: learner);
  final owned = ArpeggioMaterial('C', ArpeggioQuality.major);
  final unmet = ArpeggioMaterial('D', ArpeggioQuality.major);
  const entry = 84.0;

  /// Short of early transfer, with a right hand that plays the arpeggio it
  /// owns at the entry tempo.
  LearnerState learnerOwningOne() {
    final state = LearnerState(
      competencies: {
        for (final competency in Competency.values)
          competency: CompetencyState(
            competency: competency,
            mean: -1.0,
            variance: 1.0,
            updatedAt: t0,
          ),
      },
    );
    state.materialExecutionFor(
        (owned.materialId, HandConfiguration.right, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: owned.familyId,
      )
      ..lastEvidenceAt = t0
      ..pacedTempoBpm = entry
      ..demonstratedTempoByOctaves[1] = entry;
    return state;
  }

  Exercise traversal(
    ExerciseDirection direction, {
    double tempoBpm = entry,
    int octaves = 1,
    HandConfiguration hands = HandConfiguration.right,
  }) => Exercise.linear(
    material: unmet,
    hands: hands,
    octaves: octaves,
    direction: direction,
    tempoBpm: tempoBpm,
    guidance: GuidanceContext.continuouslyCued,
  );

  final meeting = traversal(ExerciseDirection.up);
  final followUp = traversal(ExerciseDirection.upDown);
  final gentler = traversal(ExerciseDirection.upDown, tempoBpm: 60);

  Outcome played({double? timing, double pitch = 0.95, bool started = true}) =>
      Outcome(
        started: started,
        retrieval: FactualRetrieval.notTested,
        completed: started,
        materialRetrieval: 0.9,
        pitchIntegrity: started ? pitch : 0.0,
        continuity: timing,
        temporalStability: timing,
        achievedTempoRatio: started ? 1.0 : 0.0,
        topologyAccuracy: started ? pitch : 0.0,
      );

  DateTime at = t0;
  void play(LearnerState state, Exercise exercise, Outcome outcome) {
    at = at.add(const Duration(minutes: 2));
    learner.propagateAndApplyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: learner.predict(state, exercise, at: at),
      at: at,
    );
  }

  CandidateTrace traceOf(
    LearnerState state,
    Exercise exercise,
    Set<Exercise> started,
  ) => pipeline
      .evaluate(
        state: state,
        session: SessionState(),
        candidates: withExecutionNeighbors(
          state,
          generateCandidates(instrument, [unmet, owned]),
        ),
        at: at,
        history: AttemptHistory(startedExercises: started),
      )
      .singleWhere((trace) => trace.exercise == exercise);

  TypeMatcher<CandidateTrace> admittedAndRanked(EligibilityTier tier) =>
      isA<CandidateTrace>()
          .having((trace) => trace.eligibility.tier, 'tier', tier)
          .having((trace) => trace.admissionRefusal, 'refusal', isNull)
          .having((trace) => trace.isRanked, 'ranked', isTrue);

  test(
    'the meeting is admitted at the entry tempo, ranked as its follow-up',
    () {
      final state = learnerOwningOne();

      expect(
        traceOf(state, meeting, const {}),
        admittedAndRanked(EligibilityTier.fullyEligible).having(
          (trace) => trace.challengeBypass,
          'bypass',
          ChallengeBypass.newMaterial,
        ),
      );
      expect(
        pipeline.rankedAs(
          state,
          meeting,
          facts: DecisionFacts(
            state,
            startedExercises: const {},
            offeredUpAndDown: {upAndDownShapeOf(followUp)},
          ),
        ),
        followUp,
      );
    },
  );

  test('the follow-up stays open after an untimed meeting', () {
    final state = learnerOwningOne();
    final meetingOutcome = played();
    expect(meetingOutcome.motorScore, isNull);

    play(state, meeting, meetingOutcome);

    expect(state.hasPlayed(unmet.materialId, HandConfiguration.right), isFalse);
    expect(
      traceOf(state, followUp, {meeting}),
      admittedAndRanked(EligibilityTier.fullyEligible),
    );
  });

  test('a timed follow-up ends it, well or badly', () {
    for (final (timing, pitch) in [(0.9, 0.95), (0.2, 0.6)]) {
      final state = learnerOwningOne();
      play(state, meeting, played());
      play(state, followUp, played(timing: timing, pitch: pitch));

      expect(
        state.hasPlayed(unmet.materialId, HandConfiguration.right),
        isTrue,
      );
      expect(
        traceOf(state, followUp, {meeting, followUp}).eligibility.code,
        timing > 0.5
            ? EligibilityReason.bandGeographyDemonstrated
            : EligibilityReason.bandExecutionFloor,
        reason: 'timing $timing',
      );
    }
  });

  test('a poor follow-up leaves a gentler way on', () {
    final state = learnerOwningOne();
    play(state, meeting, played());
    play(state, followUp, played(timing: 0.2, pitch: 0.6));

    expect(
      traceOf(state, gentler, {meeting, followUp}),
      admittedAndRanked(EligibilityTier.fullyEligible),
    );
  });

  test('an attempt that gives no timing keeps it, and the gentler way', () {
    final state = learnerOwningOne();
    play(state, meeting, played());
    play(state, followUp, played(started: false));

    expect(state.hasPlayed(unmet.materialId, HandConfiguration.right), isFalse);
    expect(
      traceOf(state, followUp, {meeting, followUp}).eligibility.tier,
      EligibilityTier.fullyEligible,
    );
    expect(
      traceOf(state, gentler, {meeting, followUp}),
      admittedAndRanked(EligibilityTier.fullyEligible),
    );
  });

  test('nothing beyond the gentlest shape at the entry tempo inherits it', () {
    final state = learnerOwningOne();
    play(state, meeting, played());
    final facts = DecisionFacts(state, startedExercises: {meeting});

    for (final exercise in [
      traversal(ExerciseDirection.upDown, tempoBpm: 96),
      traversal(ExerciseDirection.upDown, octaves: 2),
      traversal(ExerciseDirection.up, hands: HandConfiguration.together),
    ]) {
      expect(
        pipeline.eligibilityFor(state, exercise, facts: facts).code,
        isNot(EligibilityReason.bandExecutionMet),
        reason: '$exercise',
      );
    }
  });
}
