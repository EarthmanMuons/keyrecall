import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What an introduction is allowed to introduce.
///
/// The challenge band says a candidate is harder than would normally be
/// selected, and an introduction may override that: a learner has to meet
/// material before the model can estimate it. A prerequisite says something
/// else, that the material is not appropriate yet for a reason difficulty does
/// not capture, and an introduction has no business overriding that one.
///
/// So the exception is stratified. While the slot has something introducible
/// in a higher eligibility tier, nothing in a lower tier is reachable through
/// it at all, which keeps eligibility meaningful before ranking rather than
/// only within it.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());
  const config = v1SchedulerConfig;

  /// A learner at [mean] everywhere, with nothing yet seen.
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

  /// Whether the introduction exception would admit [exercise], given that
  /// [candidates] is everything on offer this slot.
  bool introduces(
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
      ChallengeBypass.newMaterial;

  /// Cued, because a first encounter is: material with no history here is
  /// held back from an unguided rung by a rule of its own, and that is not
  /// what these tests are about.
  Exercise introduction(
    String tonic, {
    int octaves = 1,
    double tempoBpm = 60,
    ScaleForm form = ScaleForm.major,
  }) => exerciseFor(
    TechnicalMaterial(tonic, form),
    octaves: octaves,
    tempoBpm: tempoBpm,
    guidance: GuidanceContext.continuouslyCued,
  );

  final foundation = introduction('C');
  // Provisional for a learner who has not earned two octaves.
  final twoOctaves = introduction('G', octaves: 2);

  test('a provisional introduction is unreachable while a fully eligible one '
      'is waiting', () {
    final state = learnerAt(-1.0);
    expect(
      pipeline.eligibilityFor(state, foundation).tier,
      EligibilityTier.fullyEligible,
    );
    expect(
      pipeline.eligibilityFor(state, twoOctaves).tier,
      EligibilityTier.provisionallyEligible,
    );

    final both = [foundation, twoOctaves];
    expect(introduces(state, foundation, both), isTrue);
    expect(
      introduces(state, twoOctaves, both),
      isFalse,
      reason: 'introducing something is not a licence to introduce anything',
    );
  });

  test('a provisional introduction rescues a slot with nothing better', () {
    // What provisional was always for: deferred while something better
    // exists, not forbidden.
    final state = learnerAt(-1.0);
    final onlyProvisional = [twoOctaves];

    expect(
      pipeline.introducibleTier(state, onlyProvisional),
      EligibilityTier.provisionallyEligible,
    );
    expect(introduces(state, twoOctaves, onlyProvisional), isTrue);
  });

  test('a fully eligible candidate below the ordinary band is still '
      'introduced', () {
    final state = learnerAt(-1.0);
    final p = pipeline.learner.predict(state, foundation, at: t0).overallP;

    expect(p, lessThan(config.challenge.pMin));
    expect(p, greaterThanOrEqualTo(config.challenge.pIntroductionMin));
    expect(
      introduces(state, foundation, [foundation]),
      isTrue,
      reason: 'difficulty is exactly what an introduction may bypass',
    );
  });

  test('the tier decides before the floor does', () {
    // The proof that the order of the two checks is the one intended. This
    // provisional candidate clears the introduction floor on its own, so the
    // floor would admit it; it is refused anyway, which only the tier can be
    // doing.
    final state = learnerAt(-1.0);

    expect(
      pipeline.learner.predict(state, twoOctaves, at: t0).overallP,
      greaterThanOrEqualTo(config.challenge.pIntroductionMin),
    );
    expect(introduces(state, twoOctaves, [twoOctaves]), isTrue);
    expect(introduces(state, twoOctaves, [foundation, twoOctaves]), isFalse);
  });

  test('nothing qualifying means nothing introduced', () {
    // Not "drop a tier until something clears the floor". A slot where the
    // appropriate material is too hard to introduce introduces nothing, and
    // the inappropriate material stays unreachable.
    //
    // Note that the sharper form of this, a provisional candidate above the
    // floor while the fully eligible one sits below it, is not constructible
    // from the catalog: every prerequisite here defers material that is also
    // harder, so the provisional candidate is never the easier one. The rule
    // is written to hold anyway rather than to rely on that staying true.
    final state = learnerAt(-2.0);
    final both = [foundation, twoOctaves];

    expect(
      pipeline.learner.predict(state, foundation, at: t0).overallP,
      lessThan(config.challenge.pIntroductionMin),
    );
    expect(introduces(state, foundation, both), isFalse);
    expect(introduces(state, twoOctaves, both), isFalse);
  });

  test('an altered form cannot be introduced before its foundation', () {
    // The distinction eligibility alone could not make. Provisional means
    // deferred while something better exists, which is right for an execution
    // condition and wrong for a curriculum phase: a device sitting introduced
    // harmonic and melodic minor six times before hands-together work
    // appeared once, every time through this exception.
    final state = learnerAt(-1.0);
    final harmonic = introduction('A', form: ScaleForm.harmonicMinor);

    expect(pipeline.isIntroducible(state, harmonic), isFalse);
    expect(introduces(state, harmonic, [harmonic]), isFalse);
    expect(
      pipeline.introducibleTier(state, [harmonic]),
      isNull,
      reason:
          'and it is not the stratum either, since it cannot be '
          'introduced at all',
    );
  });

  test('the barrier is asked directly, not read off the first refusal', () {
    // Straight from a device sitting: an unseen harmonic minor at an unguided
    // rung reports that its first encounter has to be cued, because that rule
    // refuses before the phase check is reached. Deciding a barrier from a
    // diagnostic that stops at the first answer is how this went wrong once
    // already.
    final state = learnerAt(-1.0);
    final unguided = exerciseFor(
      TechnicalMaterial('A', ScaleForm.harmonicMinor),
      octaves: 1,
      guidance: GuidanceContext.unguided,
    );

    expect(
      pipeline.eligibilityFor(state, unguided).code,
      EligibilityReason.unseenMaterialRequiresCue,
      reason: 'something else refuses it before the phase check is reached',
    );
    expect(pipeline.isIntroducible(state, unguided), isFalse);
  });

  test('a foundation met opens introduction again', () {
    final ready = learnerAt(0.0);
    for (final competency in [
      Competency.rhScaleExecution,
      Competency.lhScaleExecution,
      Competency.handsTogetherCoordination,
    ]) {
      ready.competency(competency).lastEvidenceAt = t0;
    }
    ready.competency(Competency.handsTogetherCoordination).mean =
        v1SchedulerConfig.eligibility.fluentHandsTogetherFloor;

    expect(
      pipeline.isIntroducible(
        ready,
        introduction('A', form: ScaleForm.harmonicMinor),
      ),
      isTrue,
      reason: 'the waiver is a way past the phase, not past the barrier only',
    );
  });

  test('ordinary challenge admission is untouched', () {
    // Material with history is not an introduction, so none of this applies
    // to it however it ranks.
    final state = learnerAt(1.0);
    state.materialMemoryFor(
      foundation.material.materialId,
      v1PrototypeLearnerParams,
    );

    expect(introduces(state, foundation, [foundation]), isFalse);
    expect(
      pipeline.introducibleTier(state, [foundation]),
      isNull,
      reason: 'nothing is left to introduce',
    );
  });
}
