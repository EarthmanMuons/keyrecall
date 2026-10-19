import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'allocation_history.dart';
import 'requirement_state.dart';

/// Days between attempts at a material after which a return counts as a
/// revisit.
///
/// Provisional and descriptive: a return after an interval, not evidence that
/// anything was retained or forgotten.
const int pilotRevisitGapDays = 7;

/// Attempts at one strand, none of them managed, after which the strand counts
/// as repeated without execution.
///
/// Provisional and descriptive: repeated unsuccessful execution, not evidence
/// that further practice would not help.
const int pilotUnmanagedRepeats = 5;

/// What one profile's practice says about the allocation pilot, projected
/// from history on the device.
///
/// Everything here is derived from the attempt and acquisition logs and
/// [evaluated], the scope coverage is read against; nothing is recorded for
/// it. Breadth counts distinct materials, a material covered when every
/// requirement on it is and retained when none of those is due, with
/// requirement counts beside them.
///
/// De-identified rather than anonymous: it names materials and requirements by
/// their catalog ids and time by days and attempts since the first attempt,
/// and carries no name, profile id, session id, or date, but a history's shape
/// can still be distinctive.
Map<String, Object?> pilotReportOf({
  required AttemptJournal journal,
  required AcquisitionJournal acquisition,
  required EvaluatedPracticeScope evaluated,
  required SchedulingAssignment assigned,
  LearnerModel learner = const LearnerModel(),
}) {
  final records = journal.records;
  final first = records.isEmpty ? null : records.first.identity.occurredAt;
  int dayOf(DateTime at) => at.difference(first!).inDays;
  final familyOfMaterial = {
    for (final state in evaluated.requirements)
      state.resolved.material.materialId: state.resolved.material.familyId,
  };
  final requirementsOf = <String, List<RequirementState>>{};
  for (final state in evaluated.requirements) {
    requirementsOf
        .putIfAbsent(state.resolved.material.materialId, () => [])
        .add(state);
  }
  final coveredMaterials = [
    for (final MapEntry(key: material, value: states) in requirementsOf.entries)
      if (states.every((state) => state.isCovered)) material,
  ];
  final retainedMaterials = [
    for (final material in coveredMaterials)
      if (!requirementsOf[material]!.any((state) => state.isDue)) material,
  ];
  final familyOfRequirement = {
    for (final state in evaluated.requirements)
      state.resolved.requirement.id: state.resolved.material.familyId,
  };

  Map<String, int> byFamily(Iterable<String?> families) {
    final counts = {
      for (final family in TechnicalMaterial.familyIds) family: 0,
    };
    for (final family in families) {
      if (family != null) {
        counts.update(family, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  final lastAt = <String, DateTime>{};
  final revisited = <String>{};
  final strandAttempts = <ExecutionContext, int>{};
  final managedAt = <ExecutionContext, int>{};
  final sessions = <String, int>{};
  final days = <int>{};
  var recovery = 0, notStarted = 0, incomplete = 0, unmeasured = 0;
  final effective = <String, int>{};
  var substitutedUnmanaged = 0;
  final owedFamilies = <String?>[];
  for (final (index, record) in records.indexed) {
    final material = record.exercise.material.materialId;
    final at = record.identity.occurredAt;
    if (lastAt[material] case final previous?
        when at.difference(previous).inDays >= pilotRevisitGapDays) {
      revisited.add(material);
    }
    lastAt[material] = at;
    sessions.update(record.identity.sessionId, (n) => n + 1, ifAbsent: () => 1);
    days.add(dayOf(at));

    final strand = executionContextOf(record.exercise);
    strandAttempts.update(strand, (n) => n + 1, ifAbsent: () => 1);
    var managed = false;
    switch (record.closure.measurement) {
      case Measured(:final outcome):
        if (!outcome.started) notStarted++;
        if (outcome.started && !outcome.completed) incomplete++;
        managed = learner.executionWasManaged(outcome);
        if (managed) managedAt.putIfAbsent(strand, () => index);
      case _:
        unmeasured++;
    }
    if (record.decision?.challengeBypass == ChallengeBypass.recovery) {
      recovery++;
    }

    if (record.allocation.policy case final policy?) {
      effective.update(policy.effective, (n) => n + 1, ifAbsent: () => 1);
    }
    if (record.allocation case AllocationObserved(:final owedRequirementId?)) {
      owedFamilies.add(familyOfRequirement[owedRequirementId]);
      if (!managed) substitutedUnmanaged++;
    }
  }

  int? firstManaged(bool Function(ExecutionContext) which) {
    final indices = [
      for (final MapEntry(key: strand, value: index) in managedAt.entries)
        if (which(strand)) index,
    ]..sort();
    return indices.firstOrNull;
  }

  bool isScale(ExecutionContext strand) =>
      familyOfMaterial[strand.$1] == TechnicalMaterial.scaleFamilyId;
  final leftHand = firstManaged(
    (strand) => isScale(strand) && strand.$2 == HandConfiguration.left,
  );
  final together = firstManaged(
    (strand) => isScale(strand) && strand.$2 == HandConfiguration.together,
  );
  Map<String, Object?> milestone(int? index) => {
    'attempts before': index,
    'day': index == null ? null : dayOf(records[index].identity.occurredAt),
  };

  final history = AllocationHistory.of(journal, acquisition);
  final waiting = history.counters.asMap.values.toList()..sort();
  final perSession = sessions.values.toList()..sort();
  final sortedDays = days.toList()..sort();
  var longestGap = 0;
  for (var i = 1; i < sortedDays.length; i++) {
    final gap = sortedDays[i] - sortedDays[i - 1];
    if (gap > longestGap) longestGap = gap;
  }

  return {
    'assigned policy': assigned.id,
    'coverage scope': evaluated.scope.goalId,
    'attempts by effective policy': effective,
    'breadth': {
      'introduced': byFamily([
        for (final material in lastAt.keys) familyOfMaterial[material],
      ]),
      'covered': byFamily([
        for (final material in coveredMaterials) familyOfMaterial[material],
      ]),
      'retained': byFamily([
        for (final material in retainedMaterials) familyOfMaterial[material],
      ]),
      'requirements covered': byFamily([
        for (final state in evaluated.requirements)
          if (state.isCovered) state.resolved.material.familyId,
      ]),
      'requirements retained': byFamily([
        for (final state in evaluated.requirements)
          if (state.isCovered && !state.isDue) state.resolved.material.familyId,
      ]),
      'revisited after $pilotRevisitGapDays days': byFamily([
        for (final material in revisited) familyOfMaterial[material],
      ]),
    },
    'progression': {
      'strands managed': byFamily([
        for (final strand in managedAt.keys) familyOfMaterial[strand.$1],
      ]),
      'first left-hand scale managed': milestone(leftHand),
      'first hands-together scale managed': milestone(together),
    },
    'difficulty': {
      'recovery attempts': recovery,
      'not started': notStarted,
      'incomplete': incomplete,
      'unmeasured': unmeasured,
      'strands repeated $pilotUnmanagedRepeats or more times, never managed':
          byFamily([
            for (final MapEntry(key: strand, value: count)
                in strandAttempts.entries)
              if (count >= pilotUnmanagedRepeats &&
                  !managedAt.containsKey(strand))
                familyOfMaterial[strand.$1],
          ]),
      'acquisition attempts': acquisition.attempts.length,
      'acquisition attempts completed': acquisition.attempts
          .where((record) => record.completion.isComplete)
          .length,
    },
    'allocation': {
      'substitutions': byFamily(owedFamilies),
      'substitutions not managed': substitutedUnmanaged,
      'requirements waiting': waiting.length,
      'longest wait': waiting.lastOrNull ?? 0,
      'median wait': waiting.isEmpty ? 0 : waiting[waiting.length ~/ 2],
    },
    'participation': {
      'attempts': records.length,
      'sessions': sessions.length,
      'active days': days.length,
      'days since first attempt': sortedDays.lastOrNull ?? 0,
      'longest break in days': longestGap,
      'median attempts per session': perSession.isEmpty
          ? 0
          : perSession[perSession.length ~/ 2],
    },
    'evidence': {
      'observed': history.observed,
      'gaps': {
        for (final MapEntry(:key, :value) in history.gaps.entries)
          key.id: value,
      },
      'stale decisions': history.staleDecisions,
      'instrumented from event': history.instrumentedFrom,
    },
  };
}
