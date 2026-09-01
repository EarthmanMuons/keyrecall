import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// A scoped goal narrows the catalog to where the scheduler can exhaust it;
/// see `docs/design/future-planning.md` section 4.9. Goals stay expressible so
/// simulation can measure that, and unrunnable until there is a floor.
void main() {
  test('a scoped goal cannot open a session', () async {
    final goal = PracticeGoal(
      id: 'FIVE_SCALES',
      targetMaterialIds: {
        for (final material in allScales.take(5)) material.materialId,
      },
    );

    await expectLater(
      PracticeSession.open(
        store: InMemoryPracticeStore(createdAt: t0),
        profile: alice,
        materials: fixtureMaterials,
        goal: goal,
      ),
      throwsUnsupportedError,
    );
  });

  test('general fluency does', () async {
    final session = await PracticeSession.open(
      store: InMemoryPracticeStore(createdAt: t0),
      profile: alice,
      materials: fixtureMaterials,
      goal: PracticeGoal.generalFluency,
    );

    expect(await session.decide(at: t0.plusDays(0.5)), isNotNull);
  });
}
