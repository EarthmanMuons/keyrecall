import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

const LearnerModel model = LearnerModel();
const SchedulerPipeline pipeline = SchedulerPipeline(learner: model);
final DateTime start = DateTime.utc(2026);

/// A performance, before it is fitted to the exercise it was of.
typedef Played = (bool, bool, FactualRetrieval, double, double?, double);

final Arbitrary<Played> anyPlayed = combine6(
  weighted<bool>([(9, constant(true)), (1, constant(false))]),
  weighted<bool>([(3, constant(true)), (1, constant(false))]),
  choiceOf(FactualRetrieval.values),
  weighted<double>([(1, float(min: 0, max: 1)), (1, float(min: 0.9, max: 1))]),
  optional(float(min: 0, max: 1)),
  float(min: 0, max: 1.5),
);

/// [played] as [exercise] could have produced it: retrieval is tested exactly
/// when the rung observes it, and an attempt that never began completed and
/// retrieved nothing.
Outcome outcomeOf(Exercise exercise, Played played) {
  final (started, completed, retrieval, quality, timing, tempo) = played;
  return Outcome(
    started: started,
    retrieval: !exercise.guidance.isRetrievalObserved
        ? FactualRetrieval.notTested
        : !started || retrieval == FactualRetrieval.notTested
        ? FactualRetrieval.failed
        : retrieval,
    completed: started && completed,
    materialRetrieval: quality,
    pitchIntegrity: quality,
    continuity: timing,
    temporalStability: timing,
    achievedTempoRatio: tempo,
    topologyAccuracy: quality,
  );
}

/// A learner partway through practice: where they started, what they are
/// practising, and the slots so far, each a pause and how it was played.
typedef Plan = (int, List<TechnicalMaterial>, List<(int, Played)>, int);

final Arbitrary<Plan> anyPlan = combine4(
  integer(min: 0, max: PlacementTier.values.length),
  list(
    choiceOf([...allScales, ...allRootPositionArpeggios]),
    minLength: 1,
    maxLength: 3,
  ),
  list(
    combine2(
      weighted<int>([
        (3, integer(min: 60, max: 3600)),
        (1, integer(min: 3600, max: 30 * 86400)),
      ]),
      anyPlayed,
    ),
    maxLength: 12,
  ),
  integer(min: 60, max: 30 * 86400),
);

/// The state and session [plan] leaves, the next slot's time, and what can be
/// offered in it, built by the real decision loop so every part is reachable.
///
/// Like a practice session, every decision is made from state propagated to
/// its own time, the next slot's included, and knows the shapes each material
/// has been played through cleanly in.
({
  LearnerState state,
  SessionState session,
  DateTime at,
  List<Exercise> candidates,
  Map<String, Set<RealizationShape>> shapes,
})
practised(Plan plan) {
  final (placement, materials, slots, pause) = plan;
  final state = placement == PlacementTier.values.length
      ? LearnerState.cold(model.params, at: start)
      : model.placementState(PlacementTier.values[placement], at: start);
  final session = SessionState();
  final candidates = generateCandidates(
    InstrumentProfile(),
    {...materials}.toList(),
  );
  final shapes = <String, Set<RealizationShape>>{};
  var at = start;
  for (final (seconds, played) in slots) {
    at = at.add(Duration(seconds: seconds));
    model.propagate(state, at);
    final result = pipeline.decide(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      demonstratedShapes: shapes,
    );
    if (result case CandidateSelected(:final candidate)) {
      final exercise = candidate.exercise;
      final outcome = outcomeOf(exercise, played);
      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );
      pipeline.recordOutcome(session, exercise, outcome, at: at);
      if (!exercise.guidance.isMaterialSupplied &&
          outcome.started &&
          outcome.completed &&
          outcome.pitchIntegrity >= _cleanPitchIntegrity) {
        shapes
            .putIfAbsent(exercise.material.materialId, () => {})
            .add(shapeOf(exercise));
      }
    }
  }
  at = at.add(Duration(seconds: pause));
  model.propagate(state, at);
  return (
    state: state,
    session: session,
    at: at,
    candidates: candidates,
    shapes: shapes,
  );
}

/// The pitch integrity a practice session counts a shape demonstrated at.
const double _cleanPitchIntegrity = 0.9;

SelectionResult nextSlot(Plan plan, {bool reversed = false}) {
  final (:state, :session, :at, :candidates, :shapes) = practised(plan);
  return pipeline
      .evaluateSlot(
        state: state,
        session: session,
        candidates: reversed ? candidates.reversed.toList() : candidates,
        at: at,
        demonstratedShapes: shapes,
      )
      .result;
}

CandidateTrace? winnerOf(SelectionResult result) => switch (result) {
  CandidateSelected(:final candidate) => candidate,
  _ => null,
};

