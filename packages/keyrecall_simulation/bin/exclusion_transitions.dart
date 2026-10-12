import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// How each prolonged exclusion of an arpeggio began: what was last attempted,
/// how it went, and where single-hand readiness stood against the band floor
/// before and after it.
///
/// Readiness is the scheduler's own reference prediction (one octave,
/// ascending, at the gentle tempo), so it does not move with the realization
/// attempted. Writes one JSON line per exclusion span of at least `--min`
/// decisions.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('player', defaultsTo: 'scale_strong_arpeggio_weak')
    ..addOption('seeds', defaultsTo: '0:100,1:101,2:102,3:103,4:104')
    ..addOption('arms', defaultsTo: 'alloc-2-0.60,alloc-4-0.60')
    ..addOption('min', defaultsTo: '100');
  final options = parser.parse(arguments);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('player'),
  );
  final minimum = int.parse(options.option('min')!);
  for (final pair in options.option('seeds')!.split(',')) {
    final [schedule, playerSeed] = [
      for (final part in pair.split(':')) int.parse(part),
    ];
    for (final arm in options.option('arms')!.split(',')) {
      stderr.writeln('${player.id} $pair $arm');
      final [_, k, floor] = arm.split('-');
      final audit = _Audit(
        RequirementAllocator(
          k: int.parse(k),
          protectionFloor: double.parse(floor),
        ),
      );
      final census = await runServiceCensus(
        player: player,
        sessions: demoSessions(
          from: demoHistoryStart,
          until: demoHistoryEnd,
          seed: schedule,
        ),
        playerSeed: playerSeed,
        intervention: audit,
      );
      for (final span in audit.spans(census, minimum)) {
        stdout.writeln(
          jsonEncode({'player': player.id, 'seeds': pair, 'arm': arm, ...span}),
        );
      }
    }
  }
}

typedef _Readiness = ({
  double execution,
  double demonstrated,
  String eligibility,
  String reason,
});

class _Attempt {
  final int decision;
  final int journalIndex;
  final Exercise exercise;
  final CandidateTrace trace;
  final SelectionStage stage;
  final bool substituted;

  _Attempt(
    this.decision,
    this.journalIndex,
    this.exercise,
    this.trace,
    this.stage,
    this.substituted,
  );
}

class _Audit implements ServiceIntervention {
  final RequirementAllocator inner;
  final _readiness = <String, Map<int, Map<String, _Readiness>>>{};
  final _attempts = <String, List<_Attempt>>{};
  final _floors = <String, ({double band, double before})>{};

  _Audit(this.inner);

  @override
  void settle(AttemptJournal journal, LearnerModel learner, int decision) =>
      inner.settle(journal, learner, decision);

  @override
  CandidateSelected? intervene({
    required int decision,
    required SelectionResult result,
    required List<RequirementState> requirements,
    required SchedulerPipeline pipeline,
    required LearnerState state,
    required SessionState session,
    required DateTime at,
    required int journalLength,
  }) {
    final override = inner.intervene(
      decision: decision,
      result: result,
      requirements: requirements,
      pipeline: pipeline,
      state: state,
      session: session,
      at: at,
      journalLength: journalLength,
    );
    final eligibility = pipeline.config.eligibility;
    for (final requirement in requirements) {
      final material = requirement.resolved.material;
      if (material.familyId != 'ARPEGGIO') continue;
      final band = admissionBandOf(material);
      _floors[material.materialId] ??= (
        band: eligibility.referenceFloorFor(band),
        before: eligibility.referenceFloorFor(
          band == AdmissionBand.foundation
              ? band
              : AdmissionBand.values[band.index - 1],
        ),
      );
      _readiness.putIfAbsent(material.materialId, () => {})[decision] = {
        for (final hand in [HandConfiguration.left, HandConfiguration.right])
          hand.name: () {
            final reference = Exercise.linear(
              material: material,
              hands: hand,
              octaves: material.progression.octaveSpans.first,
              direction: ExerciseDirection.up,
              tempoBpm: eligibility.gentleTempoBpm,
            );
            final decided = pipeline.eligibilityFor(state, reference);
            return (
              execution: pipeline.learner.executionProbability(
                state,
                reference,
              ),
              demonstrated:
                  state.materialExecution[executionContextOf(reference)]
                      ?.demonstratedTempoAt(reference.conditions.octaves) ??
                  0,
              eligibility: decided.tier.name,
              reason: decided.code.name,
            );
          }(),
      };
    }
    final chosen = override ?? result;
    if (chosen is CandidateSelected) {
      final exercise = chosen.candidate.exercise;
      if (exercise.material.familyId == 'ARPEGGIO') {
        _attempts
            .putIfAbsent(exercise.material.materialId, () => [])
            .add(
              _Attempt(
                decision,
                journalLength,
                exercise,
                chosen.candidate,
                chosen.stage,
                override != null,
              ),
            );
      }
    }
    return override;
  }

  @override
  void record(List<RequirementObservation> observations) =>
      inner.record(observations);

  @override
  List<ServiceSubstitution> get substitutions => inner.substitutions;

  @override
  Map<String, num> get diagnostics => inner.diagnostics;

