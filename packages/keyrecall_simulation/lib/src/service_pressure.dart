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

  /// The stage that chose the displaced winner.
  final SelectionStage displacedStage;

  /// Why the slot changed hands: `pressure`, an allocator's `owed`, or
  /// `follow-through`.
  final String reason;

  /// What the substitution promised: the promoted candidate survived every
  /// selection stage, was fully eligible, and realized the requirement's
  /// structure.
  final bool promotedSelectable;
  final bool promotedFullyEligible;
  final bool promotedServesRequirement;

  const ServiceSubstitution({
    required this.decision,
    required this.displacedMaterialId,
    required this.requirementId,
    required this.missed,
    required this.behindOn,
    required this.displacedStage,
    this.reason = 'pressure',
    required this.promotedSelectable,
    required this.promotedFullyEligible,
    required this.promotedServesRequirement,
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
class ServicePressure implements ServiceIntervention {
  final int threshold;
  final int unproductiveLimit;

  final Map<String, int> _missed = {};
  final Map<String, int> _unproductive = {};
  final Map<String, int> _suspendedSince = {};
  @override
  final List<ServiceSubstitution> substitutions = [];

  @override
  Map<String, num> get diagnostics => {
    'suspensions': suspensions,
    'suspended at end': _suspendedSince.length,
  };

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

  /// The requirements suspended now, and the decision each was suspended at.
  Map<String, int> get suspendedSince => Map.unmodifiable(_suspendedSince);

  bool _suspended(String requirementId) =>
      (_unproductive[requirementId] ?? 0) >= unproductiveLimit;

  /// Reads how the last promoted attempt went, once it is in [journal].
  @override
  void settle(AttemptJournal journal, LearnerModel learner, int decision) {
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
    if (_unproductive[requirementId] == unproductiveLimit) {
      suspensions++;
      _suspendedSince[requirementId] = decision;
    }
  }

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
          displacedStage: result.stage,
          promotedSelectable: result.selectable.contains(best),
          promotedFullyEligible:
              best.eligibility.tier == EligibilityTier.fullyEligible,
          promotedServesRequirement: chosen.resolved.requirement.constraints
              .matchesStructure(best.exercise),
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
  @override
  void record(List<RequirementObservation> observations) {
    final promoted = _awaiting?.$1;
    for (final observation in observations) {
      final id = observation.requirementId;
      if (observation.served) {
        _missed[id] = 0;
        if (id != promoted) {
          _unproductive[id] = 0;
          _suspendedSince.remove(id);
        }
      } else if (observation.actionable && !_suspended(id)) {
        _missed[id] = (_missed[id] ?? 0) + 1;
      } else if (_suspended(id)) {
        _missed[id] = 0;
      }
    }
  }
}

/// What a run produced, in the terms a service rule is judged by.
///
/// Every map is keyed by family.
class ServiceOutcomes {
  /// Requirements covered where the run ended, or at its last decision for a
  /// census that was not finished.
  final Map<String, int> covered;
  final Map<String, int> actionableNeverServed;

  /// The longest run of missed actionable opportunities, worst and at the
  /// 90th percentile across requirements.
  final Map<String, int> worstMissedRun;
  final Map<String, int> p90MissedRun;

  /// Of the decisions requirements spent covered, the share spent due again.
  final Map<String, double> fading;

  /// Retrieval health averaged over every decision, across every in-scope
  /// requirement, and across only those covered at that decision. The second
  /// is descriptive: arms cover different requirements.
  final Map<String, double> retrievalAll;
  final Map<String, double> retrievalCovered;

  /// Of the requirements in [covered], the share not due.
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

  /// Requirements suspended at the end, and those of them that were still
  /// actionable after being suspended, which ordinary selection never served.
  final int suspendedAtEnd;
  final int suspendedYetActionable;

  /// The longest run of missed opportunities counted only over decisions an
  /// intervention could have taken: those ordinary ranking decided.
  final Map<String, int> worstMissedAllocatable;
  final Map<String, int> p90MissedAllocatable;

  /// The median decision at which a requirement was first covered, among
  /// those covered, or null where none was.
  final Map<String, int?> medianFirstCovered;

  /// The intervention's own counts.
  final Map<String, num> diagnostics;

  const ServiceOutcomes({
    required this.covered,
    required this.actionableNeverServed,
    required this.worstMissedRun,
    required this.p90MissedRun,
    required this.fading,
    required this.retrievalAll,
    required this.retrievalCovered,
    required this.healthyAtEnd,
    required this.incomplete,
    required this.firstTimedFaltered,
    required this.switching,
    required this.substitutions,
    this.suspensions = 0,
    this.suspendedAtEnd = 0,
    this.suspendedYetActionable = 0,
    this.worstMissedAllocatable = const {},
    this.p90MissedAllocatable = const {},
    this.medianFirstCovered = const {},
    this.diagnostics = const {},
  });

  /// Every outcome, flat, for a report that reads runs back.
  Map<String, Object?> toJson() => {
    'covered': covered,
    'actionable never served': actionableNeverServed,
    'worst missed run': worstMissedRun,
    'p90 missed run': p90MissedRun,
    'worst missed allocatable': worstMissedAllocatable,
    'p90 missed allocatable': p90MissedAllocatable,
    'fading': fading,
    'retrieval all': retrievalAll,
    'retrieval covered': retrievalCovered,
    'median first covered': medianFirstCovered,
    'healthy at end': healthyAtEnd,
    'incomplete': incomplete,
    'first timed faltered': firstTimedFaltered,
    'switching': switching,
    'substitutions': substitutions,
    'diagnostics': diagnostics,
  };

  factory ServiceOutcomes.of(
    ServiceCensus census, {
    ServiceIntervention? intervention,
  }) {
    final pressure = intervention is ServicePressure ? intervention : null;
    final families = {
      for (final observation in census.observations) observation.familyId,
      for (final requirement in census.terminal) requirement.familyId,
    };
    final last = census.observations.isEmpty
        ? -1
        : census.observations.last.decision;
    final finished = census.terminal.isNotEmpty;

    final covered = {for (final family in families) family: 0};
    var healthyAtEnd = 0;
    for (final requirement in census.terminal) {
      if (!requirement.covered) continue;
      covered[requirement.familyId] = covered[requirement.familyId]! + 1;
      if (!requirement.due) healthyAtEnd++;
    }
    final coveredDecisions = <String, int>{};
    final fadingDecisions = <String, int>{};
    final retrievalSum = <String, double>{};
    final retrievalCount = <String, int>{};
    final coveredRetrievalSum = <String, double>{};
    for (final observation in census.observations) {
      final family = observation.familyId;
      retrievalSum[family] =
          (retrievalSum[family] ?? 0) + observation.retrieval;
      retrievalCount[family] = (retrievalCount[family] ?? 0) + 1;
      if (!observation.covered) continue;
      coveredDecisions[family] = (coveredDecisions[family] ?? 0) + 1;
      coveredRetrievalSum[family] =
          (coveredRetrievalSum[family] ?? 0) + observation.retrieval;
      if (observation.due) {
        fadingDecisions[family] = (fadingDecisions[family] ?? 0) + 1;
      }
      if (!finished && observation.decision == last) {
        covered[family] = covered[family]! + 1;
        if (!observation.due) healthyAtEnd++;
      }
    }

    final neverServed = {for (final family in families) family: 0};
    final runs = <String, List<int>>{};
    for (final service in census.requirements) {
      if (service.trajectory == 'actionable, never served') {
        neverServed[service.familyId] = neverServed[service.familyId]! + 1;
      }
      runs
          .putIfAbsent(service.familyId, () => [])
          .add(service.longestMissedOpportunities);
    }
    for (final list in runs.values) {
      list.sort();
    }

    final allocatable = {
      for (final decision in census.decisions)
        if (decision.stage == 'ranking' || decision.stage == 'intervened')
          decision.decision,
    };
    final allocatableRun = <String, int>{};
    final allocatableWorst = <String, int>{};
    final firstCovered = <String, int>{};
    for (final observation in census.observations) {
      final id = observation.requirementId;
      if (observation.covered) {
        firstCovered.putIfAbsent(id, () => observation.decision);
      }
      if (observation.served) {
        allocatableRun[id] = 0;
      } else if (observation.actionable &&
          allocatable.contains(observation.decision)) {
        final run = (allocatableRun[id] ?? 0) + 1;
        allocatableRun[id] = run;
        if (run > (allocatableWorst[id] ?? 0)) allocatableWorst[id] = run;
      }
    }
    final familyOf = {
      for (final observation in census.observations)
        observation.requirementId: observation.familyId,
    };
    final allocatableRuns = <String, List<int>>{};
    final firstCoveredByFamily = <String, List<int>>{};
    for (final MapEntry(key: id, value: family) in familyOf.entries) {
      allocatableRuns
          .putIfAbsent(family, () => [])
          .add(allocatableWorst[id] ?? 0);
      if (firstCovered[id] case final decision?) {
        firstCoveredByFamily.putIfAbsent(family, () => []).add(decision);
      }
    }
    for (final list in [
      ...allocatableRuns.values,
      ...firstCoveredByFamily.values,
    ]) {
      list.sort();
    }

    var suspendedYetActionable = 0;
    final suspended = pressure?.suspendedSince ?? const {};
    for (final MapEntry(key: id, value: since) in suspended.entries) {
      if (census.observations.any(
        (o) => o.requirementId == id && o.decision > since && o.actionable,
      )) {
        suspendedYetActionable++;
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

    double ratio(num part, num whole) => whole == 0 ? 0 : part / whole;
    return ServiceOutcomes(
      covered: covered,
      actionableNeverServed: neverServed,
      worstMissedRun: {
        for (final MapEntry(:key, :value) in runs.entries) key: value.last,
      },
      p90MissedRun: {
        for (final MapEntry(:key, :value) in runs.entries)
          key: value[((value.length - 1) * 0.9).round()],
      },
      fading: {
        for (final family in families)
          family: ratio(
            fadingDecisions[family] ?? 0,
            coveredDecisions[family] ?? 0,
          ),
      },
      retrievalAll: {
        for (final family in families)
          family: ratio(retrievalSum[family] ?? 0, retrievalCount[family] ?? 0),
      },
      retrievalCovered: {
        for (final family in families)
          family: ratio(
            coveredRetrievalSum[family] ?? 0,
            coveredDecisions[family] ?? 0,
          ),
      },
      healthyAtEnd: ratio(
        healthyAtEnd,
        covered.values.fold(0, (sum, n) => sum + n),
      ),
      incomplete: ratio(incomplete, measured),
      firstTimedFaltered: ratio(faltered, firstTimed.length),
      switching: ratio(switches, pairs),
      substitutions: census.substitutions.length,
      suspensions: pressure?.suspensions ?? 0,
      suspendedAtEnd: suspended.length,
      suspendedYetActionable: suspendedYetActionable,
      worstMissedAllocatable: {
        for (final MapEntry(:key, :value) in allocatableRuns.entries)
          key: value.last,
      },
      p90MissedAllocatable: {
        for (final MapEntry(:key, :value) in allocatableRuns.entries)
          key: value[((value.length - 1) * 0.9).round()],
      },
      medianFirstCovered: {
        for (final family in families)
          family: switch (firstCoveredByFamily[family]) {
            final list? when list.isNotEmpty => list[list.length ~/ 2],
            _ => null,
          },
      },
      diagnostics: intervention?.diagnostics ?? const {},
    );
  }
}