void main() {
  property('a slot chooses among what it admitted, and says so', () {
    final stages = Reached({
      SelectionStage.ranking,
      SelectionStage.frontierStep,
    });
    forAll(
      anyPlan,
      seed: propertySeed,
      maxExamples: propertyBudget(60),
      onFalsify: stages.falsified,
      tearDownAll: stages.check,
      failingOnErrors<Plan>((plan) {
        final (:state, :session, :at, :candidates, :shapes) = practised(plan);
        final result = pipeline
            .evaluateSlot(
              state: state,
              session: session,
              candidates: candidates,
              at: at,
              demonstratedShapes: shapes,
            )
            .result;

        expect(result.traces, containsAll(result.selectable));
        expect(result.selectable.every((trace) => trace.isRanked), isTrue);
        final winner = winnerOf(result);
        if (winner == null) {
          expect(result, isA<SelectionBlocked>());
          expect(result.selectable, isEmpty);
          return;
        }

        expect(
          result.selectable.any((trace) => identical(trace, winner)),
          isTrue,
          reason: 'the winner is one of the selectable candidates',
        );
        final generated = {for (final c in candidates) c.atTempo(60)};
        expect(
          generated,
          contains(winner.exercise.atTempo(60)),
          reason: 'what is offered is a shape generation produced',
        );
        if (winner.challengeBypass == null) {
          expect(
            winner.isWithinChallengeBand,
            isTrue,
            reason: 'ordinary admission is through the band',
          );
        }
        // The band a journaled decision records is this floor and the
        // band's upper edge, so the flag must be what that band says.
        final p = winner.prediction.overallP;
        expect(
          winner.isWithinChallengeBand,
          winner.challengeFloor <= p && p <= pipeline.config.challenge.pMax,
          reason: 'the band flag agrees with the band it will be recorded as',
        );

        final stage = (result as CandidateSelected).stage;
        stages.add(stage);
        final best = pipeline.selectBest(result.selectable)!;
        bool advances(CandidateTrace trace) => advancesShapeFrontier(
          trace.exercise,
          shapes[trace.exercise.material.materialId] ?? const {},
        );
        switch (stage) {
          case SelectionStage.ranking:
            expect(
              identical(winner, best),
              isTrue,
              reason: '$winner was chosen over the better ranked $best',
            );
          case SelectionStage.tempoProbe:
            expect(winner.challengeBypass, ChallengeBypass.tempoProbe);
          case SelectionStage.pulseCycle:
            expect(
              winner.challengeBypass,
              anyOf(
                ChallengeBypass.pulseSupport,
                ChallengeBypass.pulseWithdrawal,
              ),
            );
          case SelectionStage.guidanceProbe:
            expect(winner.challengeBypass, ChallengeBypass.guidanceProbe);
            expect(
              session.unservedGuidanceProbeSelections,
              greaterThanOrEqualTo(
                pipeline.config.probe.maxUnservedGuidanceProbes,
              ),
            );
          case SelectionStage.frontierStep:
            // Ranking chose the material and an ordinary realization of it
            // that steps nowhere; the step replaces it at its rung and tier.
            expect(SchedulerPipeline.isProgression(best), isTrue);
            expect(best.rankKey!.coordinationTransition, isFalse);
            expect(best.rankKey!.targetShaped, isFalse);
            expect(advances(best), isFalse);
            bool stepsFromBest(CandidateTrace trace) =>
                SchedulerPipeline.isProgression(trace) &&
                trace.exercise.material == best.exercise.material &&
                trace.exercise.guidance == best.exercise.guidance &&
                trace.rankKey!.tier == best.rankKey!.tier &&
                advances(trace);
            expect(stepsFromBest(winner), isTrue);
            expect(
              identical(
                winner,
                pipeline.selectBest([
                  for (final trace in result.selectable)
                    if (stepsFromBest(trace)) trace,
                ]),
              ),
              isTrue,
              reason: '$winner is not the best ranked step past $best',
            );
          case SelectionStage.floorCheck:
            fail('no family floor was supplied, so none can be owed');
        }
      }),
    );
  });

  property('the same slot decides the same way, in any candidate order', () {
    forAll(
      anyPlan,
      seed: propertySeed,
      maxExamples: propertyBudget(40),
      failingOnErrors<Plan>((plan) {
        final first = nextSlot(plan);
        final again = nextSlot(plan);
        final reversed = nextSlot(plan, reversed: true);

        expect(winnerOf(again)?.exercise, winnerOf(first)?.exercise);
        expect(
          again.selectable.map((trace) => trace.exercise),
          first.selectable.map((trace) => trace.exercise),
        );
        expect(again.diagnostics, first.diagnostics);

        final winner = winnerOf(first);
        final other = winnerOf(reversed);
        expect(other == null, winner == null);
        if (winner != null && other!.exercise != winner.exercise) {
          expect(
            RankTolerances.exact.compare(other.rankKey!, winner.rankKey!),
            0,
            reason:
                'candidate order may decide only an exact tie, but chose '
                '$other over $winner',
          );
        }
      }),
    );
  });
}
