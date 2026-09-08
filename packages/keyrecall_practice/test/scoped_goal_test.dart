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

  test(
    'a narrow scope stays actionable for the players that broke it',
    () async {
      final scopes = {
        'scales': v1ScaleCatalog.take(5).toList(),
        'arpeggios': proofArpeggios.take(3).toList(),
        'mixed': <TechnicalMaterial>[
          ...v1ScaleCatalog.take(2),
          ...proofArpeggios.take(2),
        ],
        'one material': v1ScaleCatalog.take(1).toList(),
      };
      final players = {
        'true beginner': PlacementTier.beginner,
        'some experience': PlacementTier.someExperience,
        'advanced': PlacementTier.advanced,
      };

      for (final scope in scopes.entries) {
        for (final player in players.entries) {
          final where = '${scope.key} for a ${player.key}';
          final goal = PracticeGoal(
            id: 'SCOPED',
            targetMaterialIds: {
              for (final material in scope.value) material.materialId,
            },
          );
          final session = await PracticeSession.open(
            store: InMemoryPracticeStore(createdAt: t0),
            profile: alicePlacedAt(player.value),
            materials: scope.value,
            goal: goal,
          );

          final decision = await session.decideOutcome(at: t0.plusDays(0.5));
          expect(
            decision,
            isA<PresentedAttempt>(),
            reason: 'the first slot of a scoped sitting resolves, for $where',
          );
          expect(
            (decision as PresentedAttempt).exercise.material.materialId,
            isIn(goal.targetMaterialIds!),
            reason: 'and stays inside the scope, for $where',
          );
        }
      }
    },
  );

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
