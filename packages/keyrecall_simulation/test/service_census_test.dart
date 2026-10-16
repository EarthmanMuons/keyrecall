import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  RequirementObservation observed(
    int decision, {
    bool due = true,
    bool fullyRanked = true,
    bool served = false,
    String? loss,
  }) => RequirementObservation(
    decision: decision,
    requirementId: 'r',
    materialId: 'C_MAJOR',
    familyId: 'SCALE',
    due: due,
    covered: !due,
    admitted: fullyRanked,
    fullyRanked: fullyRanked,
    materialRanked: fullyRanked,
    heldForRecovery: false,
    servedMaterial: served,
    served: served,
    loss: due && fullyRanked && !served ? loss ?? 'rank:retention' : null,
  );

  group('a requirement\'s service', () {
    test('counts missed opportunities, not the decisions between them', () {
      final service = RequirementService.of([
        observed(10),
        observed(11, fullyRanked: false),
        observed(12),
        observed(13, fullyRanked: false),
        observed(14),
      ]);

      expect(service.longestMissedOpportunities, 3);
      expect(service.longestDueWithoutService, 5);
      expect(service.deferred, 3);
      expect(service.blocked, 2);
    });

    test('starts a run again once it is served', () {
      final service = RequirementService.of([
        observed(0),
        observed(1),
        observed(2, served: true),
        observed(3),
      ]);

      expect(service.longestMissedOpportunities, 2);
      expect(service.served, 1);
      expect(service.trajectory, 'actionable and served');
    });

    test('keeps service while not due apart from opportunities', () {
      final service = RequirementService.of([
        observed(0, due: false, served: true),
        observed(1, due: false),
      ]);

      expect(service.servedWhileNotDue, 1);
      expect(service.actionable, 0);
      expect(service.trajectory, 'never due');
    });

    test('tells never choosable apart from never chosen', () {
      expect(
        RequirementService.of([observed(0, fullyRanked: false)]).trajectory,
        'due, never actionable',
      );
      expect(
        RequirementService.of([observed(0), observed(1)]).trajectory,
        'actionable, never served',
      );
    });
  });

  group('the term a ranking was decided on', () {
    RankKey key({
      EligibilityTier tier = EligibilityTier.fullyEligible,
      double retention = 0.5,
      double information = 1.0,
    }) => RankKey(
      tier: tier,
      retention: retention,
      information: information,
      diversity: 0,
      goals: 0,
    );

    test('is the first one, in the order the scheduler compares', () {
      expect(
        decidingRankTerm(
          key(retention: 0.2, information: 9),
          key(),
          RankTolerances.exact,
        ),
        'retention',
      );
      expect(
        decidingRankTerm(
          key(tier: EligibilityTier.provisionallyEligible, retention: 0.9),
          key(),
          RankTolerances.exact,
        ),
        'tier',
      );
    });

    test('passes over a term within its tolerance', () {
      expect(
        decidingRankTerm(
          key(retention: 0.49, information: 0.5),
          key(),
          const RankTolerances(retention: 0.05),
        ),
        'information',
      );
    });

    test('refuses to explain a loss there was not', () {
      expect(
        () => decidingRankTerm(key(), key(), RankTolerances.exact),
        throwsStateError,
      );
    });
  });

  group('a seeded run', () {
    late ServiceCensus census;

    setUpAll(() async {
      census = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: demoSessions(
          from: demoHistoryStart,
          until: demoHistoryStart.add(const Duration(days: 8)),
        ),
      );
    });

    test('gives every deferral a reason and nothing else one', () {
      for (final observation in census.observations) {
        expect(
          observation.loss != null,
          observation.deferred,
          reason: observation.canonical,
        );
      }
    });

    test('never counts work held for recovery as deferred', () {
      final held = [
        for (final observation in census.observations)
          if (observation.heldForRecovery) observation,
      ];
      expect(held, isNotEmpty);
      for (final observation in held) {
        expect(observation.blocked, isTrue);
        expect(observation.deferred, isFalse);
      }
    });

    test('serves at most one requirement a decision', () {
      final byDecision = <int, int>{};
      for (final observation in census.observations) {
        if (observation.served) {
          byDecision.update(
            observation.decision,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      }
      expect(byDecision.values.every((n) => n == 1), isTrue);
    });

    test('is pinned', () {
      expect(
        census.digest,
        '9ce32c549d83d54cc1e3bcf63959832d3756fb04e70cd6da8877974f386852c3',
      );
    });
  });

  test('decides exactly as the scheduler does without it', () async {
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryStart.add(const Duration(days: 8)),
    );
    final profile = Profile(
      id: 'census',
      displayName: 'Census',
      createdAt: demoHistoryStart,
      placement: PlayerArchetypes.developing.placement,
    );
    Future<String> journalOf(
      SchedulerPipeline? pipeline, {
      void Function(PracticeSession session)? opened,
    }) async {
      final store = InMemoryPracticeStore(createdAt: demoHistoryStart);
      await practiceDemoHistory(
        store: store,
        profile: profile,
        player: PlayerArchetypes.developing,
        materials: allPracticeMaterials,
        sessions: sessions,
        pipeline: pipeline,
        onOpen: (session, _) => opened?.call(session),
      );
      return (await store.loadJournal(profile.id)).toJsonLines();
    }

    late PracticeSession current;
    final observing = ServiceCensusPipeline(
      learner: const LearnerModel(),
      scope:
          (PracticeScopeResolver().resolve(
                    goal: PracticeGoal.generalFluency,
                    focus: PracticeFocus.unrestricted,
                    catalog: allPracticeMaterials,
                    instrument: InstrumentProfile(),
                  )
                  as ValidPracticeScope)
              .scope,
      journal: () => current.journal,
    );

    expect(
      await journalOf(observing, opened: (session) => current = session),
      await journalOf(null),
    );
    expect(observing.observations, isNotEmpty);
  });

  test('serves a requirement only in the structure it asks for', () async {
    final material = TechnicalMaterial('C', ScaleForm.major);
    CurriculumRequirement inHand(HandConfiguration hands) =>
        CurriculumRequirement(
          id: 'c-major-${hands.name}',
          familyId: material.familyId,
          materialId: material.materialId,
          constraints: ExerciseConstraints(hands: hands),
        );
    final census = await runServiceCensus(
      player: PlayerArchetypes.developing,
      sessions: demoSessions(
        from: demoHistoryStart,
        until: demoHistoryStart.add(const Duration(days: 10)),
      ),
      goal: PracticeGoal(
        id: 'CENSUS_HANDS',
        curriculum: Curriculum(
          id: 'census-hands',
          version: '1',
          requirements: [
            inHand(HandConfiguration.right),
            inHand(HandConfiguration.left),
          ],
        ),
      ),
    );

    final byDecision = <int, List<RequirementObservation>>{};
    for (final observation in census.observations) {
      byDecision.putIfAbsent(observation.decision, () => []).add(observation);
    }
    var materialOnly = 0;
    for (final observation in census.observations) {
      expect(
        !observation.fullyRanked || observation.materialRanked,
        isTrue,
        reason: observation.canonical,
      );
    }
    expect(
      census.observations.where((o) => o.materialRanked && !o.fullyRanked),
      isNotEmpty,
    );
    for (final pair in byDecision.values) {
      expect(pair.where((o) => o.served), hasLength(lessThanOrEqualTo(1)));
      if (pair.any((o) => o.servedMaterial && !o.served)) materialOnly++;
    }
    expect(materialOnly, greaterThan(0));
  });

  test('a longer calendar continues the shorter run unchanged', () async {
    final player = PlayerArchetypes.developing.copyWith(
      id: 'developing+${RetrievalMemory.version}',
      retrievalMemory: const RetrievalMemory(initialHalfLifeDays: 60),
    );
    Future<ServiceCensus> run(int days) => runServiceCensus(
      player: player,
      sessions: demoSessions(
        from: demoHistoryStart,
        until: demoHistoryStart.add(Duration(days: days)),
      ),
      intervention: RequirementAllocator(
        k: 1,
        protectionFloor: 0.6,
        relief: ContextRelief(trigger: 2, budget: 1, window: 3),
      ),
    );
    final shorter = await run(12);
    final longer = await run(20);
    String lines(ServiceCensus census, int attempts) => (AttemptJournal(
      JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
    )..appendAll(census.records.take(attempts))).toJsonLines();

    expect(longer.records.length, greaterThan(shorter.records.length));
    expect(
      lines(longer, shorter.records.length),
      lines(shorter, shorter.records.length),
    );
    expect(
      [
        for (final d in longer.decisions.take(shorter.decisions.length))
          d.canonical,
      ],
      [for (final d in shorter.decisions) d.canonical],
    );
  });
}
