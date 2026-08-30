import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'trajectory.dart';

/// The census printed whenever a detector trips.
///
/// The whole point of the harness. Every diagnosis this repository has made by
/// hand rebuilt this from print statements and a rerun, and the rebuilding is
/// where the mistakes came from: a sort compared the wrong way round once, and
/// a mechanism was asserted from a plausible reading twice. A report that
/// carries the census cannot be argued with.
String censusOf(TrajectorySlot slot, {int alternatives = 8}) {
  String describe(CandidateTrace trace) {
    final c = trace.exercise.conditions;
    return '  ${trace.exercise.material.materialId.padRight(18)}'
        '${c.hands.id.padRight(9)}${c.octaves}oct '
        '${c.direction == ScaleDirection.up ? 'up  ' : 'updn'} '
        '${c.tempoBpm.toStringAsFixed(0).padLeft(4)}bpm g=${trace.exercise.guidance.independence} '
        '${(trace.challengeBypass?.id ?? 'in-band').padRight(22)}'
        '${trace.eligibility.tier.id}/${trace.eligibility.code.id} '
        '${trace.rankKey}';
  }

  final conditions = slot.chosen.conditions;
  return [
    'slot ${slot.index} at ${slot.at.toIso8601String()}',
    'chosen:',
    describe(slot.winner),
    'played ${slot.performedTempoBpm.toStringAsFixed(0)}bpm '
        '(x${slot.outcome.achievedTempoRatio.toStringAsFixed(2)}) '
        'completed=${slot.outcome.completed} '
        'motor=${slot.outcome.motorScore.toStringAsFixed(2)} '
        'pitch=${slot.outcome.pitchIntegrity.toStringAsFixed(2)}',
    'frontier for ${slot.chosen.material.materialId}/${conditions.hands.id}: '
        '${slot.frontierBefore} paced=${slot.pacedBefore.toStringAsFixed(0)}',
    'best alternatives:',
    ...slot.alternatives.take(alternatives).map(describe),
  ].join('\n');
}

/// Every detector, run over one trajectory.
List<Anomaly> detectAnomalies(Trajectory trajectory, {int? requestedSlots}) => [
  ..._realizationStall(trajectory),
  ..._sittingRanDry(trajectory, requestedSlots ?? trajectory.slots.length),
  ..._entryTempoIgnoresPace(trajectory),
  ..._entryTempoRegression(trajectory),
  ..._belowFrontierShare(trajectory),
  ..._materialConcentration(trajectory),
  ..._progressionStall(trajectory),
  ..._handsTogetherStall(trajectory),
  ..._guidanceRegression(trajectory),
  ..._shortCycleRepetition(trajectory),
];

/// **Invariant.** A surpassed realization was chosen while an advancing one of
/// the same material and hand was admissible and equally eligible.
///
/// Structural rather than tuned: both candidates reached ranking, both are on
/// the work the learner is already doing, and one of them asks for something
/// they have demonstrably outgrown. No threshold makes that the right choice.
/// This is the shape of the eleven-slot collapse a device sitting produced.
Iterable<Anomaly> _realizationStall(Trajectory trajectory) sync* {
  for (final slot in trajectory.slots) {
    if (slot.realization != RealizationRank.surpassed) continue;
    final better = slot.alternatives.where(
      (trace) =>
          trace.exercise.material.materialId ==
              slot.chosen.material.materialId &&
          trace.exercise.conditions.hands == slot.chosen.conditions.hands &&
          trace.rankKey!.tier == slot.winner.rankKey!.tier &&
          trace.rankKey!.realization == RealizationRank.advancing,
    );
    if (better.isEmpty) continue;

    yield Anomaly(
      detector: 'realization_stall',
      severity: AnomalySeverity.invariant,
      slot: slot.index,
      summary:
          'chose ${slot.chosen.conditions.tempoBpm.toStringAsFixed(0)}bpm on '
          '${slot.chosen.material.materialId} with the frontier at '
          '${slot.frontierAtSpan.toStringAsFixed(0)}, while '
          '${better.length} advancing realizations were admissible',
      census: censusOf(slot),
    );
  }
}

/// **Invariant.** The sitting ran out of things to offer.
///
/// Sittings are unbounded and eight mechanisms can admit outside the ordinary
/// band, so a slot that admits nothing means every one of them declined. The
/// way this has actually happened is an exclusive target the candidate set did
/// not contain: recovery refuses everything but one exact exercise, and if
/// that exercise is not there the slot has nothing at all.
///
/// Read from the run ending early rather than from a slot, because a slot that
/// admits nothing is never recorded.
Iterable<Anomaly> _sittingRanDry(Trajectory trajectory, int requested) sync* {
  if (trajectory.slots.length >= requested) return;
  yield Anomaly(
    detector: 'sitting_ran_dry',
    severity: AnomalySeverity.invariant,
    slot: trajectory.slots.length,
    summary:
        'the slot after ${trajectory.slots.length} admitted nothing, with '
        '$requested asked for',
    census: trajectory.slots.isEmpty ? null : censusOf(trajectory.slots.last),
  );
}

