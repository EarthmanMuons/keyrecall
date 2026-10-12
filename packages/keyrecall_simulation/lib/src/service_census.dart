import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'demo_history.dart';
import 'service_pressure.dart';
import 'synthetic_player.dart';

/// An experimental rule run beside the scheduler, that may replace a slot
/// ordinary ranking decided.
///
/// Each decision it reads how its last choice went, is offered the slot, and
/// then sees what the decision did for every requirement.
abstract interface class ServiceIntervention {
  void settle(AttemptJournal journal, LearnerModel learner, int decision);

  /// The result to use instead of [result], or null to leave it.
  CandidateSelected? intervene({
    required int decision,
    required SelectionResult result,
    required List<RequirementState> requirements,
    required SchedulerPipeline pipeline,
    required LearnerState state,
    required SessionState session,
    required DateTime at,
    required int journalLength,
  });

  void record(List<RequirementObservation> observations);

  List<ServiceSubstitution> get substitutions;

  /// Counts that describe the rule's own contract, for reporting.
  Map<String, num> get diagnostics;
}

/// What one scheduling decision did for one scope requirement.
///
/// Facts rather than one state, because they overlap: a requirement can be
/// due and admitted and served at once, and can be served without being due.
/// "Due" is the practice layer's own judgment, and "fully ranked" means a
/// fully eligible realization reached ranking, which is all the scheduler
/// could have chosen for it.
class RequirementObservation {
  final int decision;
  final String requirementId;
  final String materialId;
  final String familyId;
  final bool due;
  final bool covered;

  /// At least one realization passed admission, at any tier.
  final bool admitted;

  /// At least one fully eligible realization in the structure the requirement
  /// asks for reached ranking.
  final bool fullyRanked;

  /// At least one fully eligible realization of its material reached ranking,
  /// whether or not it could serve this requirement.
  final bool materialRanked;

  /// Due, nothing admitted, and something was refused for a recovery target.
  final bool heldForRecovery;

  /// The winner is this requirement's material.
  final bool servedMaterial;

  /// The winner is this requirement's material in the structure it asks for,
  /// at any tempo or guidance.
  final bool served;

  /// Why a deferred requirement was not chosen: `rank:<term>` when its best
  /// realization lost the ordinary ranking on that term, `filter:<stage>` when
  /// it would have won ranking and a selection stage removed it, and
  /// `override:<stage>` when something other than ranking chose the winner.
  final String? loss;

  /// What the best fully ranked realization was for, and with which hands.
  final String? purpose;
  final String? hands;

  /// For a covered requirement that is not due: whether a fully ranked
  /// realization advances a frontier the existing progression names
  /// (`execution` or `guidance`), or reaches one it does not classify
  /// (`unclassified`). Null when there is none, or when the requirement is due.
  final String? progression;

  /// Whether the winner was progression on this requirement's material.
  final bool progressionServed;

  /// The material's retrieval health at the decision, as the practice layer
  /// reads it: zero before anything about it is remembered. Left out of
  /// [canonical], which pins classification.
  final double retrieval;

  const RequirementObservation({
    required this.decision,
    required this.requirementId,
    required this.materialId,
    required this.familyId,
    required this.due,
    required this.covered,
    required this.admitted,
    required this.fullyRanked,
    required this.materialRanked,
    required this.heldForRecovery,
    required this.servedMaterial,
    required this.served,
    this.loss,
    this.purpose,
    this.hands,
    this.progression,
    this.progressionServed = false,
    this.retrieval = 0,
  });

  /// Due and choosable, which is an opportunity whether or not it was taken.
  bool get actionable => due && fullyRanked;

  bool get deferred => actionable && !served;

  /// Due with nothing the scheduler could have chosen for it.
  bool get blocked => due && !fullyRanked;

  /// The facts a digest pins, without anything incidental to scheduling.
  String get canonical => [
    decision,
    requirementId,
    due,
    covered,
    admitted,
    fullyRanked,
    materialRanked,
    heldForRecovery,
    servedMaterial,
    served,
    loss ?? '',
    purpose ?? '',
    hands ?? '',
    progression ?? '',
    progressionServed,
  ].join('|');
}

/// What one decision chose, which every requirement it deferred lost to.
class DecisionRecord {
  final int decision;

