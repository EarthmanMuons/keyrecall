import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

void main() {
  Exercise arpeggio(String tonic, HandConfiguration hands) => Exercise.linear(
    material: ArpeggioMaterial(tonic, ArpeggioQuality.minor),
    hands: hands,
  );
  final eTogether = arpeggio('E', HandConfiguration.together);
  final aTogether = arpeggio('A', HandConfiguration.together);
  final eRight = arpeggio('E', HandConfiguration.right);
  final scaleTogether = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.together,
  );
  final together = ContextRelief.groupOf(eTogether);

  ContextRelief relief({int trigger = 3, int budget = 1, int window = 3}) =>
      ContextRelief(trigger: trigger, budget: budget, window: window);

  group('evidence from an outcome', () {
    Outcome outcome({
      bool started = true,
      bool completed = true,
      double? continuity,
    }) => Outcome(
      started: started,
      retrieval: FactualRetrieval.succeeded,
      completed: completed,
      materialRetrieval: 1,
      pitchIntegrity: 1,
      continuity: continuity,
      temporalStability: null,
      achievedTempoRatio: 1,
      topologyAccuracy: 1,
    );

    test('is incomplete whenever the attempt stopped, timed or not', () {
      expect(
        ServiceEvidence.of(outcome(completed: false, continuity: 0.8)),
        ServiceEvidence.incomplete,
      );
      expect(
        ServiceEvidence.of(outcome(completed: false, continuity: 0.1)),
        ServiceEvidence.incomplete,
      );
      expect(
        ServiceEvidence.of(outcome(completed: false)),
        ServiceEvidence.incomplete,
      );
    });

    test('tells managed, unmanaged, untimed, and unstarted apart', () {
      expect(
        ServiceEvidence.of(outcome(continuity: 0.95)),
        ServiceEvidence.managed,
      );
      expect(
        ServiceEvidence.of(outcome(continuity: 0.1)),
        ServiceEvidence.unmanaged,
      );
      expect(ServiceEvidence.of(outcome()), ServiceEvidence.untimed);
      expect(
        ServiceEvidence.of(outcome(started: false, completed: false)),
        ServiceEvidence.notStarted,
      );
    });
  });

  group('settled from a journal', () {
    const learner = LearnerModel();
    final at = DateTime.utc(2026);
    final state = learner.placementState(PlacementTier.beginner, at: at);
    final journal = AttemptJournal(
      JournalHeader(profileId: 'relief', createdAt: at),
    );
    void play(
      Exercise exercise, {
      required bool completed,
      required double continuity,
    }) {
      final outcome = Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: completed,
        materialRetrieval: 1,
        pitchIntegrity: 1,
        continuity: continuity,
        temporalStability: null,
        achievedTempoRatio: 1,
        topologyAccuracy: 1,
      );
      final weights = evidenceWeightsFor(exercise, outcome);
      final index = journal.records.length;
      journal.append(
        AttemptRecord(
          journalSequence: journal.nextSequence,
          identity: AttemptIdentity(
            profileId: 'relief',
            attemptId: 'attempt-$index',
            sessionId: 'session',
            indexInSession: index,
            occurredAt: at,
          ),
          provenance: const ModelProvenance(
            learnerModelVersion: 'test',
            schedulerModelVersion: 'test',
          ),
          exercise: exercise,
          closure: AttemptClosure.measured(
            termination: AttemptTermination.learnerStopped,
            outcome: outcome,
            weights: weights,
            memoryUpdate: learner.applyOutcome(
              state: state,
              exercise: exercise,
              outcome: outcome,
              weights: weights,
              prediction: learner.predict(state, exercise, at: at),
              at: at,
            ),
          ),
        ),
      );
    }

    test('ignores incomplete service, timed or not, and service it did not '
        'choose', () {
      final r = relief();
      for (var i = 0; i < 3; i++) {
        r.serve(journal.records.length);
        play(eTogether, completed: false, continuity: 0.8);
      }
      for (var i = 0; i < 3; i++) {
        play(eTogether, completed: true, continuity: 0.1);
      }
      r.settle(journal, learner);
      expect(r.isRelieved(together), isFalse);
      expect(r.diagnostics['relief evidence incomplete'], 3);

      for (var i = 0; i < 3; i++) {
        r.serve(journal.records.length);
        play(aTogether, completed: true, continuity: 0.1);
      }
      r.settle(journal, learner);
      expect(r.isRelieved(together), isTrue);
      expect(r.diagnostics['relief evidence unmanaged'], 3);
    });
  });

  test('counts only timed, unmanaged attempts allocation served', () {
    final r = relief();
    for (final evidence in [
      ServiceEvidence.notStarted,
      ServiceEvidence.incomplete,
      ServiceEvidence.untimed,
    ]) {
      for (var i = 0; i < 3; i++) {
        r.observe(eTogether, evidence, allocated: true);
      }
    }
    for (var i = 0; i < 3; i++) {
      r.observe(eTogether, ServiceEvidence.unmanaged, allocated: false);
    }
    expect(r.isRelieved(together), isFalse);

    for (var i = 0; i < 3; i++) {
      r.observe(eTogether, ServiceEvidence.unmanaged, allocated: true);
    }
    expect(r.isRelieved(together), isTrue);
  });

  test('shares one budget across materials, within a family and hands', () {
    final r = relief()
      ..observe(eTogether, ServiceEvidence.unmanaged, allocated: true)
      ..observe(eTogether, ServiceEvidence.unmanaged, allocated: true)
      ..observe(aTogether, ServiceEvidence.unmanaged, allocated: true);

    expect(ContextRelief.groupOf(aTogether), together);
    expect(r.isRelieved(together), isTrue);
    expect(r.isRelieved(ContextRelief.groupOf(eRight)), isFalse);
    expect(r.isRelieved(ContextRelief.groupOf(scaleTogether)), isFalse);
  });

  test('a managed attempt clears its own strand, by any route', () {
    final r = relief()
      ..observe(eTogether, ServiceEvidence.unmanaged, allocated: true)
      ..observe(eTogether, ServiceEvidence.unmanaged, allocated: true)
      ..observe(aTogether, ServiceEvidence.unmanaged, allocated: true)
      ..observe(aTogether, ServiceEvidence.unmanaged, allocated: true)
      ..observe(eTogether, ServiceEvidence.managed, allocated: false);

    expect(r.isRelieved(together), isFalse);
    r.observe(aTogether, ServiceEvidence.unmanaged, allocated: true);
    expect(r.isRelieved(together), isTrue);
  });

  test('bounds a relieved group to its budget over its last opportunities', () {
    final r = relief(trigger: 1);
    expect([for (var i = 0; i < 3; i++) r.admit(together)], [true, true, true]);

    r.observe(eTogether, ServiceEvidence.unmanaged, allocated: true);
    expect(
      [for (var i = 0; i < 7; i++) r.admit(together)],
      [true, false, false, true, false, false, true],
    );
    expect(r.admit(ContextRelief.groupOf(eRight)), isTrue);
    expect(r.diagnostics['relief served while relieved'], 3);
    expect(r.diagnostics['relief withheld'], 4);
  });

  group('a seeded run', () {
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryStart.add(const Duration(days: 12)),
    );
    String journal(ServiceCensus census) => (AttemptJournal(
      JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
    )..appendAll(census.records)).toJsonLines();

    test('changes nothing while no group is relieved', () async {
      final plain = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
        intervention: RequirementAllocator(k: 1, protectionFloor: 0.6),
      );
      final unreachable = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
        intervention: RequirementAllocator(
          k: 1,
          protectionFloor: 0.6,
          relief: ContextRelief(trigger: 1 << 20, budget: 0, window: 1),
        ),
      );

      expect(journal(unreachable), journal(plain));
    });

    test('never serves a relieved group with no budget', () async {
      final allocator = RequirementAllocator(
        k: 1,
        protectionFloor: 0.6,
        relief: ContextRelief(trigger: 1, budget: 0, window: 1),
      );
      final census = await runServiceCensus(
        player: PlayerArchetypes.developing,
        sessions: sessions,
        intervention: allocator,
      );

      expect(census.substitutions, isNotEmpty);
      expect(allocator.diagnostics['relief withheld'], greaterThan(0));
      expect(allocator.diagnostics['relief served while relieved'], 0);
    });
  });
}
