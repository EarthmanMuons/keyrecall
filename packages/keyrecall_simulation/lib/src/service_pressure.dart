import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'service_census.dart';

/// One decision the service rule changed, and why.
class ServiceSubstitution {
  final int decision;

  /// What ordinary ranking chose.
  final String displacedMaterialId;

  /// The requirement given the slot instead, and how many actionable
  /// opportunities it had missed in a row.
  final String requirementId;
  final int missed;

  /// The rank term its best realization was behind the displaced winner on,
  /// or `tie` where only candidate order separated them.
  final String behindOn;

  const ServiceSubstitution({
    required this.decision,
    required this.displacedMaterialId,
    required this.requirementId,
    required this.missed,
    required this.behindOn,
  });
}

/// An experimental requirement-service rule, run beside the scheduler rather
/// than inside it.
///
/// A requirement builds pressure while it is due and actionable and goes
/// unserved, counted in missed actionable opportunities, and any service
/// clears it. Once it has missed [threshold] in a row it may take a slot that
/// ordinary ranking decided, from among what survived every admission and
/// selection stage; recovery, probes, acquisition, and the filters are never
/// overridden. A covered requirement that is not due builds none.
///
/// Repeated failure is left to acquisition and recovery: a promoted attempt
/// that does not manage its execution counts against the requirement, and
/// after [unproductiveLimit] of them it builds no pressure until ordinary
/// selection serves it again.
class ServicePressure {
  final int threshold;
  final int unproductiveLimit;

  final Map<String, int> _missed = {};
  final Map<String, int> _unproductive = {};
  final List<ServiceSubstitution> substitutions = [];

  /// How many times a requirement stopped building pressure.
  int suspensions = 0;

  /// The requirement and exercise promoted at the last decision, until its
  /// attempt has been read.
  (String, Exercise)? _awaiting;
  int _awaitingAfter = 0;

  ServicePressure({required this.threshold, this.unproductiveLimit = 2});

  /// Actionable opportunities [requirementId] has missed in a row.
  int missedBy(String requirementId) => _missed[requirementId] ?? 0;

  /// Whether [requirementId] has stopped building pressure after promoted
  /// attempts that did not manage their execution.
  bool isSuspended(String requirementId) => _suspended(requirementId);

  bool _suspended(String requirementId) =>
      (_unproductive[requirementId] ?? 0) >= unproductiveLimit;

  /// Reads how the last promoted attempt went, once it is in [journal].
  void settle(AttemptJournal journal, LearnerModel learner) {
    final awaiting = _awaiting;
    if (awaiting == null || journal.length <= _awaitingAfter) return;
    _awaiting = null;
    final (requirementId, exercise) = awaiting;
    final record = journal.records.last;
    if (record.exercise != exercise) return;
    final managed = switch (record.closure.measurement) {
      Measured(:final outcome) => learner.executionWasManaged(outcome),
      _ => false,
    };
    _unproductive[requirementId] = managed
        ? 0
        : (_unproductive[requirementId] ?? 0) + 1;
    if (_unproductive[requirementId] == unproductiveLimit) suspensions++;
  }

  /// The result to use instead of [result], or null to leave it.
  CandidateSelected? intervene({
    required int decision,
    required SelectionResult result,
    required List<RequirementState> requirements,
    required SchedulerPipeline pipeline,
    required int journalLength,
  }) {
    if (result case CandidateSelected(
      :final candidate,
      stage: SelectionStage.ranking,
    )) {
      final pressured = [
        for (final state in requirements)
          if ((_missed[state.resolved.requirement.id] ?? 0) >= threshold &&
              !_suspended(state.resolved.requirement.id))
            state,
      ];
      if (pressured.isEmpty) return null;
      bool serves(RequirementState state, Exercise exercise) =>
          exercise.material == state.resolved.material &&
          state.resolved.requirement.constraints.matchesStructure(exercise);
      if (pressured.any((state) => serves(state, candidate.exercise))) {
        return null;
      }

      RequirementState? chosen;
      CandidateTrace? best;
      for (final state in pressured) {
        final missed = _missed[state.resolved.requirement.id]!;
        if (chosen != null &&
            missed <= _missed[chosen.resolved.requirement.id]!) {
          continue;
        }
        final own = pipeline.selectBest([
          for (final trace in result.selectable)
            if (trace.eligibility.tier == EligibilityTier.fullyEligible &&
                serves(state, trace.exercise))
              trace,
        ]);
        if (own == null) continue;
        chosen = state;
        best = own;
      }
      if (chosen == null || best == null) return null;

      final tolerances = pipeline.config.rankTolerances;
      final requirementId = chosen.resolved.requirement.id;
      substitutions.add(
        ServiceSubstitution(
          decision: decision,
          displacedMaterialId: candidate.exercise.material.materialId,
          requirementId: requirementId,
          missed: _missed[requirementId]!,
          behindOn: tolerances.compare(best.rankKey!, candidate.rankKey!) < 0
              ? decidingRankTerm(best.rankKey!, candidate.rankKey!, tolerances)
              : 'tie',
        ),
      );
      _awaiting = (requirementId, best.exercise);
      _awaitingAfter = journalLength;
      return CandidateSelected(
        diagnostics: result.diagnostics,
        traces: result.traces,
        selectable: result.selectable,
        pacing: result.pacing,
        dose: result.dose,
        introductions: result.introductions,
        candidate: best,
        stage: SelectionStage.ranking,
      );
    }
    return null;
  }