  /// The winner's material and family, or null when nothing was chosen.
  final String? materialId;
  final String? familyId;

  /// What the winner was for, as [RequirementObservation.purpose] names it.
  final String? purpose;

  /// The selection stage that chose it, or the kind of result that was not a
  /// chosen candidate.
  final String stage;

  /// Whether its requirement was due.
  final bool? due;

  const DecisionRecord({
    required this.decision,
    required this.materialId,
    required this.familyId,
    required this.purpose,
    required this.stage,
    required this.due,
  });

  String get canonical =>
      [decision, materialId ?? '', purpose ?? '', stage, due ?? ''].join('|');
}

/// How one requirement fared across a run.
class RequirementService {
  final String requirementId;
  final String materialId;
  final String familyId;
  final int decisions;
  final int due;
  final int actionable;
  final int served;
  final int deferred;
  final int servedWhileNotDue;
  final int heldForRecovery;
  final int blocked;

  /// The most consecutive actionable opportunities missed, counting only
  /// decisions at which it was actionable: a run is not consecutive decisions.
  final int longestMissedOpportunities;

  /// The most decisions in a row it stayed due without being served.
  final int longestDueWithoutService;

  final Map<String, int> losses;
  final int progressionOpportunities;
  final int progressionServed;

  /// The most progression opportunities missed in a row.
  final int longestMissedProgression;

  const RequirementService({
    required this.requirementId,
    required this.materialId,
    required this.familyId,
    required this.decisions,
    required this.due,
    required this.actionable,
    required this.served,
    required this.deferred,
    required this.servedWhileNotDue,
    required this.heldForRecovery,
    required this.blocked,
    required this.longestMissedOpportunities,
    required this.longestDueWithoutService,
    required this.losses,
    required this.progressionOpportunities,
    required this.progressionServed,
    required this.longestMissedProgression,
  });

  /// Which of the trajectories it took, for the summary.
  String get trajectory => due == 0
      ? 'never due'
      : actionable == 0
      ? 'due, never actionable'
      : served == 0
      ? 'actionable, never served'
      : 'actionable and served';

