import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Where a sweep's time goes.
///
/// Coarse timings for the trajectory loop.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '10')
    ..addOption('slots', defaultsTo: '50')
    ..addOption('archetype', defaultsTo: 'advanced');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('archetype'),
  );

  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final instrument = InstrumentProfile();

  final timers = <String, Stopwatch>{
    for (final phase in [
      'generate',
      'propagate',
      'decide',
      'ht sets',
      'sort alternatives',
      'play',
      'applyOutcome',
      'record',
      'detect',
    ])
      phase: Stopwatch(),
  };
  T time<T>(String phase, T Function() body) {
    final timer = timers[phase]!..start();
    final result = body();
    timer.stop();
    return result;
  }

  var slotCount = 0;
  var candidateEvaluations = 0;
  final wall = Stopwatch()..start();

  for (var seed = 0; seed < seeds; seed++) {
    final rng = PythonCompatibleRandom(seed);
    final at0 = DateTime.utc(2026);
    final state = learner.placementState(player.placement, at: at0);
    final playing = player.begin();
    final session = SessionState();
    final candidates = time(
      'generate',
      () => generateCandidates(instrument, allScales),
    );

    final recorded = <TrajectorySlot>[];
    for (var index = 0; index < slots; index++) {
      final at = at0.add(Duration(seconds: index * 60));
      time('propagate', () => learner.propagate(state, at));

      final selection = time(
        'decide',
        () => pipeline.decide(
          state: state,
          session: session,
          candidates: candidates,
          at: at,
        ),
      );
      final traces = selection.traces;
      candidateEvaluations += traces.length;
      final available = selection.selectable;
      final chosen = switch (selection) {
        CandidateSelected(:final candidate) => candidate,
        SelectionBlocked() => null,
      };
      if (chosen == null) break;
      slotCount++;

      final exercise = chosen.exercise;
      final residual = state.materialExecution[executionContextOf(exercise)];
      final frontierBefore = {...?residual?.demonstratedTempoByOctaves};
      final pacedBefore = residual?.pacedTempoBpm ?? 0;
      final transferableBefore = transferableTempoFor(
        state,
        exercise.conditions.hands,
        exercise.conditions.octaves,
      );

      final outcome = time('play', () => playing.play(exercise, rng));

      final ht = time('ht sets', () {
        final prerequisiteSatisfied = <String>{};
        final eligible = <String>{};
        final admitted = <String>{};
        for (final trace in traces) {
          if (trace.exercise.conditions.hands != HandConfiguration.together) {
            continue;
          }
          final id = trace.exercise.material.materialId;
          if (trace.handsTogetherPrerequisiteSatisfied == true) {
            prerequisiteSatisfied.add(id);
          }
          if (trace.eligibility.tier == EligibilityTier.fullyEligible) {
            eligible.add(id);
          }
          if (trace.isRanked) admitted.add(id);
        }
        return HandsTogetherStages(
          prerequisiteSatisfied: prerequisiteSatisfied,
          eligible: eligible,
          admitted: admitted,
          selectable: {
            for (final trace in available)
              if (trace.exercise.conditions.hands == HandConfiguration.together)
                trace.exercise.material.materialId,
          },
        );
      });

      final alternatives = time('sort alternatives', () {
        final rest = [
          for (final trace in available)
            if (!identical(trace, chosen)) trace,
        ]..sort((a, b) => b.rankKey!.compareTo(a.rankKey!));
        return rest;
      });

      time(
        'applyOutcome',
        () => learner.applyOutcome(
          state: state,
          exercise: exercise,
          outcome: outcome,
          weights: evidenceWeightsFor(exercise, outcome),
          prediction: learner.predict(state, exercise, at: at),
          at: at,
        ),
      );

      time('record', () {
        recorded.add(
          TrajectorySlot(
            index: index,
            at: at,
            chosen: exercise,
            winner: chosen,
            alternatives: alternatives,
            performedTempoBpm: playing.performedTempoFor(exercise),
            outcome: outcome,
            managedExecution: learner.executionWasManaged(outcome),
            frontierBefore: frontierBefore,
            frontierAfter: {
              ...?state
                  .materialExecution[executionContextOf(exercise)]
                  ?.demonstratedTempoByOctaves,
            },
            pacedBefore: pacedBefore,
            transferableBefore: transferableBefore,
            candidates: CandidateStageCounts(
              generated: candidates.length,
              evaluated: traces.length,
              eligible: traces
                  .where(
                    (trace) =>
                        trace.eligibility.tier == EligibilityTier.fullyEligible,
                  )
                  .length,
              admitted: traces.where((trace) => trace.isRanked).length,
              selectable: available.length,
            ),
            handsTogether: ht,
          ),
        );
      });
      pipeline.recordOutcome(session, exercise, outcome);
    }

    time(
      'detect',
      () => detectAnomalies(
        Trajectory(playerId: player.id, seed: seed, slots: recorded),
        requestedSlots: slots,
      ),
    );
  }
  wall.stop();

  final total = wall.elapsedMicroseconds;
  stdout
    ..writeln('${player.id}: $seeds seeds x $slots slots')
    ..writeln('  wall            ${(total / 1000000).toStringAsFixed(1)}s')
    ..writeln('  slots           $slotCount')
    ..writeln(
      '  ms / slot       '
      '${(total / 1000 / slotCount).toStringAsFixed(1)}',
    )
    ..writeln('  candidate evals $candidateEvaluations')
    ..writeln(
      '  evals / second  '
      '${(candidateEvaluations / (total / 1000000)).round()}',
    )
    ..writeln();
  final ordered = timers.entries.toList()
    ..sort(
      (a, b) =>
          b.value.elapsedMicroseconds.compareTo(a.value.elapsedMicroseconds),
    );
  for (final entry in ordered) {
    final micros = entry.value.elapsedMicroseconds;
    stdout.writeln(
      '  ${entry.key.padRight(18)}'
      '${(micros / 1000000).toStringAsFixed(2).padLeft(8)}s'
      '${'${(100 * micros / total).round()}%'.padLeft(6)}',
    );
  }
}
