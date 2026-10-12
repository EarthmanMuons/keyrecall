import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'requirement_allocator.dart';
import 'service_census.dart';
import 'service_pressure.dart';

/// Why a strand was given its follow-through.
enum FollowThroughTrigger {
  /// No attempt on the strand has carried a motor score.
  neverTimed,

  /// An attempt carried one, and none was managed.
  timedUnmanaged,
}

/// One prioritized follow-up, and how it went once played.
class FollowThroughEvent {
  final int decision;

  /// Where its attempt lands in the journal, which acquisition decisions keep
  /// from matching [decision].
  final int journalIndex;
  final ExecutionContext strand;
  final FollowThroughTrigger trigger;
  Outcome? outcome;

  FollowThroughEvent(
    this.decision,
    this.journalIndex,
    this.strand,
    this.trigger,
  );
}

/// Allocation with one prioritized, timing-valid follow-up per introduced
/// strand that has not yet demonstrated a tempo.
///
/// A strand is an execution context: a material, its hands, and their motion.
/// It is introduced by its first attempt. On a slot ordinary ranking decided
/// and allocation left alone, whose winner is not protected, the strand
/// introduced earliest that still lacks a demonstrated tempo, has not had its
/// follow-through, and has a fully eligible realization able to carry a motor
/// score in the final selectable set takes the slot with the best of them.
/// Eligibility, admission, tempo, guidance, and measurement are untouched, and
/// an unmanaged follow-through leaves the strand to ordinary selection.
class FollowThrough implements ServiceIntervention {
  final RequirementAllocator allocator;

  /// Disabled, it only counts what it would have had to work with.
  final bool enabled;

  final Map<ExecutionContext, int> _introducedAt = {};
  final Set<ExecutionContext> _timed = {};
  final Set<ExecutionContext> _given = {};
  final List<ServiceSubstitution> _substitutions = [];
  final Map<int, FollowThroughEvent> _pending = {};
  int _settled = 0;

  /// Every follow-through given, in order.
  final List<FollowThroughEvent> events = [];

  /// Strand-decisions while a strand awaited its follow-through, by what
  /// became of it.
  final Map<String, int> waiting = {};

  FollowThrough(this.allocator, {this.enabled = true});

  @override
  List<ServiceSubstitution> get substitutions =>
      [...allocator.substitutions, ..._substitutions]
        ..sort((a, b) => a.decision.compareTo(b.decision));

  @override
  Map<String, num> get diagnostics => {
    ...allocator.diagnostics,
    'follow-throughs': events.length,
    for (final MapEntry(:key, :value) in waiting.entries)
      'awaiting follow-through, $key': value,
  };