  /// Summarizes one requirement's observations, in decision order.
  factory RequirementService.of(List<RequirementObservation> observations) {
    final first = observations.first;
    var missed = 0, longestMissed = 0;
    var dueRun = 0, longestDue = 0;
    var missedProgression = 0, longestProgression = 0;
    final losses = <String, int>{};
    for (final observation in observations) {
      if (observation.actionable) {
        missed = observation.served ? 0 : missed + 1;
        if (missed > longestMissed) longestMissed = missed;
      }
      dueRun = observation.due && !observation.served ? dueRun + 1 : 0;
      if (dueRun > longestDue) longestDue = dueRun;
      if (observation.progression != null) {
        missedProgression = observation.progressionServed
            ? 0
            : missedProgression + 1;
        if (missedProgression > longestProgression) {
          longestProgression = missedProgression;
        }
      }
      if (observation.deferred && observation.loss != null) {
        losses.update(observation.loss!, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    int count(bool Function(RequirementObservation) test) =>
        observations.where(test).length;
    return RequirementService(
      requirementId: first.requirementId,
      materialId: first.materialId,
      familyId: first.familyId,
      decisions: observations.length,
      due: count((o) => o.due),
      actionable: count((o) => o.actionable),
      served: count((o) => o.actionable && o.served),
      deferred: count((o) => o.deferred),
      servedWhileNotDue: count((o) => !o.due && o.served),
      heldForRecovery: count((o) => o.heldForRecovery),
      blocked: count((o) => o.blocked),
      longestMissedOpportunities: longestMissed,
      longestDueWithoutService: longestDue,
      losses: losses,
      progressionOpportunities: count((o) => o.progression != null),
      progressionServed: count(
        (o) => o.progression != null && o.progressionServed,
      ),
      longestMissedProgression: longestProgression,
    );
  }
}

/// Every observation a run made, and its summary by requirement.
class ServiceCensus {
  final List<RequirementObservation> observations;
  final List<DecisionRecord> decisions;

  /// The journal the run wrote, for outcomes the census does not observe.
  final List<AttemptRecord> records;

  /// What an experimental service rule changed, empty without one.
  final List<ServiceSubstitution> substitutions;

  const ServiceCensus(
    this.observations,
    this.decisions, {
    this.records = const [],
    this.substitutions = const [],
  });

  List<RequirementService> get requirements {
    final byRequirement = <String, List<RequirementObservation>>{};
    for (final observation in observations) {
      byRequirement
          .putIfAbsent(observation.requirementId, () => [])
          .add(observation);
    }
    return [
      for (final list in byRequirement.values) RequirementService.of(list),
    ];
  }

  /// A digest of what the census observed, for pinning a seeded run.
  String get digest => sha256
      .convert(
        utf8.encode(
          [
            for (final observation in observations) observation.canonical,
            for (final decision in decisions) decision.canonical,
          ].join('\n'),
        ),
      )
      .toString();
}

/// The first rank term on which [a] falls behind [b], in the order
/// [RankTolerances.compare] reads them.
///
/// An explanation of one lexicographic comparison, not of the whole selection.
/// Checked against the comparison itself, so it cannot drift from the order
/// the scheduler uses.
String decidingRankTerm(RankKey a, RankKey b, RankTolerances tolerances) {
  int flag(bool value) => value ? 1 : 0;
  int near(double x, double y, double within) =>
      (x - y).abs() <= within ? 0 : x.compareTo(y);
  final terms = <(String, int)>[
    ('tier', a.tier.index.compareTo(b.tier.index)),
    (
      'coordination_transition',
      flag(a.coordinationTransition).compareTo(flag(b.coordinationTransition)),
    ),
    (
      'contrary_coordination',
      flag(a.contraryCoordination).compareTo(flag(b.contraryCoordination)),
    ),
    ('target_shaped', flag(a.targetShaped).compareTo(flag(b.targetShaped))),
    (
      'advances_frontier',
      flag(a.advancesFrontier).compareTo(flag(b.advancesFrontier)),
    ),
    ('retention', near(a.retention, b.retention, tolerances.retention)),
    ('information', near(a.information, b.information, tolerances.information)),
    ('diversity', near(a.diversity, b.diversity, tolerances.diversity)),
    ('goals', near(a.goals, b.goals, tolerances.goals)),
    (
      'target_shaped_goal',
      flag(a.targetShapedGoal).compareTo(flag(b.targetShapedGoal)),
    ),
    ('realization', a.realization.index.compareTo(b.realization.index)),
    (
      'realization_fit',
      near(a.realizationFit, b.realizationFit, tolerances.realizationFit),
    ),
    ('shape_progression', a.shapeProgression.compareTo(b.shapeProgression)),
  ];
  final compared = tolerances.compare(a, b);
  for (final (name, order) in terms) {
    if (order == 0) continue;
    if (order.sign != compared.sign) break;
    if (order < 0) return name;
    break;
  }
  throw StateError(
    'the rank explanation disagrees with RankTolerances.compare ($compared)',
  );
}

/// A pipeline that decides exactly as its parent and records what each
/// decision did for every requirement in [scope].
///
/// Observational only: it reads the slot its parent evaluated and recomputes
/// the requirement states the session evaluated the same instant from, so
/// nothing about the decision depends on it.
class ServiceCensusPipeline extends SchedulerPipeline {
  final ResolvedPracticeScope scope;
  final AttemptJournal Function() journal;

  /// An experimental rule to run beside the policy, or null to observe the
  /// policy alone.
  final ServiceIntervention? intervention;

  final List<RequirementObservation> observations = [];
  final List<DecisionRecord> decisions = [];
  int _decision = 0;

  ServiceCensusPipeline({
    required super.learner,
    required this.scope,
    required this.journal,
    this.intervention,
  });

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    bool diagnose = true,
  }) {
    final slot = super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      diagnose: diagnose,
    );
    final evaluated = const PracticeScopeEvaluator().evaluate(
      scope: scope,
      state: state,
      journal: journal(),
      learner: learner,
      at: at,
    );
    intervention?.settle(journal(), learner, _decision);
    final substituted = intervention?.intervene(
      decision: _decision,
      result: slot.result,
      requirements: evaluated.requirements,
      pipeline: this,
      state: state,
      session: session,
      at: at,
      journalLength: journal().length,
    );
    final result = substituted ?? slot.result;
    final observed = _observe(
      state,
      session,
      at,
      history,
      evaluated,
      result,
      substituted: substituted != null,
    );
    observations.addAll(observed);
    intervention?.record(observed);
    _decision++;
    return (
      result: result,
      guidanceProbeAvailable: slot.guidanceProbeAvailable,
      guidanceProbeSelected: slot.guidanceProbeSelected,
    );
  }

