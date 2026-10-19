import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'requirement_state.dart';

/// Breadth-relative service priority with protected maintenance.
@immutable
class AllocationPolicy {
  /// A requirement is owed once it has missed more than [k] opportunities per
  /// actionable requirement.
  final int k;

  /// Retrieval health below which a covered requirement protects a ranking
  /// winner that would observe its retrieval.
  final double protectionFloor;

  const AllocationPolicy({required this.k, required this.protectionFloor});

  /// General Fluency's in production.
  static const production = AllocationPolicy(k: 2, protectionFloor: 0.6);
}

/// Whether [result] is an allocation opportunity: a decision that becomes a
/// durable attempt, an ordinary exercise or an acquisition offer.
bool isAllocationOpportunity(SelectionResult result) =>
    result is! SelectionBlocked;

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

/// Actionable opportunities each requirement has missed in a row.
///
/// Advanced only by committed evidence. A requirement the evidence does not
/// name keeps its count, including one out of scope, which allocation never
/// owes until it returns.
@immutable
class WaitCounters {
  final Map<String, int> _missed;

  const WaitCounters.empty() : _missed = const {};

  WaitCounters._(this._missed);

  int operator [](String requirementId) => _missed[requirementId] ?? 0;

  /// Every nonzero count, in the order allocation breaks exact ties by.
  Map<String, int> get asMap => Map.unmodifiable(_missed);

  WaitCounters advance(AllocationEvidence evidence) => advanceAll([evidence]);

  /// These counters advanced by each of [evidence] in turn.
  WaitCounters advanceAll(Iterable<AllocationEvidence> evidence) {
    final next = Map.of(_missed);
    for (final each in evidence) {
      for (final id in each.served) {
        next.remove(id);
      }
      for (final id in each.missed) {
        next[id] = (next[id] ?? 0) + 1;
      }
    }
    return WaitCounters._(next);
  }
}

/// One decision as allocation reads it.
class AllocationSlot {
  final SelectionResult result;
  final AllocationPolicy policy;

  /// The candidate the decision chose, or null for acquisition or a blocked
  /// slot.
  final CandidateTrace? winner;

  /// Whether ordinary ranking chose [winner], the only slot allocation may
  /// take.
  final bool allocatable;

  /// Requirements due with a fully eligible realization that reached ranking.
  final int breadth;

  /// Each requirement's best fully eligible selectable realization.
  final Map<String, CandidateTrace> best;

  /// Fully eligible selectable realizations, by material.
  final Map<TechnicalMaterial, List<CandidateTrace>> selectable;

  /// Whether [winner] observes retrieval of a covered requirement whose health
  /// is below the policy's floor.
  final bool winnerProtected;

  final Map<String, RequirementState> _requirements;
  final Set<String> _actionable;
  final RankTolerances _order;

  AllocationSlot._({
    required this.result,
    required this.policy,
    required this.winner,
    required this.allocatable,
    required this.breadth,
    required this.best,
    required this.selectable,
    required this.winnerProtected,
    required Map<String, RequirementState> requirements,
    required Set<String> actionable,
    required RankTolerances order,
  }) : _requirements = requirements,
       _actionable = actionable,
       _order = order;

