import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
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
  final conditions = slot.chosen.conditions;
  return [
    'slot ${slot.index} at ${slot.at.toIso8601String()}',
    'chosen:',
    _describeCandidate(slot.winner),
    'played ${slot.performedTempoBpm.toStringAsFixed(0)}bpm '
        '(x${slot.outcome.achievedTempoRatio.toStringAsFixed(2)}) '
        'completed=${slot.outcome.completed} '
        'motor=${slot.outcome.motorScore.toStringAsFixed(2)} '
        'pitch=${slot.outcome.pitchIntegrity.toStringAsFixed(2)}',
    'frontier for ${slot.chosen.material.materialId}/${conditions.hands.id}: '
        '${slot.frontierBefore} paced=${slot.pacedBefore.toStringAsFixed(0)}',
    'best alternatives:',
    ...slot.alternatives.take(alternatives).map(_describeCandidate),
  ].join('\n');
}

String censusOfTerminal(TerminalTrajectorySlot slot, {int candidates = 8}) {
  final best = [...slot.traces]
    ..sort((a, b) => b.prediction.overallP.compareTo(a.prediction.overallP));
  return [
    'slot ${slot.index} at ${slot.at.toIso8601String()} admitted nothing',
    '${slot.candidates.generated} generated, '
        '${slot.candidates.evaluated} evaluated, '
        '${slot.candidates.eligible} fully eligible, '
        '${slot.candidates.admitted} admitted, '
        '${slot.candidates.selectable} selectable',
    'best predicted candidates:',
    ...best.take(candidates).map(_describeCandidate),
  ].join('\n');
}

String _describeCandidate(CandidateTrace trace) {
  final c = trace.exercise.conditions;
  return '  ${trace.exercise.material.materialId.padRight(18)}'
      '${c.hands.id.padRight(9)}${c.octaves}oct '
      '${c.direction == ScaleDirection.up ? 'up  ' : 'updn'} '
      '${c.tempoBpm.toStringAsFixed(0).padLeft(4)}bpm '
      'g=${trace.exercise.guidance.independence} '
      '${(trace.challengeBypass?.id ?? 'in-band').padRight(22)}'
      '${trace.eligibility.tier.id}/${trace.eligibility.code.id} '
      '${trace.rankKey}';
}

/// Every detector, run over one trajectory.
List<Anomaly> detectAnomalies(Trajectory trajectory, {int? requestedSlots}) => [
  ..._realizationStall(trajectory),
  ..._sittingRanDry(trajectory, requestedSlots ?? trajectory.slots.length),
  ..._entryTempoIgnoresPace(trajectory),
  ..._unmeasuredEntryIgnored(trajectory),
  ..._entryTempoRegression(trajectory),
  ..._belowFrontierShare(trajectory),
  ..._materialConcentration(trajectory),
  ..._progressionStall(trajectory),
  ..._handsTogetherStall(trajectory),
  ..._guidanceRegression(trajectory),
  ..._shortCycleRepetition(trajectory),
  ..._materialCluster(trajectory),
];

/// **Invariant.** A surpassed realization was chosen while an advancing one of
/// the same material and hand was admissible and equally eligible.
///
/// Structural rather than tuned: both candidates reached ranking, both are on
/// the work the learner is already doing, and one of them asks for something
/// they have demonstrably outgrown. No threshold makes that the right choice.
/// This is the shape of the eleven-slot collapse a device sitting produced.
///
/// Only against candidates that tie on every term the key compares first, for
/// the reason [_unmeasuredEntryIgnored] does: a better realization can lose
/// legitimately because information or diversity differs, and calling that a
/// defect would be the detector encoding what the scheduler happens to do.
/// This one has never misfired, which says the ambiguity has not been reached
/// rather than that it is not there.
Iterable<Anomaly> _realizationStall(Trajectory trajectory) sync* {
  for (final slot in trajectory.slots) {
    if (slot.realization != RealizationRank.surpassed) continue;
    final better = slot.alternatives.where(
      (trace) =>
          trace.exercise.material.materialId ==
              slot.chosen.material.materialId &&
          trace.exercise.conditions.hands == slot.chosen.conditions.hands &&
          trace.rankKey!.realization == RealizationRank.advancing &&
          _tiesBeforeRealization(trace.rankKey!, slot.winner.rankKey!),
    );
    if (better.isEmpty) continue;

    yield Anomaly(
      detector: 'realization_stall',
      severity: AnomalySeverity.invariant,
      slot: slot.index,
      magnitude: better.length.toDouble(),
      summary:
          'chose ${slot.chosen.conditions.tempoBpm.toStringAsFixed(0)}bpm on '
          '${slot.chosen.material.materialId} with the frontier at '
          '${slot.frontierAtSpan.toStringAsFixed(0)}, while '
          '${better.length} advancing realizations were admissible',
      census: censusOf(slot),
    );
  }
}