  List<RequirementObservation> _observe(
    LearnerState state,
    SessionState session,
    DateTime at,
    AttemptHistory? history,
    EvaluatedPracticeScope evaluated,
    SelectionResult result, {
    required bool substituted,
  }) {
    final traces = result.traces;
    final winner = switch (result) {
      CandidateSelected(:final candidate) => candidate,
      _ => null,
    };
    final override = switch (result) {
      CandidateSelected() when substituted => 'override:intervened',
      CandidateSelected(:final stage) when stage != SelectionStage.ranking =>
        'override:${stage.name}',
      AcquisitionOffered() => 'override:acquisition',
      SelectionBlocked() => 'override:blocked',
      _ => null,
    };
    final rankingWinner = selectBest(traces);
    final echoed = withoutFreshEcho([
      for (final trace in traces)
        if (trace.isRanked) trace,
    ], session);
    final stages = <(String, Set<CandidateTrace>)>[
      ('echo', echoed.toSet()),
      ('repetition', applyRepetitionGuard(echoed, session).toSet()),
      ('introductions', result.introductions.selectable.toSet()),
      ('pacing', result.pacing.selectable.toSet()),
      ('dose', result.dose.selectable.toSet()),
      ('novelty', result.selectable.toSet()),
    ];
    final facts = DecisionFacts(
      state,
      startedExercises: history?.startedExercises,
    );
    final byMaterial = <TechnicalMaterial, List<CandidateTrace>>{};
    for (final trace in traces) {
      byMaterial.putIfAbsent(trace.exercise.material, () => []).add(trace);
    }

    final winnerDue = winner == null
        ? null
        : evaluated.requirements.any(
            (state) =>
                state.isDue &&
                state.resolved.material == winner.exercise.material &&
                state.resolved.requirement.constraints.matchesStructure(
                  winner.exercise,
                ),
          );
    decisions.add(
      DecisionRecord(
        decision: _decision,
        materialId: winner?.exercise.material.materialId,
        familyId: winner?.exercise.material.familyId,
        purpose: winner == null ? null : _purposeOf(winner, state, facts),
        stage: switch (result) {
          CandidateSelected() when substituted => 'intervened',
          CandidateSelected(:final stage) => stage.name,
          AcquisitionOffered() => 'acquisition',
          SelectionBlocked() => 'blocked',
        },
        due: winnerDue,
      ),
    );

    return [
      for (final requirementState in evaluated.requirements)
        _observeRequirement(
          requirementState,
          byMaterial[requirementState.resolved.material] ?? const [],
          winner,
          override,
          rankingWinner,
          stages,
          state,
          facts,
          at,
        ),
    ];
  }