  factory AllocationSlot.of({
    required SelectionResult result,
    required List<RequirementState> requirements,
    required SchedulerPipeline pipeline,
    required LearnerState state,
    required DateTime at,
    required AllocationPolicy policy,
  }) {
    final winner = switch (result) {
      CandidateSelected(:final candidate) => candidate,
      _ => null,
    };
    final byMaterial = <TechnicalMaterial, List<CandidateTrace>>{};
    for (final trace in result.traces) {
      byMaterial.putIfAbsent(trace.exercise.material, () => []).add(trace);
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
    bool serves(String id, CandidateTrace trace) => _serves(byId[id]!, trace);

    final actionable = <String>{};
    final best = <String, CandidateTrace>{};
    final healthOf = <TechnicalMaterial, double>{};
    double health(TechnicalMaterial material) => healthOf[material] ??=
        state.materialMemory[material.materialId]?.retrievabilityOrPrior(at) ??
        0;
    final fading = <String>{};
    for (final requirement in requirements) {
      final id = requirement.resolved.requirement.id;
      final material = requirement.resolved.material;
      if (requirement.isDue &&
          (byMaterial[material] ?? const []).any(
            (t) =>
                t.isRanked &&
                t.eligibility.tier == EligibilityTier.fullyEligible &&
                serves(id, t),
          )) {
        actionable.add(id);
      }
      final own = pipeline.selectBest([
        for (final trace in selectable[material] ?? const <CandidateTrace>[])
          if (serves(id, trace)) trace,
      ]);
      if (own != null) best[id] = own;
      if (requirement.isCovered && health(material) < policy.protectionFloor) {
        fading.add(id);
      }
    }
    return AllocationSlot._(
      result: result,
      policy: policy,
      winner: winner,
      allocatable:
          result is CandidateSelected && result.stage == SelectionStage.ranking,
      breadth: actionable.length,
      best: best,
      selectable: selectable,
      winnerProtected:
          winner != null &&
          winner.exercise.guidance.isRetrievalObserved &&
          winner.eligibility.tier == EligibilityTier.fullyEligible &&
          fading.any((id) => serves(id, winner)),
      requirements: byId,
      actionable: actionable,
      order: pipeline.config.rankTolerances,
    );
  }

  static bool _serves(RequirementState requirement, CandidateTrace trace) {
    final resolved = requirement.resolved;
    return trace.exercise.material == resolved.material &&
        resolved.requirement.constraints.matchesStructure(trace.exercise);
  }

  /// The requirements in scope at this decision, by id, in scope order.
  Map<String, RequirementState> get requirements => _requirements;

  /// Whether [trace] serves the in-scope requirement [requirementId].
  bool serves(String requirementId, CandidateTrace trace) =>
      _serves(_requirements[requirementId]!, trace);

  /// Ordinary ranking's order, better candidates greater.
  int compare(CandidateTrace a, CandidateTrace b) =>
      _order.compare(a.rankKey!, b.rankKey!);

  /// What allocation would choose with [waiting], or null to leave the slot.
  ///
  /// Only requirements in scope are owed, and only an allocatable slot is
  /// taken. [bestByRequirement] replaces [best], and [protectedWinner] false
  /// ignores protection, for asking what else might have happened.
  AllocationChoice<CandidateTrace>? choose(
    Map<String, int> waiting, {
    bool protectedWinner = true,
    Map<String, CandidateTrace>? bestByRequirement,
  }) {
    if (!allocatable) return null;
    return allocate(
      winner: winner!,
      winnerProtected: protectedWinner && winnerProtected,
      waiting: {
        for (final MapEntry(:key, :value) in waiting.entries)
          if (_requirements.containsKey(key)) key: value,
      },
      bestByRequirement: bestByRequirement ?? best,
      breadth: breadth,
      k: policy.k,
      compare: compare,
      serves: serves,
    );
  }

  /// [result] with [candidate] chosen by ranking in place of [winner].
  CandidateSelected substitute(CandidateTrace candidate) => CandidateSelected(
    diagnostics: result.diagnostics,
    traces: result.traces,
    selectable: result.selectable,
    pacing: result.pacing,
    dose: result.dose,
    introductions: result.introductions,
    candidate: candidate,
    stage: SelectionStage.ranking,
  );

  /// What presenting [chosen] does for every requirement in scope, or what
  /// acquisition does when [chosen] is null.
  AllocationEvidence evidence(CandidateTrace? chosen) {
    final served = [
      for (final id in _requirements.keys)
        if (chosen != null && serves(id, chosen)) id,
    ];
    return AllocationEvidence(
      served: served,
      missed: [
        for (final id in _requirements.keys)
          if (_actionable.contains(id) && !served.contains(id)) id,
      ],
    );
  }

  /// Allocation's decision with [counters], or ordinary ranking's with
  /// [allocating] false, and the evidence either would commit.
  AllocationResolution resolve(
    WaitCounters counters, {
    required bool allocating,
  }) {
    final choice = allocating ? choose(counters.asMap) : null;
    final chosen = choice?.candidate ?? winner;
    return AllocationResolution(
      result: choice == null ? result : substitute(choice.candidate),
      choice: choice,
      evidence: evidence(chosen),
    );
  }
}

/// What allocation resolved for one decision.
class AllocationResolution {
  /// The decision to present.
  final SelectionResult result;

  /// The substitution allocation made, or null when it left the slot.
  final AllocationChoice<CandidateTrace>? choice;

