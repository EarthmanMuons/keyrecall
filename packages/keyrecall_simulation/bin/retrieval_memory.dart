import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// [RetrievalMemory] on fixed practice schedules, with no scheduler.
///
/// Each schedule practises one material six times under one guidance rung,
/// massed into a session or spread across days or weeks, and reads the
/// player's retrievability of it afterwards. Means over [_players] seeded
/// players, since a failed unguided retrieval encodes nothing and which ones
/// fail is drawn.
///
/// Writes one JSON line per configuration and schedule.
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('half-lives', defaultsTo: '15,60,240')
    ..addOption('learning', defaultsTo: '0.5,1,2')
    ..addOption('spacing', defaultsTo: '0,0.5,1')
    ..addOption('familiarity', defaultsTo: '0.3,0.6')
    ..addOption('restoration', defaultsTo: 'full');
  final options = parser.parse(arguments);
  List<double> numbers(String name) => [
    for (final part in options.option(name)!.split(',')) double.parse(part),
  ];

  for (final halfLife in numbers('half-lives')) {
    for (final learning in numbers('learning')) {
      for (final spacing in numbers('spacing')) {
        final memory = RetrievalMemory.scenario(
          '$learning:$halfLife:$spacing:${options.option('restoration')}',
        );
        for (final familiarity in numbers('familiarity')) {
          for (final schedule in _schedules) {
            stdout.writeln(
              jsonEncode({
                'model': memory.version,
                'initial half-life': halfLife,
                'learning': learning,
                'spacing': spacing,
                'familiarity': familiarity,
                ..._run(memory, familiarity, schedule),
              }),
            );
          }
        }
      }
    }
  }
}

const _players = 400;
const _readAfterDays = [0, 7, 30, 90, 365];

final _material = TechnicalMaterial('C', ScaleForm.major);
final _start = DateTime.utc(2026);

typedef _Schedule = ({String name, GuidanceContext? guidance, Duration apart});

const _schedules = <_Schedule>[
  (name: 'none', guidance: null, apart: Duration.zero),
  (
    name: 'unguided, massed',
    guidance: GuidanceContext.unguided,
    apart: Duration(minutes: 2),
  ),
  (
    name: 'unguided, daily',
    guidance: GuidanceContext.unguided,
    apart: Duration(days: 1),
  ),
  (
    name: 'unguided, weekly',
    guidance: GuidanceContext.unguided,
    apart: Duration(days: 7),
  ),
  (
    name: 'previewed, daily',
    guidance: GuidanceContext.notesPreviewedOnly,
    apart: Duration(days: 1),
  ),
  (
    name: 'cued, daily',
    guidance: GuidanceContext.continuouslyCued,
    apart: Duration(days: 1),
  ),
];

Map<String, Object?> _run(
  RetrievalMemory memory,
  double familiarity,
  _Schedule schedule,
) {
  final player = PlayerArchetypes.developing.copyWith(
    id: 'developing+${memory.version}',
    materialFamiliarity: {_material.materialId: familiarity},
    retrievalMemory: memory,
  );
  final retrieved = List.filled(_readAfterDays.length, 0.0);
  var successes = 0;
  // Every schedule ends on the same day, so a reading after it is the same
  // distance from the start whatever came before.
  final end = _start.add(const Duration(days: 43));
  for (var seed = 0; seed < _players; seed++) {
    final playing = player.begin()..restUntil(_start);
    if (schedule.guidance case final guidance?) {
      final exercise = Exercise.linear(
        material: _material,
        hands: HandConfiguration.right,
        guidance: guidance,
      );
      final random = PythonCompatibleRandom(seed);
      for (var i = 5; i >= 0; i--) {
        final outcome = playing.play(
          exercise,
          random,
          at: end.subtract(schedule.apart * i),
        );
        if (outcome.retrieval == FactualRetrieval.succeeded) successes++;
      }
    }
    for (final (i, days) in _readAfterDays.indexed) {
      retrieved[i] += playing.familiarityAt(
        _material.materialId,
        end.add(Duration(days: days)),
      );
    }
  }
  return {
    'schedule': schedule.name,
    'successes': successes / _players,
    'retrievability': {
      for (final (i, days) in _readAfterDays.indexed)
        '$days': retrieved[i] / _players,
    },
  };
}
