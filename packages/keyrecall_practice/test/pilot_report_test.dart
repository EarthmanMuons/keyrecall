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
        profile: alice.scheduledBy(SchedulingAssignment.allocationPilot),
        materials: allPracticeMaterials,
      );
      final records = await practise(session, attempts: 12);
      final report = session.pilotReport(at: t0.plusDays(30));
      final encoded = jsonEncode(report);

      expect(
        report['assigned policy'],
        SchedulingAssignment.allocationPilot.id,
      );
      expect(report['attempts by effective policy'], {
        SchedulingAssignment.allocationPilot.id: 12,
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
      profile: alice.scheduledBy(SchedulingAssignment.allocationPilot),
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
}
