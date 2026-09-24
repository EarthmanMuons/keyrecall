import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('every census scope resolves', () {
    for (final scope in AlteredFormScope.values) {
      final fixture = alteredFormFixture(scope);
      final resolution = PracticeScopeResolver().resolve(
        goal: fixture.goal,
        focus: fixture.focus,
        catalog: fixture.materials,
        instrument: InstrumentProfile(),
      );
      expect(resolution, isA<ValidPracticeScope>(), reason: scope.name);
      final targets = {
        for (final requirement
            in (resolution as ValidPracticeScope).scope.requirements)
          if (requirement.isTarget) requirement.material.materialId,
      };
      expect(targets, fixture.targetMaterialIds, reason: scope.name);
    }
  });

  test('an introduction records what the learner held', () async {
    final [run] = await runAlteredFormMatrix(
      arms: [AlteredFormArm.shipped],
      scopes: const [AlteredFormScope.broad],
      players: [PlayerArchetypes.intermediate],
      seeds: 1,
      slots: 40,
    );

    final harmonic = run.first(ScaleForm.harmonicMinor);
    expect(harmonic, isNotNull);
    expect(
      harmonic!.majorsRetrieved + harmonic.naturalMinorsRetrieved,
      greaterThan(0),
    );
  });

  test('a focus on one altered form reaches it rather than blocking', () async {
    // Its natural minor is covered by the first right-hand retrieval, and the
    // form then waits on that scale in the left hand and hands together.
    final [run] = await runAlteredFormMatrix(
      arms: [AlteredFormArm.shipped],
      scopes: const [AlteredFormScope.narrowAltered],
      players: [PlayerArchetypes.advanced],
      seeds: 1,
      slots: 30,
    );

    expect(run.first(ScaleForm.harmonicMinor), isNotNull);
    expect(run.terminal, isNot(AlteredFormTerminal.blocked));
    expect(run.liveSupportSelections, greaterThan(0));
  });
}
