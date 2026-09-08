import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

void main() {
  const params = v1LearnerParams;
  final at = DateTime.utc(2026);
  final scale = TechnicalMaterial('C', ScaleForm.major);
  final arpeggio = ArpeggioMaterial('C', ArpeggioQuality.major);

  LearnerState practised() {
    final state = const LearnerModel().placementState(
      PlacementTier.someExperience,
      at: at,
    );
    state.materialExecutionFor(
        (scale.materialId, HandConfiguration.right, HandMotion.parallel),
        at,
        params,
        familyId: scale.familyId,
      )
      ..paced(120)
      ..lastEvidenceAt = at;
    state.materialExecutionFor(
        (arpeggio.materialId, HandConfiguration.right, HandMotion.parallel),
        at,
        params,
        familyId: arpeggio.familyId,
      )
      ..paced(60)
      ..lastEvidenceAt = at;
    return state;
  }

  double paceFor(LearnerState state, TechnicalMaterial material) =>
      transferableTempoFor(
        state,
        HandConfiguration.right,
        1,
        family: material.familyId,
      );

  test('a pace is evidence about the family it was played in', () {
    final state = practised();

    expect(paceFor(state, scale), 120);
    expect(
      paceFor(state, arpeggio),
      60,
      reason: 'the hand plays scales at 120 and that is not a claim about this',
    );
  });

  test('and the family survives a checkpoint', () {
    final state = practised();
    final checkpoint = LearnerStateCheckpoint.capture(
      profileId: 'family-provenance',
      state: state,
      learnerModelVersion: params.modelVersion,
      throughJournalSequence: 0,
      throughAttemptId: 'attempt-0',
      coversThrough: at,
    );

    final reread = LearnerStateCheckpoint.fromJson(
      jsonDecode(jsonEncode(checkpoint.toJson())) as Map<String, Object?>,
      params: params,
    );

    expect(paceFor(reread.state, scale), paceFor(state, scale));
    expect(paceFor(reread.state, arpeggio), paceFor(state, arpeggio));
    expect(
      reread.state.materialExecution.values.map((r) => r.familyId).toSet(),
      {scale.familyId, arpeggio.familyId},
      reason: 'the field is written and read, not defaulted on either side',
    );
  });

  test('a checkpoint without recorded families is refused, not guessed', () {
    final state = practised();
    final json =
        jsonDecode(
              jsonEncode(
                LearnerStateCheckpoint.capture(
                  profileId: 'family-provenance',
                  state: state,
                  learnerModelVersion: params.modelVersion,
                  throughJournalSequence: 0,
                  throughAttemptId: 'attempt-0',
                  coversThrough: at,
                ).toJson(),
              ),
            )
            as Map<String, Object?>;
    final residuals =
        (json['state'] as Map<String, Object?>)['material_execution']
            as Map<String, Object?>;
    for (final residual in residuals.values) {
      (residual as Map<String, Object?>).remove('family_id');
    }

    expect(
      () => LearnerStateCheckpoint.fromJson(json, params: params),
      throwsA(isA<JournalFormatException>()),
      reason:
          'a scale id does not name its family, so the only alternative to '
          'rebuilding from the attempts is inventing provenance',
    );
  });
}
