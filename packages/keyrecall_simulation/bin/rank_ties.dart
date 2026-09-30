import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How often candidate order decides a slot, and along which dimensions.
///
/// Reads the production trajectory of every archetype and reports each slot
/// whose top rank was shared by candidates that ranking picks differently in
/// generated and in reversed order. Observational: nothing chosen changes.
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('slots', defaultsTo: '40')
    ..addOption(
      'catalog',
      defaultsTo: 'v1',
      allowed: ['v1', 'scales', 'mixed'],
      help: 'v1 scales, every scale, or every scale with the proof arpeggios',
    );
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final catalog = options.option('catalog')!;
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
      final census = censusRankTies(
        player: player,
        seed: seed,
        materials: materials,
        slots: slots,
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
      'rank tie census: catalog $catalog, $seeds seeds, $slots slots, '
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
