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

/// What became of one owed requirement at one decision.
///
/// `served`, or `no slot` when it had a feasible candidate and another
/// obligation, a protected winner, or other owed work took the decision. When
/// nothing feasible existed, the furthest stage its compatible realizations
/// reached: `no candidate`, `admission` (with the leading refusal),
/// `obligation` (refused only for recovery), `provisional` (with the leading
/// eligibility reason), or `filtered` (with the first stage that removed its
/// best candidate).
class OwedExclusion {
  final int decision;
  final String requirementId;
  final String materialId;
  final String familyId;
  final bool covered;
  final bool allocatable;
  final String kind;
  final String detail;

  const OwedExclusion({
    required this.decision,
    required this.requirementId,
    required this.materialId,
    required this.familyId,
    required this.covered,
    required this.allocatable,
    required this.kind,
    required this.detail,
  });

  /// Whether nothing feasible could have served it, for a reason of its own
  /// rather than a recovery holding the whole decision.
  bool get unservable =>
      kind != 'served' && kind != 'no slot' && kind != 'obligation';
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
  bool _winnerProtected = false;
  int _breadth = 0;

  @override
  final List<ServiceSubstitution> substitutions = [];

  /// Every decision at which a requirement was owed, and what became of it.
  final List<OwedExclusion> exclusions = [];

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