  /// What committing [result] advances waiting by.
  final AllocationEvidence evidence;

  const AllocationResolution({
    required this.result,
    required this.choice,
    required this.evidence,
  });
}

/// What allocation reads at one decision, taken together so that what the
/// decision records is exactly what it read.
@immutable
class AllocationRequest {
  /// Every requirement in scope, as the evaluation the decision was scoped by
  /// left it, in scope order.
  final List<RequirementState> requirements;

  final WaitCounters counters;

  /// The history [counters] were folded from.
  final AllocationBasis basis;

  /// The policy to apply, or null to observe ordinary ranking unchanged.
  final AllocationPolicy? policy;

  AllocationRequest({
    required List<RequirementState> requirements,
    required this.counters,
    required this.basis,
    this.policy,
  }) : requirements = List.unmodifiable(requirements);
}

/// What allocation made of one decision.
@immutable
class AllocationVerdict {
  /// What presenting the decision does for every requirement in scope.
  final AllocationEvidence evidence;

  /// The history the decision's counters were folded from, as requested.
  final AllocationBasis basis;

  /// The owed requirement allocation took the slot for, or null when it left
  /// ordinary ranking's choice.
  final String? owedRequirementId;

  /// What to persist about the decision when allocation decided it: ordinary
  /// ranking's diagnostics, named as such, and then allocation's own account.
  /// Null when allocation only observed, whose diagnostics are ranking's.
  final String? diagnostics;

  const AllocationVerdict({
    required this.evidence,
    required this.basis,
    this.owedRequirementId,
    this.diagnostics,
  });
}

/// [result] as [request] resolves it, and what that records for allocation.
///
/// What every host runs, wherever it decides.
({SelectionResult result, AllocationVerdict allocation}) resolveAllocation(
  SelectionResult result,
  AllocationRequest request, {
  required SchedulerPipeline pipeline,
  required LearnerState state,
  required DateTime at,
}) {
  final policy = request.policy;
  final slot = AllocationSlot.of(
    result: result,
    requirements: request.requirements,
    pipeline: pipeline,
    state: state,
    at: at,
    policy: policy ?? AllocationPolicy.production,
  );
  final resolution = slot.resolve(request.counters, allocating: policy != null);
  return (
    result: resolution.result,
    allocation: AllocationVerdict(
      evidence: resolution.evidence,
      basis: request.basis,
      owedRequirementId: resolution.choice?.requirementId,
      diagnostics: policy == null
          ? null
          : allocationDiagnostics(slot, resolution, request.counters),
    ),
  );
}

/// What allocation made of [slot], after ordinary ranking's diagnostics,
/// which are kept as they were written and named as ranking's.
///
/// The final exercise is described in full and by its candidate number, so
/// it can be found whether or not ranking listed it among its contenders.
String allocationDiagnostics(
  AllocationSlot slot,
  AllocationResolution resolution,
  WaitCounters counters,
) {
  final traces = slot.result.traces;
  String described(CandidateTrace? trace) => trace == null
      ? 'none'
      : 'candidate=${traces.indexOf(trace)} '
            '${trace.exercise.material.materialId} '
            '${trace.exercise.conditions.hands.id} '
            '${trace.exercise.conditions.handMotion.id} '
            '${trace.exercise.conditions.octaves}oct '
            '${trace.exercise.conditions.direction.id} '
            '${trace.exercise.conditions.tempoBpm}bpm '
            'g=${trace.exercise.guidance.independence}';
  final choice = resolution.choice;
  final finalCandidate = switch (resolution.result) {
    CandidateSelected(:final candidate) => candidate,
    _ => null,
  };
  return [
    'section=ordinary_ranking; the selection diagnostics below describe '
        'ordinary ranking, and winner names its choice',
    slot.result.diagnostics,
    '',
    'section=allocation; allocation diagnostics v1; what was presented',
    'policy k=${slot.policy.k} protection_floor=${slot.policy.protectionFloor} '
        'breadth=${slot.breadth} allocatable=${slot.allocatable} '
        'winner_protected=${slot.winnerProtected}',
    'substituted=${choice != null} '
        'owed_requirement=${choice?.requirementId ?? '-'} '
        'waited=${choice == null ? '-' : counters[choice.requirementId!]}',
    'ordinary_winner ${described(slot.winner)}',
    'final ${described(finalCandidate)}',
  ].join('\n');
}
