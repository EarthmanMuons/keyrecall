import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Allocation with and without early follow-through, for the scale-strong
/// player at several arpeggio ability offsets, on fixed schedule:player seed
/// pairs.
///
/// Writes one JSON line per trajectory. Arms without follow-through still count
/// what it would have had to work with.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('offsets', defaultsTo: '-1.2,-0.8,-0.4,0')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption('arms', defaultsTo: 'alloc-2,alloc-2-ft,alloc-4,alloc-4-ft');
  final options = parser.parse(arguments);
  for (final offset in options.option('offsets')!.split(',')) {
    final player = PlayerArchetypes.scaleStrongArpeggioWeak.copyWith(
      familyAbility: {
        TechnicalMaterial.scaleFamilyId: 0.8,
        TechnicalMaterial.arpeggioFamilyId: double.parse(offset),
      },
    );
    for (final pair in options.option('seeds')!.split(',')) {
      final [schedule, playerSeed] = [
        for (final part in pair.split(':')) int.parse(part),
      ];
      for (final arm in options.option('arms')!.split(',')) {
        stderr.writeln('$offset $pair $arm');
        final parts = arm.split('-');
        final followThrough = FollowThrough(
          RequirementAllocator(k: int.parse(parts[1]), protectionFloor: 0.6),
          enabled: parts.length > 2,
        );
        final census = await runServiceCensus(
          player: player,
          sessions: demoSessions(
            from: demoHistoryStart,
            until: demoHistoryEnd,
            seed: schedule,
          ),
          playerSeed: playerSeed,
          intervention: followThrough,
        );
        final bandFloor = [
          for (final e in followThrough.allocator.exclusions)
            if (e.detail == 'bandExecutionFloor') e,
        ];
        final lastOwed = <String, OwedExclusion>{};
        for (final e in followThrough.allocator.exclusions) {
          lastOwed[e.requirementId] = e;
        }
        stdout.writeln(
          jsonEncode({
            'offset': double.parse(offset),
            'seeds': pair,
            'arm': arm,
            'outcomes': ServiceOutcomes.of(
              census,
              intervention: followThrough,
            ).toJson(),
            for (final family in [
              TechnicalMaterial.arpeggioFamilyId,
              TechnicalMaterial.scaleFamilyId,
            ])
              'strands $family': summarizeStrands(
                census.records,
                family,
                events: followThrough.events,
              ),
            'band floor exclusions': bandFloor.length,
            'band floor requirements': {
              for (final e in bandFloor) e.requirementId,
            }.length,
            'band floor at last owed decision': lastOwed.values
                .where((e) => e.detail == 'bandExecutionFloor')
                .length,
          }),
        );
      }
    }
  }
}