/// **Invariant.** An introduction was clamped below the pace this hand has
/// shown, by the band cap alone.
///
/// Two policy inputs contradicting each other, which is what makes this
/// structural rather than a threshold. `transferableTempoFor` exists to answer
/// what tempo an unseen scale should be met at, and is deliberately the median
/// of what this hand actually does. The cap in `entryTempoFor` then discards
/// that answer for anything past the early-transfer band and substitutes the
/// gentlest tempo on the ladder.
///
/// The cap was right before pace was measured: a new geography at an unknown
/// speed was two unknowns at once, and the gentle tempo was the only honest
/// default. It is not a claim anybody would defend now that the evidence
/// exists, and it makes an intermediate player meet F natural minor at sixty
/// while meeting A natural minor at ninety-six in the same sitting.
///
/// Deliberately *not* "a later introduction was slower than an earlier one".
/// That is legitimate: geography transfers imperfectly, the bands exist to say
/// so, and meeting D flat melodic minor gently after A major at a hundred and
/// eight is the bands working. See [_entryTempoRegression], which measures
/// that as an observation.
Iterable<Anomaly> _entryTempoIgnoresPace(Trajectory trajectory) sync* {
  for (final slot in trajectory.slots) {
    if (slot.winner.challengeBypass != ChallengeBypass.newMaterial) continue;
    final transferable = slot.transferableBefore;
    if (transferable <= 0) continue;
    final asked = slot.chosen.conditions.tempoBpm;
    if (asked >= transferable) continue;

    yield Anomaly(
      detector: 'entry_tempo_ignores_pace',
      severity: AnomalySeverity.invariant,
      slot: slot.index,
      summary:
          'met ${slot.chosen.material.materialId} at '
          '${asked.toStringAsFixed(0)}bpm on '
          '${slot.chosen.conditions.hands.id} while this hand had shown '
          '${transferable.toStringAsFixed(0)}bpm on material it owns',
      census: censusOf(slot),
    );
  }
}

/// **Observation.** A material was introduced more slowly than an earlier
/// introduction on the same hand, with no failure in between.
///
/// Not an invariant, because it compares unrelated materials. A later scale
/// can legitimately arrive gentler than an earlier one: the admission bands
/// exist precisely because scale geography transfers imperfectly, so meeting a
/// black-key melodic minor slowly after an easy major is the design working
/// rather than a regression.
///
/// Kept as a count, because a run full of them still says something about how
/// the introductions across a sitting hang together.
Iterable<Anomaly> _entryTempoRegression(Trajectory trajectory) sync* {
  final highest = <HandConfiguration, (double, int)>{};
  var failedSince = <HandConfiguration>{};
  for (final slot in trajectory.slots) {
    final hands = slot.chosen.conditions.hands;
    if (!slot.outcome.completed) failedSince.add(hands);
    if (slot.winner.challengeBypass != ChallengeBypass.newMaterial) continue;

    final tempo = slot.chosen.conditions.tempoBpm;
    final previous = highest[hands];
    if (previous != null &&
        tempo < previous.$1 &&
        !failedSince.contains(hands)) {
      yield Anomaly(
        detector: 'entry_tempo_regression',
        severity: AnomalySeverity.observation,
        slot: slot.index,
        summary:
            'met new material at ${tempo.toStringAsFixed(0)}bpm on '
            '${hands.id} after meeting one at '
            '${previous.$1.toStringAsFixed(0)}bpm at slot ${previous.$2}, '
            'with nothing having gone wrong in between',
        census: censusOf(slot),
      );
    }
    if (previous == null || tempo > previous.$1) {
      highest[hands] = (tempo, slot.index);
    }
    failedSince = failedSince.difference({hands});
  }
}

/// **Observation.** How much of the sitting went to work the learner has
/// already surpassed.
///
/// A proportion, reported rather than asserted. Some repetition below the
/// frontier is ordinary practice; nobody knows yet where ordinary stops.
Iterable<Anomaly> _belowFrontierShare(Trajectory trajectory) sync* {
  if (trajectory.slots.isEmpty) return;
  final below = trajectory.slots
      .where((slot) => slot.realization == RealizationRank.surpassed)
      .length;
  final share = below / trajectory.slots.length;
  if (share < 0.2) return;
  yield Anomaly(
    detector: 'below_frontier_share',
    severity: AnomalySeverity.observation,
    summary:
        '$below of ${trajectory.slots.length} slots '
        '(${(share * 100).round()}%) asked for work already surpassed',
  );
}

