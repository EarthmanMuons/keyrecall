import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Offering a scale again rather than reaching for one that is not ready.
///
/// The slot a beginner reaches after meeting the foundation had exactly one
/// move available, and it was the wrong one. Everything already met was shut
/// out of admission entirely: out of the ordinary band, no rung established so
/// the guidance probe could not climb, the bootstrap probe days away, and the
/// observation probe counting supported attempts that a previewed introduction
/// resets. Introducing was all that was left, so introducing is what happened,
/// and once the appropriate material ran out it introduced the inappropriate.
///
/// So this is an admission path rather than a ranking preference. There was
/// nothing to prefer.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());

  LearnerState learnerAt(double mean) => LearnerState(
    competencies: {
      for (final competency in Competency.values)
        competency: CompetencyState(
          competency: competency,
          mean: mean,
          variance: 1.0,
          updatedAt: t0,
        ),
    },
  );

  Exercise foundation(
    String tonic, {
    GuidanceContext guidance = GuidanceContext.notesPreviewedOnly,
    int octaves = 1,
  }) => exerciseFor(
    TechnicalMaterial(tonic, ScaleForm.major),
    octaves: octaves,
    guidance: guidance,
  );

  /// Records that [tonic] has been met by both hands, and retrieved when
  /// asked.
  void meet(LearnerState state, String tonic, {bool retrieved = false}) {
    final memory = state.materialMemoryFor(
      '${tonic}_MAJOR',
      v1PrototypeLearnerParams,
    );
    if (retrieved) memory.factualLastRetrievalAt = t0;
    // Both hands, because a hand that has never played the scale is an
    // introduction of its own and would take the slot ahead of this.
    for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
      state
              .materialExecutionFor(
                ('${tonic}_MAJOR', hands, HandMotion.parallel),
                t0,
                v1PrototypeLearnerParams,
              )
              .lastEvidenceAt =
          t0;
    }
  }

  /// Whether the consolidation exception admits [exercise], given everything
  /// on offer this slot.
  bool consolidates(
    LearnerState state,
    Exercise exercise,
    List<Exercise> candidates,
  ) =>
      pipeline.challengeBypassFor(
        state: state,
        exercise: exercise,
        prediction: pipeline.learner.predict(state, exercise, at: t0),
        at: t0,
        override: null,
        recoveryTarget: null,
        tempoProbe: null,
        supportedAttempts: 0,
        eligibility: pipeline.eligibilityFor(state, exercise).tier,
        introducibleTier: pipeline.introducibleTier(state, candidates),
      ) ==
      ChallengeBypass.consolidation;

  test('a scale met and not yet retrieved is offered again', () {
    final state = learnerAt(-1.0);
    meet(state, 'C');

    expect(consolidates(state, foundation('C'), [foundation('C')]), isTrue);
  });

  test('something appropriate left to introduce comes first', () {
    // Step one of the ordering: while the slot can still introduce material a
    // learner is ready for, it should.
    final state = learnerAt(-1.0);
    meet(state, 'C');

    expect(
      consolidates(state, foundation('C'), [foundation('C'), foundation('G')]),
      isFalse,
      reason: 'G major is unseen, fully eligible, and not yet met',
    );
  });

  test('a scale already retrieved stops suppressing novelty', () {
    // The other end of it. Consolidation is unfinished business, not a reason
    // to keep somebody on five scales forever.
    final state = learnerAt(-1.0);
    meet(state, 'C', retrieved: true);

    expect(consolidates(state, foundation('C'), [foundation('C')]), isFalse);
  });

  test('it offers the previewed rung and no other', () {
    // A cued repeat cannot turn a scale that has been shown into one that has
    // been produced, and an unguided one hands out independence that is meant
    // to be earned: failing every retrieval would become a way to be asked
    // harder questions.
    final state = learnerAt(-1.0);
    meet(state, 'C');

    for (final guidance in [
      GuidanceContext.continuouslyCued,
      GuidanceContext.unguided,
    ]) {
      expect(
        consolidates(state, foundation('C', guidance: guidance), [
          foundation('C'),
        ]),
        isFalse,
        reason: 'independence ${guidance.independence}',
      );
    }
  });

  test('it consolidates at the tier it is on, not below it', () {
    // Two octaves of a met scale is still a way of playing it the learner has
    // not earned, so it is not what offering the scale again means.
    final state = learnerAt(-1.0);
    meet(state, 'C');
    final wide = foundation('C', octaves: 2);

    expect(
      pipeline.eligibilityFor(state, wide).tier,
      EligibilityTier.provisionallyEligible,
    );
    expect(consolidates(state, wide, [wide]), isFalse);
  });

  test('recovery still comes first', () {
    // Something that just went wrong matters more than something that has not
    // been finished, and the recovery context is exclusive besides.
    final state = learnerAt(-1.0);
    meet(state, 'C');
    final target = foundation('C', guidance: GuidanceContext.continuouslyCued);

    expect(
      pipeline.challengeBypassFor(
        state: state,
        exercise: foundation('C'),
        prediction: pipeline.learner.predict(state, foundation('C'), at: t0),
        at: t0,
        override: null,
        recoveryTarget: target,
        tempoProbe: null,
        supportedAttempts: 0,
        eligibility: pipeline.eligibilityFor(state, foundation('C')).tier,
        introducibleTier: null,
      ),
      isNull,
      reason: 'a recovery context refuses everything but its target',
    );
  });
}
