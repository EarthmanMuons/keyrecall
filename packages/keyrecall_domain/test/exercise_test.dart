import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final cMajor = TechnicalMaterial('C', ScaleForm.major);
  final fSharpHarmonicMinor = TechnicalMaterial('F#', ScaleForm.harmonicMinor);

  group('material identity', () {
    test('is the tonic and the form, and nothing about performance', () {
      expect(cMajor.materialId, 'C_MAJOR');
      expect(fSharpHarmonicMinor.materialId, 'F#_HARMONIC_MINOR');
      expect(cMajor, TechnicalMaterial('C', ScaleForm.major));
      expect(cMajor, isNot(TechnicalMaterial('C', ScaleForm.naturalMinor)));
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

  group('tonic canonicalization', () {
    test('accepts the spellings the catalog uses', () {
      for (final tonic in ['C', 'F#', 'Bb', 'A', 'G#', 'Eb', 'Cb', 'B#']) {
        expect(
          TechnicalMaterial.isCanonicalTonic(tonic),
          isTrue,
          reason: tonic,
        );
        expect(TechnicalMaterial(tonic, ScaleForm.major).tonic, tonic);
      }
    });

    test('rejects anything that is not already canonical', () {
      // Each of these would otherwise become a separate material with its own
      // memory state, sharing nothing with the one it was meant to be.
      for (final tonic in [
        'f#',
        'F\u266f',
        ' F#',
        'F# ',
        'F##',
        'Fbb',
        'H',
        '',
        'F#m',
      ]) {
        expect(
          TechnicalMaterial.isCanonicalTonic(tonic),
          isFalse,
          reason: tonic,
        );
        expect(
          () => TechnicalMaterial(tonic, ScaleForm.major),
          throwsArgumentError,
          reason: tonic,
        );
      }
    });

    test('does not quietly repair input', () {
      // Normalizing here would hide the upstream bug that produced the bad
      // spelling. Parsing is a boundary concern, not a domain one.
      expect(
        () => TechnicalMaterial(' F# ', ScaleForm.major),
        throwsArgumentError,
      );
    });

    test('the catalog is canonical throughout', () {
      for (final material in v1ScaleCatalog) {
        expect(TechnicalMaterial.isCanonicalTonic(material.tonic), isTrue);
      }
    });
  });

  group('execution conditions', () {
    test('reject a span or tempo that cannot be played', () {
      ExecutionConditions withTempo(double tempoBpm) => ExecutionConditions(
        hands: HandConfiguration.right,
        tempoBpm: tempoBpm,
      );

      expect(() => withTempo(0), throwsArgumentError);
      expect(() => withTempo(-80), throwsArgumentError);
      expect(() => withTempo(double.nan), throwsArgumentError);
      expect(() => withTempo(double.infinity), throwsArgumentError);
      expect(
        () => ExecutionConditions(hands: HandConfiguration.right, octaves: 0),
        throwsArgumentError,
      );
    });

    test('default to the least-assumptive span, which is one octave', () {
      // A default is invisible policy. Two octaves carries a prerequisite of
      // its own, so defaulting to it would have every unspecified call site
      // quietly asking a harder question than it meant to, which is what it
      // did until this test existed.
      expect(ExecutionConditions(hands: HandConfiguration.right).octaves, 1);
      expect(
        Exercise.linear(
          material: TechnicalMaterial('C', ScaleForm.major),
          hands: HandConfiguration.right,
        ).conditions.octaves,
        1,
      );
    });

    test('one octave creates no multi-octave opportunity to be measured', () {
      expect(
        Exercise.linear(
          material: TechnicalMaterial('C', ScaleForm.major),
          hands: HandConfiguration.right,
        ).structuralQ,
        isNot(contains(Competency.multiOctaveContinuation)),
      );
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
    final channels = [
      motorCompetencies,
      topologyCompetencies,
      coordinationCompetencies,
    ];

    expect(
      channels.reduce((all, channel) => all.union(channel)),
      Competency.values.toSet(),
    );
    for (final competency in Competency.values) {
      expect(
        channels.where((channel) => channel.contains(competency)).length,
        1,
        reason: '\$competency belongs to one prediction channel',
      );
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

  group('key signatures', () {
    test('every catalog material has one', () {
      for (final material in allScales) {
        expect(
          () => keySignatureFifths(material),
          returnsNormally,
          reason: material.materialId,
        );
      }
    });

    test('a minor form takes its relative major signature', () {
      // The convention rather than a simplification: harmonic minor's raised
      // seventh is an alteration of the key, written where it occurs, so it
      // does not belong in the signature.
      for (final form in ScaleForm.values) {
        if (form == ScaleForm.major) continue;
        expect(
          keySignatureFifths(TechnicalMaterial('A', form)),
          0,
          reason: 'A minor is written like C major, in ${form.id}',
        );
        expect(keySignatureFifths(TechnicalMaterial('E', form)), 1);
      }
    });

    test('sharps are positive and flats negative', () {
      expect(keySignatureFifths(TechnicalMaterial('G', ScaleForm.major)), 1);
      expect(keySignatureFifths(TechnicalMaterial('F', ScaleForm.major)), -1);
      expect(keySignatureFifths(TechnicalMaterial('Db', ScaleForm.major)), -5);
    });

    test('a tonic nobody decided how to write is refused', () {
      expect(
        () => keySignatureFifths(TechnicalMaterial('D#', ScaleForm.major)),
        throwsArgumentError,
      );
    });
  });

  group('the catalog', () {
    test('supports every scale form, in every key', () {
      expect(
        allScales.map((material) => material.form).toSet(),
        ScaleForm.values.toSet(),
      );
      expect(allScales, hasLength(48));
      expect(
        allScales.map((material) => material.materialId).toSet(),
        hasLength(allScales.length),
      );
    });

    test('offers a subset of what it supports', () {
      final supported = allScales.map((material) => material.materialId);

      expect(
        v1ScaleCatalog.map((material) => material.materialId),
        everyElement(isIn(supported)),
      );
      expect(
        v1ScaleCatalog.length,
        lessThan(allScales.length),
        reason:
            'what a learner is offered is a judgment about the learner, '
            'and a narrower question than what the system can play',
      );
      expect(
        v1ScaleCatalog.map((material) => material.materialId).toSet(),
        hasLength(v1ScaleCatalog.length),
      );
    });

    test('has a canonical fingering for everything it supports', () {
      for (final material in allScales) {
        for (final hand in Hand.values) {
          expect(
            canonicalFingering(material, hand),
            isNotNull,
            reason: '${material.materialId} $hand',
          );
        }
      }
    });
  });
}
