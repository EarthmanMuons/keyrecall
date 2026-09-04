import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('slots', defaultsTo: '80')
    ..addOption('jobs', defaultsTo: '8')
    ..addOption(
      'mode',
      allowed: ['baseline', 'transfer'],
      defaultsTo: 'baseline',
    );
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final jobs = int.parse(options.option('jobs')!);
  final mode = options.option('mode')!;
  final arms = switch (mode) {
    'baseline' => const [ArpeggioPolicyArm.baseline],
    'transfer' => ArpeggioPolicyArm.sensitivityArms.where(
      (arm) => arm.id.startsWith('transfer_'),
    ),
    _ => throw StateError('unreachable mode $mode'),
  };
  final scopes = mode == 'baseline'
      ? ArpeggioPolicyScope.values
      : const [
          ArpeggioPolicyScope.fullArpeggioCorpus,
          ArpeggioPolicyScope.fullMixed,
        ];

  final stopwatch = Stopwatch()..start();
  final runs = await runArpeggioPolicyMatrix(
    arms: arms,
    scopes: scopes,
    seeds: seeds,
    slots: slots,
    parallelism: jobs,
    onProgress: (completed, total) {
      if (completed == total || completed % 8 == 0) {
        stderr.writeln(
          'completed $completed/$total trajectories '
          '(${stopwatch.elapsed.inSeconds}s)',
        );
      }
    },
  );

  stdout
    ..writeln(
      'full-catalog arpeggio policy $mode: $seeds seeds x $slots slots, '
      '$jobs jobs, '
      '${stopwatch.elapsed.inSeconds}s',
    )
    ..writeln(_header);
  for (final group in _grouped(runs)) {
    stdout.writeln(_row(group));
  }

  if (mode == 'baseline') {
    stdout
      ..writeln()
      ..writeln('baseline full-mixed shift from scale-only milestones')
      ..writeln('player\tpaired\tfirst_scale\tfirst_2oct\tfirst_ht');
    for (final player in PlayerArchetypes.all) {
      final pairs = <(ArpeggioPolicyRun, ArpeggioPolicyRun)>[];
      for (var seed = 0; seed < seeds; seed++) {
        final scale = _find(
          runs,
          ArpeggioPolicyArm.baseline.id,
          ArpeggioPolicyScope.scaleOnly,
          player.id,
          seed,
        );
        final mixed = _find(
          runs,
          ArpeggioPolicyArm.baseline.id,
          ArpeggioPolicyScope.fullMixed,
          player.id,
          seed,
        );
        if (scale != null && mixed != null) pairs.add((scale, mixed));
      }
      stdout.writeln(
        '${player.id}\t${pairs.length}\t'
        '${_meanDelta(pairs, (run) => run.firstScaleSlot)}\t'
        '${_meanDelta(pairs, (run) => run.firstTwoOctaveScaleSlot)}\t'
        '${_meanDelta(pairs, (run) => run.firstHandsTogetherScaleSlot)}',
      );
    }
  }

  stdout
    ..writeln()
    ..writeln('fingering-family selection distribution')
    ..writeln('arm\tscope\tfingering_family\tselections\tshare');
  for (final armId in {for (final run in runs) run.armId}) {
    for (final scope in scopes.where(
      (scope) => scope != ArpeggioPolicyScope.scaleOnly,
    )) {
      final scopeRuns = runs
          .where((run) => run.armId == armId && run.scope == scope)
          .toList();
      final selections = _combinedCounts(
        scopeRuns.map((run) => run.arpeggioFingeringFamilySelections),
      );
      final total = _sum(selections.values);
      for (final entry
          in selections.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) {
        stdout.writeln(
          '$armId\t${scope.name}\t${entry.key}\t${entry.value}\t'
          '${(entry.value / total).toStringAsFixed(3)}',
        );
      }
    }
  }
}

const _header =
    'arm\tscope\tplayer\truns\tselections\tarpeggio_share\tmaterial_peak\t'
    'materials_selected\tgeometry_peak\trh_only_share\tlh_only_share\t'
    'ht_share\tfloor_invoke_rate\tfloor_select_rate\tmax_floor_run\t'
    'first_arpeggio\tfirst_rh\tfirst_lh\tfirst_ht\tfirst_2oct\tfirst_4oct\t'
    'prediction_p10\tprediction_p50\tprediction_p90\tadmitted_in_band\t'
    'blocked_rate\tcaught_up_rate\tlimit_rate\tinvalid_rate\tstop_material\t'
    'stop_hands\tstop_span';

Iterable<List<ArpeggioPolicyRun>> _grouped(List<ArpeggioPolicyRun> runs) sync* {
  for (final armId in {for (final run in runs) run.armId}) {
    for (final scope in ArpeggioPolicyScope.values) {
      for (final player in PlayerArchetypes.all) {
        final group = runs
            .where(
              (run) =>
                  run.armId == armId &&
                  run.scope == scope &&
                  run.playerId == player.id,
            )
            .toList();
        if (group.isNotEmpty) yield group;
      }
    }
  }
}

