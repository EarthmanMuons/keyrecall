import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart'
    hide AttemptRecord;

/// v1-14 and allocation at `k` of 2 on [DemoCalendar] re-datings of the same
/// practice, read with a held-out assessment around every absence.
///
/// A reading closes the session before each absence of at least four days,
/// opens the session after it, and closes that session; two more close the
/// run and follow it after [_delay] away. Readings ask every material with
/// their own draws and practise nothing, so arms on one calendar are read at
/// the same instants with the same luck. Only the reading after the run ages
/// the player, since splitting the run's own decay steps would move it by
/// rounding. Each reports the held-out result, the
/// scheduler's expected retrieval of the same questions, and the player's own
/// familiarity, which is its true retrieval probability.
///
/// Writes one JSON line per player, seed pair, calendar, and arm.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('profiles', defaultsTo: '19,2,16,3,4,0')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption('calendars', defaultsTo: 'reference,interrupted,extendedBreak')
    ..addOption('arms', defaultsTo: 'v1-14,alloc-2');
  final options = parser.parse(arguments);
  final assessment = standardAssessment(allPracticeMaterials);
  for (final index in options.option('profiles')!.split(',')) {
    final profile = PlausibilityCohort.profiles[int.parse(index)];
    final player = profile.player;
    for (final pair in options.option('seeds')!.split(',')) {
      final [schedule, playerSeed] = [
        for (final part in pair.split(':')) int.parse(part),
      ];
      final drawn = demoSessions(
        from: demoHistoryStart,
        until: demoHistoryEnd,
        seed: schedule,
      );
      for (final name in options.option('calendars')!.split(',')) {
        final sessions = DemoCalendar.values
            .byName(name)
            .of(drawn, seed: schedule);
        final absences = {
          for (var i = 1; i < sessions.length; i++)
            if (sessions[i].start.difference(sessions[i - 1].start).inDays >= 4)
              i: sessions[i].start.difference(sessions[i - 1].start).inDays,
        };
        for (final arm in options.option('arms')!.split(',')) {
          stderr.writeln('${player.id} $pair $name $arm');
          final allocator = arm == 'v1-14'
              ? null
              : RequirementAllocator(k: 2, protectionFloor: 0.6);
          final reader = _Reader(assessment, absences);
          final census = await runServiceCensus(
            player: player,
            sessions: sessions,
            playerSeed: playerSeed,
            intervention: allocator,
            onArrival: reader.arrive,
            onClose: reader.close,
          );
          reader.delayed();
          stdout.writeln(
            jsonEncode({
              'player': player.id,
              'unit': profile.unit,
              'seeds': pair,
              'calendar': name,
              'arm': arm,
              'days': sessions.last.start
                  .difference(sessions.first.start)
                  .inDays,
              'attempts': census.records.length,
              'outcomes': ServiceOutcomes.of(
                census,
                intervention: allocator,
              ).toJson(),
              'readings': reader.readings,
              'returns': [
                for (final session in absences.keys)
                  _returnOf(census.records, session),
              ],
            }),
          );
        }
      }
    }
  }
}

const _delay = Duration(days: 21);

class _Reader {
  final AssessmentSet assessment;
  final Map<int, int> absences;
  final List<Map<String, Object?>> readings = [];
  int _session = -1;
  late PracticeSession _last;
  late PlayerState _playing;
  late DateTime _closedAt;

  _Reader(this.assessment, this.absences);

  void arrive(PracticeSession session, PlayerState playing, DateTime at) {
    _session++;
    if (absences[_session] case final days?) {
      _read('arrival', session, playing, at, away: days);
    }
  }

  void close(PracticeSession session, PlayerState playing, DateTime at) {
    _last = session;
    _playing = playing;
    _closedAt = at;
    if (absences.containsKey(_session + 1)) {
      _read('before absence', session, playing, at);
    } else if (absences.containsKey(_session)) {
      _read('return closed', session, playing, at);
    }
  }

  void delayed() {
    _read('end', _last, _playing, _closedAt);
    _playing.restUntil(_closedAt.add(_delay));
    _read('delayed', _last, _playing, _closedAt.add(_delay));
  }

  void _read(
    String kind,
    PracticeSession session,
    PlayerState playing,
    DateTime at, {
    int? away,
  }) {
    const learner = LearnerModel();
    final belief = session.state.copy();
    learner.propagate(belief, at);
    final reading = assess(assessment, playing, at: at, state: belief);
    Map<String, Object?> summary(AssessmentReading r, String? family) {
      final materials = [
        for (final m in allPracticeMaterials)
          if (family == null || m.familyId == family) m,
      ];
      var known = 0.0, gained = 0.0;
      for (final material in materials) {
        final now = playing.familiarityOf(material.materialId);
        known += now;
        gained +=
            now -
            (playing.player.materialFamiliarity[material.materialId] ??
                playing.player.familiarity);
      }
      return {
        'held-out retrieval': r.retrieval,
        'held-out managed': r.managed,
        'estimated retrieval': r.predictedRetrieval,
        'true retrieval': known / materials.length,
        'retained gain': gained,
      };
    }

    readings.add({
      'kind': kind,
      'session': _session,
      'away': ?away,
      'attempts': session.journal.records.length,
      'all': summary(reading, null),
      for (final MapEntry(:key, :value) in reading.families.entries)
        key: summary(value, key),
    });
  }
}

/// What the session after an absence asked and got, which depends on the
/// policy that chose it.
Map<String, Object?> _returnOf(List<AttemptRecord> records, int session) {
  final played = [
    for (final r in records)
      if (r.identity.sessionId == 'demo-session-$session') r,
  ];
  final outcomes = [
    for (final r in played)
      switch (r.closure.measurement) {
        Measured(:final outcome) => outcome,
        _ => null,
      },
  ];
  final tested = [
    for (final o in outcomes)
      if (o != null && o.retrieval.isTested) o,
  ];
  final managed = outcomes.indexWhere(
    (o) => o != null && const LearnerModel().executionWasManaged(o),
  );
  return {
    'session': session,
    'attempts': played.length,
    'tests': tested.length,
    'retrieved': tested
        .where((o) => o.retrieval == FactualRetrieval.succeeded)
        .length,
    'not started': outcomes.where((o) => o != null && !o.started).length,
    'before managed': managed < 0 ? null : managed,
  };
}