  RequirementObservation _observeRequirement(
    RequirementState requirementState,
    List<CandidateTrace> own,
    CandidateTrace? winner,
    String? override,
    CandidateTrace? rankingWinner,
    List<(String, Set<CandidateTrace>)> stages,
    LearnerState state,
    DecisionFacts facts,
    DateTime at,
  ) {
    final resolved = requirementState.resolved;
    final material = resolved.material;
    final constraints = resolved.requirement.constraints;
    final materialRanked = [
      for (final trace in own)
        if (trace.isRanked &&
            trace.eligibility.tier == EligibilityTier.fullyEligible)
          trace,
    ];
    final ranked = [
      for (final trace in materialRanked)
        if (constraints.matchesStructure(trace.exercise)) trace,
    ];
    final best = selectBest(ranked);
    final due = requirementState.isDue;
    final servedMaterial = winner?.exercise.material == material;
    final served =
        servedMaterial && constraints.matchesStructure(winner!.exercise);

    String? loss;
    if (due && best != null && !served) {
      if (override != null) {
        loss = override;
      } else if (rankingWinner != null &&
          config.rankTolerances.compare(best.rankKey!, rankingWinner.rankKey!) <
              0) {
        loss =
            'rank:${decidingRankTerm(best.rankKey!, rankingWinner.rankKey!, config.rankTolerances)}';
      } else {
        final removedBy = stages
            .where((stage) => !stage.$2.contains(best))
            .map((stage) => stage.$1)
            .firstOrNull;
        loss = 'filter:${removedBy ?? 'choice'}';
      }
    }

    String? progression;
    if (!due && requirementState.isCovered) {
      for (final trace in ranked) {
        final kind = _progressionOf(trace);
        if (kind == null) continue;
        if (progression == null || progression == 'unclassified') {
          progression = kind;
        }
      }
    }

    return RequirementObservation(
      decision: _decision,
      requirementId: resolved.requirement.id,
      materialId: material.materialId,
      familyId: material.familyId,
      due: due,
      covered: requirementState.isCovered,
      admitted: own.any((trace) => trace.admissionRefusal == null),
      fullyRanked: best != null,
      materialRanked: materialRanked.isNotEmpty,
      heldForRecovery:
          due &&
          !own.any((trace) => trace.admissionRefusal == null) &&
          own.any(
            (trace) => trace.admissionRefusal == AdmissionRefusal.recovery,
          ),
      servedMaterial: servedMaterial,
      served: served,
      loss: loss,
      purpose: best == null ? null : _purposeOf(best, state, facts),
      hands: best?.exercise.conditions.hands.name,
      progression: progression,
      progressionServed:
          progression != null &&
          servedMaterial &&
          _progressionOf(winner!) != null,
      retrieval:
          state.materialMemory[material.materialId]?.retrievabilityOrPrior(
            at,
          ) ??
          0,
    );
  }

  String _purposeOf(
    CandidateTrace trace,
    LearnerState state,
    DecisionFacts facts,
  ) {
    if (trace.challengeBypass case final bypass?) return bypass.name;
    if (isIntroduction(state, trace.exercise, facts: facts)) {
      return 'introduction';
    }
    if (trace.executionAdvance != ExecutionAdvance.none) {
      return 'advance:${trace.executionAdvance.name}';
    }
    return 'realization:${trace.rankKey!.realization.name}';
  }

  /// Which existing frontier [trace] advances, or null for none.
  static String? _progressionOf(CandidateTrace trace) {
    if (trace.executionAdvance != ExecutionAdvance.none) return 'execution';
    if (trace.challengeBypass == ChallengeBypass.guidanceProbe) {
      return 'guidance';
    }
    if (trace.rankKey?.realization == RealizationRank.advancing) {
      return 'unclassified';
    }
    return null;
  }
}

/// Runs [player] through [sessions] under [goal] and records the census.
Future<ServiceCensus> runServiceCensus({
  required SyntheticPlayer player,
  required List<DemoSession> sessions,
  PracticeGoal goal = PracticeGoal.generalFluency,
  List<TechnicalMaterial>? materials,
  ServiceIntervention? intervention,
  int playerSeed = 0,
}) async {
  final catalog = materials ?? allPracticeMaterials;
  final scope =
      (PracticeScopeResolver().resolve(
                goal: goal,
                focus: PracticeFocus.unrestricted,
                catalog: catalog,
                instrument: InstrumentProfile(),
              )
              as ValidPracticeScope)
          .scope;
  late PracticeSession current;
  final pipeline = ServiceCensusPipeline(
    learner: const LearnerModel(),
    scope: scope,
    journal: () => current.journal,
    intervention: intervention,
  );
  final store = InMemoryPracticeStore(createdAt: demoHistoryStart);
  await practiceDemoHistory(
    store: store,
    profile: Profile(
      id: 'census',
      displayName: 'Census',
      createdAt: demoHistoryStart,
      placement: player.placement,
    ),
    player: player,
    materials: catalog,
    sessions: sessions,
    seed: playerSeed,
    goal: goal,
    pipeline: pipeline,
    onOpen: (session, _) => current = session,
  );
  return ServiceCensus(
    pipeline.observations,
    pipeline.decisions,
    records: (await store.loadJournal('census')).records,
    substitutions: intervention?.substitutions ?? const [],
  );
}
