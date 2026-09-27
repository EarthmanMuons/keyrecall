import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// When harmonic and melodic minor are first introduced, and what the learner
/// held at that moment, across goal and focus shapes.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('slots', defaultsTo: '120')
    ..addOption('jobs', defaultsTo: '8')
    ..addFlag('factorial', help: 'cross the two altered-form switches')
    ..addFlag('breadth', help: 'vary the core retrieval breadth')
    ..addMultiOption(
      'scope',
      allowed: [for (final scope in AlteredFormScope.values) scope.name],
    );
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final jobs = int.parse(options.option('jobs')!);

  final stopwatch = Stopwatch()..start();
  final runs = await runAlteredFormMatrix(
    arms: options.flag('factorial')
        ? AlteredFormArm.factorial
        : options.flag('breadth')
        ? AlteredFormArm.breadth
        : [AlteredFormArm.shipped],
    scopes: options.multiOption('scope').isEmpty
        ? AlteredFormScope.values
        : [
            for (final name in options.multiOption('scope'))
              AlteredFormScope.values.byName(name),
          ],
    seeds: seeds,
    slots: slots,
    parallelism: jobs,
    onProgress: (completed, total) {
      if (completed == total || completed % 16 == 0) {
        stderr.writeln(
          'completed $completed/$total trajectories '
          '(${stopwatch.elapsed.inSeconds}s)',
        );
      }
    },
  );

  stdout
    ..writeln(
      'altered-form census: $seeds seeds x $slots slots, $jobs jobs, '
      '${stopwatch.elapsed.inSeconds}s',
    )
    ..writeln(
      [
        'arm',
        'scope',
        'player',
        'runs',
        'harmonic',
        'harmonic_slot',
        'majors',
        'naturals',
        'bands',
        'own_natural',
        'waiver_open',
        'melodic',
        'melodic_slot',
        'support_share',
        'live_slots',
        'live_picks',
        'live_after_open',
        'blocked',
        'caught_up',
        'same_tonic',
        'minor_hands',
        'first_managed',
        'first_supplied',
        'first_recovery',
        'window_altered',
        'core_retained',
        'altered_covered',
      ].join('\t'),
    );

  final groups = <String, List<AlteredFormRun>>{};
  for (final run in runs) {
    groups
        .putIfAbsent('${run.armId}/${run.scope.name}/${run.playerId}', () => [])
        .add(run);
  }
  for (final group in groups.values) {
    final first = group.first;
    final harmonic = [
      for (final run in group) ?run.first(ScaleForm.harmonicMinor),
    ];
    final melodic = [
      for (final run in group) ?run.first(ScaleForm.melodicMinor),
    ];
    final attempts = [for (final run in group) ...run.firstAttempts];
    final window = [for (final run in group) ...run.afterOpening(_window)];
    final selections = group.fold(0, (sum, run) => sum + run.selections);
    final support = group.fold(0, (sum, run) => sum + run.supportSelections);
    stdout.writeln(
      [
        first.armId,
        first.scope.name,
        first.playerId,
        '${group.length}',
        '${harmonic.length}',
        _mean(harmonic.map((introduction) => introduction.slot)),
        _mean(harmonic.map((introduction) => introduction.majorsRetrieved)),
        _mean(
          harmonic.map((introduction) => introduction.naturalMinorsRetrieved),
        ),
        _mean(harmonic.map((introduction) => introduction.bandsRetrieved)),
        '${harmonic.where((introduction) => introduction.naturalMinorRetrieved).length}',
        '${harmonic.where((introduction) => introduction.waiverOpen).length}',
        '${melodic.length}',
        _mean(melodic.map((introduction) => introduction.slot)),
        selections == 0 ? '-' : (support / selections).toStringAsFixed(3),
        _mean(group.map((run) => run.liveSupportSlots)),
        _mean(group.map((run) => run.liveSupportSelections)),
        _mean(group.map((run) => run.liveSupportSelectionsAfterOpening)),
        _terminals(group, AlteredFormTerminal.blocked),
        _terminals(group, AlteredFormTerminal.caughtUp),
        _mean(harmonic.map((introduction) => introduction.sameTonicRetrievals)),
        _mean(
          harmonic.map(
            (introduction) => introduction.naturalMinorHandsRetrieved,
          ),
        ),
        _share(attempts, (attempt) => attempt.managed),
        _share(attempts, (attempt) => attempt.guidance.isMaterialSupplied),
        _share(attempts, (attempt) => attempt.recovery),
        _share(
          window,
          (pick) => pick.form != null && !coreForms.contains(pick.form),
        ),
        _fraction([
          for (final run in group) ?run.coreRetainedAfterOpening(_window),
        ]),
        '${group.fold(0, (sum, run) => sum + run.alteredCovered)}/'
            '${group.fold(0, (sum, run) => sum + run.alteredTargets)}',
      ].join('\t'),
    );
  }
}

/// Picks read after the first altered form is introduced.
const _window = 40;

String _share<T>(List<T> items, bool Function(T) test) => items.isEmpty
    ? '-'
    : (items.where(test).length / items.length).toStringAsFixed(3);

String _fraction(List<double> values) => values.isEmpty
    ? '-'
    : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(3);

String _mean(Iterable<int> values) => values.isEmpty
    ? '-'
    : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1);

/// How many runs ended at [terminal], and the mean slot they ended on.
String _terminals(List<AlteredFormRun> group, AlteredFormTerminal terminal) {
  final ended = [
    for (final run in group)
      if (run.terminal == terminal) run.terminalSlot!,
  ];
  return ended.isEmpty ? '0' : '${ended.length}@${_mean(ended)}';
}