  @override
  void settle(AttemptJournal journal, LearnerModel learner, int decision) {
    allocator.settle(journal, learner, decision);
    final records = journal.records;
    for (; _settled < records.length; _settled++) {
      final record = records[_settled];
      final strand = executionContextOf(record.exercise);
      _introducedAt.putIfAbsent(strand, () => _settled);
      if (record.closure.measurement case Measured(:final outcome)) {
        if (outcome.motorScore != null) _timed.add(strand);
        _pending.remove(_settled)?.outcome = outcome;
      }
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
    final allocated = allocator.intervene(
      decision: decision,
      result: result,
      requirements: requirements,
      pipeline: pipeline,
      state: state,
      session: session,
      at: at,
      journalLength: journalLength,
    );
    final awaiting = [
      for (final MapEntry(key: strand, value: introduced)
          in _introducedAt.entries)
        if (!_given.contains(strand) &&
            (state.materialExecution[strand]?.demonstratedOctaves ?? 0) == 0)
          (strand, introduced),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (awaiting.isEmpty) return allocated;

    bool timingValid(CandidateTrace trace) =>
        TimingCapacity.of(trace.exercise).supportsMotorScore;
    final followUps = <ExecutionContext, List<CandidateTrace>>{};
    for (final trace in result.selectable) {
      if (trace.eligibility.tier == EligibilityTier.fullyEligible &&
          timingValid(trace)) {
        followUps
            .putIfAbsent(executionContextOf(trace.exercise), () => [])
            .add(trace);
      }
    }
    final winner = switch (result) {
      CandidateSelected(:final candidate) => candidate,
      _ => null,
    };
    final rankingSlot =
        result is CandidateSelected && result.stage == SelectionStage.ranking;
    final open = enabled && rankingSlot && allocated == null;
    final slotHolder = !rankingSlot
        ? switch (result) {
            CandidateSelected(:final stage) => stage.name,
            AcquisitionOffered() => 'acquisition',
            SelectionBlocked() => 'blocked',
          }
        : allocated != null
        ? 'allocation'
        : allocator.winnerProtected
        ? 'protected winner'
        : null;

    ExecutionContext? chosen;
    for (final (strand, _) in awaiting) {
      final String fate;
      if (followUps[strand] == null) {
        fate = _whyUnavailable(strand, result.traces, timingValid);
      } else if (winner != null &&
          executionContextOf(winner.exercise) == strand &&
          timingValid(winner)) {
        fate = 'chosen by ${slotHolder ?? 'ranking'}';
      } else if (slotHolder != null) {
        fate = 'slot held by $slotHolder';
      } else if (!enabled) {
        fate = 'available';
      } else if (chosen == null && open) {
        chosen = strand;
        fate = 'followed through';
      } else {
        fate = 'another strand followed through';
      }
      waiting.update(fate, (n) => n + 1, ifAbsent: () => 1);
    }
    if (chosen == null) return allocated;

    final promoted = pipeline.selectBest(followUps[chosen]!)!;
    final event = FollowThroughEvent(
      decision,
      journalLength,
      chosen,
      _timed.contains(chosen)
          ? FollowThroughTrigger.timedUnmanaged
          : FollowThroughTrigger.neverTimed,
    );
    _given.add(chosen);
    events.add(event);
    _pending[journalLength] = event;
    final order = pipeline.config.rankTolerances;
    _substitutions.add(
      ServiceSubstitution(
        decision: decision,
        displacedMaterialId: winner!.exercise.material.materialId,
        requirementId: '${chosen.$1}/${chosen.$2.name}',
        missed: 0,
        behindOn: order.compare(promoted.rankKey!, winner.rankKey!) < 0
            ? decidingRankTerm(promoted.rankKey!, winner.rankKey!, order)
            : 'tie',
        displacedStage: SelectionStage.ranking,
        reason: 'follow-through',
        promotedSelectable: result.selectable.contains(promoted),
        promotedFullyEligible:
            promoted.eligibility.tier == EligibilityTier.fullyEligible,
        promotedServesRequirement:
            executionContextOf(promoted.exercise) == chosen &&
            timingValid(promoted),
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

  /// The furthest a strand's timing-valid realizations got, when none reached
  /// the final selectable set fully eligible.
  static String _whyUnavailable(
    ExecutionContext strand,
    List<CandidateTrace> traces,
    bool Function(CandidateTrace) timingValid,
  ) {
    final own = [
      for (final trace in traces)
        if (executionContextOf(trace.exercise) == strand && timingValid(trace))
          trace,
    ];
    if (own.isEmpty) return 'none generated';
    final eligible = own.where(
      (t) => t.eligibility.tier == EligibilityTier.fullyEligible,
    );
    if (eligible.isEmpty) {
      return 'not fully eligible, ${own.first.eligibility.code.name}';
    }
    final admitted = eligible.where((t) => t.admissionRefusal == null);
    if (admitted.isEmpty) {
      return 'refused, ${eligible.first.admissionRefusal!.name}';
    }
    return 'filtered';
  }

  @override
  void record(List<RequirementObservation> observations) =>
      allocator.record(observations);
}

/// How every strand of [familyId] went from introduction to managed
/// execution, read from the journal a run wrote.
///
/// Gaps are in attempts, which are decisions wherever no acquisition task was
/// offered between them.
Map<String, Object?> summarizeStrands(
  List<AttemptRecord> records,
  String familyId, {
  List<FollowThroughEvent> events = const [],
  LearnerModel learner = const LearnerModel(),
}) {
  final introduced = <ExecutionContext, int>{};
  final firstTimed = <ExecutionContext, int>{};
  final firstManaged = <ExecutionContext, int>{};
  for (final (index, record) in records.indexed) {
    if (record.exercise.material.familyId != familyId) continue;
    final strand = executionContextOf(record.exercise);
    introduced.putIfAbsent(strand, () => index);
    if (record.closure.measurement case Measured(:final outcome)) {
      if (outcome.motorScore != null) {
        firstTimed.putIfAbsent(strand, () => index);
      }
      if (learner.executionWasManaged(outcome)) {
        firstManaged.putIfAbsent(strand, () => index);
      }
    }
  }
  List<int> gaps(Map<ExecutionContext, int> to) => [
    for (final MapEntry(key: strand, value: at) in to.entries)
      at - introduced[strand]!,
  ]..sort();
  int? median(List<int> values) =>
      values.isEmpty ? null : values[values.length ~/ 2];

  String result(Outcome? outcome) {
    if (outcome == null) return 'unrecorded';
    if (!outcome.started) return 'not started';
    if (!outcome.completed) return 'incomplete';
    final motor = outcome.motorScore;
    if (motor == null) return 'no motor score';
    if (learner.executionWasManaged(outcome)) return 'managed';
    return motor >= 0.4 ? 'near miss' : 'motor below 0.4';
  }

  final followThroughs = {
    for (final trigger in FollowThroughTrigger.values)
      trigger.name: <String, int>{},
  };
  for (final event in events) {
    if (records.length <= event.journalIndex ||
        records[event.journalIndex].exercise.material.familyId != familyId) {
      continue;
    }
    followThroughs[event.trigger.name]!.update(
      result(event.outcome),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  return {
    'introduced': introduced.length,
    'timed': firstTimed.length,
    'managed': firstManaged.length,
    'median decisions to timed': median(gaps(firstTimed)),
    'median decisions to managed': median(gaps(firstManaged)),
    'follow-throughs': followThroughs,
  };
}
