import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How each scope requirement was served over the seeded demo schedule: when
/// it was due and choosable, how often it was chosen, how long it waited, and
/// what won instead.
///
/// Requirement service is the practice layer's own notion of need. Work on a
/// covered requirement that is not due is reported separately as progression,
/// and never counts as a deferral.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption(
      'player',
      defaultsTo: ['true_beginner', 'developing', 'advanced'],
    )
    ..addOption('days')
    ..addOption('top', defaultsTo: '8');
  final options = parser.parse(arguments);
  final until = switch (options.option('days')) {
    final days? => demoHistoryStart.add(Duration(days: int.parse(days))),
    null => demoHistoryEnd,
  };
  final top = int.parse(options.option('top')!);

  for (final id in options.multiOption('player')) {
    final player = PlayerArchetypes.all.firstWhere((p) => p.id == id);
    final census = await runServiceCensus(
      player: player,
      sessions: demoSessions(from: demoHistoryStart, until: until),
    );
    _report(id, census, top);
  }
}

void _report(String player, ServiceCensus census, int top) {
  final requirements = census.requirements;
  final families = {for (final r in requirements) r.familyId}.toList()..sort();
  final decisions = requirements.isEmpty ? 0 : requirements.first.decisions;
  stdout.writeln('\n== $player: $decisions decisions, digest ${census.digest}');

  for (final family in families) {
    final own = [
      for (final r in requirements)
        if (r.familyId == family) r,
    ];
    int sum(int Function(RequirementService) of) =>
        own.fold(0, (total, r) => total + of(r));
    final trajectories = <String, int>{};
    for (final r in own) {
      trajectories.update(r.trajectory, (n) => n + 1, ifAbsent: () => 1);
    }
    final losses = <String, int>{};
    for (final r in own) {
      r.losses.forEach(
        (reason, n) => losses.update(reason, (m) => m + n, ifAbsent: () => n),
      );
    }
    final reasons = losses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    stdout
      ..writeln('\n$family: ${own.length} requirements')
      ..writeln(
        '  trajectories   ${[for (final e in trajectories.entries) '${e.key} ${e.value}'].join(', ')}',
      )
      ..writeln(
        '  opportunities  due ${sum((r) => r.due)}, actionable '
        '${sum((r) => r.actionable)}, served ${sum((r) => r.served)}, '
        'deferred ${sum((r) => r.deferred)}, blocked ${sum((r) => r.blocked)} '
        '(held for recovery ${sum((r) => r.heldForRecovery)}), served while '
        'not due ${sum((r) => r.servedWhileNotDue)}',
      )
      ..writeln(
        '  deferred lost  ${[for (final e in reasons.take(top)) '${e.key} ${e.value}'].join(', ')}',
      )
      ..writeln('  lost to        ${_lostTo(census, family, top)}')
      ..writeln(
        '  progression    opportunities ${sum((r) => r.progressionOpportunities)}, '
        'served ${sum((r) => r.progressionServed)}, longest run of missed opportunities '
        '${own.fold(0, (m, r) => r.longestMissedProgression > m ? r.longestMissedProgression : m)}',
      );
    final waiting = [...own]
      ..sort(
        (a, b) => b.longestMissedOpportunities.compareTo(
          a.longestMissedOpportunities,
        ),
      );
    for (final r in waiting.take(top)) {
      if (r.longestMissedOpportunities == 0) break;
      stdout.writeln(
        '    ${r.materialId.padRight(28)} actionable ${r.actionable}, served '
        '${r.served}, longest run of missed actionable opportunities '
        '${r.longestMissedOpportunities}, longest run of decisions due without '
        'service ${r.longestDueWithoutService}',
      );
    }
  }
}

/// What won the decisions at which [family] had a deferred requirement, by
/// the winner's family, purpose, and whether its own requirement was due.
String _lostTo(ServiceCensus census, String family, int top) {
  final deferring = {
    for (final observation in census.observations)
      if (observation.familyId == family && observation.deferred)
        observation.decision,
  };
  final winners = <String, int>{};
  for (final decision in census.decisions) {
    if (!deferring.contains(decision.decision)) continue;
    final key = decision.familyId == null
        ? decision.stage
        : '${decision.familyId!.toLowerCase()} ${decision.purpose} '
              '(${decision.due! ? 'due' : 'not due'})';
    winners.update(key, (n) => n + 1, ifAbsent: () => 1);
  }
  final ranked = winners.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return '${deferring.length} decisions: '
      '${[for (final e in ranked.take(top)) '${e.key} ${e.value}'].join(', ')}';
}
