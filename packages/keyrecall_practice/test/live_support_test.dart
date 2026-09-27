import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

void main() {
  final natural = TechnicalMaterial('D', ScaleForm.naturalMinor);
  final harmonic = TechnicalMaterial('D', ScaleForm.harmonicMinor);
  final scope =
      (PracticeScopeResolver().resolve(
                goal: PracticeGoal(
                  id: 'D_HARMONIC',
                  targetMaterialIds: {harmonic.materialId},
                ),
                focus: PracticeFocus.unrestricted,
                catalog: [natural, harmonic],
                instrument: InstrumentProfile(),
              )
              as ValidPracticeScope)
          .scope;
  final target = scope.requirements.singleWhere(
    (resolved) => resolved.isTarget,
  );
  final support = scope.requirements.singleWhere(
    (resolved) => resolved.isSupport,
  );

  /// The support covered and healthy, the target it prepares still due.
  EvaluatedPracticeScope evaluated() => EvaluatedPracticeScope(
    scope: scope,
    requirements: [
      RequirementState(
        resolved: target,
        coverage: RequirementCoverage.uncovered,
        workStatus: RequirementWorkStatus.due,
      ),
      RequirementState(
        resolved: support,
        coverage: RequirementCoverage.covered,
        workStatus: RequirementWorkStatus.healthy,
      ),
    ],
    coverage: const ScopeCoverage(coveredTargetIds: {}, targetCount: 1),
  );

  test('covered support stays offered while a dependent waits on it', () {
    final live = evaluated().liveSupport(
      (requirement) => requirement == target
          ? {(natural.materialId, HandConfiguration.left)}
          : const {},
    );

    expect(live.keys.single.resolved, support);
    expect(live.values.single, {HandConfiguration.left});
  });

  test('and retires once nothing waits on it', () {
    expect(evaluated().liveSupport((_) => const {}), isEmpty);
  });

  test('live support is offered only in the hands it is waited on in', () {
    final candidates = candidatesDueIn(
      scope,
      [target.requirement.id],
      {
        support.requirement.id: {HandConfiguration.left},
      },
    );
    final supportCandidates = [
      for (final exercise in candidates)
        if (exercise.material == natural) exercise,
    ];

    expect(supportCandidates, isNotEmpty);
    expect(
      supportCandidates.map((exercise) => exercise.conditions.hands).toSet(),
      {HandConfiguration.left},
    );
    expect(
      candidates.where((exercise) => exercise.material == harmonic),
      target.candidates,
    );
  });
}
