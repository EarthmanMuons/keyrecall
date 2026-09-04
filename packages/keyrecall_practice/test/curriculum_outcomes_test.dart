import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  test('invalid scope returns before scheduling', () async {
    final pipeline = CountingPipeline();
    final session = await _open(
      goal: PracticeGoal(id: 'INVALID', targetMaterialIds: {'ABSENT'}),
      pipeline: pipeline,
    );

    final decision = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(decision, isA<PracticeInvalidScope>());
    expect(pipeline.decisions, 0);
    expect(session.session.attemptsThisSession, 0);
    expect(session.pending, isNull);
  });

  test('incomplete but not actionable returns caught up', () async {
    final pipeline = CountingPipeline();
    final session = await _open(
      goal: _goalFor('NARROW', fixtureMaterials.first),
      pipeline: pipeline,
      evaluator: _fixedEvaluator(
        RequirementCoverage.uncovered,
        RequirementWorkStatus.notYetActionable,
      ),
    );

    final decision = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(decision, isA<PracticeCaughtUp>());
    expect((decision as PracticeCaughtUp).coverage.isComplete, isFalse);
    expect(pipeline.decisions, 0);
    expect(session.session.attemptsThisSession, 0);
    expect(session.pending, isNull);
  });

  test('complete scope may select maintenance work', () async {
    final session = await _open(
      goal: _goalFor('MAINTENANCE', fixtureMaterials.first),
      evaluator: _fixedEvaluator(
        RequirementCoverage.covered,
        RequirementWorkStatus.due,
      ),
    );

    final decision = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(decision, isA<PresentedAttempt>());
    expect((decision as PresentedAttempt).coverage?.isComplete, isTrue);
  });

  test('complete and healthy scope returns caught up', () async {
    final session = await _open(
      goal: _goalFor('HEALTHY', fixtureMaterials.first),
      evaluator: _fixedEvaluator(
        RequirementCoverage.covered,
        RequirementWorkStatus.healthy,
      ),
    );

    final decision = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(decision, isA<PracticeCaughtUp>());
    expect((decision as PracticeCaughtUp).coverage.isComplete, isTrue);
    expect(session.session.attemptsThisSession, 0);
  });

  test('a narrow unresolved scope reports a rejected safe entry', () async {
    final session = await _open(
      goal: _goalFor('BLOCKED', fixtureMaterials.first),
      pipeline: pipelineCappedAt(1),
      evaluator: _fixedEvaluator(
        RequirementCoverage.uncovered,
        RequirementWorkStatus.due,
      ),
    );
    session.session.attemptsThisSession = 1;

    final decision = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(decision, isA<PracticeBlocked>());
    expect(
      (decision as PracticeBlocked).reason,
      BlockedReason.safeEntryRejected,
    );
    expect(session.session.attemptsThisSession, 2);
    expect(session.pending, isNull);
  });

  test('broadening a caught-up focus affects the next decision', () async {
    final first = fixtureMaterials.first;
    final second = fixtureMaterials[1];
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
            workStatus: resolved.material == first
                ? RequirementWorkStatus.notYetActionable
                : RequirementWorkStatus.due,
          ),
    );
    final session = await _open(
      goal: _goalFor('FIRST', first),
      evaluator: evaluator,
    );
    final before = learnerStateHash(session.state);

    expect(
      await session.decideOutcome(at: t0.plusDays(0.5)),
      isA<PracticeCaughtUp>(),
    );
    session.updateScope(goal: _goalFor('SECOND', second));
    final next = await session.decideOutcome(at: t0.plusDays(0.5));

    expect(next, isA<PresentedAttempt>());
    expect((next as PresentedAttempt).exercise.material, second);
    expect(learnerStateHash(session.state), before);
  });

  test('a focus change does not replace an outstanding attempt', () async {
    final first = fixtureMaterials.first;
    final second = fixtureMaterials[1];
    final session = await _open(
      goal: _goalFor('FIRST', first),
      evaluator: _fixedEvaluator(
        RequirementCoverage.uncovered,
        RequirementWorkStatus.due,
      ),
    );
    final outstanding =
        await session.decideOutcome(at: t0.plusDays(0.5)) as PresentedAttempt;

    session.updateScope(goal: _goalFor('SECOND', second));

    expect(outstanding.exercise.material, first);
    expect(session.hasOutstandingAttempt, isTrue);
    await session.closeWithOutcome(outcomeFor(outstanding.exercise));
    final next = await session.decideOutcome(at: t0.plusDays(1));
    expect((next as PresentedAttempt).exercise.material, second);
  });
}

PracticeGoal _goalFor(String id, TechnicalMaterial material) =>
    PracticeGoal(id: id, targetMaterialIds: {material.materialId});

PracticeScopeEvaluator _fixedEvaluator(
  RequirementCoverage coverage,
  RequirementWorkStatus workStatus,
) => PracticeScopeEvaluator(
  assess:
      ({
        required resolved,
        required state,
        required journal,
        required learner,
        required at,
      }) => RequirementState(
        resolved: resolved,
        coverage: coverage,
        workStatus: workStatus,
      ),
);

Future<PracticeSession> _open({
  required PracticeGoal goal,
  SchedulerPipeline? pipeline,
  PracticeScopeEvaluator evaluator = const PracticeScopeEvaluator(),
}) => PracticeSession.open(
  store: InMemoryPracticeStore(createdAt: t0),
  profile: alice,
  materials: fixtureMaterials,
  learner: learner,
  pipeline: pipeline,
  goal: goal,
  scopeEvaluator: evaluator,
  sessionId: 'session',
  nextId: countingIds(),
);

class CountingPipeline extends SchedulerPipeline {
  int decisions = 0;

  CountingPipeline() : super(learner: learner);

  @override
  SelectionResult decide({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
  }) {
    decisions++;
    return super.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      practiceEntryPolicy: practiceEntryPolicy,
    );
  }
}
