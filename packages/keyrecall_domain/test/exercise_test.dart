import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  const cMajor = TechnicalMaterial('C', ScaleForm.major);
  const fSharpHarmonicMinor = TechnicalMaterial('F#', ScaleForm.harmonicMinor);

  group('material identity', () {
    test('is the tonic and the form, and nothing about performance', () {
      expect(cMajor.materialId, 'C_MAJOR');
      expect(fSharpHarmonicMinor.materialId, 'F#_HARMONIC_MINOR');
      expect(cMajor, const TechnicalMaterial('C', ScaleForm.major));
      expect(
        cMajor,
        isNot(const TechnicalMaterial('C', ScaleForm.naturalMinor)),
      );
    });

    test('is shared across every way of playing the same scale', () {
      final ids = {
        for (final hands in HandConfiguration.values)
          for (final guidance in GuidanceContext.ladder)
            Exercise.linear(
              material: cMajor,
              hands: hands,
              guidance: guidance,
            ).material.materialId,
      };
      expect(ids, {'C_MAJOR'});
    });
  });

  group('structural Q', () {
    test('selects one topology competency from the scale form', () {
      for (final form in ScaleForm.values) {
        final exercise = Exercise.linear(
          material: TechnicalMaterial('C', form),
          hands: HandConfiguration.right,
        );
        expect(exercise.structuralQ.intersection(topologyCompetencies), {
          form.topologyCompetency,
        });
      }
    });

    test('selects hand competencies from the hand configuration', () {
      Set<Competency> qFor(HandConfiguration hands) =>
          Exercise.linear(material: cMajor, hands: hands).structuralQ;

      expect(
        qFor(HandConfiguration.right),
        contains(Competency.rhScaleExecution),
      );
      expect(
        qFor(HandConfiguration.right),
        isNot(contains(Competency.lhScaleExecution)),
      );
      expect(
        qFor(HandConfiguration.left),
        contains(Competency.lhScaleExecution),
      );
      expect(
        qFor(HandConfiguration.together),
        containsAll([
          Competency.rhScaleExecution,
          Competency.lhScaleExecution,
          Competency.handsTogetherCoordination,
        ]),
      );
      expect(
        qFor(HandConfiguration.right),
        isNot(contains(Competency.handsTogetherCoordination)),
      );
    });

    test('selects localized competencies from the motor opportunities', () {
      final single = Exercise.linear(
        material: cMajor,
        hands: HandConfiguration.right,
        octaves: 1,
        direction: ScaleDirection.up,
      );
      final wide = Exercise.linear(
        material: cMajor,
        hands: HandConfiguration.right,
        octaves: 2,
      );

      expect(single.structuralQ, contains(Competency.scalarCrossing));
      expect(
        single.structuralQ,
        isNot(contains(Competency.multiOctaveContinuation)),
      );
      expect(single.structuralQ, isNot(contains(Competency.directionReversal)));
      expect(
        wide.structuralQ,
        containsAll([
          Competency.multiOctaveContinuation,
          Competency.directionReversal,
        ]),
      );
    });

    test('is unaffected by guidance', () {
      final byGuidance = [
        for (final guidance in GuidanceContext.ladder)
          Exercise.linear(
            material: fSharpHarmonicMinor,
            hands: HandConfiguration.right,
            guidance: guidance,
          ).structuralQ,
      ];
      expect(byGuidance[1], byGuidance[0]);
      expect(byGuidance[2], byGuidance[0]);
      expect(byGuidance[0], contains(Competency.harmonicMinorTopology));
    });
  });

  group('exercise equality', () {
    test('distinguishes guidance but not object identity', () {
      final unguided = Exercise.linear(
        material: cMajor,
        hands: HandConfiguration.right,
      );
      final same = Exercise.linear(
        material: cMajor,
        hands: HandConfiguration.right,
      );
      final cued = unguided.withGuidance(GuidanceContext.continuouslyCued);

      expect(unguided, same);
      expect(unguided.hashCode, same.hashCode);
      expect(unguided, isNot(cued));
      expect(unguided.hasSameRealizationAs(cued), isTrue);
    });

    test('survives use as a map key', () {
      final byExercise = {
        Exercise.linear(material: cMajor, hands: HandConfiguration.right): 1,
      };
      expect(
        byExercise[Exercise.linear(
          material: cMajor,
          hands: HandConfiguration.right,
        )],
        1,
      );
    });

    test('withGuidance changes only the guidance', () {
      final original = Exercise.linear(
        material: cMajor,
        hands: HandConfiguration.together,
        octaves: 2,
        tempoBpm: 120,
      );
      final changed = original.withGuidance(GuidanceContext.notesPreviewedOnly);

      expect(changed.conditions, original.conditions);
      expect(changed.opportunities, original.opportunities);
      expect(changed.pattern, original.pattern);
      expect(changed.guidance, GuidanceContext.notesPreviewedOnly);
    });
  });

  group('stable identifiers', () {
    test('round-trip for every enum that persists one', () {
      for (final value in Competency.values) {
        expect(Competency.fromId(value.id), value);
      }
      for (final value in ScaleForm.values) {
        expect(ScaleForm.fromId(value.id), value);
      }
      for (final value in HandConfiguration.values) {
        expect(HandConfiguration.fromId(value.id), value);
      }
      for (final value in ScaleDirection.values) {
        expect(ScaleDirection.fromId(value.id), value);
      }
      for (final value in MotorOpportunity.values) {
        expect(MotorOpportunity.fromId(value.id), value);
      }
      for (final value in ExercisePattern.values) {
        expect(ExercisePattern.fromId(value.id), value);
      }
    });

    test('reject an unknown identifier loudly', () {
      expect(() => Competency.fromId('NOPE'), throwsArgumentError);
      expect(() => ScaleForm.fromId('NOPE'), throwsArgumentError);
    });
  });

  test('the competency channels partition the ontology', () {
    expect(
      motorCompetencies.union(topologyCompetencies),
      Competency.values.toSet(),
    );
    expect(motorCompetencies.intersection(topologyCompetencies), isEmpty);
    for (final competency in Competency.values) {
      expect(competency.isMotor, isNot(competency.isTopology));
    }
  });

  test('the hand-execution competencies pair with each other only', () {
    expect(Competency.rhScaleExecution.pairedHand, Competency.lhScaleExecution);
    expect(Competency.lhScaleExecution.pairedHand, Competency.rhScaleExecution);
    for (final competency in Competency.values) {
      if (competency == Competency.rhScaleExecution ||
          competency == Competency.lhScaleExecution) {
        continue;
      }
      expect(competency.pairedHand, isNull);
    }
  });

  test('the catalog covers every scale form', () {
    expect(
      v1ScaleCatalog.map((material) => material.form).toSet(),
      ScaleForm.values.toSet(),
    );
    expect(
      v1ScaleCatalog.map((material) => material.materialId).toSet(),
      hasLength(v1ScaleCatalog.length),
    );
  });
}