/// **Invariant.** An unmeasured realization was chosen while an equally
/// eligible one of the same material, hand and span sat nearer the intended
/// entry.
///
/// The realization term's other half. `unmeasured` says nothing has been
/// demonstrated at this span, which is true of every tempo there at once, so
/// until the fit term existed a learner reaching a new span had sixty and a
/// hundred and twenty tied and generation order decided. Structural for the
/// same reason as [_realizationStall]: both candidates reached ranking, both
/// are the same work at different speeds, and one of them is the one the
/// evidence points at.
Iterable<Anomaly> _unmeasuredEntryIgnored(Trajectory trajectory) sync* {
  for (final slot in trajectory.slots) {
    if (slot.realization != RealizationRank.unmeasured) continue;
    final conditions = slot.chosen.conditions;
    final nearer = slot.alternatives.where(
      (trace) =>
          trace.exercise.material.materialId ==
              slot.chosen.material.materialId &&
          trace.exercise.conditions.hands == conditions.hands &&
          trace.exercise.conditions.octaves == conditions.octaves &&
          trace.rankKey!.realization == RealizationRank.unmeasured &&
          trace.rankKey!.realizationFit > slot.winner.rankKey!.realizationFit &&
          _tiesBeforeRealization(trace.rankKey!, slot.winner.rankKey!),
    );
    if (nearer.isEmpty) continue;

    yield Anomaly(
      detector: 'unmeasured_entry_ignored',
      severity: AnomalySeverity.invariant,
      slot: slot.index,
      magnitude: nearer.length.toDouble(),
      summary:
          'chose ${conditions.tempoBpm.toStringAsFixed(0)}bpm at '
          '${conditions.octaves} octaves of '
          '${slot.chosen.material.materialId}, with ${nearer.length} '
          'realizations of the same work sitting nearer the entry the '
          'evidence points at',
      census: censusOf(slot),
    );
  }
}