  /// Updates pressure from what one decision did, after [intervene].
  void record(List<RequirementObservation> observations) {
    final promoted = _awaiting?.$1;
    for (final observation in observations) {
      final id = observation.requirementId;
      if (observation.served) {
        _missed[id] = 0;
        if (id != promoted) _unproductive[id] = 0;
      } else if (observation.actionable && !_suspended(id)) {
        _missed[id] = (_missed[id] ?? 0) + 1;
      } else if (_suspended(id)) {
        _missed[id] = 0;
      }
    }
  }
}

/// What a run produced, in the terms a service rule is judged by.
class ServiceOutcomes {
  /// Per family.
  final Map<String, int> covered;
  final Map<String, int> actionableNeverServed;
  final Map<String, int> worstMissedRun;

  /// Requirement-decisions spent covered and due again, per family: retrieval
  /// that was let fade.
  final Map<String, int> fadingDecisions;

  /// Of the requirements covered at the end, how many are not due.
  final double healthyAtEnd;

  final double incomplete;

  /// Of single-hand strands that reached a timed attempt, how many faltered
  /// on it: incomplete or under 0.9 of the pitches.
  final double firstTimedFaltered;

  /// How often an attempt's material differs from the one before it in the
  /// same session.
  final double switching;

  final int substitutions;
  final int suspensions;

  const ServiceOutcomes({
    required this.covered,
    required this.actionableNeverServed,
    required this.worstMissedRun,
    required this.fadingDecisions,
    required this.healthyAtEnd,
    required this.incomplete,
    required this.firstTimedFaltered,
    required this.switching,
    required this.substitutions,
    this.suspensions = 0,
  });

  factory ServiceOutcomes.of(
    ServiceCensus census, {
    ServicePressure? pressure,
  }) {
    final covered = <String, int>{};
    final neverServed = <String, int>{};
    final worst = <String, int>{};
    final fading = <String, int>{};
    for (final observation in census.observations) {
      if (observation.due && observation.covered) {
        fading.update(observation.familyId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    var coveredAtEnd = 0, healthyAtEnd = 0;
    final last = census.observations.isEmpty
        ? -1
        : census.observations.last.decision;
    for (final observation in census.observations) {
      if (observation.decision != last || !observation.covered) continue;
      coveredAtEnd++;
      if (!observation.due) healthyAtEnd++;
    }
    for (final service in census.requirements) {
      final family = service.familyId;
      covered.putIfAbsent(family, () => 0);
      neverServed.putIfAbsent(family, () => 0);
      if (service.trajectory == 'actionable, never served') {
        neverServed[family] = neverServed[family]! + 1;
      }
      if (service.longestMissedOpportunities > (worst[family] ?? 0)) {
        worst[family] = service.longestMissedOpportunities;
      }
    }
    for (final observation in census.observations) {
      if (observation.decision == last && observation.covered) {
        covered[observation.familyId] = covered[observation.familyId]! + 1;
      }
    }

    var measured = 0, incomplete = 0, switches = 0, pairs = 0;
    final firstTimed = <String, Outcome>{};
    AttemptRecord? previous;
    for (final record in census.records) {
      if (record.closure.measurement case Measured(:final outcome)) {
        measured++;
        if (!outcome.completed) incomplete++;
        final hands = record.exercise.conditions.hands;
        if (hands != HandConfiguration.together && outcome.motorScore != null) {
          firstTimed.putIfAbsent(
            '${record.exercise.material.materialId}/${hands.name}',
            () => outcome,
          );
        }
      }
      if (previous != null &&
          previous.identity.sessionId == record.identity.sessionId) {
        pairs++;
        if (previous.exercise.material != record.exercise.material) {
          switches++;
        }
      }
      previous = record;
    }
    final faltered = firstTimed.values
        .where((outcome) => !outcome.completed || outcome.pitchIntegrity < 0.9)
        .length;

    return ServiceOutcomes(
      covered: covered,
      actionableNeverServed: neverServed,
      worstMissedRun: worst,
      fadingDecisions: fading,
      healthyAtEnd: coveredAtEnd == 0 ? 0 : healthyAtEnd / coveredAtEnd,
      incomplete: measured == 0 ? 0 : incomplete / measured,
      firstTimedFaltered: firstTimed.isEmpty ? 0 : faltered / firstTimed.length,
      switching: pairs == 0 ? 0 : switches / pairs,
      substitutions: census.substitutions.length,
      suspensions: pressure?.suspensions ?? 0,
    );
  }
}
