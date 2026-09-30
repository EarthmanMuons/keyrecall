import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How often candidate order decides a slot, and along which dimensions.
///
/// Reads the production trajectory of every archetype and reports each slot
/// whose top rank was shared by candidates that ranking picks differently in
/// generated and in reversed order. Observational: nothing chosen changes.
///
/// With `--goal`, each trajectory runs through the production practice
/// session under that goal instead, which is how the app always practises.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('slots', defaultsTo: '40')
    ..addOption(
      'catalog',
      defaultsTo: 'v1',
      allowed: ['v1', 'scales', 'mixed'],
      help: 'v1 scales, every scale, or every scale with the proof arpeggios',
    )
    ..addOption(
      'goal',
      defaultsTo: 'none',
      allowed: [
        'none',
        for (final scope in GoalTrajectoryScope.values) scope.name,
      ],
      help: 'run under a production goal, which ignores --catalog and --slots',
    )
    ..addOption('sessions', defaultsTo: '10')
    ..addOption('slots-per-session', defaultsTo: '20');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final goal = options.option('goal')!;
  final scope = goal == 'none' ? null : GoalTrajectoryScope.values.byName(goal);
  final sessions = int.parse(options.option('sessions')!);
  final slotsPerSession = int.parse(options.option('slots-per-session')!);
  final catalog = scope == null
      ? 'catalog ${options.option('catalog')!}'
      : 'goal $goal';
  final List<TechnicalMaterial> materials = switch (catalog) {
    'scales' => allScales,
    'mixed' => [...allScales, ...proofArpeggios],
    _ => v1ScaleCatalog,
  };

  var slotCount = 0;
  var selections = 0;
  final ties = <RankTie>[];
  final byPlayer = <String, (int, int)>{};
  for (final player in PlayerArchetypes.all) {
    for (var seed = 0; seed < seeds; seed++) {
      final census = scope == null
          ? censusRankTies(
              player: player,
              seed: seed,
              materials: materials,
              slots: slots,
            )
          : await censusGoalRankTies(
              scope: scope,
              player: player,
              seed: seed,
              sessions: sessions,
              slotsPerSession: slotsPerSession,
            );
      slotCount += census.slots;
      selections += census.slotsWithSelection;
      ties.addAll(census.ties);
      final (seen, decided) = byPlayer[player.id] ?? (0, 0);
      byPlayer[player.id] = (
        seen + census.slotsWithSelection,
        decided + census.ties.length,
      );
    }
    stderr.writeln('${player.id} done');
  }

  final presented = [
    for (final tie in ties)
      if (tie.presented) tie,
  ];
  String share(int part, int whole) =>
      whole == 0 ? '-' : '${(100 * part / whole).toStringAsFixed(1)}%';

  stdout
    ..writeln(
      'rank tie census: $catalog, $seeds seeds, '
      '${scope == null ? '$slots slots' : '$sessions sessions of $slotsPerSession slots'}, '
      '${PlayerArchetypes.all.length} archetypes',
    )
    ..writeln(
      'slots $slotCount, with a selection $selections, decided by candidate '
      'order ${ties.length} (${share(ties.length, selections)}), of which '
      'presented ${presented.length} (${share(presented.length, selections)})',
    )
    ..writeln()
    ..writeln('tied candidates at the top rank, presented ties:');
  final sizes = <int, int>{};
  for (final tie in presented) {
    sizes[tie.tied] = (sizes[tie.tied] ?? 0) + 1;
  }
  for (final size in sizes.keys.toList()..sort()) {
    stdout.writeln('  $size\t${sizes[size]}');
  }

  stdout
    ..writeln()
    ..writeln('by archetype: selections, decided by order, share');
  for (final MapEntry(key: id, value: (seen, decided)) in byPlayer.entries) {
    stdout.writeln('  $id\t$seen\t$decided\t${share(decided, seen)}');
  }

  final kindsOfTie = <String, int>{};
  for (final tie in presented) {
    final differing = {
      for (final dimension in tie.differences.keys)
        if (exerciseDimensions.contains(dimension)) dimension,
    };
    for (final kind in [
      if (tie.isMaterialTie) 'material',
      if (!tie.isMaterialTie && differing.contains('direction'))
        'same material, differs in direction',
      if (!tie.isMaterialTie && differing.contains('octaves'))
        'same material, differs in span',
      if (!tie.isMaterialTie &&
          differing.length == 1 &&
          differing.contains('hands'))
        'same material, differs only in hands',
      if (!tie.isMaterialTie &&
          !differing.contains('direction') &&
          !differing.contains('octaves') &&
          !(differing.length == 1 && differing.contains('hands')))
        'same material, other: ${differing.isEmpty ? '(none)' : differing.join(' + ')}',
    ]) {
      kindsOfTie[kind] = (kindsOfTie[kind] ?? 0) + 1;
    }
  }
  stdout
    ..writeln()
    ..writeln(
      'presented ties by kind (direction and span can both hold for one tie):',
    );
  for (final MapEntry(:key, :value)
      in (kindsOfTie.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))) {
    stdout.writeln('  $value\t${share(value, presented.length)}\t$key');
  }

  final materialTies = [
    for (final tie in presented)
      if (tie.isMaterialTie) tie,
  ];
  final kinds = <String, int>{};
  final families = <String, int>{};
  final roles = <String, int>{};
  final reasons = <String, int>{};
  final keys = <String, int>{};
  for (final tie in materialTies) {
    kinds[tie.materialKind] = (kinds[tie.materialKind] ?? 0) + 1;
    final family =
        '${tie.winner.exercise.material.familyId} over '
        '${tie.reversed.exercise.material.familyId}';
    families[family] = (families[family] ?? 0) + 1;
    final role = '${tie.winnerRole} over ${tie.reversedRole}';
    roles[role] = (roles[role] ?? 0) + 1;
    final reason =
        '${tie.winner.eligibility.code.id} over '
        '${tie.reversed.eligibility.code.id}';
    reasons[reason] = (reasons[reason] ?? 0) + 1;
    final key = tie.winner.rankKey!;
    final summary =
        '${key.tier.id} retention ${key.retention.toStringAsFixed(3)} '
        'information ${key.information.toStringAsFixed(3)} '
        'diversity ${key.diversity} goals ${key.goals} '
        '${key.realization.id} fit ${key.realizationFit}';
    keys[summary] = (keys[summary] ?? 0) + 1;
  }
  stdout
    ..writeln()
    ..writeln(
      'material ties, presented: ${materialTies.length} '
      '(${share(materialTies.length, presented.length)} of presented ties); '
      '${scope == null ? 'no goal was in force, so every goal term is inactive here' : 'under ${scope.name}'}',
    );
  for (final MapEntry(:key, :value)
      in (kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) {
    stdout.writeln('  $value\t$key');
  }
  stdout.writeln('  by family:');
  for (final MapEntry(:key, :value)
      in (families.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))) {
    stdout.writeln('    $value\t$key');
  }
  var earlierFirst = 0;
  var laterFirst = 0;
  for (final tie in materialTies) {
    final (won, lost) = (tie.winnerIntroduction, tie.reversedIntroduction);
    if (won == null || lost == null) continue;
    if (won < lost) earlierFirst++;
    if (won > lost) laterFirst++;
  }
  if (scope != null) {
    stdout.writeln(
      '  candidate order picks the material the curriculum introduces '
      'earlier $earlierFirst times and later $laterFirst',
    );
  }
  stdout.writeln('  by role in the goal:');
  for (final MapEntry(:key, :value)
      in (roles.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) {
    stdout.writeln('    $value\t$key');
  }
  stdout.writeln('  by eligibility reason:');
  for (final MapEntry(:key, :value)
      in (reasons.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))) {
    stdout.writeln('    $value\t$key');
  }
  stdout.writeln('  the rank key both sides shared, most common first:');
  for (final MapEntry(:key, :value)
      in (keys.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(8)) {
    stdout.writeln('    $value\t$key');
  }

  final dimensions = <String, int>{};
  final signatures = <String, int>{};
  final outcomes = <String, Map<String, int>>{};
  for (final tie in presented) {
    final differences = tie.differences;
    signatures[differences.keys.join(' + ')] =
        (signatures[differences.keys.join(' + ')] ?? 0) + 1;
    for (final MapEntry(key: dimension, value: (won, lost))
        in differences.entries) {
      dimensions[dimension] = (dimensions[dimension] ?? 0) + 1;
      final contest = outcomes.putIfAbsent(dimension, () => {});
      contest['$won over $lost'] = (contest['$won over $lost'] ?? 0) + 1;
    }
  }

  List<MapEntry<String, int>> ranked(Map<String, int> counts) =>
      counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  stdout
    ..writeln()
    ..writeln('dimensions the two sides differ on, presented ties:');
  for (final MapEntry(:key, :value) in ranked(dimensions)) {
    stdout.writeln('  $key\t$value\t${share(value, presented.length)}');
  }
  stdout
    ..writeln()
    ..writeln('combinations of differing dimensions, presented ties:');
  for (final MapEntry(:key, :value) in ranked(signatures).take(15)) {
    stdout.writeln('  $value\t${key.isEmpty ? '(none)' : key}');
  }
  var likelier = 0;
  var lessLikely = 0;
  for (final tie in presented) {
    final won = tie.winner.prediction.overallP;
    final lost = tie.reversed.prediction.overallP;
    if (won > lost) likelier++;
    if (won < lost) lessLikely++;
  }
  stdout
    ..writeln()
    ..writeln(
      'where predictions differ, generated order picks the likelier '
      'candidate $likelier times and the less likely $lessLikely',
    );

  stdout
    ..writeln()
    ..writeln('which value generated order picks, per dimension:');
  for (final MapEntry(key: dimension, value: _) in ranked(dimensions)) {
    stdout.writeln('  $dimension');
    for (final MapEntry(:key, :value) in ranked(outcomes[dimension]!).take(8)) {
      stdout.writeln('    $value\t$key');
    }
  }
}
