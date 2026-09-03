import 'dart:io';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Where predicted success sits, at the slot that admitted nothing.
///
/// The census established what the terminal state is not: not exhaustion, not
/// a support floor, not a missing recovery state. Recovery was inactive, four
/// of five materials were established, seventy two candidates were fully
/// eligible, the repetition guard excluded nothing, and every candidate died
/// at challenge admission.
///
/// So the question is only where those candidates sat relative to the band.
/// Above it and the learner has outgrown what they are permitted to do; below
/// it and they are stuck; both at once with nothing between, and the
/// prerequisites and the band have left no bridge from work that is now too
/// easy to work that would be appropriate.
///
/// Provisional candidates are reported too, not because they should be
/// selectable but because their predicted success says what is on the other
/// side of each prerequisite.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '40')
    ..addOption('slots', defaultsTo: '60')
    ..addOption('examples', defaultsTo: '2')
    ..addOption('archetype', defaultsTo: 'true_beginner');
  final options = parser.parse(arguments);
  final seeds = int.parse(options.option('seeds')!);
  final slots = int.parse(options.option('slots')!);
  final exampleLimit = int.parse(options.option('examples')!);
  final player = PlayerArchetypes.all.firstWhere(
    (p) => p.id == options.option('archetype'),
  );

  const learner = LearnerModel();
  const pipeline = SchedulerPipeline(learner: learner);
  final band = pipeline.config.challenge;
  final goal = PracticeGoal(
    id: 'FIVE_SCALES',
    targetMaterialIds: {
      for (final material in allScales.take(5)) material.materialId,
    },
  );
  final narrow = goal.scopeOf(allScales);

  var dry = 0;
  var below = 0;
  var within = 0;
  var above = 0;
  final nearestBelow = <double>[];
  final nearestAbove = <double>[];
  final rendered = <String>[];

  for (var seed = 0; seed < seeds; seed++) {
    final slot = _dryStateFor(
      player: player,
      seed: seed,
      slots: slots,
      materials: narrow,
      pipeline: pipeline,
    );
    if (slot == null) continue;
    dry++;

    final eligible = [
      for (final trace in slot.traces)
        if (trace.eligibility.tier == EligibilityTier.fullyEligible) trace,
    ];
    final low = [
      for (final trace in eligible)
        if (trace.prediction.overallP < band.pMin) trace,
    ];
    final mid = [
      for (final trace in eligible)
        if (trace.prediction.overallP >= band.pMin &&
            trace.prediction.overallP <= band.pMax)
          trace,
    ];
    final high = [
      for (final trace in eligible)
        if (trace.prediction.overallP > band.pMax) trace,
    ];
    below += low.length;
    within += mid.length;
    above += high.length;

    if (low.isNotEmpty) {
      nearestBelow.add(
        low.map((t) => t.prediction.overallP).reduce((a, b) => a > b ? a : b),
      );
    }
    if (high.isNotEmpty) {
      nearestAbove.add(
        high.map((t) => t.prediction.overallP).reduce((a, b) => a < b ? a : b),
      );
    }

    if (rendered.length < exampleLimit) {
      rendered.add(_render(seed, slot, narrow));
    }
  }

  String mean(List<double> values) => values.isEmpty
      ? '-'
      : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(3);

  stdout
    ..writeln(
      '${player.id}: $dry dry sittings of $seeds, '
      'scoped to ${narrow.length} materials',
    )
    ..writeln('band is ${band.pMin} to ${band.pMax}\n')
    ..writeln('fully eligible candidates at the dry slot, summed:')
    ..writeln('  below the band  ${below.toString().padLeft(7)}')
    ..writeln('  inside it       ${within.toString().padLeft(7)}')
    ..writeln('  above it        ${above.toString().padLeft(7)}\n')
    ..writeln('  highest p below the band, mean  ${mean(nearestBelow)}')
    ..writeln('  lowest p above the band, mean   ${mean(nearestAbove)}');

  for (final example in rendered) {
    stdout.writeln('\n$example');
  }
}

class _DrySlot {
  final int index;
  final List<CandidateTrace> traces;
  final LearnerState state;

  const _DrySlot(this.index, this.traces, this.state);
}

_DrySlot? _dryStateFor({
  required SyntheticPlayer player,
  required int seed,
  required int slots,
  required List<TechnicalMaterial> materials,
  required SchedulerPipeline pipeline,
}) {
  final learner = pipeline.learner;
  final rng = PythonCompatibleRandom(seed);
  final at0 = DateTime.utc(2026);
  final state = learner.placementState(player.placement, at: at0);
  final playing = player.begin();
  final session = SessionState();
  final candidates = generateCandidates(InstrumentProfile(), materials);

  for (var index = 0; index < slots; index++) {
    final at = at0.add(Duration(seconds: index * 60));
    learner.propagate(state, at);
    final selection = pipeline.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
    );
    final traces = selection.traces;
    final chosen = switch (selection) {
      CandidateSelected(:final candidate) => candidate,
      SelectionBlocked() => null,
    };
    if (chosen == null) return _DrySlot(index, traces, state);

    final exercise = chosen.exercise;
    final outcome = playing.play(exercise, rng);
    learner.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: learner.predict(state, exercise, at: at),
      at: at,
    );
    pipeline.recordOutcome(session, exercise, outcome);
  }
  return null;
}

String _render(int seed, _DrySlot slot, List<TechnicalMaterial> materials) {
  String describe(CandidateTrace trace) {
    final c = trace.exercise.conditions;
    return '      p=${trace.prediction.overallP.toStringAsFixed(2)} '
        '${trace.exercise.material.materialId.padRight(12)}'
        '${c.hands.id.padRight(9)}${c.octaves}oct '
        '${c.tempoBpm.toStringAsFixed(0).padLeft(3)}bpm '
        'g=${trace.exercise.guidance.independence}';
  }

  List<CandidateTrace> best(bool Function(CandidateTrace) where, int take) {
    final matching = slot.traces.where(where).toList()
      ..sort((a, b) => b.prediction.overallP.compareTo(a.prediction.overallP));
    return matching.take(take).toList();
  }

  final established = [
    for (final material in materials)
      (slot.state.materialMemory[material.materialId]?.hasFactualRetrieval ??
              false)
          ? material.materialId
          : '${material.materialId} (not established)',
  ];

  return [
    '  seed $seed, dry at slot ${slot.index}',
    '  materials: ${established.join(', ')}',
    '',
    '    fully eligible, easiest three:',
    ...best(
      (t) => t.eligibility.tier == EligibilityTier.fullyEligible,
      3,
    ).map(describe),
    '',
    '    behind the octave-span prerequisite, best three:',
    ...best(
      (t) => t.eligibility.code == EligibilityReason.octaveSpanPrerequisite,
      3,
    ).map(describe),
    '',
    '    behind the hands-together prerequisite, best three:',
    ...best(
      (t) => t.eligibility.code == EligibilityReason.handsTogetherPrerequisite,
      3,
    ).map(describe),
  ].join('\n');
}
