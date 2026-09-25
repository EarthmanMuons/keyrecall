import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// Changing goal changes what is offered and what counts, never the evidence.
///
/// Coverage is read from the journal against whichever goal is active, so a
/// switch recomputes it rather than carrying a count across, and switching
/// back reads the same history the same way.
void main() {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];
  final cMajor = TechnicalMaterial('C', ScaleForm.major);
  final gMajor = TechnicalMaterial('G', ScaleForm.major);

  Exercise played(
    TechnicalMaterial material,
    HandConfiguration hands, {
    int octaves = 1,
    GuidanceContext guidance = GuidanceContext.unguided,
  }) => Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    direction: ExerciseDirection.upDown,
    guidance: guidance,
  );

  /// C major right hand from memory, C major left hand after a preview, and
  /// G major hands together over two octaves from memory.
  AttemptJournal history() {
    final journal = AttemptJournal(
      JournalHeader(profileId: alice.id, createdAt: t0),
    );
    for (final (index, exercise) in [
      played(cMajor, HandConfiguration.right),
      played(
        cMajor,
        HandConfiguration.left,
        guidance: GuidanceContext.notesPreviewedOnly,
      ),
      played(gMajor, HandConfiguration.together, octaves: 2),
    ].indexed) {
      journal.append(
        recordOf(
          exercise,
          outcome: Outcome(
            started: true,
            retrieval: FactualRetrieval.succeeded,
            completed: true,
            materialRetrieval: 0.95,
            pitchIntegrity: 0.95,
            continuity: 0.95,
            temporalStability: 0.95,
            achievedTempoRatio: 1,
            topologyAccuracy: 0.95,
            coordination:
                exercise.conditions.hands == HandConfiguration.together
                ? 0.95
                : null,
          ),
          sequence: index,
        ),
      );
    }
    return journal;
  }

  Set<String> coveredUnder(String goalId, AttemptJournal journal) {
    final scope =
        (PracticeScopeResolver().resolve(
                  goal: supportedGoals[goalId]!,
                  focus: PracticeFocus.unrestricted,
                  catalog: catalog,
                  instrument: InstrumentProfile(),
                )
                as ValidPracticeScope)
            .scope;
    final evaluated = const PracticeScopeEvaluator().evaluate(
      scope: scope,
      state: LearnerState.cold(params, at: t0),
      journal: journal,
      learner: learner,
      at: t0.plusDays(5),
    );
    return {
      for (final state in evaluated.requirements)
        if (state.isCovered) state.resolved.requirement.id,
    };
  }

  test('each goal reads the history for the shapes it asks for', () {
    final journal = history();

    expect(coveredUnder('FOUNDATIONS', journal), {
      'C_MAJOR:RIGHT:1',
    }, reason: 'the left hand was previewed, which is not from memory');
    expect(coveredUnder('KEY_FLUENCY_24', journal), {'G_MAJOR:TOGETHER:2'});
  });

  test('switching away and back reads the same history the same way', () {
    final journal = history();
    final before = coveredUnder('FOUNDATIONS', journal);
    final records = journal.records.length;

    for (final goalId in ['KEY_FLUENCY_24', 'GENERAL_FLUENCY', 'FOUNDATIONS']) {
      coveredUnder(goalId, journal);
    }

    expect(coveredUnder('FOUNDATIONS', journal), before);
    expect(journal.records, hasLength(records));
  });

  test('general technique counts the previewed attempt that goals do not', () {
    expect(
      coveredUnder('GENERAL_FLUENCY', history()),
      containsAll([
        catalogRequirementId('GENERAL_FLUENCY', cMajor.materialId),
        catalogRequirementId('GENERAL_FLUENCY', gMajor.materialId),
      ]),
    );
  });

  test('each hand\'s retrievals do not depend on the goal at all', () {
    expect(retrievedMaterialHands(history().records), {
      (cMajor.materialId, Hand.right),
      (cMajor.materialId, Hand.left),
      (gMajor.materialId, Hand.right),
      (gMajor.materialId, Hand.left),
    }, reason: 'memory evidence, where a preview still counts');
  });

  group('a sitting that changes goal', () {
    test(
      'keeps its learner and journal, and decides in the new scope',
      () async {
        final store = InMemoryPracticeStore(createdAt: t0);
        final session = await openSession(store, materials: catalog);
        session.updateScope(goal: supportedGoals['FOUNDATIONS']!);
        await practise(session, attempts: 3);
        final records = session.journal.records.length;
        final memory = {...session.state.materialMemory.keys};

        session.updateScope(goal: supportedGoals['KEY_FLUENCY_24']!);
        final decision = await session.decideOutcome(at: t0.plusDays(3));

        expect(session.journal.records, hasLength(records));
        expect(session.state.materialMemory.keys, containsAll(memory));
        expect(decision, isA<PresentedAttempt>());
        final exercise = (decision as PresentedAttempt).exercise;
        expect(exercise.material.scaleForm, isIn(coreForms));
        expect(decision.coverage!.targetCount, 24);
      },
    );

    test('and back again counts what it counted before', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store, materials: catalog);
      session.updateScope(goal: supportedGoals['FOUNDATIONS']!);
      await practise(session, attempts: 4);

      Future<int> coveredNow(double day) async {
        final decision = await session.decideOutcome(at: t0.plusDays(day));
        final coverage = switch (decision) {
          PresentedAttempt(:final coverage) => coverage!,
          PracticeCaughtUp(:final coverage) => coverage,
          PracticeBlocked(:final coverage) => coverage,
          _ => throw StateError('unexpected $decision'),
        };
        // A clear miss closes the slot and cannot cover anything, so every
        // count below reads the same history.
        if (decision is PresentedAttempt) {
          await session.acknowledgePresentation(decision.decision.attemptId);
          await session.closeWithOutcome(
            outcomeFor(decision.exercise, succeeded: false, quality: 0.1),
          );
        }
        return coverage.coveredTargets;
      }

      final before = await coveredNow(4);
      session.updateScope(goal: supportedGoals['KEY_FLUENCY_24']!);
      await coveredNow(4.1);
      session.updateScope(goal: PracticeGoal.generalFluency);
      await coveredNow(4.2);
      session.updateScope(goal: supportedGoals['FOUNDATIONS']!);

      expect(await coveredNow(4.3), before);
    });
  });
}
