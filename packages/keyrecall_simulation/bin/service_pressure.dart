import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The seeded demo schedule under v1-14 and under an experimental
/// requirement-service rule at each [threshold], side by side.
///
/// A counterfactual, not a candidate for promotion: the rule runs beside the
/// scheduler and only ever takes a slot ordinary ranking decided.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('player', defaultsTo: 'developing')
    ..addOption('thresholds', defaultsTo: '25,50,100,200')
    ..addOption('unproductive', defaultsTo: '2')
    ..addOption('days');
  final options = parser.parse(arguments);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('player'),
  );
  final thresholds = [
    for (final value in options.option('thresholds')!.split(','))
      int.parse(value),
  ];
  final unproductive = int.parse(options.option('unproductive')!);
  final until = switch (options.option('days')) {
    final days? => demoHistoryStart.add(Duration(days: int.parse(days))),
    null => demoHistoryEnd,
  };
  final sessions = demoSessions(from: demoHistoryStart, until: until);

  final arms = <String, ServiceCensus>{
    'v1-14': await runServiceCensus(player: player, sessions: sessions),
  };
  final outcomes = {'v1-14': ServiceOutcomes.of(arms['v1-14']!)};
  for (final threshold in thresholds) {
    stderr.writeln('${player.id}: threshold $threshold');
    final pressure = ServicePressure(
      threshold: threshold,
      unproductiveLimit: unproductive,
    );
    final arm = 'pressure $threshold';
    arms[arm] = await runServiceCensus(
      player: player,
      sessions: sessions,
      pressure: pressure,
    );
    outcomes[arm] = ServiceOutcomes.of(arms[arm]!, pressure: pressure);
  }

  String row(String label, String Function(ServiceOutcomes) cell) =>
      '${label.padRight(34)}${[for (final o in outcomes.values) cell(o).padLeft(14)].join()}';
  String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  stdout
    ..writeln('\n== ${player.id}, unproductive limit $unproductive')
    ..writeln(
      row('', (_) => '').substring(0, 34) +
          [for (final key in outcomes.keys) key.padLeft(14)].join(),
    );
  for (final family in ['ARPEGGIO', 'SCALE']) {
    final name = family.toLowerCase();
    stdout
      ..writeln(row('$name covered', (o) => '${o.covered[family] ?? 0}'))
      ..writeln(
        row(
          '$name actionable, never served',
          (o) => '${o.actionableNeverServed[family] ?? 0}',
        ),
      )
      ..writeln(
        row(
          '$name worst missed run',
          (o) => '${o.worstMissedRun[family] ?? 0}',
        ),
      )
      ..writeln(
        row(
          '$name fading decisions',
          (o) => '${o.fadingDecisions[family] ?? 0}',
        ),
      );
  }
  stdout
    ..writeln(row('covered and healthy at end', (o) => percent(o.healthyAtEnd)))
    ..writeln(row('incomplete attempts', (o) => percent(o.incomplete)))
    ..writeln(
      row('first timed attempt faltered', (o) => percent(o.firstTimedFaltered)),
    )
    ..writeln(row('material switches', (o) => percent(o.switching)))
    ..writeln(row('substitutions', (o) => '${o.substitutions}'))
    ..writeln(row('suspensions', (o) => '${o.suspensions}'));
  for (final MapEntry(:key, :value) in arms.entries) {
    if (value.substitutions.isEmpty) continue;
    final behind = <String, int>{};
    for (final substitution in value.substitutions) {
      behind.update(substitution.behindOn, (n) => n + 1, ifAbsent: () => 1);
    }
    final ranked = behind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    stdout.writeln(
      '$key promoted work was behind on: '
      '${[for (final e in ranked.take(4)) '${e.key} ${e.value}'].join(', ')}',
    );
  }
}