  /// Whether the last decision's ranking winner was protected.
  bool get winnerProtected => _winnerProtected;

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
    required SessionState session,
    required DateTime at,
    required int journalLength,
  }) {
    final winner = switch (result) {
      CandidateSelected(:final candidate) => candidate,
      _ => null,
    };
    _allocatable =
        result is CandidateSelected && result.stage == SelectionStage.ranking;

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
    bool serves(String id, CandidateTrace trace) {
      final resolved = byId[id]!.resolved;
      return trace.exercise.material == resolved.material &&
          resolved.requirement.constraints.matchesStructure(trace.exercise);
    }

    _breadth = 0;
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
    final order = pipeline.config.rankTolerances;
    int compare(CandidateTrace a, CandidateTrace b) =>
        order.compare(a.rankKey!, b.rankKey!);
    final bound = k * _breadth;
    final owed = [
      for (final id in byId.keys)
        if ((_waiting[id] ?? 0) > bound) id,
    ];
    final winnerProtected = _winnerProtected =
        winner != null && isProtected(winner);

    AllocationChoice<CandidateTrace>? choice;
    if (_allocatable) {
      AllocationChoice<CandidateTrace>? choose(
        Map<String, int> waiting, {
        bool protectedWinner = true,
      }) => allocate(
        winner: winner!,
        winnerProtected: protectedWinner && winnerProtected,
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
      if (owed.any((id) => !best.containsKey(id))) _owedUnservable++;
      choice = choose(_waiting);
      final shadow = choose(_journalWaiting);
      if (choice != null) _choices++;
      if (shadow != null) _journalChoices++;
      if (choice?.candidate != shadow?.candidate) _disagreements++;
      if (winnerProtected && choose(_waiting, protectedWinner: false) != null) {
        _withheldForProtection++;
      }
    }

    final chosen = choice?.candidate ?? winner;
    final echoed = withoutFreshEcho([
      for (final trace in result.traces)
        if (trace.isRanked) trace,
    ], session);
    final stages = <(String, Set<CandidateTrace>)>[
      ('echo', echoed.toSet()),
      ('repetition', pipeline.applyRepetitionGuard(echoed, session).toSet()),
      ('introductions', result.introductions.selectable.toSet()),
      ('pacing', result.pacing.selectable.toSet()),
      ('dose', result.dose.selectable.toSet()),
      ('novelty', result.selectable.toSet()),
    ];
    final stage = switch (result) {
      CandidateSelected(:final stage) => stage.name,
      AcquisitionOffered() => 'acquisition',
      SelectionBlocked() => 'blocked',
    };
    for (final id in owed) {
      final requirement = byId[id]!;
      final (kind, detail) = best.containsKey(id)
          ? (chosen != null && serves(id, chosen))
                ? ('served', choice == null ? 'ranking' : 'allocation')
                : !_allocatable
                ? ('no slot', stage)
                : winnerProtected
                ? ('no slot', 'protected winner')
                : ('no slot', 'another owed requirement')
          : _unservable(
              [
                for (final trace
                    in byMaterial[requirement.resolved.material] ??
                        const <CandidateTrace>[])
                  if (serves(id, trace)) trace,
              ],
              stages,
              pipeline,
            );
      exclusions.add(
        OwedExclusion(
          decision: decision,
          requirementId: id,
          materialId: requirement.resolved.material.materialId,
          familyId: requirement.resolved.material.familyId,
          covered: requirement.isCovered,
          allocatable: _allocatable,
          kind: kind,
          detail: detail,
        ),
      );
    }

    if (choice == null) return null;
    final promoted = choice.candidate;
    final promotedFor = choice.requirementId!;
    final displaced = winner!;
    substitutions.add(
      ServiceSubstitution(
        decision: decision,
        displacedMaterialId: displaced.exercise.material.materialId,
        requirementId: promotedFor,
        missed: _waiting[promotedFor] ?? 0,
        behindOn: compare(promoted, displaced) < 0
            ? decidingRankTerm(promoted.rankKey!, displaced.rankKey!, order)
            : 'tie',
        displacedStage: (result as CandidateSelected).stage,
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

  /// The furthest stage [compatible] realizations of an owed requirement
  /// reached, when none of them is feasible, and the leading reason there.
  static (String, String) _unservable(
    List<CandidateTrace> compatible,
    List<(String, Set<CandidateTrace>)> stages,
    SchedulerPipeline pipeline,
  ) {
    String leading(Iterable<String> reasons) {
      final counts = <String, int>{};
      for (final reason in reasons) {
        counts.update(reason, (n) => n + 1, ifAbsent: () => 1);
      }
      return (counts.entries.toList()..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            return byCount != 0 ? byCount : a.key.compareTo(b.key);
          }))
          .first
          .key;
    }

    if (compatible.isEmpty) return ('no candidate', 'none generated');
    final admitted = [
      for (final trace in compatible)
        if (trace.admissionRefusal == null) trace,
    ];
    if (admitted.isEmpty) {
      final refusals = [
        for (final trace in compatible) trace.admissionRefusal!.name,
      ];
      return refusals.every((r) => r == AdmissionRefusal.recovery.name)
          ? ('obligation', 'recovery')
          : (
              'admission',
              leading(
                refusals.where((r) => r != AdmissionRefusal.recovery.name),
              ),
            );
    }
    final full = [
      for (final trace in admitted)
        if (trace.eligibility.tier == EligibilityTier.fullyEligible &&
            trace.isRanked)
          trace,
    ];
    if (full.isEmpty) {
      return (
        'provisional',
        leading([for (final trace in admitted) trace.eligibility.code.name]),
      );
    }
    final best = pipeline.selectBest(full)!;
    return (
      'filtered',
      stages.where((stage) => !stage.$2.contains(best)).firstOrNull?.$1 ??
          'unattributed',
    );
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

/// What [exclusions] add up to over a run, once per requirement-decision.
///
/// A requirement's unservable run counts consecutive decisions at which it was
/// owed with nothing feasible for a reason of its own. A recovery holding the
/// whole decision neither extends nor ends it; anything else ends it.
Map<String, Object?> summarizeExclusions(
  List<OwedExclusion> exclusions,
  ServiceCensus census,
) {
  Map<String, int> countBy(String Function(OwedExclusion) key) {
    final counts = <String, int>{};
    for (final exclusion in exclusions) {
      counts.update(key(exclusion), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  final lastServed = <String, int>{};
  for (final observation in census.observations) {
    if (observation.served) {
      lastServed[observation.requirementId] = observation.decision;
    }
  }
  final byRequirement = <String, List<OwedExclusion>>{};
  for (final exclusion in exclusions) {
    byRequirement.putIfAbsent(exclusion.requirementId, () => []).add(exclusion);
  }
  final requirements = <Map<String, Object?>>[];
  final buckets = {'under 10': 0, '10 to 99': 0, '100 or more': 0};
  for (final MapEntry(key: id, value: own) in byRequirement.entries) {
    final unservable = [
      for (final e in own)
        if (e.unservable) e,
    ];
    if (unservable.isEmpty) continue;
    var run = 0, longest = 0, previous = -2;
    for (final exclusion in own) {
      if (exclusion.kind == 'obligation') {
        previous = exclusion.decision;
        continue;
      }
      if (exclusion.unservable) {
        run = exclusion.decision == previous + 1 ? run + 1 : 1;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
      previous = exclusion.decision;
    }
    buckets.update(
      longest < 10
          ? 'under 10'
          : longest < 100
          ? '10 to 99'
          : '100 or more',
      (n) => n + 1,
    );
    final reasons = <String, int>{};
    for (final e in unservable) {
      reasons.update('${e.kind}: ${e.detail}', (n) => n + 1, ifAbsent: () => 1);
    }
    final leading =
        (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first;
    requirements.add({
      'requirement': id,
      'material': own.first.materialId,
      'family': own.first.familyId,
      'covered': own.last.covered,
      'unservable': unservable.length,
      'longest run': longest,
      'last served': lastServed[id],
      'leading reason': leading.key,
      'reasons': reasons.length,
    });
  }
  requirements.sort(
    (a, b) => (b['longest run'] as int).compareTo(a['longest run'] as int),
  );
  return {
    'owed decisions': exclusions.length,
    'no feasible candidate': exclusions.where((e) => e.unservable).length,
    'held for recovery': exclusions.where((e) => e.kind == 'obligation').length,
    'feasible, no slot': exclusions.where((e) => e.kind == 'no slot').length,
    'served': exclusions.where((e) => e.kind == 'served').length,
    'by kind': countBy((e) => e.kind),
    'by reason': countBy((e) => '${e.kind}: ${e.detail}'),
    'unservable requirements': requirements.length,
    'longest unservable run': buckets,
    'requirements': requirements,
  };
}
