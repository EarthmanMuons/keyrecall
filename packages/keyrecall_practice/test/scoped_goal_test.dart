import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('a scoped goal schedules only its resolved material envelope', () async {
    final goal = PracticeGoal(
      id: 'FIVE_SCALES',
      targetMaterialIds: {
        for (final material in fixtureMaterials.take(2)) material.materialId,
      },
    );

    final session = await PracticeSession.open(
      store: InMemoryPracticeStore(createdAt: t0),
      profile: alice,
      materials: fixtureMaterials,
      goal: goal,
    );

    final decision = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(decision, isA<PresentedAttempt>());
    expect(
      (decision as PresentedAttempt).exercise.material.materialId,
      isIn(goal.targetMaterialIds!),
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
