import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// What may be introduced now, which is a different question from what a
/// learner is working toward and from what they should play next.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());
  const config = v1SchedulerConfig;

  Exercise scale(
    String tonic,
    ScaleForm form, {
    HandConfiguration hands = HandConfiguration.right,
  }) => Exercise.linear(material: TechnicalMaterial(tonic, form), hands: hands);

  /// A learner whose competencies all sit at [mean], on the logit scale
  /// placement uses.
  LearnerState learnerAt(double mean) => LearnerState(
    competencies: {
      for (final competency in Competency.values)
        competency: CompetencyState(
          competency: competency,
          mean: mean,
          variance: 1.0,
          updatedAt: DateTime.utc(2026),
        ),
    },
  );

  /// Records that [count] major and natural-minor scales have been retrieved,
  /// spread over as many admission bands as the catalog offers.
  ///
  /// The ordinary base an altered minor form is introduced on top of. Tests
  /// about anything else give it to themselves so the form-introduction gate
  /// is not what they end up measuring.
  LearnerState withCoreBreadth(LearnerState state, {int count = 24}) {
    final core =
        [
          for (final material in allScales)
            if (coreForms.contains(material.form)) material,
        ]..sort(
          (a, b) =>
              admissionBandOf(a).index.compareTo(admissionBandOf(b).index),
        );

    for (final material in core.take(count)) {
      state
          .materialMemoryFor(material.materialId, v1PrototypeLearnerParams)
          .factualLastRetrievalAt = DateTime.utc(
        2026,
      );
    }
    return state;
  }

  /// The material question, asked of a learner this material is not new to.
  ///
  /// Whether a material may be met unguided the first time is a question about
  /// the rung rather than the material, and has its own group below.
  EligibilityDecision decide(LearnerState state, Exercise exercise) {
    state.materialMemoryFor(
      exercise.material.materialId,
      v1PrototypeLearnerParams,
    );
    return pipeline.eligibilityFor(state, exercise);
  }

  group('foundation material', () {
    test('is admissible to a rank beginner', () {
      final beginner = learnerAt(-2.0);

      for (final material in [
        TechnicalMaterial('C', ScaleForm.major),
        TechnicalMaterial('G', ScaleForm.major),
        TechnicalMaterial('F', ScaleForm.major),
        TechnicalMaterial('A', ScaleForm.naturalMinor),
        TechnicalMaterial('D', ScaleForm.naturalMinor),
      ]) {
        final decision = decide(
          beginner,
          Exercise.linear(material: material, hands: HandConfiguration.right),
        );

        expect(
          decision.tier,
          EligibilityTier.fullyEligible,
          reason: '${material.materialId} is where everybody starts',
        );
      }
    });

    test('includes the natural minor that minor topology comes from', () {
      // Requiring minor familiarity to earn the only material that produces
      // it would keep every minor scale outranked forever.
      expect(
        decide(learnerAt(-2.0), scale('A', ScaleForm.naturalMinor)).code,
        EligibilityReason.foundationMaterial,
      );
    });
  });

  group('later bands', () {
    test('wait for single-hand execution, and say so', () {
      final beginner = learnerAt(-1.0);
      final decision = decide(beginner, scale('Eb', ScaleForm.major));

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.bandExecutionFloor);
      expect(decision.reason, contains('INTERMEDIATE_KEYBOARD'));
    });

    test('open as execution rises', () {
      final material = TechnicalMaterial('Eb', ScaleForm.major);
      final exercise = Exercise.linear(
        material: material,
        hands: HandConfiguration.right,
      );

      expect(
        decide(learnerAt(0.0), exercise).tier,
        EligibilityTier.provisionallyEligible,
        reason: 'early transfer is met at 0.0, intermediate is not',
      );
      expect(
        decide(learnerAt(0.5), exercise).tier,
        EligibilityTier.fullyEligible,
      );
    });

    test('read the hand that is actually playing', () {
      final state = learnerAt(-1.0);
      state.competency(Competency.rhScaleExecution).mean = 1.0;

      expect(
        decide(state, scale('Bb', ScaleForm.major)).tier,
        EligibilityTier.fullyEligible,
      );
      expect(
        decide(
          state,
          scale('Bb', ScaleForm.major, hands: HandConfiguration.left),
        ).tier,
        EligibilityTier.provisionallyEligible,
        reason: 'the left hand has not earned it yet',
      );
    });
  });

  group('minor forms', () {
    test('harmonic minor waits for some minor topology', () {
      final none = withCoreBreadth(learnerAt(-1.0));
      final decision = decide(none, scale('A', ScaleForm.harmonicMinor));

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.minorTopologyPrerequisite);
    });

    test('any minor topology will do, not the same tonic', () {
      final state = withCoreBreadth(learnerAt(-1.0));
      state.competency(Competency.naturalMinorTopology).mean = 0.5;

      expect(
        decide(state, scale('A', ScaleForm.harmonicMinor)).tier,
        EligibilityTier.fullyEligible,
        reason: 'the curricula give no support for a per-key ladder',
      );
    });

    test('melodic minor waits for one of the other two', () {
      final state = withCoreBreadth(learnerAt(-1.0));
      final decision = decide(state, scale('A', ScaleForm.melodicMinor));

      expect(decision.code, EligibilityReason.melodicFormPrerequisite);

      state.competency(Competency.harmonicMinorTopology).mean = 0.5;
      expect(
        decide(state, scale('A', ScaleForm.melodicMinor)).tier,
        EligibilityTier.fullyEligible,
      );
    });
  });

  group('enlarging the vocabulary', () {
    Exercise harmonic() => scale('A', ScaleForm.harmonicMinor);
    Exercise melodic() => scale('A', ScaleForm.melodicMinor);

    /// A learner who can transfer, so only breadth is left to decide it.
    LearnerState transferable() {
      final state = learnerAt(0.0);
      state.competency(Competency.naturalMinorTopology).mean = 0.5;
      state.competency(Competency.harmonicMinorTopology).mean = 0.5;
      return state;
    }

    test('an altered minor form waits for a base of ordinary scales', () {
      final beginner = transferable();
      final decision = decide(beginner, harmonic());

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(
        decision.code,
        EligibilityReason.harmonicMinorRepertoireBreadth,
        reason:
            'able to transfer and still better served by settling what a '
            'scale is first',
      );
    });

    test('the base is retrievals, not presentations', () {
      final shown = transferable();
      for (final material in allScales) {
        if (!coreForms.contains(material.form)) continue;
        // Seen, and never once produced from memory.
        shown.materialMemoryFor(material.materialId, v1PrototypeLearnerParams);
      }

      expect(
        decide(shown, harmonic()).code,
        EligibilityReason.harmonicMinorRepertoireBreadth,
        reason: 'having been shown a scale is not having it',
      );
    });

    test('a wide enough base opens harmonic minor', () {
      final ready = withCoreBreadth(transferable());

      expect(decide(ready, harmonic()).tier, EligibilityTier.fullyEligible);
    });

    test('melodic minor asks for more of a base than harmonic minor', () {
      final between = withCoreBreadth(
        transferable(),
        count: config.eligibility.harmonicMinorCoreRetrievals,
      );

      expect(decide(between, harmonic()).tier, EligibilityTier.fullyEligible);
      expect(
        decide(between, melodic()).code,
        EligibilityReason.melodicMinorRepertoireBreadth,
        reason: 'two altered degrees in a form the convention does not use',
      );
    });

    test('a narrow base is not a broad one, however many scales', () {
      // Every retrieval in the easiest band, and nowhere else.
      final narrow = transferable();
      var given = 0;
      for (final material in allScales) {
        if (!coreForms.contains(material.form)) continue;
        if (admissionBandOf(material) != AdmissionBand.foundation) continue;
        narrow
            .materialMemoryFor(material.materialId, v1PrototypeLearnerParams)
            .factualLastRetrievalAt = DateTime.utc(
          2026,
        );
        given++;
      }

      expect(given, lessThan(config.eligibility.harmonicMinorCoreRetrievals));
      expect(
        decide(narrow, harmonic()).code,
        EligibilityReason.harmonicMinorRepertoireBreadth,
      );
    });

    test('it never asks a fluent learner to earn what they arrived with', () {
      final fluent = transferable();
      for (final competency in [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
      ]) {
        fluent.competency(competency).mean =
            config.eligibility.fluentExecutionFloor;
      }

      expect(
        decide(fluent, harmonic()).tier,
        EligibilityTier.fullyEligible,
        reason:
            'the rule keeps a beginner\'s vocabulary from outrunning their '
            'base, not everyone from what they already play',
      );
      expect(decide(fluent, melodic()).tier, EligibilityTier.fullyEligible);
    });

    test('it says nothing about major or natural minor', () {
      final beginner = transferable();

      for (final form in coreForms) {
        expect(
          decide(beginner, scale('A', form)).code,
          isNot(EligibilityReason.harmonicMinorRepertoireBreadth),
        );
      }
    });
  });

  group('hands together', () {
    test('still asks for both hands first, unchanged', () {
      final state = learnerAt(1.0);
      state.competency(Competency.lhScaleExecution).mean = -1.0;
      final strict = SchedulerPipeline(
        learner: const LearnerModel(),
        config: SchedulerConfig(
          modelVersion: 'test',
          eligibility: const EligibilityConfig(
            handTogetherCompetencyThreshold: 0.0,
            earlyTransferExecutionFloor: 0.0,
            intermediateExecutionFloor: 0.4,
            advancedExecutionFloor: 0.8,
            minorTopologyFloor: 0.0,
            harmonicMinorCoreRetrievals: 0,
            melodicMinorCoreRetrievals: 0,
            coreRetrievalBands: 0,
            fluentExecutionFloor: 1.0,
          ),
          safety: const SafetyConfig(maxSessionAttempts: 40),
          challenge: v1SchedulerConfig.challenge,
          diversity: v1SchedulerConfig.diversity,
          probe: v1SchedulerConfig.probe,
        ),
      );

      state.materialMemoryFor('C_MAJOR', v1PrototypeLearnerParams);
      final decision = strict.eligibilityFor(
        state,
        scale('C', ScaleForm.major, hands: HandConfiguration.together),
      );

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.handsTogetherPrerequisite);
    });
  });

  test('nothing is ever forbidden, only outranked', () {
    // Every rejection is provisional, so a learner with an unusual profile
    // still has something to play rather than an empty slot.
    final beginner = learnerAt(-3.0);

    for (final material in allScales) {
      final decision = decide(
        beginner,
        Exercise.linear(material: material, hands: HandConfiguration.right),
      );
      expect(
        decision.tier,
        anyOf(
          EligibilityTier.fullyEligible,
          EligibilityTier.provisionallyEligible,
        ),
        reason:
            'a third, harder tier would have to be confronted here rather '
            'than leaving a learner with an empty slot',
      );
    }
  });

  test('the band stands in for a fingering axis nothing measures', () {
    // B flat major introduces a right-hand pattern the learner has never
    // used; D major reuses the one they know from C major. Admission cannot
    // tell them apart, and this test is what would fail first if a
    // motor-family competency ever made that difference observable.
    final state = learnerAt(0.0);

    final newPattern = decide(state, scale('Bb', ScaleForm.major));
    final familiarPattern = decide(state, scale('D', ScaleForm.major));

    expect(newPattern.tier, familiarPattern.tier);
    expect(newPattern.code, familiarPattern.code);
    expect(
      admissionBandOf(TechnicalMaterial('Bb', ScaleForm.major)),
      admissionBandOf(TechnicalMaterial('D', ScaleForm.major)),
    );
  });

  group('material with no history here', () {
    test('may be introduced, but not from memory', () {
      final capable = learnerAt(2.0);
      final material = TechnicalMaterial('C', ScaleForm.major);

      final unguided = pipeline.eligibilityFor(
        capable,
        Exercise.linear(material: material, hands: HandConfiguration.right),
      );

      expect(unguided.tier, EligibilityTier.provisionallyEligible);
      expect(unguided.code, EligibilityReason.unseenMaterialRequiresCue);
    });

    test('is fully eligible at a rung that supplies it', () {
      final capable = learnerAt(2.0);

      for (final guidance in [
        GuidanceContext.notesPreviewedOnly,
        GuidanceContext.continuouslyCued,
      ]) {
        final decision = pipeline.eligibilityFor(
          capable,
          Exercise.linear(
            material: TechnicalMaterial('C', ScaleForm.major),
            hands: HandConfiguration.right,
            guidance: guidance,
          ),
        );

        expect(
          decision.tier,
          EligibilityTier.fullyEligible,
          reason: 'a cued first encounter is how unseen material enters',
        );
      }
    });

    test('says nothing about whether the learner knows the scale', () {
      // The rule reads the absence of history here, not an assumption about
      // the learner: a beginner and an expert are held back identically, and
      // one prior entry releases both.
      for (final mean in [-2.0, 2.0]) {
        final state = learnerAt(mean);
        final exercise = Exercise.linear(
          material: TechnicalMaterial('C', ScaleForm.major),
          hands: HandConfiguration.right,
        );

        expect(
          pipeline.eligibilityFor(state, exercise).code,
          EligibilityReason.unseenMaterialRequiresCue,
        );

        state.materialMemoryFor('C_MAJOR', v1PrototypeLearnerParams);
        expect(
          pipeline.eligibilityFor(state, exercise).code,
          isNot(EligibilityReason.unseenMaterialRequiresCue),
        );
      }
    });

    test('once history exists, ordinary rules decide the unguided rung', () {
      final beginner = learnerAt(-2.0);
      beginner.materialMemoryFor('B_MAJOR', v1PrototypeLearnerParams);

      final decision = pipeline.eligibilityFor(
        beginner,
        Exercise.linear(
          material: TechnicalMaterial('B', ScaleForm.major),
          hands: HandConfiguration.right,
        ),
      );

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.bandExecutionFloor);
    });
  });
}
