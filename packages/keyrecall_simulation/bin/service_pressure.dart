import 'dart:io';

import 'package:args/args.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// The demo schedule under v1-14 and under an experimental requirement-service
/// rule at each threshold, on fixed pairs of schedule and player seeds.
///
/// Every arm sees the same pairs, so each outcome is reported as its paired
/// difference from v1-14 and how many pairs it improved. A counterfactual, not
/// a candidate for promotion: the rule only takes slots ordinary ranking
/// decided.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('player', defaultsTo: 'developing')
    ..addOption('thresholds', defaultsTo: '50,100')
    ..addOption('unproductive', defaultsTo: '2')
    ..addOption(
      'seeds',
      help: 'schedule:player seed pairs',
      defaultsTo: '0:100,1:101,2:102,3:103,4:104',
    );
  final options = parser.parse(arguments);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('player'),
  );
  final thresholds = [
    for (final value in options.option('thresholds')!.split(','))
      int.parse(value),
  ];
  final unproductive = int.parse(options.option('unproductive')!);
  final pairs = [
    for (final pair in options.option('seeds')!.split(','))
      (int.parse(pair.split(':')[0]), int.parse(pair.split(':')[1])),
  ];

  final arms = ['v1-14', for (final t in thresholds) 'pressure $t'];
  final results = {for (final arm in arms) arm: <ServiceOutcomes>[]};
  for (final (schedule, playerSeed) in pairs) {
    final sessions = demoSessions(
      from: demoHistoryStart,
      until: demoHistoryEnd,
      seed: schedule,
    );
    for (final arm in arms) {
      stderr.writeln('${player.id} seeds $schedule:$playerSeed $arm');
      final threshold = arm == 'v1-14' ? null : int.parse(arm.split(' ').last);
      final pressure = threshold == null
          ? null
          : ServicePressure(
              threshold: threshold,
              unproductiveLimit: unproductive,
            );
      final census = await runServiceCensus(
        player: player,
        sessions: sessions,
        playerSeed: playerSeed,
        pressure: pressure,
      );
      results[arm]!.add(ServiceOutcomes.of(census, pressure: pressure));
    }
  }

  stdout.writeln(
    '\n== ${player.id}, unproductive limit $unproductive, seed pairs '
    '${[for (final (a, b) in pairs) '$a:$b'].join(' ')}',
  );
  void measure(
    String name,
    num Function(ServiceOutcomes) of, {
    required bool higherIsBetter,
    bool percent = false,
  }) {
    String show(num value) => percent
        ? (value * 100).toStringAsFixed(1)
        : value is int
        ? '$value'
        : value.toStringAsFixed(3);
    final baseline = [for (final o in results['v1-14']!) of(o)];
    stdout.writeln(
      '${name.padRight(34)} v1-14       ${baseline.map(show).join(' ')}',
    );
    for (final arm in arms.skip(1)) {
      final values = [for (final o in results[arm]!) of(o)];
      final diffs = [
        for (var i = 0; i < values.length; i++) values[i] - baseline[i],
      ];
      final better = diffs.where((d) => higherIsBetter ? d > 0 : d < 0).length;
      final worse = diffs.where((d) => higherIsBetter ? d < 0 : d > 0).length;
      stdout.writeln(
        '${''.padRight(34)} ${arm.padRight(12)}${values.map(show).join(' ')}'
        '   diff ${diffs.map((d) => '${d >= 0 ? '+' : ''}${show(d)}').join(' ')}'
        '   better $better, worse $worse of ${diffs.length}',
      );
    }
  }

  for (final family in ['ARPEGGIO', 'SCALE']) {
    final name = family.toLowerCase();
    measure(
      '$name covered',
      (o) => o.covered[family] ?? 0,
      higherIsBetter: true,
    );
    measure(
      '$name actionable, never served',
      (o) => o.actionableNeverServed[family] ?? 0,
      higherIsBetter: false,
    );
    measure(
      '$name worst missed run',
      (o) => o.worstMissedRun[family] ?? 0,
      higherIsBetter: false,
    );
    measure(
      '$name p90 missed run',
      (o) => o.p90MissedRun[family] ?? 0,
      higherIsBetter: false,
    );
    measure(
      '$name fading share %',
      (o) => o.fading[family] ?? 0,
      higherIsBetter: false,
      percent: true,
    );
    measure(
      '$name retrieval, all',
      (o) => o.retrievalAll[family] ?? 0,
      higherIsBetter: true,
    );
    measure(
      '$name retrieval, covered',
      (o) => o.retrievalCovered[family] ?? 0,
      higherIsBetter: true,
    );
  }
  measure(
    'covered and healthy at end %',
    (o) => o.healthyAtEnd,
    higherIsBetter: true,
    percent: true,
  );
  measure(
    'incomplete attempts %',
    (o) => o.incomplete,
    higherIsBetter: false,
    percent: true,
  );
  measure(
    'first timed faltered %',
    (o) => o.firstTimedFaltered,
    higherIsBetter: false,
    percent: true,
  );
  measure(
    'material switches %',
    (o) => o.switching,
    higherIsBetter: false,
    percent: true,
  );
  measure('substitutions', (o) => o.substitutions, higherIsBetter: false);
  measure('suspensions', (o) => o.suspensions, higherIsBetter: false);
  measure('suspended at end', (o) => o.suspendedAtEnd, higherIsBetter: false);
  measure(
    'suspended, still actionable',
    (o) => o.suspendedYetActionable,
    higherIsBetter: false,
  );
}
