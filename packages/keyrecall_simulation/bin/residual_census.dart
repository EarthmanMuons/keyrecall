import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '4')
    ..addOption('slots', defaultsTo: '80');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final players = [
    PlayerArchetypes.developing,
    PlayerArchetypes.intermediate,
    PlayerArchetypes.advanced,
    PlayerArchetypes.unevenHands,
  ];
  const scopes = [
    ArpeggioPolicyScope.fullArpeggioCorpus,
    ArpeggioPolicyScope.fullMixed,
  ];

  final stopwatch = Stopwatch()..start();
  final byScope = <ArpeggioPolicyScope, List<ResidualObservation>>{};
  for (final scope in scopes) {
    final observations = <ResidualObservation>[];
    for (final player in players) {
      for (var seed = 0; seed < seeds; seed++) {
        observations.addAll(
          await runResidualTrajectory(
            scope: scope,
            player: player,
            slots: slots,
            seed: seed,
          ),
        );
        stderr.writeln(
          '${scope.name} ${player.id} seed $seed '
          '(${stopwatch.elapsed.inSeconds}s)',
        );
      }
    }
    byScope[scope] = observations;
  }

  stdout.writeln(
    'arpeggio residual census: $seeds seeds x $slots slots, '
    '${stopwatch.elapsed.inSeconds}s',
  );

  for (final scope in scopes) {
    final arpeggios = [
      for (final observation in byScope[scope]!)
        if (observation.exercise.material.familyId ==
            TechnicalMaterial.arpeggioFamilyId)
          observation,
    ];
    stdout
      ..writeln()
      ..writeln('${scope.name}: ${arpeggios.length} arpeggio attempts')
      ..writeln('axis\tlevel\tn\tmean_execution\tsd_execution\tmean_topology');
    for (final partition in _partitions(arpeggios)) {
      for (final level in partition.byLevel.keys.toList()..sort()) {
        final values = partition.byLevel[level]!;
        final topology = ResidualPartition.of(
          partition.axis,
          arpeggios,
          _levelOf(partition.axis),
          (observation) => observation.topology,
        ).byLevel[level]!;
        stdout.writeln(
          '${partition.axis}\t$level\t${values.length}\t'
          '${mean(values).toStringAsFixed(4)}\t'
          '${standardDeviation(values).toStringAsFixed(4)}\t'
          '${mean(topology).toStringAsFixed(4)}',
        );
      }
    }

    stdout
      ..writeln()
      ..writeln('${scope.name}: does a cell come back the same way')
      ..writeln('cell\tcontrolled_for\tcells\tsplit_half_r');
    for (final cell in _cells.entries) {
      for (final control in _controls.entries) {
        final reliability = SplitHalfReliability.of(
          control.value == null
              ? arpeggios
              : centeredBy(arpeggios, control.value!),
          cell.value,
        );
        stdout.writeln(
          '${cell.key}\t${control.key}\t${reliability.cells}\t'
          '${reliability.correlation.toStringAsFixed(3)}',
        );
      }
    }
  }
}

/// The partitions a material-hand residual would have to survive.
List<ResidualPartition> _partitions(List<ResidualObservation> observations) => [
  for (final axis in _levels.keys)
    ResidualPartition.of(
      axis,
      observations,
      _levels[axis]!,
      (observation) => observation.execution,
    ),
];

String Function(ResidualObservation) _levelOf(String axis) => _levels[axis]!;

final _levels = <String, String Function(ResidualObservation)>{
  'hands': (observation) => observation.hands.id,
  'span': (observation) => '${observation.exercise.conditions.octaves}oct',
  'direction': (observation) => observation.exercise.conditions.direction.id,
  'tempo': (observation) =>
      '${observation.exercise.conditions.tempoBpm.round()}bpm',
  'guidance': (observation) =>
      'g=${observation.exercise.guidance.independence}',
  'quality': (observation) =>
      (observation.exercise.material as ArpeggioMaterial).quality.id,
  'geometry': _geometryOf,
};

final _cells = <String, String Function(ResidualObservation)>{
  'material': (observation) => observation.materialId,
  'material-hand': (observation) => observation.materialHand,
  'geometry-hand': (observation) =>
      '${_geometryOf(observation)}:${observation.hands.id}',
};

/// What a material-keyed residual has to survive being measured against.
final _controls = <String, String Function(ResidualObservation)?>{
  'nothing': null,
  'hand': (observation) => observation.hands.id,
  'hand+tempo': (observation) =>
      '${observation.hands.id}:'
      '${observation.exercise.conditions.tempoBpm.round()}',
  'hand+tempo+guidance': (observation) =>
      '${observation.hands.id}:'
      '${observation.exercise.conditions.tempoBpm.round()}:'
      '${observation.exercise.guidance.independence}',
};

/// The canonical fingering of the hand that plays, or both where two do.
String _geometryOf(ResidualObservation observation) {
  final material = observation.exercise.material;
  return [
    for (final hand in Hand.values)
      if (_uses(observation.hands, hand))
        canonicalFingering(material, hand)?.ascending(1).join() ?? '?',
  ].join('+');
}

bool _uses(HandConfiguration hands, Hand hand) => switch (hand) {
  Hand.right => hands.usesRightHand,
  Hand.left => hands.usesLeftHand,
};
