import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  test(
    'acquisition fallback retains focus and the shared selection stages',
    () {
      final state = stateAt(PlacementTier.beginner);
      final entries = [
        for (final material in materials.take(2))
          exerciseFor(
            material,
            guidance: GuidanceContext.continuouslyCued,
            direction: ExerciseDirection.up,
            tempoBpm: 60,
          ),
      ];
      for (final exercise in entries) {
        state.materialMemoryFor(exercise.material.materialId, learnerParams);
        state
                .materialExecutionFor(
                  executionContextOf(exercise),
                  t0,
                  learnerParams,
                  familyId: TechnicalMaterial.scaleFamilyId,
                )
                .lastEvidenceAt =
            t0;
      }
      // A frontier elsewhere in the family, so the pre-frontier floor does not
      // apply and ordinary admission really is exhausted here.
      state
          .materialExecutionFor(
            (
              materials[2].materialId,
              HandConfiguration.right,
              HandMotion.parallel,
            ),
            t0,
            learnerParams,
            familyId: materials[2].familyId,
          )
          .demonstrate(octaves: 1, tempoBpm: 60);
      final emphasis = GoalEmphasis({entries.last.material.materialId: 3});
      final session = SessionState();
      final slot = pipeline.evaluateSlot(
        state: state,
        session: session,
        candidates: entries,
        at: t0,
        emphasis: emphasis,
        acquisitionFloor: scaleAcquisitionFloor(entries),
      );
      final result = slot.result as CandidateSelected;
      expect(
        result.candidate.challengeBypass,
        ChallengeBypass.acquisitionFloor,
      );
      expect(result.candidate.exercise, entries.last);
      expect(result.candidate.rankKey!.goals, 2);
      expect(
        pipeline.selectable(result.traces, session, state: state, at: t0),
        result.selectable,
      );
      expect(
        pipeline.selectChoice(result.traces, session, state: state, at: t0),
        same(result.candidate),
      );
    },
  );

  test('curriculum refusal survives in-band admission and every override', () {
    final state = stateAt(PlacementTier.advanced);
    final candidates = generateCandidates(instrument, [
      TechnicalMaterial('A', ScaleForm.harmonicMinor),
      TechnicalMaterial('A', ScaleForm.melodicMinor),
    ]);
    for (final override in [null, ...ChallengeBypass.values]) {
      final result = pipeline.decide(
        state: state,
        session: SessionState(supportedAttemptsSinceObservation: 10),
        candidates: candidates,
        at: t0,
        overrides: {
          if (override != null)
            for (final e in candidates) e: override,
        },
        acquisitionFloor: scaleAcquisitionFloor(candidates),
      );
      expect(result.traces.any((t) => t.isWithinChallengeBand), isTrue);
      expect(result, isA<SelectionBlocked>());
      expect(
        result.traces.every(
          (t) => t.admissionRefusal == AdmissionRefusal.curriculum,
        ),
        isTrue,
      );
    }
  });

  test(
    'resolved introductions are reachable, unique, and inside the envelope',
    () {
      final state = stateAt(PlacementTier.advanced);
      state.materialExecutionFor(
          ('C_MAJOR', HandConfiguration.right, HandMotion.parallel),
          t0,
          learnerParams,
          familyId: TechnicalMaterial.scaleFamilyId,
        )
        ..paced(120)
        ..lastEvidenceAt = t0;
      final candidates = generateCandidates(instrument, [
        TechnicalMaterial('F', ScaleForm.naturalMinor),
      ]).where((e) => e.conditions.hands == HandConfiguration.right).toList();
      const entry = PracticeEntryPolicy.uniform(60);
      final envelope = CandidateEnvelope(candidates);
      final refined = withExecutionNeighbors(
        state,
        candidates,
        entryPolicy: entry,
      );
      expect(refined.toSet(), hasLength(refined.length));
      expect(refined.every(envelope.contains), isTrue);
      expect(
        withExecutionNeighbors(state, refined, entryPolicy: entry),
        refined,
      );
      for (final candidate in candidates) {
        final target = resolveIntroduction(
          state,
          candidate,
          entryPolicy: entry,
        );
        expect(target.source, IntroductionTempoSource.cautiousTransfer);
        expect(target.exercise.conditions.tempoBpm, 116);
        expect(refined, contains(target.exercise));
      }
      final result =
          pipeline.decide(
                state: state,
                session: SessionState(),
                candidates: candidates,
                at: t0,
              )
              as CandidateSelected;
      expect(result.candidate.exercise.conditions.tempoBpm, 116);
      expect(
        result.traces
            .where((t) => t.isRanked)
            .every((t) => t.exercise.conditions.tempoBpm == 116),
        isTrue,
      );
    },
  );

  test(
    'pending targets can change tempo but cannot restore an excluded shape',
    () {
      final state = stateAt(PlacementTier.advanced);
      final candidates = generateCandidates(instrument, [materials.first]);
      final envelope = CandidateEnvelope(candidates);
      final inside = candidates.first.atTempo(73);
      final outside = exerciseFor(
        TechnicalMaterial('F', ScaleForm.naturalMinor),
      );
      for (final target in [inside, outside]) {
        for (final recovering in [true, false]) {
          final session = SessionState(
            lastFailedExercise: recovering ? target : null,
            tempoProbe: recovering ? null : target,
          );
          final result = pipeline.decide(
            state: state,
            session: session,
            candidates: candidates,
            at: t0,
          );
          expect(
            result.traces.every((t) => envelope.contains(t.exercise)),
            isTrue,
          );
          expect(result, isA<CandidateSelected>());
          expect(
            envelope.contains((result as CandidateSelected).candidate.exercise),
            isTrue,
          );
        }
      }
      final empty = pipeline.decide(
        state: state,
        session: SessionState(lastFailedExercise: outside, tempoProbe: inside),
        candidates: [],
        at: t0,
      );
      expect(empty, isA<SelectionBlocked>());
      expect(empty.traces, isEmpty);
    },
  );
}
