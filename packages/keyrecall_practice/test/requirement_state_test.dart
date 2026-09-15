import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
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

  test('the same scope, state, history, and time evaluate identically', () {
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
            workStatus: RequirementWorkStatus.due,
          ),
    );
    final state = learner.newState(at: t0);
    final journal = AttemptJournal(
      JournalHeader(profileId: alice.id, createdAt: t0),
    );
    final scope = _scope();

    EvaluatedPracticeScope evaluate() => evaluator.evaluate(
      scope: scope,
      state: state,
      journal: journal,
      learner: learner,
      at: t0,
    );

    final first = evaluate();
    final second = evaluate();
    expect(first.coverage.coveredTargets, second.coverage.coveredTargets);
    expect(first.coverage.targetCount, second.coverage.targetCount);
    expect(
      first.requirements.map(
        (state) => (
          state.resolved.requirement.id,
          state.coverage,
          state.workStatus,
          state.resolved.candidates,
        ),
      ),
      second.requirements.map(
        (state) => (
          state.resolved.requirement.id,
          state.coverage,
          state.workStatus,
          state.resolved.candidates,
        ),
      ),
    );
  });

  group('assessing coverage against history', () {
    test('a clean attempt below the required pace covers nothing', () {
      final evaluated = _evaluate(
        requirement: _tempoRequirement(120),
        played: [
          recordOf(
            _exerciseAt(60),
            outcome: outcomeFor(_exerciseAt(60), quality: 0.95),
          ),
        ],
      );

      expect(evaluated.coverage.coveredTargets, 0);
      expect(evaluated.requirements.single.isDue, isTrue);
    });

    test('the same performance at the pace asked for covers it', () {
      final evaluated = _evaluate(
        requirement: _tempoRequirement(120),
        played: [
          recordOf(
            _exerciseAt(120),
            outcome: outcomeFor(_exerciseAt(120), quality: 0.95),
          ),
        ],
      );

      expect(evaluated.coverage.coveredTargets, 1);
      expect(evaluated.coverage.isComplete, isTrue);
    });

    test('remembering the material is not demonstrating it', () {
      final exercise = _exerciseAt(120);
      final evaluated = _evaluate(
        requirement: _tempoRequirement(120),
        played: [
          recordOf(
            exercise,
            // Every degree retrieved, half of them in the wrong octave.
            outcome: Outcome(
              started: true,
              retrieval: FactualRetrieval.succeeded,
              completed: true,
              materialRetrieval: 1,
              pitchIntegrity: 0.5,
              continuity: 0.9,
              temporalStability: 0.9,
              achievedTempoRatio: 1,
              topologyAccuracy: 1,
            ),
          ),
        ],
      );

      expect(evaluated.coverage.coveredTargets, 0);
    });

    test('only active targets are counted, not retained support', () {
      final material = fixtureMaterials.first;
      final requirement = _tempoRequirement(120);
      final scope = ResolvedPracticeScope(
        goalId: 'GOAL',
        curriculumId: 'CURRICULUM',
        curriculumVersion: '1',
        isNarrow: true,
        requirements: [
          ResolvedRequirement(
            requirement: requirement,
            material: material,
            candidates: [_exerciseAt(120)],
          ),
          ResolvedRequirement(
            requirement: CurriculumRequirement(
              id: 'SUPPORT',
              familyId: material.familyId,
              materialId: material.materialId,
            ),
            material: material,
            candidates: [_exerciseAt(60)],
            roles: const {ResolvedRequirementRole.support},
          ),
        ],
      );

      final evaluated = const PracticeScopeEvaluator().evaluate(
        scope: scope,
        state: learner.newState(at: t0),
        journal: _journalOf(const []),
        learner: learner,
        at: t0,
      );

      expect(evaluated.coverage.targetCount, 1);
      expect(evaluated.requirements, hasLength(2));
    });
  });
}

EvaluatedPracticeScope _evaluate({
  required CurriculumRequirement requirement,
  required List<AttemptRecord> played,
}) => const PracticeScopeEvaluator().evaluate(
  scope: ResolvedPracticeScope(
    goalId: 'GOAL',
    curriculumId: 'CURRICULUM',
    curriculumVersion: '1',
    isNarrow: true,
    requirements: [
      ResolvedRequirement(
        requirement: requirement,
        material: fixtureMaterials.first,
        candidates: [_exerciseAt(120)],
      ),
    ],
  ),
  state: learner.newState(at: t0),
  journal: _journalOf(played),
  learner: learner,
  at: t0.plusDays(1.5),
);

AttemptJournal _journalOf(List<AttemptRecord> records) {
  final journal = AttemptJournal(
    JournalHeader(profileId: alice.id, createdAt: t0),
  );
  for (final record in records) {
    journal.append(record);
  }
  return journal;
}

CurriculumRequirement _tempoRequirement(double bpm) => CurriculumRequirement(
  id: 'TARGET',
  familyId: fixtureMaterials.first.familyId,
  materialId: fixtureMaterials.first.materialId,
  constraints: ExerciseConstraints(minimumTempoBpm: bpm),
);

Exercise _exerciseAt(double tempoBpm) => Exercise.linear(
  material: fixtureMaterials.first,
  hands: HandConfiguration.right,
  tempoBpm: tempoBpm,
);

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
    isNarrow: true,
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
