import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Exploration may dominate the choice of what to practise. It may not do so
/// indefinitely while an independence question sits ranked and unasked.
void main() {
  final threshold = config.probe.maxUnservedGuidanceProbes;

  /// A state where [material] has been established at the previewed rung, so
  /// its unguided candidate is a ranked guidance probe.
  LearnerState established(TechnicalMaterial material) {
    final state = stateAt(PlacementTier.advanced);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = t0
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0
      ..establishedIndependence =
          GuidanceContext.notesPreviewedOnly.independence
      ..establishedIndependenceAt = t0;
    return state;
  }

  List<CandidateTrace> tracesFor(
    LearnerState state,
    SessionState session, {
    List<Exercise>? candidates,
  }) => pipeline.evaluate(
    state: state,
    session: session,
    candidates: candidates ?? allCandidates(),
    at: t0.plusDays(1),
  );

  group('the counter', () {
    test('rises when a ranked probe loses a free contest', () {
      final session = SessionState();

      session.recordSelectionOpportunity(
        guidanceProbeRanked: true,
        guidanceProbeSelected: false,
      );

      expect(session.unservedGuidanceProbeSelections, 1);
    });

    test('does not rise when no probe was ranked', () {
      final session = SessionState();

      session.recordSelectionOpportunity(
        guidanceProbeRanked: false,
        guidanceProbeSelected: false,
      );

      expect(
        session.unservedGuidanceProbeSelections,
        0,
        reason:
            'a question nobody could ask is not a question that went '
            'unasked',
      );
    });

    test('does not rise on a slot that was never a contest', () {
      for (final session in [
        SessionState(lastFailedExercise: exerciseFor(materials.first)),
        SessionState(tempoProbe: exerciseFor(materials.first)),
      ]) {
        session.recordSelectionOpportunity(
          guidanceProbeRanked: true,
          guidanceProbeSelected: false,
        );

        expect(
          session.unservedGuidanceProbeSelections,
          0,
          reason:
              'recovery and tempo probes narrow the slot to one candidate, '
              'so nothing lost it',
        );
      }
    });

    test('resets when one is selected', () {
      final session = SessionState(unservedGuidanceProbeSelections: 99);

      session.recordSelectionOpportunity(
        guidanceProbeRanked: true,
        guidanceProbeSelected: true,
      );

      expect(session.unservedGuidanceProbeSelections, 0);
    });
  });

  group('the guard', () {
    test('services the waiting question once the wait is long enough', () {
      final material = materials.first;
      final state = established(material);
      final patient = SessionState(unservedGuidanceProbeSelections: threshold);
      final fresh = SessionState();

      final traces = tracesFor(state, fresh);
      final chosenWhenFresh = pipeline.selectChoice(traces, fresh);
      final chosenWhenOverdue = pipeline.selectChoice(traces, patient);

      expect(
        chosenWhenFresh?.challengeBypass,
        isNot(ChallengeBypass.guidanceProbe),
        reason: 'a test where novelty was not winning proves nothing',
      );
      expect(chosenWhenOverdue?.challengeBypass, ChallengeBypass.guidanceProbe);
    });

    test('picks the best-ranked probe, not the first one it finds', () {
      final state = stateAt(PlacementTier.advanced);
      for (final material in materials) {
        state.materialMemoryFor(material.materialId, learnerParams)
          ..memoryAnchorAt = t0
          ..factualLastRetrievalAt = t0
          ..lastRetrievalAttemptAt = t0
          ..establishedIndependence =
              GuidanceContext.notesPreviewedOnly.independence
          ..establishedIndependenceAt = t0;
      }
      final overdue = SessionState(unservedGuidanceProbeSelections: threshold);

      final traces = tracesFor(state, overdue);
      final probes = [
        for (final trace in traces)
          if (trace.challengeBypass == ChallengeBypass.guidanceProbe) trace,
      ];
      expect(probes.length, greaterThan(1));

      expect(
        pipeline.selectChoice(traces, overdue),
        same(pipeline.selectBest(probes)),
        reason:
            'ranking still decides which independence question is the '
            'right one; fairness only decides that one gets asked',
      );
    });

    test('never manufactures a question nobody has earned', () {
      // A learner with no established rung has no independence probe to
      // service, however long the counter has run.
      final beginner = stateAt(PlacementTier.beginner);
      final overdue = SessionState(
        unservedGuidanceProbeSelections: threshold * 10,
      );

      final traces = tracesFor(beginner, overdue);
      expect(
        traces.where(
          (trace) => trace.challengeBypass == ChallengeBypass.guidanceProbe,
        ),
        isEmpty,
      );
      expect(pipeline.overdueGuidanceProbe(traces, overdue), isNull);
      expect(pipeline.selectChoice(traces, overdue), isNotNull);
    });

    test('is inert when the probe would have won anyway', () {
      final material = materials.first;
      final state = established(material);
      final only = [exerciseFor(material)];
      final overdue = SessionState(unservedGuidanceProbeSelections: threshold);
      final fresh = SessionState();

      final traces = tracesFor(state, fresh, candidates: only);

      expect(
        pipeline.selectChoice(traces, overdue)?.exercise,
        pipeline.selectChoice(traces, fresh)?.exercise,
      );
    });
  });
}
