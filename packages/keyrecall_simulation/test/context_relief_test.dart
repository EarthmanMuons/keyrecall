import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

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
