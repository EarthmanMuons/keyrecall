import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('coverage and due state form independent dimensions', () {
    final scope = _scope();
    final states = <String, (RequirementCoverage, RequirementWorkStatus)>{
      'A': (RequirementCoverage.uncovered, RequirementWorkStatus.due),
      'B': (
        RequirementCoverage.uncovered,
        RequirementWorkStatus.notYetActionable,
      ),
      'C': (RequirementCoverage.covered, RequirementWorkStatus.due),
      'D': (RequirementCoverage.covered, RequirementWorkStatus.healthy),
    };
    final evaluator = PracticeScopeEvaluator(
      assess:
          ({
            required resolved,
            required state,
            required journal,
            required learner,
            required at,
          }) {
            final values = states[resolved.requirement.id]!;
            return RequirementState(
              resolved: resolved,
              coverage: values.$1,
              workStatus: values.$2,
            );
          },
    );

    final evaluated = evaluator.evaluate(
      scope: scope,
      state: learner.newState(at: t0),
      journal: AttemptJournal(
        JournalHeader(profileId: alice.id, createdAt: t0),
      ),
      learner: learner,
      at: t0,
    );

    expect(evaluated.coverage.coveredTargets, 2);
    expect(evaluated.coverage.targetCount, 4);
    expect(evaluated.coverage.isComplete, isFalse);
    expect(
      evaluated.dueRequirements.map((state) => state.resolved.requirement.id),
      ['A', 'C'],
    );
    expect(evaluated.isCaughtUp, isFalse);
  });

  test('an incomplete scope may still be caught up', () {
    final evaluator = PracticeScopeEvaluator(
      assess:
          ({
            required resolved,
            required state,
            required journal,
            required learner,
            required at,
          }) => RequirementState(
            resolved: resolved,
            coverage: RequirementCoverage.uncovered,
            workStatus: RequirementWorkStatus.notYetActionable,
          ),
    );

    final evaluated = evaluator.evaluate(
      scope: _scope(),
      state: learner.newState(at: t0),
      journal: AttemptJournal(
        JournalHeader(profileId: alice.id, createdAt: t0),
      ),
      learner: learner,
      at: t0,
    );

    expect(evaluated.coverage.isComplete, isFalse);
    expect(evaluated.isCaughtUp, isTrue);
  });
}

ResolvedPracticeScope _scope() {
  final material = fixtureMaterials.first;
  final candidates = [
    Exercise.linear(
      material: material,
      hands: HandConfiguration.right,
      guidance: GuidanceContext.continuouslyCued,
    ),
  ];
  return ResolvedPracticeScope(
    goalId: 'GOAL',
    curriculumId: 'CURRICULUM',
    curriculumVersion: '1',
    requirements: [
      for (final id in ['A', 'B', 'C', 'D'])
        ResolvedRequirement(
          requirement: CurriculumRequirement(
            id: id,
            familyId: material.familyId,
            materialId: material.materialId,
          ),
          material: material,
          candidates: candidates,
        ),
    ],
  );
}
