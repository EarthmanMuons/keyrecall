import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'service_census.dart';
import 'service_pressure.dart';

/// What allocation chose for a slot, and why.
class AllocationChoice<T> {
  final T candidate;

  /// The requirement served, for an owed choice.
  final String? requirementId;

  /// Always `owed`: protection only ever keeps a slot, it never takes one.
  final String reason;

  const AllocationChoice(this.candidate, this.reason, [this.requirementId]);
}

/// The allocation contract for one slot ordinary ranking decided, or null to
/// leave [winner].
///
/// A requirement is owed once its [waiting] exceeds [k] times [breadth], the
/// number of requirements actionable now. Nothing changes while nothing owed
/// has a candidate, while [winner] already serves an owed requirement, or
/// while [winner] is protected: protection keeps its own slot and claims no
/// other. Otherwise the owed requirement furthest past its bound takes the
/// slot, its best candidate by [compare] breaking ties.
AllocationChoice<T>? allocate<T>({
  required T winner,
  required bool winnerProtected,
  required Map<String, int> waiting,
  required Map<String, T> bestByRequirement,
  required int breadth,
  required int k,
  required int Function(T a, T b) compare,
  required bool Function(String requirementId, T candidate) serves,
}) {
  final bound = k * breadth;
  final owed = [
    for (final MapEntry(key: id, value: missed) in waiting.entries)
      if (missed > bound && bestByRequirement.containsKey(id)) id,
  ];
  if (owed.isEmpty) return null;
  if (owed.any((id) => serves(id, winner))) return null;
  if (winnerProtected) return null;
  String? chosen;
  for (final id in owed) {
    if (chosen == null) {
      chosen = id;
      continue;
    }
    final byWaiting = waiting[id]!.compareTo(waiting[chosen]!);
    if (byWaiting > 0 ||
        (byWaiting == 0 &&
            compare(
                  bestByRequirement[id] as T,
                  bestByRequirement[chosen] as T,
                ) >
                0)) {
      chosen = id;
    }
  }
  return AllocationChoice(bestByRequirement[chosen] as T, 'owed', chosen);
}

/// The first stage of the allocation design, run beside the scheduler:
/// breadth-relative service priority and protected maintenance over the
/// existing selectable set, with no new acquisition or recovery path.
///
/// A slot is protected when ordinary ranking's own winner can observe
/// retrieval of a covered requirement whose health has fallen below
/// [protectionFloor]. Owed service never displaces it, and a fading material
/// elsewhere in the scope protects nothing about this slot.
///
/// Waiting is counted exactly, in actionable opportunities missed in a row.
/// The journal-reconstructible counter, decisions due without service, is kept
/// beside it and decides a shadow choice, so the two can be compared without
/// either being persisted.
class RequirementAllocator implements ServiceIntervention {
  final int k;
  final double protectionFloor;

  final Map<String, int> _waiting = {};
  final Map<String, int> _journalWaiting = {};
  final Map<String, int> _breadthAtStart = {};
  bool _allocatable = false;
  int _breadth = 0;

  @override
  final List<ServiceSubstitution> substitutions = [];

  int _postponedByBreadth = 0;
  int _withheldForProtection = 0;
  int _owedUnservable = 0;
  int _choices = 0;
  int _journalChoices = 0;
  int _disagreements = 0;

  RequirementAllocator({required this.k, required this.protectionFloor});

  /// Actionable opportunities [requirementId] has missed in a row.
  int waitingFor(String requirementId) => _waiting[requirementId] ?? 0;

  /// Decisions [requirementId] has been due without service, the counter the
  /// journal could reproduce.
  int journalWaitingFor(String requirementId) =>
      _journalWaiting[requirementId] ?? 0;

  @override
  Map<String, num> get diagnostics => {
    'owed selections': substitutions.length,
    'service withheld for protection': _withheldForProtection,
    'postponed by breadth': _postponedByBreadth,
    'owed, nothing feasible': _owedUnservable,
    'exact counter acted': _choices,
    'journal counter acted': _journalChoices,
    'counters chose differently': _disagreements,
  };

  @override
  void settle(AttemptJournal journal, LearnerModel learner, int decision) {}

