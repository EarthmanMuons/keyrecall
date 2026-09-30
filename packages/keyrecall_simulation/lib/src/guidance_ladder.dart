import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'goal_trajectory_experiment.dart';
import 'python_compatible_random.dart';
import 'synthetic_performance.dart';
import 'synthetic_player.dart';

/// The rung an attempt was presented at.
enum Rung { cued, previewed, unguided }

Rung rungOf(GuidanceContext guidance) => guidance.concurrentPitchCues
    ? Rung.cued
    : guidance.notesPreviewed
    ? Rung.previewed
    : Rung.unguided;

/// One presented attempt, and what became of the unguided version of it.
class LadderSlot {
  final int session;
  final Rung rung;

  /// How the chosen candidate was admitted, or null for the ordinary band.
  final ChallengeBypass? bypass;

  /// For a supported attempt, why the unguided realization of the same
  /// material and hand was not the one chosen: `admitted` when it survived
  /// admission and lost the ranking, otherwise the refusal or eligibility
  /// reason, or `absent`.
  final String? unguidedFate;

  final FactualRetrieval retrieval;
  final double pitchIntegrity;
  final double? motorScore;

  const LadderSlot({
    required this.session,
    required this.rung,
    required this.bypass,
    required this.unguidedFate,
    required this.retrieval,
    required this.pitchIntegrity,
    required this.motorScore,
  });

  /// Whether the attempt met the pitch and timing coverage asks for.
  bool meets(RequirementCompletionPolicy policy) =>
      pitchIntegrity >= policy.minimumPitchIntegrity &&
      (motorScore ?? 0) >= policy.minimumMotorScore;
}

/// Follows [player] under [scope] and records, for every attempt, the rung it
/// was presented at and why a more independent one was not.
///
/// Separates the three reasons a learner stays supported: the unguided
/// realization was not eligible or admitted, it was admitted and lost the
/// ranking, or it was chosen and failed.
Future<List<LadderSlot>> traceGuidanceLadder({
  required GoalTrajectoryScope scope,
  required SyntheticPlayer player,
  required int seed,
  int sessions = 10,
  int slotsPerSession = 20,
}) async {
  final at0 = DateTime.utc(2026);
  const learner = LearnerModel();
  final pipeline = _LastSelection(learner: learner);
  final store = InMemoryPracticeStore(createdAt: at0);
  final profile = Profile(
    id: '${player.id}-$seed',
    displayName: player.id,
    createdAt: at0,
    placement: player.placement,
  );
  final plan = scope.plan;
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];
  final resolution = plan.resolve(catalog) as ResolvedPlan;
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final slots = <LadderSlot>[];
  var ids = 0;

  for (var sessionIndex = 0; sessionIndex < sessions; sessionIndex++) {
    final start = at0.add(Duration(days: sessionIndex + 1));
    playing.restUntil(start);
    final session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: catalog,
      learner: learner,
      pipeline: pipeline,
      goal: resolution.goal,
      focus: resolution.focus,
      sessionId: '${profile.id}-$sessionIndex',
      nextId: () => '${profile.id}-${ids++}',
    );
    for (var index = 0; index < slotsPerSession; index++) {
      final at = start.add(Duration(minutes: index));
      final decided = await session.decideOutcome(at: at);
      if (decided case PresentedAttempt(:final exercise, :final decision)) {
        final selection = pipeline.last!;
        final rung = rungOf(exercise.guidance);
        final outcome = playing.play(exercise, random);
        slots.add(
          LadderSlot(
            session: sessionIndex,
            rung: rung,
            bypass: selection is CandidateSelected
                ? selection.candidate.challengeBypass
                : null,
            unguidedFate: rung == Rung.unguided
                ? null
                : _unguidedFate(selection.traces, exercise),
            retrieval: outcome.retrieval,
            pitchIntegrity: outcome.pitchIntegrity,
            motorScore: outcome.motorScore,
          ),
        );
        await session.acknowledgePresentation(decision.attemptId);
        await session.closeWithOutcome(outcome, observedWallTime: at);
      } else if (decided case PresentedAcquisition(:final task)) {
        await session.closeAcquisition(
          performAcquisition(state: playing, task: task, rng: random),
          at: at,
        );
      } else {
        break;
      }
    }
  }
  return slots;
}

String _unguidedFate(List<CandidateTrace> traces, Exercise chosen) {
  final unguided = [
    for (final trace in traces)
      if (rungOf(trace.exercise.guidance) == Rung.unguided &&
          trace.exercise.material == chosen.material &&
          trace.exercise.conditions.hands == chosen.conditions.hands)
        trace,
  ];
  if (unguided.isEmpty) return 'absent';
  if (unguided.any((trace) => trace.isRanked)) return 'admitted';
  return ({
    for (final trace in unguided)
      trace.admissionRefusal?.name ?? trace.eligibility.code.name,
  }.toList()..sort()).join('+');
}

class _LastSelection extends SchedulerPipeline {
  SelectionResult? last;

  _LastSelection({required super.learner});

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
    Set<Exercise>? attemptedExercises,
    Set<(String, Hand)>? retrievedMaterialHands,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    Map<String, Set<RealizationShape>> demonstratedShapes = const {},
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
      attemptedExercises: attemptedExercises,
      retrievedMaterialHands: retrievedMaterialHands,
      executionEvidenceRevisions: executionEvidenceRevisions,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      demonstratedShapes: demonstratedShapes,
      diagnose: diagnose,
    );
    last = slot.result;
    return slot;
  }
}
