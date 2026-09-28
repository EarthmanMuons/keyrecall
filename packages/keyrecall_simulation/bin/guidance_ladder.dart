import 'package:args/args.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Why a player stays on supported rungs, over the first and second half of
/// their sessions.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('player', defaultsTo: 'true_beginner')
    ..addOption('scope', defaultsTo: 'foundations')
    ..addOption('seeds', defaultsTo: '4');
  final options = parser.parse(arguments);
  final player = PlayerArchetypes.all.firstWhere(
    (candidate) => candidate.id == options.option('player'),
  );
  final scope = GoalTrajectoryScope.values.byName(options.option('scope')!);
  final slots = [
    for (var seed = 0; seed < int.parse(options.option('seeds')!); seed++)
      ...await traceGuidanceLadder(scope: scope, player: player, seed: seed),
  ];
  const policy = RequirementCompletionPolicy.standard;

  for (final (label, half) in [
    ('first half', slots.where((slot) => slot.session < 5)),
    ('second half', slots.where((slot) => slot.session >= 5)),
  ]) {
    final picks = half.toList();
    print('$label: ${picks.length} attempts');
    for (final rung in Rung.values) {
      final at = picks.where((slot) => slot.rung == rung).toList();
      final retrieved = at
          .where((slot) => slot.retrieval == FactualRetrieval.succeeded)
          .toList();
      print(
        '  ${rung.name}: ${at.length}, retrieved ${retrieved.length}, '
        'meeting coverage pitch and timing '
        '${retrieved.where((slot) => slot.meets(policy)).length}',
      );
    }
    final fates = <String, int>{};
    for (final slot in picks) {
      if (slot.unguidedFate case final fate?) {
        fates[fate] = (fates[fate] ?? 0) + 1;
      }
    }
    print('  unguided version of a supported attempt: $fates');
    final bypasses = <String, int>{};
    for (final slot in picks.where((slot) => slot.rung == Rung.unguided)) {
      final key = slot.bypass?.id ?? 'band';
      bypasses[key] = (bypasses[key] ?? 0) + 1;
    }
    print('  unguided attempts admitted through: $bypasses');
  }
}
