import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  group('waiting', () {
    RequirementObservation observed(
      String id, {
      bool due = true,
      bool actionable = true,
      bool served = false,
    }) => RequirementObservation(
      decision: 0,
      requirementId: id,
      materialId: 'C_MAJOR',
      familyId: 'SCALE',
      due: due,
      covered: false,
      admitted: actionable,
      fullyRanked: actionable,
      materialRanked: actionable,
      heldForRecovery: false,
      servedMaterial: served,
      served: served,
    );

    test('counts opportunities, while the journal counter counts due time', () {
      final allocator = RequirementAllocator(k: 2, protectionFloor: 0.6)
        ..record([observed('r')])
        ..record([observed('r', actionable: false)])
        ..record([observed('r')]);

      expect(allocator.waitingFor('r'), 2);
      expect(allocator.journalWaitingFor('r'), 3);
    });

    test('a clock that does not count a slot leaves waiting alone', () {
      final blocked = SelectionBlocked(
        traces: const [],
        selectable: const [],
        pacing: const PacingDecision.inactive([]),
        introductions: IntroductionDecision.inactive(const []),
        reason: BlockedReason.admissionExhausted,
      );
      expect(
        [for (final clock in OpportunityClock.values) clock.counts(blocked)],
        [true, false, false],
      );
    });

    test('clears on service, and is kept while out of scope', () {
      final allocator = RequirementAllocator(k: 2, protectionFloor: 0.6)
        ..record([observed('r'), observed('s')])
        ..record([observed('r', served: true), observed('s')])
        ..record([observed('r')]);

      expect(allocator.waitingFor('r'), 1);
      expect(allocator.waitingFor('s'), 2);
      expect(allocator.journalWaitingFor('s'), 0);
    });
  });

  test('an acquisition offer is an opportunity, under the clocks that count '
      'it, on the decisions characterized before the port', () async {
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryStart.add(const Duration(days: 14)),
    );
    Future<String> digest(OpportunityClock clock) async =>
        (await runServiceCensus(
          player: PlausibilityCohort.profiles[9].player,
          sessions: sessions,
          playerSeed: 100,
          intervention: RequirementAllocator(
            k: 2,
            protectionFloor: 0.6,
            clock: clock,
          ),
        )).digest;

    final everySlot = await digest(OpportunityClock.everySlot);
    expect(
      everySlot,
      '138a195e3117d73bfc8899390fc60cdf6cf4e569b407e4def025b5832b6d5c4c',
    );
    expect(await digest(OpportunityClock.attemptsAndAcquisition), everySlot);
    expect(await digest(OpportunityClock.ordinaryAttempts), isNot(everySlot));
  });

  group('a seeded run', () {
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryStart.add(const Duration(days: 12)),
    );

    test('changes nothing while nothing is owed', () async {
      final baseline = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
      );
      final unreachable = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
        intervention: RequirementAllocator(k: 1 << 20, protectionFloor: 0),
      );

      expect(unreachable.substitutions, isEmpty);
      String journal(ServiceCensus census) => (AttemptJournal(
        JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
      )..appendAll(census.records)).toJsonLines();
      expect(journal(unreachable), journal(baseline));
    });

    test(
      "takes only ranking's slots, for work that survived selection",
      () async {
        final census = await runServiceCensus(
          player: PlayerArchetypes.developing,
          sessions: sessions,
          intervention: RequirementAllocator(k: 1, protectionFloor: 0.7),
        );

        expect(census.substitutions, isNotEmpty);
        for (final substitution in census.substitutions) {
          expect(substitution.displacedStage, SelectionStage.ranking);
          expect(substitution.promotedSelectable, isTrue);
          expect(substitution.promotedFullyEligible, isTrue);
          expect(substitution.promotedServesRequirement, isTrue);
        }
        const learner = LearnerModel();
        expect(
          replayJournal(
            AttemptJournal(
              JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
            )..appendAll(census.records),
            model: learner,
            initial: learner.placementState(
              PlacementTier.beginner,
              at: demoHistoryStart,
            ),
          ).isFaithful,
          isTrue,
        );
      },
    );
  });

  test('accounts for every owed decision once', () async {
    final allocator = RequirementAllocator(k: 1, protectionFloor: 0.6);
    final census = await runServiceCensus(
      player: PlayerArchetypes.developing,
      sessions: demoSessions(
        from: demoHistoryStart,
        until: demoHistoryStart.add(const Duration(days: 12)),
      ),
      intervention: allocator,
    );
    final exclusions = allocator.exclusions;
    expect(exclusions, isNotEmpty);

    final keys = {for (final e in exclusions) (e.decision, e.requirementId)};
    expect(keys, hasLength(exclusions.length));
    final served = {
      for (final o in census.observations)
        if (o.served) (o.decision, o.requirementId),
    };
    for (final exclusion in exclusions) {
      expect(
        exclusion.kind,
        isIn([
          'served',
          'no slot',
          'no candidate',
          'admission',
          'obligation',
          'provisional',
          'filtered',
        ]),
      );
      expect(
        exclusion.kind == 'served',
        served.contains((exclusion.decision, exclusion.requirementId)),
        reason: '${exclusion.decision} ${exclusion.requirementId}',
      );
    }

    final summary = summarizeExclusions(exclusions, census);
    expect(
      (summary['no feasible candidate'] as int) +
          (summary['held for recovery'] as int) +
          (summary['feasible, no slot'] as int) +
          (summary['served'] as int),
      summary['owed decisions'],
    );
  });

  group('an unservable run', () {
    OwedExclusion at(int decision, String kind) => OwedExclusion(
      decision: decision,
      requirementId: 'r',
      materialId: 'm',
      familyId: 'f',
      covered: false,
      allocatable: true,
      kind: kind,
      detail: '',
    );
    int longestRun(List<OwedExclusion> exclusions) {
      final summary = summarizeExclusions(
        exclusions,
        const ServiceCensus([], []),
      );
      final [requirement] = summary['requirements'] as List;
      return (requirement as Map)['longest run'] as int;
    }

    test('continues through a recovery hold without counting it', () {
      expect(
        longestRun([
          at(1, 'provisional'),
          at(2, 'obligation'),
          at(3, 'provisional'),
        ]),
        2,
      );
    });

    test('restarts after a decision where it was not owed', () {
      expect(longestRun([at(1, 'provisional'), at(3, 'provisional')]), 1);
    });
  });
}
