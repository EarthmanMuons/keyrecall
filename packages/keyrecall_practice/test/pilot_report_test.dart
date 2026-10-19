import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final scale = fixtureMaterials.first;

  final other = fixtureMaterials[1];

  Exercise played(HandConfiguration hands, [TechnicalMaterial? material]) =>
      Exercise.linear(
        material: material ?? scale,
        hands: hands,
        octaves: 1,
        direction: ExerciseDirection.up,
        tempoBpm: 60,
        guidance: GuidanceContext.continuouslyCued,
      );

  /// [plays] in order, a day apart unless a gap is given, as history.
  Map<String, Object?> reportOn(List<(Exercise, bool managed, int day)> plays) {
    final journal = AttemptJournal(
      JournalHeader(profileId: alice.id, createdAt: t0),
    );
    for (final (index, (exercise, managed, day)) in plays.indexed) {
      final record = recordOf(
        exercise,
        sequence: index,
        outcome: outcomeFor(
          exercise,
          succeeded: managed,
          quality: managed ? 0.9 : 0.2,
        ),
      );
      journal.append(
        AttemptRecord(
          journalSequence: index,
          identity: AttemptIdentity(
            profileId: alice.id,
            attemptId: 'attempt-$index',
            sessionId: 'session-${day ~/ 2}',
            indexInSession: index,
            occurredAt: t0.plusDays(day.toDouble()),
          ),
          provenance: record.provenance,
          exercise: exercise,
          closure: record.closure,
        ),
      );
    }
    final scope =
        (PracticeScopeResolver().resolve(
                  goal: PracticeGoal.generalFluency,
                  focus: PracticeFocus.unrestricted,
                  catalog: fixtureMaterials,
                  instrument: InstrumentProfile(),
                )
                as ValidPracticeScope)
            .scope;
    return pilotReportOf(
      journal: journal,
      acquisition: AcquisitionJournal(
        AcquisitionJournalHeader(profileId: alice.id, createdAt: t0),
      ),
      evaluated: const PracticeScopeEvaluator().evaluate(
        scope: scope,
        state: learner.placementState(PlacementTier.someExperience, at: t0),
        journal: journal,
        learner: learner,
        at: t0.plusDays(30),
      ),
      assigned: SchedulingAssignment.v1_14,
    );
  }

  test('reads progression milestones as attempts and days from the first', () {
    final report = reportOn([
      (played(HandConfiguration.right), true, 0),
      (played(HandConfiguration.left), false, 1),
      (played(HandConfiguration.left), true, 2),
      (played(HandConfiguration.together), false, 3),
      (played(HandConfiguration.together), true, 5),
    ]);
    final progression = report['progression']! as Map<String, Object?>;

    expect(progression['first left-hand scale managed'], {
      'attempts before': 2,
      'day': 2,
    });
    expect(progression['first hands-together scale managed'], {
      'attempts before': 4,
      'day': 5,
    });
    expect((progression['strands managed']! as Map)[scale.familyId], 3);
  });

  test('counts a return after a week as a revisit, and a strand never managed '
      'in five tries as repeated', () {
    final report = reportOn([
      for (var day = 0; day < 5; day++)
        (played(HandConfiguration.together), false, day),
      for (var day = 5; day < 10; day++)
        (played(HandConfiguration.right, other), day == 9, day),
      (played(HandConfiguration.right), true, 16),
    ]);
    final breadth = report['breadth']! as Map<String, Object?>;
    final difficulty = report['difficulty']! as Map<String, Object?>;
    final participation = report['participation']! as Map<String, Object?>;

    expect(
      (breadth['revisited after $pilotRevisitGapDays days']!
          as Map)[scale.familyId],
      1,
    );
    expect(
      (difficulty['strands repeated $pilotUnmanagedRepeats or more times, '
              'never managed']!
          as Map)[scale.familyId],
      1,
    );
    expect(participation['longest break in days'], 7);
    expect(participation['active days'], 11);
    expect(participation['sessions'], 6);
  });

  test(
    'a pilot profile\'s report reads its own decisions, and names nobody',
    () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(
        store,
        profile: alice.scheduledBy(SchedulingAssignment.allocation),
        materials: allPracticeMaterials,
      );
      final records = await practise(session, attempts: 12);
      final report = session.pilotReport(at: t0.plusDays(30));
      final encoded = jsonEncode(report);

      expect(report['assigned policy'], SchedulingAssignment.allocation.id);
      expect(report['attempts by effective policy'], {
        SchedulingAssignment.allocation.id: 12,
      });
      expect(
        (report['evidence']! as Map<String, Object?>)['observed'],
        12 + session.acquisitionJournal.attempts.length,
      );
      for (final private in [
        alice.id,
        alice.displayName,
        session.sessionId,
        records.first.identity.attemptId,
        '${t0.year}-',
      ]) {
        expect(encoded, isNot(contains(private)), reason: private);
      }
    },
  );

  test(
    'counts a material once, covered only when all its requirements are',
    () {
      final material = fixtureMaterials.first;
      final candidates = [played(HandConfiguration.right)];
      RequirementState requirement(String id, {required bool covered}) =>
          RequirementState(
            resolved: ResolvedRequirement(
              requirement: CurriculumRequirement(
                id: id,
                familyId: material.familyId,
                materialId: material.materialId,
              ),
              material: material,
              candidates: candidates,
            ),
            coverage: covered
                ? RequirementCoverage.covered
                : RequirementCoverage.uncovered,
            workStatus: RequirementWorkStatus.healthy,
          );
      AcquisitionJournal acquisition() => AcquisitionJournal(
        AcquisitionJournalHeader(profileId: alice.id, createdAt: t0),
      );
      Map<String, Object?> breadthWith(List<bool> covered) {
        final requirements = [
          for (final (index, isCovered) in covered.indexed)
            requirement('R$index', covered: isCovered),
        ];
        return pilotReportOf(
              journal: AttemptJournal(
                JournalHeader(profileId: alice.id, createdAt: t0),
              ),
              acquisition: acquisition(),
              evaluated: EvaluatedPracticeScope(
                scope: ResolvedPracticeScope(
                  goalId: 'GOAL',
                  curriculumId: 'CURRICULUM',
                  curriculumVersion: '1',
                  isNarrow: false,
                  requirements: [
                    for (final state in requirements) state.resolved,
                  ],
                ),
                requirements: requirements,
                coverage: ScopeCoverage(
                  coveredTargetIds: const {},
                  targetCount: 0,
                ),
              ),
              assigned: SchedulingAssignment.v1_14,
            )['breadth']!
            as Map<String, Object?>;
      }

      final partly = breadthWith([true, false]);
      final wholly = breadthWith([true, true]);

      expect((partly['covered']! as Map)[material.familyId], 0);
      expect((partly['requirements covered']! as Map)[material.familyId], 1);
      expect((wholly['covered']! as Map)[material.familyId], 1);
      expect((wholly['retained']! as Map)[material.familyId], 1);
      expect((wholly['requirements covered']! as Map)[material.familyId], 2);
    },
  );

  test('reads coverage against General Fluency whatever the session is '
      'focused on', () async {
    final session = await openSession(
      InMemoryPracticeStore(createdAt: t0),
      profile: alice.scheduledBy(SchedulingAssignment.allocation),
      materials: allPracticeMaterials,
    );
    await practise(session, attempts: 12);
    final unfocused = session.pilotReport(at: t0.plusDays(30));
    session.updateScope(
      goal: PracticeGoal.generalFluency,
      focus: PracticeFocus(
        exclusiveRequirementIds: {
          catalogRequirementId(
            PracticeGoal.generalFluency.id,
            allPracticeMaterials.first.materialId,
          ),
        },
      ),
    );
    final focused = session.pilotReport(at: t0.plusDays(30));

    expect(focused['coverage scope'], PracticeGoal.generalFluency.id);
    expect(focused['breadth'], unfocused['breadth']);
  });

  group('participation', () {
    Future<void> supportedAt(
      InMemoryPracticeStore store,
      String sessionId,
      double day,
    ) async {
      final session = await openSession(
        store,
        sessionId: sessionId,
        ids: countingIds('$sessionId-$day'),
        pipeline: const AlwaysOffersAcquisition(),
      );
      await session.decideOutcome(at: t0.plusDays(day));
      await session.closeAcquisition(
        PerformanceTranscript.empty,
        at: t0.plusDays(day),
      );
    }

    test(
      'counts supported practice alone, without inventing milestones',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        await supportedAt(store, 'monday', 1);
        await supportedAt(store, 'monday', 1.1);
        await supportedAt(store, 'wednesday', 3);
        final report = (await openSession(
          store,
          sessionId: 'report',
        )).pilotReport(at: t0.plusDays(30));
        final participation = report['participation']! as Map<String, Object?>;
        final progression = report['progression']! as Map<String, Object?>;

        expect(participation['ordinary attempts'], 0);
        expect(participation['supported attempts'], 3);
        expect(participation['sessions'], 2);
        expect(participation['active days'], 2);
        expect(participation['days since first attempt'], 2);
        expect(
          (progression['first hands-together scale managed']! as Map)['day'],
          isNull,
        );
      },
    );

    test(
      'counts one session once when it held both kinds of attempt',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        await supportedAt(store, 'session', 1);
        final ordinary = await openSession(
          store,
          sessionId: 'session',
          ids: countingIds('ordinary'),
        );
        final presented =
            await ordinary.decideOutcome(at: t0.plusDays(1.1))
                as PresentedAttempt;
        await ordinary.closeWithOutcome(outcomeFor(presented.exercise));
        final participation =
            ordinary.pilotReport(at: t0.plusDays(30))['participation']!
                as Map<String, Object?>;

        expect(participation['ordinary attempts'], 1);
        expect(participation['supported attempts'], 1);
        expect(participation['sessions'], 1);
        expect(participation['active days'], 1);
        expect(participation['median attempts per session, of either kind'], 2);
      },
    );
  });

  test('tells waiting in General Fluency from waiting kept for other goals', () {
    final record = recordOf(played(HandConfiguration.right));
    final inScope = catalogRequirementId(
      PracticeGoal.generalFluency.id,
      scale.materialId,
    );
    final journal =
        AttemptJournal(JournalHeader(profileId: alice.id, createdAt: t0))
          ..append(
            AttemptRecord(
              journalSequence: 0,
              identity: record.identity,
              provenance: record.provenance,
              exercise: record.exercise,
              closure: record.closure,
              allocation: AllocationObserved(
                policy: AllocationPolicyIdentity(
                  assigned: SchedulingAssignment.v1_14.id,
                  effective: SchedulingAssignment.v1_14.id,
                ),
                basis: AllocationBasis(attempts: 0, acquisitionAttempts: 0),
                evidence: AllocationEvidence(
                  served: const [],
                  missed: [inScope, 'FOUNDATIONS:${scale.materialId}'],
                ),
              ),
            ),
          );
    final scope =
        (PracticeScopeResolver().resolve(
                  goal: PracticeGoal.generalFluency,
                  focus: PracticeFocus.unrestricted,
                  catalog: fixtureMaterials,
                  instrument: InstrumentProfile(),
                )
                as ValidPracticeScope)
            .scope;
    final allocation =
        pilotReportOf(
              journal: journal,
              acquisition: AcquisitionJournal(
                AcquisitionJournalHeader(profileId: alice.id, createdAt: t0),
              ),
              evaluated: const PracticeScopeEvaluator().evaluate(
                scope: scope,
                state: learner.placementState(
                  PlacementTier.someExperience,
                  at: t0,
                ),
                journal: journal,
                learner: learner,
                at: t0.plusDays(2),
              ),
              assigned: SchedulingAssignment.v1_14,
            )['allocation']!
            as Map<String, Object?>;

    expect(allocation['requirements waiting'], 1);
    expect(
      allocation['requirements waiting outside ${PracticeGoal.generalFluency.id}'],
      1,
    );
  });
}
