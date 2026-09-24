import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What may be introduced now, which is a different question from what a
/// learner is working toward and from what they should play next.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());
  const config = v1SchedulerConfig;

  /// One octave, so the octave-span prerequisite is never what a test about
  /// material admission ends up measuring. It has its own group below.
  Exercise scale(
    String tonic,
    ScaleForm form, {
    HandConfiguration hands = HandConfiguration.right,
    int octaves = 1,
  }) => Exercise.linear(
    material: TechnicalMaterial(tonic, form),
    hands: hands,
    octaves: octaves,
  );

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

  /// Marks [competency] as having received evidence.
  ///
  /// What separates a mean somebody demonstrated from one placement seeded
  /// from their own account of themselves.
  LearnerState observing(LearnerState state, Iterable<Competency> which) {
    for (final competency in which) {
      state.competency(competency).lastEvidenceAt = t0;
    }
    return state;
  }

  /// Records that [hands] has played [material] through one octave and
  /// retrieved it.
  ///
  /// Both halves, because the gates read both: memory says a scale was
  /// retrieved and execution residuals say which hand was playing.
  LearnerState retrieving(
    LearnerState state,
    TechnicalMaterial material, {
    HandConfiguration hands = HandConfiguration.right,
  }) {
    state
            .materialMemoryFor(material.materialId, learnerParams)
            .factualLastRetrievalAt =
        t0;
    state.materialExecutionFor(
        (material.materialId, hands, HandMotion.parallel),
        t0,
        learnerParams,
        familyId: material.familyId,
      )
      ..lastEvidenceAt = t0
      ..demonstratedTempoByOctaves[1] = 60;
    return state;
  }

  /// Records that [hands] has played and retrieved [count] major and
  /// natural-minor scales, spread over as many admission bands as the catalog
  /// offers.
  LearnerState withHandBreadth(
    LearnerState state, {
    int count = 24,
    HandConfiguration hands = HandConfiguration.right,
  }) {
    final core =
        [
          for (final material in allScales)
            if (coreForms.contains(material.form)) material,
        ]..sort(
          (a, b) =>
              admissionBandOf(a).index.compareTo(admissionBandOf(b).index),
        );

    for (final material in core.take(count)) {
      retrieving(state, material, hands: hands);
    }
    return state;
  }

  /// A learner with the ordinary-form foundation an altered form asks for.
  LearnerState withFoundation(LearnerState state, {int count = 24}) {
    observing(state, [
      Competency.rhScaleExecution,
      Competency.lhScaleExecution,
      Competency.handsTogetherCoordination,
    ]);
    for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
      withHandBreadth(state, count: count, hands: hands);
    }
    return state;
  }

  /// The material question, asked of a learner this material is not new to.
  ///
  /// Whether a material may be met unguided the first time is a question about
  /// the rung rather than the material, and has its own group below.
  EligibilityDecision decide(LearnerState state, Exercise exercise) {
    state.materialMemoryFor(exercise.material.materialId, learnerParams);
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
          Exercise.linear(
            material: material,
            hands: HandConfiguration.right,
            octaves: 1,
          ),
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
        octaves: 1,
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
      final none = withFoundation(learnerAt(-1.0));
      final decision = decide(none, scale('A', ScaleForm.harmonicMinor));

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.minorTopologyPrerequisite);
    });

    test('any minor topology will do, not the same tonic', () {
      final state = withFoundation(learnerAt(-1.0));
      state.competency(Competency.naturalMinorTopology).mean = 0.5;

      expect(
        decide(state, scale('A', ScaleForm.harmonicMinor)).tier,
        EligibilityTier.fullyEligible,
        reason: 'topology is a competency, and the tonic is the foundation\'s',
      );
    });

    test('melodic minor waits for one of the other two', () {
      final state = withFoundation(learnerAt(-1.0));
      final decision = decide(state, scale('A', ScaleForm.melodicMinor));

      expect(decision.code, EligibilityReason.melodicFormPrerequisite);

      state.competency(Competency.harmonicMinorTopology).mean = 0.5;
      expect(
        decide(state, scale('A', ScaleForm.melodicMinor)).tier,
        EligibilityTier.fullyEligible,
      );
    });
  });

  group('the foundation an altered minor form sits on', () {
    Exercise harmonic({HandConfiguration hands = HandConfiguration.right}) =>
        scale('A', ScaleForm.harmonicMinor, hands: hands);
    Exercise melodic() => scale('A', ScaleForm.melodicMinor);

    /// A learner who can transfer and has A natural minor in both hands, so
    /// only the phase is left to decide it.
    LearnerState transferable({bool knowingTheTonic = true}) {
      final state = learnerAt(0.0);
      state.competency(Competency.naturalMinorTopology).mean = 0.5;
      state.competency(Competency.harmonicMinorTopology).mean = 0.5;
      if (knowingTheTonic) {
        for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
          retrieving(
            state,
            TechnicalMaterial('A', ScaleForm.naturalMinor),
            hands: hands,
          );
        }
      }
      return state;
    }

    test('a learner with nothing behind them waits for both hands', () {
      final decision = decide(transferable(), harmonic());

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.alteredFormHandsFoundation);
    });

    test('one observed hand is not both', () {
      final oneHand = observing(transferable(), [Competency.rhScaleExecution]);

      expect(
        decide(oneHand, harmonic()).code,
        EligibilityReason.alteredFormHandsFoundation,
        reason: 'a scale learned in one hand is not a scale learned',
      );
    });

    test('both hands separately still wait for hands together', () {
      final separate = observing(transferable(), [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
      ]);

      expect(
        decide(separate, harmonic()).code,
        EligibilityReason.alteredFormHandsTogetherFoundation,
        reason:
            'not because harmonic minor needs two hands, but because having '
            'put two together is what marks the phase it belongs to',
      );
    });

    test('the phase gate applies to one-hand candidates too', () {
      // Deliberate. The hands-together condition is a marker of where the
      // learner is in the curriculum, and a phase they have not reached is
      // not reached for right-hand work either.
      final separate = observing(transferable(), [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
      ]);

      for (final hands in HandConfiguration.values) {
        expect(
          decide(separate, harmonic(hands: hands)).code,
          EligibilityReason.alteredFormHandsTogetherFoundation,
          reason: hands.id,
        );
      }
    });

    test('breadth is asked of each hand, not of the profile', () {
      // The bug this replaced: twelve right-hand scales spoke for a left hand
      // that had played none of them, because memory is keyed by material and
      // never knew which hand was playing.
      final lopsided = observing(transferable(), [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
        Competency.handsTogetherCoordination,
      ]);
      withHandBreadth(lopsided, hands: HandConfiguration.right);

      expect(
        decide(lopsided, harmonic()).code,
        EligibilityReason.harmonicMinorRepertoireBreadth,
        reason: 'and the right hand having all of it does not settle it',
      );
    });

    test('the base is retrievals, not presentations', () {
      final shown = observing(transferable(), [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
        Competency.handsTogetherCoordination,
      ]);
      for (final material in allScales) {
        if (!coreForms.contains(material.form)) continue;
        // Seen and played by both hands, and never once produced from memory.
        shown.materialMemoryFor(material.materialId, learnerParams);
        for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
          shown
                  .materialExecutionFor(
                    (material.materialId, hands, HandMotion.parallel),
                    t0,
                    learnerParams,
                    familyId: material.familyId,
                  )
                  .lastEvidenceAt =
              t0;
        }
      }

      expect(
        decide(shown, harmonic()).code,
        EligibilityReason.harmonicMinorRepertoireBreadth,
        reason: 'having been shown a scale is not having it',
      );
    });

    test('a wide enough base opens harmonic minor', () {
      expect(
        decide(withFoundation(transferable()), harmonic()).tier,
        EligibilityTier.fullyEligible,
      );
    });

    test('melodic minor asks for more of a base than harmonic minor', () {
      final between = withFoundation(
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
      // Every scale from one band, which the early-transfer band has enough of
      // to clear the count on its own. Breadth is the point, so it does not.
      final narrow = observing(transferable(knowingTheTonic: false), [
        Competency.rhScaleExecution,
        Competency.lhScaleExecution,
        Competency.handsTogetherCoordination,
      ]);
      var given = 0;
      for (final material in allScales) {
        if (!coreForms.contains(material.form)) continue;
        if (admissionBandOf(material) != AdmissionBand.earlyTransfer) continue;
        narrow
                .materialMemoryFor(material.materialId, learnerParams)
                .factualLastRetrievalAt =
            t0;
        for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
          narrow
                  .materialExecutionFor(
                    (material.materialId, hands, HandMotion.parallel),
                    t0,
                    learnerParams,
                    familyId: material.familyId,
                  )
                  .lastEvidenceAt =
              t0;
        }
        given++;
      }

      expect(
        given,
        greaterThanOrEqualTo(config.eligibility.harmonicMinorCoreRetrievals),
        reason: 'enough of them to clear the count',
      );
      expect(
        decide(narrow, scale('E', ScaleForm.harmonicMinor)).code,
        EligibilityReason.harmonicMinorRepertoireBreadth,
        reason: 'and all of them in one band',
      );
    });

    test('a self-report is not the fluency the waiver is for', () {
      // The bug this replaced, and the reason the waiver reads observation as
      // well as the mean: placement seeds means from what somebody said about
      // themselves, so advanced onboarding alone opened every altered form
      // before a single note was played.
      final claimed = const LearnerModel().placementState(
        PlacementTier.advanced,
        at: t0,
      );

      expect(
        claimed.competency(Competency.handsTogetherCoordination).mean,
        greaterThanOrEqualTo(config.eligibility.fluentHandsTogetherFloor),
        reason: 'the mean alone would have waived it',
      );
      expect(
        decide(claimed, harmonic()).tier,
        EligibilityTier.provisionallyEligible,
      );
    });

    test('fluent hands-together playing waives the foundation', () {
      // The escape hatch, and the only one. Somebody playing a scale hands
      // together this well is playing it with two hands that each work, so
      // asking them for six ordinary scales in each hand first would be an
      // artificial path through material they have just shown.
      final fluent = retrieving(
        observing(transferable(), [Competency.handsTogetherCoordination]),
        TechnicalMaterial('A', ScaleForm.naturalMinor),
      );
      fluent.competency(Competency.handsTogetherCoordination).mean =
          config.eligibility.fluentHandsTogetherFloor;

      expect(decide(fluent, harmonic()).tier, EligibilityTier.fullyEligible);
      expect(decide(fluent, melodic()).tier, EligibilityTier.fullyEligible);
    });

    test('one fluent hand is not enough to skip the phase', () {
      // A single channel, and not the one that defines the phase being
      // skipped. Waiving a phase without observing its defining dimension
      // would be internally inconsistent.
      final oneHand = observing(transferable(), [Competency.rhScaleExecution]);
      oneHand.competency(Competency.rhScaleExecution).mean =
          config.eligibility.fluentHandsTogetherFloor;

      expect(
        decide(oneHand, harmonic()).tier,
        EligibilityTier.provisionallyEligible,
      );
    });

    test('exposure to hands-together work is not fluency at it', () {
      // One ragged first attempt proves somebody has been in the two-hand
      // regime, which is what the ordinary path asks for. It does not prove
      // they are past the phase, which is what the waiver asks for.
      final exposed = observing(transferable(), [
        Competency.handsTogetherCoordination,
      ]);
      exposed.competency(Competency.handsTogetherCoordination).mean =
          config.eligibility.fluentHandsTogetherFloor - 0.5;

      expect(
        decide(exposed, harmonic()).tier,
        EligibilityTier.provisionallyEligible,
      );
    });

    test('its own natural minor is what it builds on', () {
      final state = withFoundation(transferable());
      state
          .materialExecution[(
            TechnicalMaterial('A', ScaleForm.naturalMinor).materialId,
            HandConfiguration.right,
            HandMotion.parallel,
          )]!
          .demonstratedTempoByOctaves
          .clear();

      expect(
        decide(state, harmonic()).code,
        EligibilityReason.materialProgressionPrerequisite,
      );
      expect(
        decide(state, harmonic(hands: HandConfiguration.left)).tier,
        EligibilityTier.fullyEligible,
        reason: 'the left hand has played it',
      );
    });

    group('its own natural minor', () {
      final dNatural = TechnicalMaterial('D', ScaleForm.naturalMinor);
      Exercise dHarmonic(HandConfiguration hands) =>
          scale('D', ScaleForm.harmonicMinor, hands: hands);

      /// The phase behind the learner, D natural minor played by both hands
      /// and retrieved by the right alone.
      LearnerState rightRetrievedLeftCued() {
        final state = withFoundation(transferable());
        state.materialMemory.remove(dNatural.materialId);
        for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
          retrieving(state, dNatural, hands: hands);
        }
        return state;
      }

      /// Every core scale retrieved by both hands, except D natural minor by
      /// the left.
      final rightRetrieved = {
        for (final material in allScales)
          if (coreForms.contains(material.form))
            for (final hand in Hand.values) (material.materialId, hand),
      }..remove((dNatural.materialId, Hand.left));

      EligibilityDecision decideWith(
        LearnerState state,
        Exercise exercise,
        Set<(String, Hand)> retrieved,
      ) {
        state.materialMemoryFor(exercise.material.materialId, learnerParams);
        return pipeline.eligibilityFor(
          state,
          exercise,
          facts: DecisionFacts(state, retrievedMaterialHands: retrieved),
        );
      }

      test('is asked of the hand that retrieved it, not of the material', () {
        final state = rightRetrievedLeftCued();
        final retrieved = rightRetrieved;

        expect(
          decideWith(state, dHarmonic(HandConfiguration.right), retrieved).tier,
          EligibilityTier.fullyEligible,
        );
        expect(
          decideWith(state, dHarmonic(HandConfiguration.left), retrieved).code,
          EligibilityReason.alteredFormNaturalMinorFoundation,
          reason: 'memory knows D natural minor was retrieved, not by whom',
        );
        expect(
          decideWith(
            state,
            dHarmonic(HandConfiguration.together),
            retrieved,
          ).code,
          EligibilityReason.alteredFormNaturalMinorFoundation,
        );
      });

      test('and breadth is counted the same way', () {
        // Both hands played every core scale, and memory says each was
        // retrieved. Only the right hand's retrievals were its own.
        final state = withFoundation(transferable());
        final rightOnly = {
          for (final (materialId, hand) in rightRetrieved)
            if (hand == Hand.right) (materialId, hand),
          (dNatural.materialId, Hand.left),
        };

        expect(
          decideWith(state, dHarmonic(HandConfiguration.left), rightOnly).code,
          EligibilityReason.harmonicMinorRepertoireBreadth,
        );
      });

      test('is a barrier, not the generic prerequisite\'s rank penalty', () {
        // The declaration is the same one scope resolution reads, and the
        // generic reading of it is satisfied: the hand has demonstrated the
        // scale. Played is not known, and the altered form is not introduced.
        final state = rightRetrievedLeftCued();
        final left = dHarmonic(HandConfiguration.left);

        expect(
          state
              .materialExecution[(
                dNatural.materialId,
                HandConfiguration.left,
                HandMotion.parallel,
              )]!
              .demonstratedTempoByOctaves,
          isNotEmpty,
        );
        expect(
          pipeline.isIntroducible(
            state,
            left,
            facts: DecisionFacts(state, retrievedMaterialHands: rightRetrieved),
          ),
          isFalse,
        );
      });

      test('is not lifted by the waiver', () {
        final fluent = observing(transferable(), [
          Competency.handsTogetherCoordination,
        ]);
        fluent.competency(Competency.handsTogetherCoordination).mean =
            config.eligibility.fluentHandsTogetherFloor;

        expect(
          decideWith(fluent, dHarmonic(HandConfiguration.right), const {}).code,
          EligibilityReason.alteredFormNaturalMinorFoundation,
        );
      });

      test('can be switched off for a census', () {
        final off = SchedulerPipeline(
          learner: const LearnerModel(),
          config: config.withEligibility(
            config.eligibility.withAlteredFormPolicy(
              sameTonicAlteredFormPrerequisite: false,
            ),
          ),
        );
        final state = rightRetrievedLeftCued();
        final left = dHarmonic(HandConfiguration.left);
        state.materialMemoryFor(left.material.materialId, learnerParams);

        expect(
          off
              .eligibilityFor(
                state,
                left,
                facts: DecisionFacts(state, retrievedMaterialHands: const {}),
              )
              .code,
          isNot(EligibilityReason.alteredFormNaturalMinorFoundation),
        );
      });
    });

    test('it says nothing about major or natural minor', () {
      for (final form in coreForms) {
        expect(
          decide(transferable(), scale('A', form)).code,
          isNot(EligibilityReason.harmonicMinorRepertoireBreadth),
        );
      }
    });
  });

  group('octave span', () {
    test('two octaves wait for one, and say so', () {
      final decision = decide(
        learnerAt(-1.0),
        scale('C', ScaleForm.major, octaves: 2),
      );

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.octaveSpanPrerequisite);
    });

    test('one octave of the same material is untouched', () {
      expect(
        decide(learnerAt(-1.0), scale('C', ScaleForm.major)).tier,
        EligibilityTier.fullyEligible,
        reason: 'the span is the condition under question, not the scale',
      );
    });

    test('it opens as ordinary one-octave work raises execution', () {
      expect(
        decide(
          learnerAt(config.eligibility.multiOctaveExecutionFloor),
          scale('C', ScaleForm.major, octaves: 2),
        ).tier,
        EligibilityTier.fullyEligible,
      );
    });

    test('a learner who arrived able to play never meets it', () {
      expect(
        decide(learnerAt(0.0), scale('Db', ScaleForm.major, octaves: 2)).code,
        isNot(EligibilityReason.octaveSpanPrerequisite),
        reason:
            'placement puts some experience at zero, and the floor is '
            'below it',
      );
    });

    test('it reads the hand that is actually playing', () {
      final state = learnerAt(1.0);
      state.competency(Competency.lhScaleExecution).mean = -2.0;

      expect(
        decide(state, scale('C', ScaleForm.major, octaves: 2)).tier,
        EligibilityTier.fullyEligible,
      );
      expect(
        decide(
          state,
          scale(
            'C',
            ScaleForm.major,
            hands: HandConfiguration.left,
            octaves: 2,
          ),
        ).code,
        EligibilityReason.octaveSpanPrerequisite,
      );
    });
  });

  group('hands together', () {
    /// Record that [hands] has managed C major at [span].
    void demonstrated(LearnerState state, HandConfiguration hands, int span) {
      state.materialExecutionFor(
          ('C_MAJOR', hands, HandMotion.parallel),
          t0,
          learnerParams,
          familyId: TechnicalMaterial.scaleFamilyId,
        )
        ..demonstrate(octaves: span, tempoBpm: 60)
        ..readyForHandsTogether(octaves: span, tempoBpm: 60)
        ..lastEvidenceAt = t0;
    }

    Exercise together({int octaves = 1}) => scale(
      'C',
      ScaleForm.major,
      hands: HandConfiguration.together,
      octaves: octaves,
    );

    test('still asks for both hands first', () {
      // Fluent by every general measure, and still asked to play the scale
      // with each hand before playing it with both.
      final state = learnerAt(1.0);
      state.materialMemoryFor('C_MAJOR', learnerParams);
      demonstrated(state, HandConfiguration.right, 1);

      final decision = pipeline.eligibilityFor(state, together());

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.handsTogetherPrerequisite);
    });

    test('both hands on the material is the whole prerequisite', () {
      // Weak by every general measure, and admitted anyway: what qualifies
      // somebody to try playing a scale with both hands is having played it
      // with each. Coordination is an early skill, not a reward for fluency.
      final state = learnerAt(-1.0);
      state.materialMemoryFor('C_MAJOR', learnerParams);
      demonstrated(state, HandConfiguration.right, 1);
      demonstrated(state, HandConfiguration.left, 1);

      expect(
        pipeline.eligibilityFor(state, together()).tier,
        EligibilityTier.fullyEligible,
      );
    });

    test('the prerequisite is asked at the span being played', () {
      final state = learnerAt(1.0);
      state.materialMemoryFor('C_MAJOR', learnerParams);
      demonstrated(state, HandConfiguration.right, 1);
      demonstrated(state, HandConfiguration.left, 1);

      expect(
        pipeline.eligibilityFor(state, together(octaves: 2)).code,
        EligibilityReason.handsTogetherPrerequisite,
        reason: 'neither hand has managed two octaves of it alone',
      );
    });

    test('once hands together is established it goes on through its own '
        'record', () {
      // One octave together is managed; two is an ordinary span step from
      // there, and does not send the learner back to prove each hand again.
      final state = learnerAt(-1.0);
      state.materialMemoryFor('C_MAJOR', learnerParams);
      demonstrated(state, HandConfiguration.together, 1);

      expect(
        pipeline.eligibilityFor(state, together(octaves: 2)).code,
        isNot(EligibilityReason.handsTogetherPrerequisite),
      );
    });
  });

  test('nothing is ever forbidden, only outranked', () {
    // Every rejection is provisional, so a learner with an unusual profile
    // still has something to play rather than an empty slot.
    final beginner = learnerAt(-3.0);

    for (final material in allScales) {
      final decision = decide(
        beginner,
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
        ),
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
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
        ),
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
            octaves: 1,
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
          octaves: 1,
        );

        expect(
          pipeline.eligibilityFor(state, exercise).code,
          EligibilityReason.unseenMaterialRequiresCue,
        );

        state.materialMemoryFor('C_MAJOR', learnerParams);
        expect(
          pipeline.eligibilityFor(state, exercise).code,
          isNot(EligibilityReason.unseenMaterialRequiresCue),
        );
      }
    });

    test('once history exists, ordinary rules decide the unguided rung', () {
      final beginner = learnerAt(-2.0);
      beginner.materialMemoryFor('B_MAJOR', learnerParams);

      final decision = pipeline.eligibilityFor(
        beginner,
        Exercise.linear(
          material: TechnicalMaterial('B', ScaleForm.major),
          hands: HandConfiguration.right,
          octaves: 1,
        ),
      );

      expect(decision.tier, EligibilityTier.provisionallyEligible);
      expect(decision.code, EligibilityReason.bandExecutionFloor);
    });
  });
}
