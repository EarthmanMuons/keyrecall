import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

void main() {
  final material = materials.first;
  final entry = exerciseFor(
    material,
    guidance: GuidanceContext.continuouslyCued,
    direction: ScaleDirection.up,
    tempoBpm: generatedTempi.first,
  );
  final floor = AcquisitionFloor([
    AcquisitionFloorEntry(requirementId: material.materialId, exercise: entry),
  ]);

  LearnerState introducedState() {
    final state = stateAt(PlacementTier.beginner);
    state.materialMemoryFor(material.materialId, learnerParams);
    state
            .materialExecutionFor(
              (
                material.materialId,
                HandConfiguration.right,
                HandMotion.parallel,
              ),
              t0,
              learnerParams,
            )
            .lastEvidenceAt =
        t0;
    return state;
  }

  test('the scale family supplies supported single-hand entries', () {
    final candidates = generateCandidates(instrument, [material]);
    final entries = scaleAcquisitionFloor(candidates).entries;

    expect(entries, hasLength(2));
    expect(
      entries.map((entry) => entry.exercise.conditions.hands),
      containsAll([HandConfiguration.right, HandConfiguration.left]),
    );
    for (final entry in entries) {
      expect(entry.requirementId, material.materialId);
      expect(entry.exercise.conditions.octaves, 1);
      expect(entry.exercise.conditions.direction, ScaleDirection.up);
      expect(entry.exercise.conditions.tempoBpm, generatedTempi.first);
      expect(entry.exercise.guidance, GuidanceContext.continuouslyCued);
    }
  });

  test('family entries retain the requirement they support', () {
    final candidates = generateCandidates(instrument, [material]);
    final entries = scaleAcquisitionFloorFor([
      AcquisitionFloorRequest(
        requirementId: 'C_MAJOR_HT_TWO_OCTAVES',
        candidates: candidates,
      ),
    ]).entries;

    expect(entries.map((entry) => entry.requirementId).toSet(), {
      'C_MAJOR_HT_TWO_OCTAVES',
    });
  });

  test('ordinary admission wins without consulting the floor', () {
    final result = pipeline.decide(
      state: stateAt(PlacementTier.beginner),
      session: SessionState(),
      candidates: [entry],
      at: t0,
      acquisitionFloor: floor,
    );

    expect(result, isA<CandidateSelected>());
    expect(
      (result as CandidateSelected).candidate.challengeBypass,
      ChallengeBypass.newMaterial,
    );
  });

  test('a valid floor uses ordinary ranking after admission exhausts', () {
    final result = pipeline.decide(
      state: introducedState(),
      session: SessionState(),
      candidates: [entry],
      at: t0,
      acquisitionFloor: floor,
    );

    expect(result, isA<CandidateSelected>());
    final selected = (result as CandidateSelected).candidate;
    expect(selected.exercise, entry);
    expect(selected.challengeBypass, ChallengeBypass.acquisitionFloor);
  });

  test('an unresolved requirement with no entry reports why it blocked', () {
    final result = pipeline.decide(
      state: introducedState(),
      session: SessionState(),
      candidates: [entry],
      at: t0,
      acquisitionFloor: AcquisitionFloor(const []),
    );

    expect(
      (result as SelectionBlocked).reason,
      BlockedReason.noSafeEntryRealization,
    );
  });

  test('an entry outside the active candidates is rejected', () {
    final result = pipeline.decide(
      state: introducedState(),
      session: SessionState(),
      candidates: [entry],
      at: t0,
      acquisitionFloor: AcquisitionFloor([
        AcquisitionFloorEntry(
          requirementId: material.materialId,
          exercise: entry.atTempo(80),
        ),
      ]),
    );

    expect(
      (result as SelectionBlocked).reason,
      BlockedReason.safeEntryRejected,
    );
  });

  test('the floor cannot bypass session safety', () {
    final session = SessionState()..attemptsThisSession = 1;
    final result = SchedulerPipeline(learner: learner, config: boundedTo(1))
        .decide(
          state: introducedState(),
          session: session,
          candidates: [entry],
          at: t0,
          acquisitionFloor: floor,
        );

    expect(
      (result as SelectionBlocked).reason,
      BlockedReason.safeEntryRejected,
    );
  });
}