  @override
  CandidateSelected? intervene({
    required int decision,
    required SelectionResult result,
    required List<RequirementState> requirements,
    required SchedulerPipeline pipeline,
    required LearnerState state,
    required DateTime at,
    required int journalLength,
  }) {
    _allocatable = false;
    if (result case CandidateSelected(
      :final candidate,
      stage: SelectionStage.ranking,
    )) {
      _allocatable = true;
      final ranked = <TechnicalMaterial, List<CandidateTrace>>{};
      for (final trace in result.traces) {
        if (trace.isRanked &&
            trace.eligibility.tier == EligibilityTier.fullyEligible) {
          ranked.putIfAbsent(trace.exercise.material, () => []).add(trace);
        }
      }
      final selectable = <TechnicalMaterial, List<CandidateTrace>>{};
      for (final trace in result.selectable) {
        if (trace.eligibility.tier == EligibilityTier.fullyEligible) {
          selectable.putIfAbsent(trace.exercise.material, () => []).add(trace);
        }
      }

      final byId = {
        for (final state in requirements) state.resolved.requirement.id: state,
      };
      bool serves(String id, CandidateTrace trace) {
        final resolved = byId[id]!.resolved;
        return trace.exercise.material == resolved.material &&
            resolved.requirement.constraints.matchesStructure(trace.exercise);
      }

      _breadth = 0;
      final best = <String, CandidateTrace>{};
      final healthOf = <TechnicalMaterial, double>{};
      double health(TechnicalMaterial material) => healthOf[material] ??=
          state.materialMemory[material.materialId]?.retrievabilityOrPrior(
            at,
          ) ??
          0;
      final fading = <String>{};
      for (final requirement in requirements) {
        final id = requirement.resolved.requirement.id;
        final material = requirement.resolved.material;
        if (requirement.isDue &&
            (ranked[material] ?? const []).any((t) => serves(id, t))) {
          _breadth++;
        }
        final own = pipeline.selectBest([
          for (final trace in selectable[material] ?? const <CandidateTrace>[])
            if (serves(id, trace)) trace,
        ]);
        if (own != null) best[id] = own;
        if (requirement.isCovered && health(material) < protectionFloor) {
          fading.add(id);
        }
      }

      bool isProtected(CandidateTrace trace) =>
          trace.exercise.guidance.isRetrievalObserved &&
          trace.eligibility.tier == EligibilityTier.fullyEligible &&
          fading.any((id) => serves(id, trace));
      final winnerProtected = isProtected(candidate);
      final order = pipeline.config.rankTolerances;
      int compare(CandidateTrace a, CandidateTrace b) =>
          order.compare(a.rankKey!, b.rankKey!);

      AllocationChoice<CandidateTrace>? choose(Map<String, int> waiting) =>
          allocate(
            winner: candidate,
            winnerProtected: winnerProtected,
            waiting: {
              for (final MapEntry(:key, :value) in waiting.entries)
                if (byId.containsKey(key)) key: value,
            },
            bestByRequirement: best,
            breadth: _breadth,
            k: k,
            compare: compare,
            serves: serves,
          );

      final bound = k * _breadth;
      if (_waiting.entries.any(
        (e) =>
            e.value > bound &&
            byId.containsKey(e.key) &&
            !best.containsKey(e.key),
      )) {
        _owedUnservable++;
      }
      final choice = choose(_waiting);
      final shadow = choose(_journalWaiting);
      if (choice != null) _choices++;
      if (shadow != null) _journalChoices++;
      if (choice?.candidate != shadow?.candidate) _disagreements++;
      if (winnerProtected &&
          allocate(
                winner: candidate,
                winnerProtected: false,
                waiting: {
                  for (final MapEntry(:key, :value) in _waiting.entries)
                    if (byId.containsKey(key)) key: value,
                },
                bestByRequirement: best,
                breadth: _breadth,
                k: k,
                compare: compare,
                serves: serves,
              ) !=
              null) {
        _withheldForProtection++;
      }
      if (choice == null) return null;

      final promoted = choice.candidate;
      final promotedFor = choice.requirementId!;
      substitutions.add(
        ServiceSubstitution(
          decision: decision,
          displacedMaterialId: candidate.exercise.material.materialId,
          requirementId: promotedFor,
          missed: _waiting[promotedFor] ?? 0,
          behindOn: compare(promoted, candidate) < 0
              ? decidingRankTerm(promoted.rankKey!, candidate.rankKey!, order)
              : 'tie',
          displacedStage: result.stage,
          reason: choice.reason,
          promotedSelectable: result.selectable.contains(promoted),
          promotedFullyEligible:
              promoted.eligibility.tier == EligibilityTier.fullyEligible,
          promotedServesRequirement: serves(promotedFor, promoted),
        ),
      );
      return CandidateSelected(
        diagnostics: result.diagnostics,
        traces: result.traces,
        selectable: result.selectable,
        pacing: result.pacing,
        dose: result.dose,
        introductions: result.introductions,
        candidate: promoted,
        stage: SelectionStage.ranking,
      );
    }
    return null;
  }

  @override
  void record(List<RequirementObservation> observations) {
    final present = {for (final o in observations) o.requirementId};
    for (final map in [_waiting, _journalWaiting, _breadthAtStart]) {
      map.removeWhere((id, _) => !present.contains(id));
    }
    for (final observation in observations) {
      final id = observation.requirementId;
      if (observation.served) {
        _waiting.remove(id);
        _journalWaiting.remove(id);
        _breadthAtStart.remove(id);
        continue;
      }
      _journalWaiting[id] = observation.due
          ? (_journalWaiting[id] ?? 0) + 1
          : 0;
      if (!observation.actionable) continue;
      final waited = (_waiting[id] ?? 0) + 1;
      _waiting[id] = waited;
      final start = _breadthAtStart.putIfAbsent(id, () => _breadth);
      if (_allocatable && waited > k * start && waited <= k * _breadth) {
        _postponedByBreadth++;
      }
    }
  }
}