/// **Observation.** One material took an implausible share of the sitting.
Iterable<Anomaly> _materialConcentration(Trajectory trajectory) sync* {
  if (trajectory.slots.length < 10) return;
  final counts = <String, int>{};
  for (final slot in trajectory.slots) {
    final id = slot.chosen.material.materialId;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final worst = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final share = worst.value / trajectory.slots.length;
  if (share < 0.4) return;
  yield Anomaly(
    detector: 'material_concentration',
    severity: AnomalySeverity.observation,
    summary:
        '${worst.key} took ${worst.value} of ${trajectory.slots.length} slots '
        '(${(share * 100).round()}%)',
  );
}

/// **Observation.** No frontier advanced for a long stretch despite the
/// learner completing what they were asked for.
///
/// Meeting material does not count as a stall. A learner working through
/// scales they have never played is going somewhere, and a run of
/// introductions is breadth rather than a frontier that will not move.
Iterable<Anomaly> _progressionStall(Trajectory trajectory) sync* {
  const window = 12;
  var since = 0;
  var completedSince = 0;
  for (final slot in trajectory.slots) {
    final advanced =
        slot.realization == RealizationRank.advancing ||
        slot.winner.challengeBypass == ChallengeBypass.newMaterial;
    if (advanced && slot.outcome.completed) {
      since = 0;
      completedSince = 0;
      continue;
    }
    if (slot.outcome.completed) completedSince++;
    since++;
    if (since == window && completedSince >= window ~/ 2) {
      yield Anomaly(
        detector: 'progression_stall',
        severity: AnomalySeverity.observation,
        slot: slot.index,
        summary:
            'no frontier advanced across $window slots, $completedSince of '
            'them completed',
        census: censusOf(slot),
      );
    }
  }
}

/// **Observation.** Both hands own a material and hands-together never
/// arrives.
Iterable<Anomaly> _handsTogetherStall(Trajectory trajectory) sync* {
  final byHand = <String, Set<HandConfiguration>>{};
  int? readyAt;
  String? readyMaterial;
  for (final slot in trajectory.slots) {
    final id = slot.chosen.material.materialId;
    final hands = slot.chosen.conditions.hands;
    if (hands == HandConfiguration.together) return;
    if (!slot.outcome.completed) continue;
    (byHand[id] ??= {}).add(hands);
    if (readyAt == null &&
        byHand[id]!.containsAll({
          HandConfiguration.right,
          HandConfiguration.left,
        })) {
      readyAt = slot.index;
      readyMaterial = id;
    }
  }
  if (readyAt == null) return;
  final waited = trajectory.slots.length - readyAt;
  if (waited < 15) return;
  yield Anomaly(
    detector: 'hands_together_stall',
    severity: AnomalySeverity.observation,
    summary:
        'both hands owned $readyMaterial by slot $readyAt and hands together '
        'never arrived in the following $waited slots',
  );
}

/// **Observation.** Support went back up and stayed up after independence was
/// working, without a failure explaining it.
Iterable<Anomaly> _guidanceRegression(Trajectory trajectory) sync* {
  final best = <String, int>{};
  for (final slot in trajectory.slots) {
    final id = slot.chosen.material.materialId;
    final independence = slot.chosen.guidance.independence;
    final reached = best[id];
    if (reached != null &&
        independence < reached &&
        slot.outcome.completed &&
        slot.winner.challengeBypass != ChallengeBypass.recovery) {
      yield Anomaly(
        detector: 'guidance_regression',
        severity: AnomalySeverity.observation,
        slot: slot.index,
        summary:
            'offered $id at independence $independence after reaching '
            '$reached, outside recovery',
        census: censusOf(slot),
      );
    }
    if (slot.outcome.completed && (reached == null || independence > reached)) {
      best[id] = independence;
    }
  }
}

/// **Observation.** The same exercise came back immediately, repeatedly.
///
/// The tempo probe echo, generalized: any two-slot cycle that repeats is the
/// scheduler talking to itself rather than teaching.
Iterable<Anomaly> _shortCycleRepetition(Trajectory trajectory) sync* {
  var run = 0;
  for (var i = 2; i < trajectory.slots.length; i++) {
    final same =
        trajectory.slots[i].chosen.material.materialId ==
        trajectory.slots[i - 2].chosen.material.materialId;
    run = same ? run + 1 : 0;
    if (run == 4) {
      yield Anomaly(
        detector: 'short_cycle_repetition',
        severity: AnomalySeverity.observation,
        slot: i,
        summary: 'the same two materials alternated for six slots',
        census: censusOf(trajectory.slots[i]),
      );
    }
  }
}
