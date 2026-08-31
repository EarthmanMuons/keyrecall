import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'trajectory.dart';
import 'trajectory_detectors.dart';

enum CaseOrder { first, worst }

class TrajectoryCase {
  final Trajectory trajectory;
  final Anomaly anomaly;

  const TrajectoryCase({required this.trajectory, required this.anomaly});
}

List<TrajectoryCase> detectorCases(
  Iterable<Trajectory> trajectories, {
  required String detector,
  int limit = 3,
  CaseOrder order = CaseOrder.first,
  int? requestedSlots,
}) => selectTrajectoryCases(
  trajectoryCases(
    trajectories,
    detector: detector,
    requestedSlots: requestedSlots,
  ),
  limit: limit,
  order: order,
);

List<TrajectoryCase> trajectoryCases(
  Iterable<Trajectory> trajectories, {
  required String detector,
  int? requestedSlots,
}) {
  final cases = <TrajectoryCase>[];
  for (final trajectory in trajectories) {
    for (final anomaly in detectAnomalies(
      trajectory,
      requestedSlots: requestedSlots,
    )) {
      if (anomaly.detector != detector) continue;
      cases.add(TrajectoryCase(trajectory: trajectory, anomaly: anomaly));
    }
  }
  return cases;
}

List<TrajectoryCase> selectTrajectoryCases(
  Iterable<TrajectoryCase> source, {
  int limit = 3,
  CaseOrder order = CaseOrder.first,
}) {
  final byArchetype = <String, List<TrajectoryCase>>{};
  for (final selected in source) {
    (byArchetype[selected.trajectory.playerId] ??= []).add(selected);
  }
  final selected = <TrajectoryCase>[];
  final archetypes = byArchetype.keys.toList()..sort();
  for (final archetype in archetypes) {
    final cases = byArchetype[archetype]!;
    cases.sort((a, b) => _compareCases(a, b, order));
    selected.addAll(cases.take(limit));
  }
  return selected;
}

int _compareCases(TrajectoryCase a, TrajectoryCase b, CaseOrder order) {
  if (order == CaseOrder.worst) {
    final byMagnitude = b.anomaly.magnitude.compareTo(a.anomaly.magnitude);
    if (byMagnitude != 0) return byMagnitude;
  }
  final bySeed = a.trajectory.seed.compareTo(b.trajectory.seed);
  if (bySeed != 0) return bySeed;
  return (a.anomaly.slot ?? -1).compareTo(b.anomaly.slot ?? -1);
}

String renderTrajectoryCase(TrajectoryCase selected) {
  final trajectory = selected.trajectory;
  final anomaly = selected.anomaly;
  final detail = switch (anomaly.detector) {
    'entry_tempo_regression' => _entryTempoTimeline(trajectory, anomaly),
    'entry_tempo_band_step_down' => _entryTempoTimeline(trajectory, anomaly),
    'hands_together_stall' => _handsTogetherTimeline(trajectory, anomaly),
    _ => _nearbyTimeline(trajectory, anomaly),
  };
  return [
    '${trajectory.playerId} seed ${trajectory.seed}',
    '${anomaly.detector} magnitude=${anomaly.magnitude.toStringAsFixed(2)}',
    anomaly.summary,
    detail,
    if (anomaly.census != null) ...['decisive census:', anomaly.census!],
  ].join('\n');
}

String _entryTempoTimeline(Trajectory trajectory, Anomaly anomaly) {
  final anchor = anomaly.slot;
  if (anchor == null || anchor >= trajectory.slots.length) {
    return anomaly.census ?? '';
  }
  final current = trajectory.slots[anchor];
  final hand = current.chosen.conditions.hands;
  TrajectorySlot? baseline;
  for (final slot in trajectory.slots.take(anchor)) {
    if (slot.chosen.conditions.hands != hand) continue;
    if (!slot.outcome.completed) {
      baseline = null;
      continue;
    }
    if (slot.winner.challengeBypass != ChallengeBypass.newMaterial) continue;
    if (baseline == null ||
        slot.chosen.conditions.tempoBpm > baseline.chosen.conditions.tempoBpm) {
      baseline = slot;
    }
  }

  final start = baseline?.index ?? 0;
  final events = trajectory.slots
      .skip(start)
      .take(anchor - start + 1)
      .where(
        (slot) =>
            slot.chosen.conditions.hands == hand &&
            (slot.winner.challengeBypass == ChallengeBypass.newMaterial ||
                slot.winner.challengeBypass == ChallengeBypass.tempoProbe ||
                slot.winner.challengeBypass == ChallengeBypass.recovery ||
                !slot.outcome.completed),
      );
  final signals = <String>[];
  final expected = _entryPolicyTempo(current);
  if (expected != null && current.chosen.conditions.tempoBpm < expected) {
    signals.add('asked tempo is below the current entry policy');
  }
  if (baseline != null &&
      current.transferableBefore < baseline.transferableBefore) {
    signals.add('transferable hand pace fell between introductions');
  }
  if (baseline != null &&
      admissionBandOf(current.chosen.material).index >
          admissionBandOf(baseline.chosen.material).index) {
    signals.add('the later material is in a later admission band');
  }
  final contextual = events.any(
    (slot) =>
        slot.winner.challengeBypass == ChallengeBypass.tempoProbe ||
        slot.winner.challengeBypass == ChallengeBypass.recovery,
  );
  if (contextual) signals.add('a tempo probe or recovery occurred in between');
  if (signals.isEmpty) signals.add('no listed policy distinction explains it');

  return [
    'signals: ${signals.join('; ')}',
    'entry timeline (${hand.id}):',
    ...events.map(_entryLine),
  ].join('\n');
}