  /// Exclusion spans: from a requirement's first unservable decision until it
  /// is next served or has a feasible candidate, through recovery holds and
  /// decisions where it was not owed.
  Iterable<Map<String, Object?>> spans(
    ServiceCensus census,
    int minimum,
  ) sync* {
    final served = <String, List<int>>{};
    for (final o in census.observations) {
      if (o.served) served.putIfAbsent(o.materialId, () => []).add(o.decision);
    }
    final byMaterial = <String, List<OwedExclusion>>{};
    for (final e in inner.exclusions) {
      if (e.familyId == 'ARPEGGIO') {
        byMaterial.putIfAbsent(e.materialId, () => []).add(e);
      }
    }
    final lastDecision = census.decisions.length - 1;
    for (final MapEntry(key: materialId, value: own) in byMaterial.entries) {
      int? start;
      var unservable = 0;
      final reasons = <String, int>{};
      final services = served[materialId] ?? const [];
      Map<String, Object?>? close(int end) {
        final from = start!;
        start = null;
        if (end - from < minimum) return null;
        return _describe(materialId, from, end, unservable, {
          ...reasons,
        }, census);
      }

      for (final e in own) {
        if (start != null &&
            services.any((d) => d > start! && d <= e.decision)) {
          final end = services.firstWhere((d) => d > start!);
          if (close(end) case final span?) yield span;
        }
        if (e.unservable) {
          if (start == null) {
            start = e.decision;
            unservable = 0;
            reasons.clear();
          }
          unservable++;
          reasons.update(
            '${e.kind}: ${e.detail}',
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        } else if (e.kind != 'obligation' && start != null) {
          if (close(e.decision) case final span?) yield span;
        }
      }
      if (start != null) {
        final end = services.where((d) => d > start!).firstOrNull;
        if (close(end ?? lastDecision) case final span?) {
          yield {...span, 'open at end': end == null};
        }
      }
    }
  }

  Map<String, Object?> _describe(
    String materialId,
    int start,
    int end,
    int unservable,
    Map<String, int> reasons,
    ServiceCensus census,
  ) {
    final readiness = _readiness[materialId]!;
    Map<String, Object?>? readinessAt(int decision) {
      final at = readiness[decision];
      if (at == null) return null;
      return {
        for (final MapEntry(:key, :value) in at.entries)
          key: {
            'execution': _round(value.execution),
            'demonstrated': value.demonstrated,
            'eligibility': value.eligibility,
            'reason': value.reason,
          },
      };
    }

    int? nextObserved(int decision) =>
        (readiness.keys.where((d) => d > decision).toList()..sort())
            .firstOrNull;
    final attempts = _attempts[materialId] ?? const <_Attempt>[];
    final before = attempts.where((a) => a.decision < start).toList();
    final during = attempts
        .where((a) => a.decision >= start && a.decision < end)
        .toList();
    final executions = [
      for (final MapEntry(key: d, value: at) in readiness.entries)
        if (d >= start && d < end)
          at.values.map((r) => r.execution).reduce((a, b) => a < b ? a : b),
    ];
    return {
      'material': materialId,
      'start': start,
      'end': end,
      'length': end - start,
      'unservable': unservable,
      'reasons': reasons,
      'floors': {
        'band': _floors[materialId]!.band,
        'band before': _floors[materialId]!.before,
      },
      'attempts before': before.length,
      'last attempts': [
        for (final a in before.skip(before.length > 3 ? before.length - 3 : 0))
          _describeAttempt(a, census, readinessAt, nextObserved),
      ],
      'at start': readinessAt(start),
      'at end': readinessAt(nextObserved(end - 1) ?? end),
      'weaker hand during': executions.isEmpty
          ? null
          : {
              'min': _round(executions.reduce((a, b) => a < b ? a : b)),
              'max': _round(executions.reduce((a, b) => a > b ? a : b)),
            },
      'attempts during': [
        for (final a in during)
          _describeAttempt(a, census, readinessAt, nextObserved),
      ],
    };
  }

  Map<String, Object?> _describeAttempt(
    _Attempt attempt,
    ServiceCensus census,
    Map<String, Object?>? Function(int) readinessAt,
    int? Function(int) nextObserved,
  ) {
    final conditions = attempt.exercise.conditions;
    final record = attempt.journalIndex < census.records.length
        ? census.records[attempt.journalIndex]
        : null;
    final json = record?.toJson();
    final after = nextObserved(attempt.decision);
    return {
      'decision': attempt.decision,
      'exercise':
          '${conditions.hands.name} ${conditions.octaves}oct '
          '${conditions.direction.name} ${conditions.tempoBpm.round()}bpm '
          '${attempt.exercise.guidance}',
      'stage': attempt.stage.name,
      'substituted': attempt.substituted,
      'eligibility':
          '${attempt.trace.eligibility.tier.name} '
          '${attempt.trace.eligibility.code.name}',
      'bypass': attempt.trace.challengeBypass?.name,
      'record matches': record?.exercise == attempt.exercise,
      'closure': json?['closure'],
      'timed': json?['timing'] != null,
      'before': readinessAt(attempt.decision),
      'after': after == null ? null : readinessAt(after),
    };
  }
}

double _round(double value) => (value * 1000).round() / 1000;
