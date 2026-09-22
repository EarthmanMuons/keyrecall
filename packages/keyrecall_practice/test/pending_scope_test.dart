import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// A decision nobody answered is disposable, and the scope it was made under
/// can be gone by the time the next run opens. These reopen under a changed
/// scope, which is what narrowing practice looks like from the sitting's side.
void main() {
  test('a decision outside the scope in force is abandoned', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await _open(store, goal: _over(fixtureMaterials.first));
    await session.decide(at: t0.plusDays(0.5));

    final reopened = await _open(store, goal: _over(fixtureMaterials[1]));

    expect(reopened.pending, isNull);
    expect(await store.loadPendingDecision(alice.id), isNull);
    expect(
      reopened.journal.length,
      0,
      reason: 'an attempt nobody observed is not history, however it ended',
    );
  });

  test('a decision the scope still admits is kept', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await _open(store, goal: _over(fixtureMaterials.first));
    final presented = await session.decide(at: t0.plusDays(0.5));

    final reopened = await _open(store, goal: _over(fixtureMaterials.first));

    expect(reopened.pending?.attemptId, presented!.decision.attemptId);
  });

  test(
    'a decision whose shape the scope no longer admits is abandoned',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final goal = _over(fixtureMaterials.first);
      final session = await _open(store, goal: goal);
      final presented = await session.decide(at: t0.plusDays(0.5));
      final hands = presented!.exercise.conditions.hands;

      // Same material, and every realization of it but the one on screen.
      final reopened = await _open(
        store,
        goal: goal,
        resolver: PracticeScopeResolver(
          families: [
            _ScalesExcept((exercise) => exercise.conditions.hands == hands),
          ],
        ),
      );

      expect(
        reopened.candidates,
        isNotEmpty,
        reason: 'setup: the scope resolves',
      );
      expect(reopened.pending, isNull);
      expect(await store.loadPendingDecision(alice.id), isNull);
    },
  );

  test('a decision under a scope that did not resolve is kept', () async {
    final store = InMemoryPracticeStore(createdAt: t0);
    final session = await _open(store, goal: _over(fixtureMaterials.first));
    final presented = await session.decide(at: t0.plusDays(0.5));

    final reopened = await _open(
      store,
      goal: PracticeGoal(id: 'INVALID', targetMaterialIds: {'ABSENT'}),
    );

    expect(reopened.pending?.attemptId, presented!.decision.attemptId);
  });
}

PracticeGoal _over(TechnicalMaterial material) => PracticeGoal(
  id: material.materialId,
  targetMaterialIds: {material.materialId},
);

Future<PracticeSession> _open(
  PracticeStore store, {
  required PracticeGoal goal,
  PracticeScopeResolver? resolver,
}) => PracticeSession.open(
  store: store,
  profile: alice,
  materials: fixtureMaterials,
  learner: learner,
  goal: goal,
  scopeResolver: resolver,
  sessionId: 'session-1',
  nextId: countingIds(),
);

/// The scale family without the realizations [omit] names.
class _ScalesExcept implements PracticeMaterialFamily {
  final bool Function(Exercise) omit;

  const _ScalesExcept(this.omit);

  static const _scales = ScalePracticeMaterialFamily();

  @override
  String get familyId => _scales.familyId;

  @override
  double get entryTempoBpm => _scales.entryTempoBpm;

  @override
  List<Exercise> generate(
    InstrumentProfile instrument,
    TechnicalMaterial material,
  ) => [
    for (final exercise in _scales.generate(instrument, material))
      if (!omit(exercise)) exercise,
  ];

  @override
  AcquisitionFloor acquisitionFloorFor(
    Iterable<AcquisitionFloorRequest> requests,
  ) => _scales.acquisitionFloorFor(requests);
}