/// Whether two keys are equal on everything decided before the realization.
bool _tiesBeforeRealization(RankKey a, RankKey b) =>
    a.tier == b.tier &&
    a.coordinationTransition == b.coordinationTransition &&
    a.retention == b.retention &&
    a.information == b.information &&
    a.diversity == b.diversity &&
    a.goals == b.goals;

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
  final terminal = trajectory.terminal;
  yield Anomaly(
    detector: 'sitting_ran_dry',
    severity: AnomalySeverity.invariant,
    slot: trajectory.slots.length,
    magnitude: (requested - trajectory.slots.length).toDouble(),
    summary:
        'the slot after ${trajectory.slots.length} admitted nothing, with '
        '$requested asked for',
    census: terminal == null ? null : censusOfTerminal(terminal),
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
/// exists, and it made an intermediate player meet F natural minor at sixty
/// while meeting A natural minor at ninety-six in the same sitting.
///
/// The early-transfer band may use the full transferable tempo. Later bands
/// may enter one rung below the material's established pace.
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
    final floor = _entryTempoFloor(slot)!;
    final asked = slot.chosen.conditions.tempoBpm;
    if (asked >= floor) continue;

    yield Anomaly(
      detector: 'entry_tempo_ignores_pace',
      severity: AnomalySeverity.invariant,
      slot: slot.index,
      magnitude: floor - asked,
      summary:
          'met ${slot.chosen.material.materialId} at '
          '${asked.toStringAsFixed(0)}bpm on '
          '${slot.chosen.conditions.hands.id} while this hand had shown '
          '${transferable.toStringAsFixed(0)}bpm on material it owns, more '
          'than the one rung a harder geography is worth',
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
/// A step that exactly matches the documented later-band discount is reported
/// separately from an otherwise unexplained regression.
Iterable<Anomaly> _entryTempoRegression(Trajectory trajectory) sync* {
  final highest = <HandConfiguration, (double, int)>{};
  for (final slot in trajectory.slots) {
    final hands = slot.chosen.conditions.hands;
    if (slot.winner.challengeBypass == ChallengeBypass.newMaterial) {
      final tempo = slot.chosen.conditions.tempoBpm;
      final previous = highest[hands];
      if (previous != null && tempo < previous.$1) {
        final previousSlot = trajectory.slots[previous.$2];
        final band = admissionBandOf(slot.chosen.material);
        final previousBand = admissionBandOf(previousSlot.chosen.material);
        final expected = _entryTempoFloor(slot);
        final isBandStep =
            expected != null &&
            tempo == expected &&
            band.index > previousBand.index;
        yield Anomaly(
          detector: isBandStep
              ? 'entry_tempo_band_step_down'
              : 'entry_tempo_regression',
          severity: AnomalySeverity.observation,
          slot: slot.index,
          magnitude: previous.$1 - tempo,
          subject: slot.chosen.material.materialId,
          summary: isBandStep
              ? 'met later-band material at ${tempo.toStringAsFixed(0)}bpm '
                    'on ${hands.id}, the documented one-rung discount from '
                    '${previous.$1.toStringAsFixed(0)}bpm'
              : 'met new material at ${tempo.toStringAsFixed(0)}bpm on '
                    '${hands.id} after meeting one at '
                    '${previous.$1.toStringAsFixed(0)}bpm at slot '
                    '${previous.$2}, with nothing having gone wrong in between',
          census: censusOf(slot),
        );
      }
      if (slot.outcome.completed && (previous == null || tempo > previous.$1)) {
        highest[hands] = (tempo, slot.index);
      }
    }
    if (!slot.outcome.completed) highest.remove(hands);
  }
}

double? _entryTempoFloor(TrajectorySlot slot) {
  final transferable = slot.transferableBefore;
  if (transferable <= 0) return null;
  return admissionBandOf(
        slot.chosen.material,
      ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer)
      ? transferable
      : tempoBefore(transferable);
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
    magnitude: share,
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
    magnitude: share,
    subject: worst.key,
    summary:
        '${worst.key} took ${worst.value} of ${trajectory.slots.length} slots '
        '(${(share * 100).round()}%)',
  );
}

/// **Observation.** Neither a frontier nor the material set advanced for a
/// long stretch despite the learner completing what they were asked for.
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
        slot.frontierAdvanced ||
        (slot.winner.challengeBypass == ChallengeBypass.newMaterial &&
            slot.outcome.started);
    if (advanced) {
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
        magnitude: completedSince.toDouble(),
        summary:
            'no frontier advanced and no material was introduced across '
            '$window slots, $completedSince of them completed',
        census: censusOf(slot),
      );
    }
  }
}

/// **Observation.** A material passed the hands-together prerequisite but was
/// never selected.
Iterable<Anomaly> _handsTogetherStall(Trajectory trajectory) sync* {
  final readyAt = <String, int>{};
  final chosenAt = <String, int>{};
  for (final slot in trajectory.slots) {
    for (final id in slot.handsTogether.prerequisiteSatisfied) {
      readyAt.putIfAbsent(id, () => slot.index);
    }
    if (slot.chosen.conditions.hands == HandConfiguration.together) {
      chosenAt.putIfAbsent(slot.chosen.material.materialId, () => slot.index);
    }
  }
  for (final ready in readyAt.entries) {
    final chosen = chosenAt[ready.key];
    if (chosen != null && chosen >= ready.value) continue;
    final waited = trajectory.slots.length - ready.value - 1;
    if (waited < 15) continue;
    yield Anomaly(
      detector: 'hands_together_stall',
      severity: AnomalySeverity.observation,
      magnitude: waited.toDouble(),
      subject: ready.key,
      summary:
          'the hands-together prerequisite passed for ${ready.key} at slot '
          '${ready.value}, but it was not selected in the following $waited '
          'slots',
    );
  }
}

