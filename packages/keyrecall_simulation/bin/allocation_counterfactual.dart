import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The allocation-only counterfactual against v1-14 and service pressure at
/// 100, on fixed schedule:player seed pairs.
///
/// Running writes one JSON line per trajectory, so a grid can be split across
/// processes by player and seed; `--report` reads the lines back and compares
/// every arm with v1-14 pair by pair.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('player', defaultsTo: 'developing')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption(
      'arms',
      defaultsTo:
          'v1-14,pressure-100,alloc-2-0.60,alloc-2-0.70,alloc-4-0.60,'
          'alloc-4-0.70,alloc-8-0.60,alloc-8-0.70',
    )
    ..addFlag('report', help: 'compare the JSON lines given as arguments');
  final options = parser.parse(arguments);
  if (options.flag('report')) {
    _report([
      for (final path in options.rest)
        for (final line in File(path).readAsLinesSync())
          if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ]);
    return;
  }

  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('player'),
  );
  for (final pair in options.option('seeds')!.split(',')) {
    final [schedule, playerSeed] = [
      for (final part in pair.split(':')) int.parse(part),
    ];
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryEnd,
      seed: schedule,
    );
    for (final arm in options.option('arms')!.split(',')) {
      stderr.writeln('${player.id} $pair $arm');
      final intervention = _intervention(arm);
      final census = await runServiceCensus(
        player: player,
        sessions: sessions,
        playerSeed: playerSeed,
        intervention: intervention,
      );
      stdout.writeln(
        jsonEncode({
          'player': player.id,
          'seeds': pair,
          'arm': arm,
          'outcomes': ServiceOutcomes.of(
            census,
            intervention: intervention,
          ).toJson(),
          if (intervention is RequirementAllocator)
            'exclusions': summarizeExclusions(intervention.exclusions, census),
        }),
      );
    }
  }
}

ServiceIntervention? _intervention(String arm) {
  final parts = arm.split('-');
  return switch (parts.first) {
    'v1' => null,
    'pressure' => ServicePressure(threshold: int.parse(parts[1])),
    'alloc' => RequirementAllocator(
      k: int.parse(parts[1]),
      protectionFloor: double.parse(parts[2]),
    ),
    _ => throw ArgumentError.value(arm, 'arm'),
  };
}

void _report(List<Map<String, Object?>> runs) {
  final players = {for (final run in runs) run['player'] as String};
  for (final player in players) {
    final own = [
      for (final run in runs)
        if (run['player'] == player) run,
    ];
    final seeds = {for (final run in own) run['seeds'] as String}.toList();
    final arms = <String>[];
    for (final run in own) {
      if (!arms.contains(run['arm'])) arms.add(run['arm'] as String);
    }
    Map<String, Object?>? outcomesOf(String arm, String seed) =>
        own.firstWhere(
              (run) => run['arm'] == arm && run['seeds'] == seed,
              orElse: () => const {},
            )['outcomes']
            as Map<String, Object?>?;

    stdout.writeln('\n== $player, seed pairs ${seeds.join(' ')}');
    void measure(
      String label,
      num? Function(Map<String, Object?>) of, {
      required bool higherIsBetter,
    }) {
      List<num?> values(String arm) => [
        for (final seed in seeds)
          switch (outcomesOf(arm, seed)) {
            final outcomes? => of(outcomes),
            null => null,
          },
      ];
      String show(num? value) => value == null
          ? '-'
          : value is int
          ? '$value'
          : value.toStringAsFixed(3);
      final baseline = values('v1-14');
      stdout.writeln(label);
      for (final arm in arms) {
        final own = values(arm);
        var better = 0, worse = 0;
        for (var i = 0; i < own.length; i++) {
          final a = own[i], b = baseline[i];
          if (arm == 'v1-14' || a == null || b == null || a == b) continue;
          if ((a > b) == higherIsBetter) {
            better++;
          } else {
            worse++;
          }
        }
        stdout.writeln(
          '  ${arm.padRight(14)}${own.map((v) => show(v).padLeft(9)).join()}'
          '${arm == 'v1-14' ? '' : '   better $better, worse $worse'}',
        );
      }
    }

    num? family(Map<String, Object?> o, String key, String family) =>
        (o[key] as Map<String, Object?>)[family] as num?;
    for (final name in ['ARPEGGIO', 'SCALE']) {
      final lower = name.toLowerCase();
      for (final (key, higher) in [
        ('covered', true),
        ('actionable never served', false),
        ('median first covered', false),
        ('worst missed run', false),
        ('p90 missed run', false),
        ('worst missed allocatable', false),
        ('p90 missed allocatable', false),
        ('fading', false),
        ('retrieval all', true),
        ('retrieval covered', true),
      ]) {
        measure(
          '$lower $key',
          (o) => family(o, key, name),
          higherIsBetter: higher,
        );
      }
    }
    for (final (key, higher) in [
      ('healthy at end', true),
      ('incomplete', false),
      ('first timed faltered', false),
      ('switching', false),
      ('substitutions', false),
    ]) {
      measure(key, (o) => o[key] as num?, higherIsBetter: higher);
    }
    final diagnostics = {
      for (final run in own)
        ...(run['outcomes'] as Map<String, Object?>)['diagnostics']
            as Map<String, Object?>,
    }.keys;
    for (final key in diagnostics) {
      measure(
        'diagnostic: $key',
        (o) => (o['diagnostics'] as Map<String, Object?>)[key] as num?,
        higherIsBetter: false,
      );
    }
  }
}