String _row(List<ArpeggioPolicyRun> runs) {
  final first = runs.first;
  final schedulerDecisions = _sum(runs.map((run) => run.schedulerDecisions));
  final selections = _sum(runs.map((run) => run.selections));
  final evaluated = _sum(runs.map((run) => run.arpeggioCandidatesEvaluated));
  final predictions = [
    for (final run in runs) ...run.admittedArpeggioPredictions,
  ]..sort();
  final materialSelections = <String, int>{};
  final fingeringFamilySelections = <String, int>{};
  final handSelections = <HandConfiguration, int>{};
  for (final run in runs) {
    for (final entry in run.arpeggioMaterialSelections.entries) {
      materialSelections[entry.key] =
          (materialSelections[entry.key] ?? 0) + entry.value;
    }
    for (final entry in run.arpeggioFingeringFamilySelections.entries) {
      fingeringFamilySelections[entry.key] =
          (fingeringFamilySelections[entry.key] ?? 0) + entry.value;
    }
    for (final entry in run.arpeggioHandSelections.entries) {
      handSelections[entry.key] =
          (handSelections[entry.key] ?? 0) + entry.value;
    }
  }
  final arpeggioSelections = _sum(materialSelections.values);
  final fingeringFamilyExposures = _sum(fingeringFamilySelections.values);
  String rate(int count, int total) =>
      total == 0 ? '-' : (count / total).toStringAsFixed(3);
  String firstSlot(int? Function(ArpeggioPolicyRun) read) {
    final values = runs.map(read).whereType<int>().toList();
    return values.isEmpty
        ? '-'
        : '${(values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1)}'
              '[${values.length}/${runs.length}]';
  }

  return [
    first.armId,
    first.scope.name,
    first.playerId,
    '${runs.length}',
    '$selections',
    rate(
      _sum(
        runs.map(
          (run) =>
              run.familySelections[TechnicalMaterial.arpeggioFamilyId] ?? 0,
        ),
      ),
      selections,
    ),
    rate(
      materialSelections.values.fold(0, (a, b) => a > b ? a : b),
      arpeggioSelections,
    ),
    '${materialSelections.length}',
    rate(
      fingeringFamilySelections.values.fold(0, (a, b) => a > b ? a : b),
      fingeringFamilyExposures,
    ),
    rate(handSelections[HandConfiguration.right] ?? 0, arpeggioSelections),
    rate(handSelections[HandConfiguration.left] ?? 0, arpeggioSelections),
    rate(handSelections[HandConfiguration.together] ?? 0, arpeggioSelections),
    rate(_sum(runs.map((run) => run.floorInvocations)), schedulerDecisions),
    rate(_sum(runs.map((run) => run.floorSelections)), selections),
    '${runs.map((run) => run.longestFloorRun).fold(0, (a, b) => a > b ? a : b)}',
    firstSlot((run) => run.firstArpeggioSlot),
    firstSlot((run) => run.firstRightHandArpeggioSlot),
    firstSlot((run) => run.firstLeftHandArpeggioSlot),
    firstSlot((run) => run.firstHandsTogetherArpeggioSlot),
    firstSlot((run) => run.firstTwoOctaveArpeggioSlot),
    firstSlot((run) => run.firstFourOctaveArpeggioSlot),
    _quantile(predictions, 0.1),
    _quantile(predictions, 0.5),
    _quantile(predictions, 0.9),
    rate(
      _sum(runs.map((run) => run.admittedArpeggioCandidatesInBand)),
      predictions.length,
    ),
    rate(
      runs
          .where((run) => run.terminal == ArpeggioPolicyTerminal.blocked)
          .length,
      runs.length,
    ),
    rate(
      runs
          .where((run) => run.terminal == ArpeggioPolicyTerminal.caughtUp)
          .length,
      runs.length,
    ),
    rate(
      runs
          .where((run) => run.terminal == ArpeggioPolicyTerminal.slotLimit)
          .length,
      runs.length,
    ),
    rate(
      runs
          .where((run) => run.terminal == ArpeggioPolicyTerminal.invalid)
          .length,
      runs.length,
    ),
    rate(
      _stops(runs, EligibilityReason.materialProgressionPrerequisite),
      evaluated,
    ),
    rate(_stops(runs, EligibilityReason.handsTogetherPrerequisite), evaluated),
    rate(_stops(runs, EligibilityReason.octaveSpanPrerequisite), evaluated),
  ].join('\t');
}

int _stops(List<ArpeggioPolicyRun> runs, EligibilityReason reason) =>
    _sum(runs.map((run) => run.progressionStops[reason] ?? 0));

int _sum(Iterable<int> values) => values.fold(0, (sum, value) => sum + value);

Map<K, int> _combinedCounts<K>(Iterable<Map<K, int>> counts) {
  final combined = <K, int>{};
  for (final count in counts) {
    for (final entry in count.entries) {
      combined[entry.key] = (combined[entry.key] ?? 0) + entry.value;
    }
  }
  return combined;
}

String _quantile(List<double> sorted, double probability) => sorted.isEmpty
    ? '-'
    : sorted[((sorted.length - 1) * probability).round()].toStringAsFixed(3);

ArpeggioPolicyRun? _find(
  List<ArpeggioPolicyRun> runs,
  String arm,
  ArpeggioPolicyScope scope,
  String player,
  int seed,
) {
  for (final run in runs) {
    if (run.armId == arm &&
        run.scope == scope &&
        run.playerId == player &&
        run.seed == seed) {
      return run;
    }
  }
  return null;
}

String _meanDelta(
  List<(ArpeggioPolicyRun, ArpeggioPolicyRun)> pairs,
  int? Function(ArpeggioPolicyRun) read,
) {
  final deltas = <int>[];
  for (final (scale, mixed) in pairs) {
    final before = read(scale);
    final after = read(mixed);
    if (before != null && after != null) deltas.add(after - before);
  }
  return deltas.isEmpty
      ? '-'
      : (deltas.reduce((a, b) => a + b) / deltas.length).toStringAsFixed(1);
}