/// **Observation.** Support went back up and stayed up after independence was
/// working, without a failure explaining it.
Iterable<Anomaly> _guidanceRegression(Trajectory trajectory) sync* {
  final best = <String, int>{};
  final pending = <String, (int, TrajectorySlot)>{};
  for (final slot in trajectory.slots) {
    final id = slot.chosen.material.materialId;
    if (slot.outcome.retrieval == FactualRetrieval.failed) {
      best.remove(id);
      pending.remove(id);
      continue;
    }
    final independence = slot.chosen.guidance.independence;
    final reached = best[id];
    if (reached != null &&
        independence < reached &&
        slot.outcome.completed &&
        slot.winner.challengeBypass != ChallengeBypass.recovery) {
      pending.putIfAbsent(id, () => (reached, slot));
    }
    if (slot.outcome.retrieval == FactualRetrieval.succeeded &&
        (reached == null || independence >= reached)) {
      best[id] = independence;
      pending.remove(id);
    }
  }
  for (final entry in pending.entries) {
    final (reached, slot) = entry.value;
    yield Anomaly(
      detector: 'guidance_regression',
      severity: AnomalySeverity.observation,
      slot: slot.index,
      magnitude: (trajectory.slots.length - slot.index).toDouble(),
      subject: entry.key,
      summary:
          '${entry.key} stayed below independence $reached from slot '
          '${slot.index} through the end of the sitting, without an '
          'intervening retrieval failure',
      census: censusOf(slot),
    );
  }
}

/// **Observation.** Two materials alternated for six slots.
///
/// The tempo probe echo, generalized: a two-slot cycle that repeats is the
/// scheduler talking to itself rather than teaching.
///
/// Alternation specifically, which this did not always mean. Comparing each
/// slot with the one two before it is true of a solid run of one material as
/// well, so a learner being taken through a scale - right hand, recover, left
/// hand, hands together - was reported as churn under a summary that described
/// something else entirely. That is a cluster rather than a cycle, and worth
/// counting separately.
Iterable<Anomaly> _shortCycleRepetition(Trajectory trajectory) sync* {
  var run = 0;
  for (var i = 2; i < trajectory.slots.length; i++) {
    final earlier = trajectory.slots[i - 2].chosen.material.materialId;
    final previous = trajectory.slots[i - 1].chosen.material.materialId;
    final current = trajectory.slots[i].chosen.material.materialId;
    run = current == earlier && current != previous ? run + 1 : 0;
    if (run == 4) {
      yield Anomaly(
        detector: 'short_cycle_repetition',
        severity: AnomalySeverity.observation,
        slot: i,
        magnitude: 6,
        subject: current,
        summary: '$current and $previous alternated for six slots',
        census: censusOf(trajectory.slots[i]),
      );
    }
  }
}

/// **Observation.** One material held six slots in a row.
///
/// Not the same thing as alternating, and not obviously wrong: taking a scale
/// through each hand and then both is a cluster somebody would recognize as
/// practice. Counted so that a run of them can be looked at rather than
/// assumed either way.
Iterable<Anomaly> _materialCluster(Trajectory trajectory) sync* {
  var run = 1;
  for (var i = 1; i < trajectory.slots.length; i++) {
    final same =
        trajectory.slots[i].chosen.material.materialId ==
        trajectory.slots[i - 1].chosen.material.materialId;
    run = same ? run + 1 : 1;
    if (run == 6) {
      yield Anomaly(
        detector: 'material_cluster',
        severity: AnomalySeverity.observation,
        slot: i,
        magnitude: 6,
        subject: trajectory.slots[i].chosen.material.materialId,
        summary:
            '${trajectory.slots[i].chosen.material.materialId} held six '
            'consecutive slots',
        census: censusOf(trajectory.slots[i]),
      );
    }
  }
}
