import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final floor = exerciseFor(
    materials.first,
    guidance: GuidanceContext.continuouslyCued,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
  );
  final state = stateAt(PlacementTier.advanced);
  seedAllMaterials(state);
  state.materialMemoryFor(materials[1].materialId, learnerParams)
    ..memoryAnchorAt = t0
    ..factualLastRetrievalAt = t0
    ..lastRetrievalAttemptAt = t0
    ..establishedIndependence = GuidanceContext.notesPreviewedOnly.independence
    ..establishedIndependenceAt = t0;

  final baseline =
      pipeline
              .evaluateSlot(
                state: state,
                session: SessionState(unservedGuidanceProbeSelections: 10),
                candidates: [...allCandidates(), floor],
                at: t0.plusDays(1),
              )
              .result
          as CandidateSelected;

  test('acquisition replacing an overdue probe does not service it', () {
    final session = SessionState(unservedGuidanceProbeSelections: 10);
    final result = pipeline.decide(
      state: state,
      session: session,
      candidates: [...allCandidates(), floor],
      at: t0.plusDays(1),
      acquisition: const AcquisitionProgress.empty(),
      acquisitionFamilyFloor: scaleAcquisitionFloor([floor]),
      attemptedExercises: {floor},
    );
    expect(result, isA<AcquisitionOffered>());
    expect(SelectionEffect.of(result).guidanceProbeSelected, isFalse);
    expect(session.unservedGuidanceProbeSelections, 11);
  });

  for (final waiting in [0, 10]) {
    for (final kind in ['ordinary', 'acquisition', 'blocked']) {
      test(
        '$kind accounts only for its final result with $waiting waiting',
        () {
          final SelectionResult result = switch (kind) {
            'ordinary' => baseline,
            'acquisition' => AcquisitionOffered(
              traces: baseline.traces,
              selectable: baseline.selectable,
              pacing: baseline.pacing,
              introductions: baseline.introductions,
              task: AcquisitionTask.unmeteredTraversal(floor),
              stuck: null,
              displaced: baseline.candidate.exercise,
            ),
            _ => SelectionBlocked(
              traces: baseline.traces,
              selectable: baseline.selectable,
              pacing: baseline.pacing,
              introductions: baseline.introductions,
              reason: BlockedReason.admissionExhausted,
            ),
          };
          final effect = SelectionEffect.of(result);
          final session = SessionState(
            unservedGuidanceProbeSelections: waiting,
          );
          effect.applyTo(session);
          expect(effect.guidanceProbeAvailable, isTrue);
          expect(effect.guidanceProbeSelected, kind == 'ordinary');
          expect(
            session.unservedGuidanceProbeSelections,
            kind == 'ordinary' ? 0 : waiting + 1,
          );
          expect(
            session.lastAcquisitionParent,
            kind == 'acquisition' ? floor : null,
          );
          expect(session.attemptsThisSession, 1);
          expect(session.recentMaterialIds, isEmpty);
          expect(session.recentFamilies, isEmpty);
        },
      );
    }
  }
}
