import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'context_relief.dart';
import 'service_census.dart';
import 'service_pressure.dart';

/// Which decisions advance allocation's waiting.
enum OpportunityClock {
  /// Every decision, whatever it produced.
  everySlot,

  /// Decisions that chose an ordinary exercise.
  ordinaryAttempts,

  /// Decisions that chose an ordinary exercise or offered acquisition, the
  /// production contract.
  attemptsAndAcquisition;

  bool counts(SelectionResult result) => switch (this) {
    everySlot => true,
    ordinaryAttempts => result is CandidateSelected,
    attemptsAndAcquisition => isAllocationOpportunity(result),
  };
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

  /// Bounds service to execution groups that allocation has served repeatedly
  /// without managed execution, or null for none.
  final ContextRelief? relief;

  final OpportunityClock clock;

  WaitCounters _waiting = const WaitCounters.empty();
  AllocationSlot? _slot;
  AllocationEvidence? _evidence;
  final Map<String, int> _journalWaiting = {};
  final Map<String, int> _breadthAtStart = {};
  bool _allocatable = false;
  bool _counted = true;
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

  RequirementAllocator({
    required this.k,
    required this.protectionFloor,
    this.relief,
    this.clock = OpportunityClock.attemptsAndAcquisition,
  });

  AllocationPolicy get policy =>
      AllocationPolicy(k: k, protectionFloor: protectionFloor);

  /// Actionable opportunities [requirementId] has missed in a row.
  int waitingFor(String requirementId) => _waiting[requirementId];

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
    ...?relief?.diagnostics,
  };

  @override
  void settle(AttemptJournal journal, LearnerModel learner, int decision) =>
      relief?.settle(journal, learner);

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
    final slot = _slot = AllocationSlot.of(
      result: result,
      requirements: requirements,
      pipeline: pipeline,
      state: state,
      at: at,
      policy: policy,
    );
    final winner = slot.winner;
    _allocatable = slot.allocatable;
    _counted = clock.counts(result);
    _breadth = slot.breadth;

    final byMaterial = <TechnicalMaterial, List<CandidateTrace>>{};
    for (final trace in result.traces) {
      byMaterial.putIfAbsent(trace.exercise.material, () => []).add(trace);
    }
    final byId = slot.requirements;
    final best = slot.best;
    final serves = slot.serves;
    final bound = k * _breadth;
    final owed = [
      for (final id in byId.keys)
        if (_waiting[id] > bound) id,
    ];
    final winnerProtected = _winnerProtected = slot.winnerProtected;

    AllocationChoice<CandidateTrace>? choice;
    final withheld = <String>{};
    if (_allocatable) {
      if (owed.any((id) => !best.containsKey(id))) _owedUnservable++;
      choice = slot.choose(_waiting.asMap);
      final shadow = slot.choose(_journalWaiting);
      if (choice != null) _choices++;
      if (shadow != null) _journalChoices++;
      if (choice?.candidate != shadow?.candidate) _disagreements++;
      if (winnerProtected &&
          slot.choose(_waiting.asMap, protectedWinner: false) != null) {
        _withheldForProtection++;
      }
      if (relief case final relief?) {
        while (choice != null &&
            !relief.admit(ContextRelief.groupOf(choice.candidate.exercise))) {
          withheld.add(ContextRelief.groupOf(choice.candidate.exercise));
          final among = {
            for (final requirement in requirements)
              requirement.resolved.requirement.id: ?pipeline.selectBest([
                for (final trace
                    in slot.selectable[requirement.resolved.material] ??
                        const <CandidateTrace>[])
                  if (serves(requirement.resolved.requirement.id, trace) &&
                      !withheld.contains(ContextRelief.groupOf(trace.exercise)))
                    trace,
              ]),
          };
          choice = slot.choose(_waiting.asMap, bestByRequirement: among);
          if (choice != null &&
              best[choice.requirementId] != choice.candidate &&
              withheld.contains(
                ContextRelief.groupOf(best[choice.requirementId]!.exercise),
              )) {
            relief.usedAlternative();
          }
        }
      }
    }

    final chosen = choice?.candidate ?? winner;
    _evidence = slot.evidence(chosen);
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
                : withheld.contains(ContextRelief.groupOf(best[id]!.exercise))
                ? ('no slot', 'relief')
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
    relief?.serve(journalLength);
    substitutions.add(
      ServiceSubstitution(
        decision: decision,
        displacedMaterialId: displaced.exercise.material.materialId,
        requirementId: promotedFor,
        missed: _waiting[promotedFor],
        behindOn: slot.compare(promoted, displaced) < 0
            ? decidingRankTerm(
                promoted.rankKey!,
                displaced.rankKey!,
                pipeline.config.rankTolerances,
              )
            : 'tie',
        displacedStage: (result as CandidateSelected).stage,
        reason: choice.reason,
        promotedSelectable: result.selectable.contains(promoted),
        promotedFullyEligible:
            promoted.eligibility.tier == EligibilityTier.fullyEligible,
        promotedServesRequirement: serves(promotedFor, promoted),
      ),
    );
    return slot.substitute(promoted);
  }

  /// Replaces the candidate the last decision presents, for a rule that takes
  /// the slot after allocation.
  void presented(CandidateTrace candidate) =>
      _evidence = _slot!.evidence(candidate);

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
    final observed = AllocationEvidence(
      served: [
        for (final o in observations)
          if (o.served) o.requirementId,
      ],
      missed: [
        for (final o in observations)
          if (o.deferred) o.requirementId,
      ],
    );
    if (_evidence case final evidence? when evidence != observed) {
      throw StateError('allocation evidence $evidence, census $observed');
    }
    _evidence = null;
    if (!_counted) return;
    final present = {for (final o in observations) o.requirementId};
    for (final map in [_journalWaiting, _breadthAtStart]) {
      map.removeWhere((id, _) => !present.contains(id));
    }
    _waiting = _waiting.advance(observed);
    for (final observation in observations) {
      final id = observation.requirementId;
      if (observation.served) {
        _journalWaiting.remove(id);
        _breadthAtStart.remove(id);
        continue;
      }
      _journalWaiting[id] = observation.due
          ? (_journalWaiting[id] ?? 0) + 1
          : 0;
      if (!observation.actionable) continue;
      final waited = _waiting[id];
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
