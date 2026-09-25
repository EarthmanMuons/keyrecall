import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

void main() {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];

  ResolvedPracticeScope resolved(String goalId) =>
      (PracticeScopeResolver().resolve(
                goal: supportedGoals[goalId]!,
                focus: PracticeFocus.unrestricted,
                catalog: catalog,
                instrument: InstrumentProfile(),
              )
              as ValidPracticeScope)
          .scope;

  Set<String> tonicsOf(ResolvedPracticeScope scope, ScaleForm form) => {
    for (final requirement in scope.requirements)
      if (requirement.material.scaleForm == form) requirement.material.tonic,
  };

  test('every goal resolves over the production catalog', () {
    for (final goalId in supportedGoals.keys) {
      expect(
        PracticePlan(goalId: goalId).resolve(catalog),
        isA<ResolvedPlan>(),
        reason: goalId,
      );
      expect(resolved(goalId).requirements, isNotEmpty, reason: goalId);
    }
  });

  test('the finite goals are from memory, and general technique is not', () {
    for (final goalId in ['FOUNDATIONS', 'KEY_FLUENCY_24']) {
      expect(
        {
          for (final requirement in resolved(goalId).requirements)
            requirement.requirement.retrieval,
        },
        {CoverageRetrieval.unguided},
        reason: goalId,
      );
    }
    expect(
      {
        for (final requirement in resolved('GENERAL_FLUENCY').requirements)
          requirement.requirement.retrieval,
      },
      {CoverageRetrieval.observed},
    );
  });

  group('Foundations', () {
    final scope = resolved('FOUNDATIONS');

    test('is ten scales in each hand, with nothing held as support', () {
      expect(tonicsOf(scope, ScaleForm.major), {'C', 'G', 'D', 'A', 'F', 'Bb'});
      expect(tonicsOf(scope, ScaleForm.naturalMinor), {'A', 'E', 'D', 'G'});
      expect(scope.targetRequirementIds, hasLength(20));
      expect(scope.supportRequirementIds, isEmpty);
    });

    test('asks for one octave, up and down, in a single hand', () {
      for (final requirement in scope.requirements) {
        expect(requirement.targetCandidates, isNotEmpty);
        for (final exercise in requirement.targetCandidates) {
          expect(exercise.conditions.hands, isNot(HandConfiguration.together));
          expect(exercise.conditions.octaves, 1);
          expect(exercise.conditions.direction, ExerciseDirection.upDown);
        }
      }
    });

    test('spans both early bands', () {
      expect(
        {
          for (final requirement in scope.requirements)
            admissionBandOf(requirement.material),
        },
        {AdmissionBand.foundation, AdmissionBand.earlyTransfer},
      );
    });
  });

  group('24-key fluency', () {
    final scope = resolved('KEY_FLUENCY_24');
    final scales = [
      for (final requirement in scope.requirements)
        if (requirement.material is ScaleMaterial) requirement,
    ];
    final arpeggios = [
      for (final requirement in scope.requirements)
        if (requirement.material is ArpeggioMaterial) requirement,
    ];

    test('is version 2, which added the arpeggios', () {
      expect(keyFluencyCurriculum.version, '2');
    });

    test('is every major and minor key as a scale and an arpeggio', () {
      expect(tonicsOf(scope, ScaleForm.major), hasLength(12));
      expect(tonicsOf(scope, ScaleForm.naturalMinor), hasLength(12));
      expect(scales, hasLength(24));
      expect(arpeggios, hasLength(24));
      expect({
        for (final requirement in arpeggios) requirement.material,
      }, allRootPositionArpeggios.toSet());
      expect(scope.targetRequirementIds, hasLength(48));
      expect(scope.supportRequirementIds, isEmpty);
    });

    test('holds no altered minor form and no inversion', () {
      for (final requirement in scope.requirements) {
        final material = requirement.material;
        if (material is ScaleMaterial) {
          expect(coreForms, contains(material.form));
        } else {
          expect(
            (material as ArpeggioMaterial).inversion,
            ArpeggioInversion.root,
          );
        }
      }
    });

    test('asks for two octaves, up and down, hands together, of each', () {
      for (final requirement in scope.requirements) {
        expect(requirement.targetCandidates, isNotEmpty);
        for (final exercise in requirement.targetCandidates) {
          expect(exercise.conditions.hands, HandConfiguration.together);
          expect(exercise.conditions.octaves, 2);
          expect(exercise.conditions.direction, ExerciseDirection.upDown);
        }
      }
    });
  });
}