double? _entryPolicyTempo(TrajectorySlot slot) {
  final transferable = slot.transferableBefore;
  if (transferable <= 0) return null;
  return admissionBandOf(
        slot.chosen.material,
      ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer)
      ? transferable
      : tempoBefore(transferable);
}

String _entryLine(TrajectorySlot slot) {
  final exercise = slot.chosen;
  final expected = _entryPolicyTempo(slot);
  return '  ${slot.index.toString().padLeft(2)} '
      '${(slot.winner.challengeBypass?.id ?? 'ordinary').padRight(19)} '
      '${exercise.material.materialId.padRight(19)} '
      '${admissionBandOf(exercise.material).id.padRight(21)} '
      'asked=${exercise.conditions.tempoBpm.toStringAsFixed(0).padLeft(3)} '
      'transfer=${slot.transferableBefore.toStringAsFixed(0).padLeft(3)} '
      'policy=${expected?.toStringAsFixed(0).padLeft(3) ?? '  -'} '
      'completed=${slot.outcome.completed}';
}

String _handsTogetherTimeline(Trajectory trajectory, Anomaly anomaly) {
  final material = anomaly.subject;
  if (material == null) return anomaly.census ?? '';
  final ready = trajectory.slots.indexWhere(
    (slot) => slot.handsTogether.prerequisiteSatisfied.contains(material),
  );
  if (ready < 0) return anomaly.census ?? '';

  return [
    'hands-together timeline ($material):',
    for (final slot in trajectory.slots.skip(ready))
      _handsTogetherLine(slot, material),
  ].join('\n');
}

String _handsTogetherLine(TrajectorySlot slot, String material) {
  final stages = slot.handsTogether;
  final admitted = stages.admitted.contains(material);
  final selectable = stages.selectable.contains(material);
  final chosen = slot.chosen;
  final selected =
      chosen.material.materialId == material &&
      chosen.conditions.hands == HandConfiguration.together;
  final candidates = [slot.winner, ...slot.alternatives].where(
    (trace) =>
        trace.exercise.material.materialId == material &&
        trace.exercise.conditions.hands == HandConfiguration.together,
  );
  final best = candidates.isEmpty ? null : candidates.first.rankKey;
  return '  ${slot.index.toString().padLeft(2)} '
      'P=${stages.prerequisiteSatisfied.contains(material)} '
      'E=${stages.eligible.contains(material)} A=$admitted S=$selectable '
      'guarded=${admitted && !selectable} selected=$selected '
      'chosen=${chosen.material.materialId}/${chosen.conditions.hands.id} '
      'htRank=${best ?? '-'}';
}

String _nearbyTimeline(Trajectory trajectory, Anomaly anomaly) {
  final anchor = anomaly.slot ?? trajectory.slots.length - 1;
  final start = (anchor - 5).clamp(0, trajectory.slots.length);
  final end = (anchor + 1).clamp(0, trajectory.slots.length);
  return [
    'timeline:',
    for (final slot in trajectory.slots.sublist(start, end))
      '  ${slot.index.toString().padLeft(2)} '
          '${slot.chosen.material.materialId}/'
          '${slot.chosen.conditions.hands.id} '
          '${slot.chosen.conditions.tempoBpm.toStringAsFixed(0)}bpm '
          '${slot.winner.challengeBypass?.id ?? 'ordinary'} '
          'completed=${slot.outcome.completed} '
          'frontierAdvanced=${slot.frontierAdvanced}',
  ].join('\n');
}
