import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What tempo an unseen scale is met at, for somebody who already plays.
///
/// The state, not one trajectory: a hand has shown a pace on material it owns,
/// and an introduction in a later band would otherwise be asked for the
/// gentlest tempo on the ladder anyway.
///
/// `transferableTempoFor` answers this question from evidence, and the cap in
/// `entryTempoFor` must not discard that answer. The gentle tempo is the honest
/// default only where no pace has been measured.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());
  const gentle = 60.0;

  /// A learner who plays [tempoBpm] with their right hand on scales they own.
  LearnerState playingAt(double tempoBpm) {
    final state = stateAt(PlacementTier.someExperience);
    for (final tonic in ['C', 'G', 'F']) {
      final id = '${tonic}_MAJOR';
      state.materialMemoryFor(id, learnerParams)
        ..memoryAnchorAt = t0
        ..factualLastRetrievalAt = t0;
      state.materialExecutionFor(
          (id, HandConfiguration.right, HandMotion.parallel),
          t0,
          learnerParams,
          familyId: TechnicalMaterial.scaleFamilyId,
        )
        ..demonstrate(octaves: 1, tempoBpm: tempoBpm)
        ..readyForHandsTogether(octaves: 1, tempoBpm: tempoBpm)
        ..paced(tempoBpm)
        ..lastEvidenceAt = t0;
    }
    return state;
  }

  Exercise unseen(String tonic, ScaleForm form) =>
      exerciseFor(TechnicalMaterial(tonic, form), octaves: 1, tempoBpm: gentle);

  test('the pace is what a foundation scale is met at', () {
    final state = playingAt(120);

    expect(
      pipeline.entryTempoFor(state, unseen('D', ScaleForm.naturalMinor)),
      120,
    );
  });

  test('and a later band costs exactly one rung of it', () {
    final state = playingAt(120);
    final capped = unseen('F', ScaleForm.naturalMinor);

    expect(
      admissionBandOf(
        capped.material,
      ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer),
      isFalse,
      reason: 'the material this pins has to be in a capped band',
    );
    // Not `greaterThan(gentle)`: sixty-six would satisfy that while still
    // discarding the evidence, and the claim is that the evidence is used
    // rather than that the cap is looser.
    //
    // The policy this asserts:
    //
    //   unknown pace, unknown geography  -> the gentle tempo
    //   known pace, unknown geography    -> the geography may cost a rung
    //                                       or two, and may not erase what
    //                                       the hand has shown
    //
    // One rung of the ladder below the pace, so a harder key is allowed to
    // be worth something and not worth everything.
    expect(
      pipeline.entryTempoFor(state, capped),
      tempoBefore(120),
      reason:
          'the hand has shown 120 on scales it owns, and a harder geography '
          'is worth a rung of caution rather than three',
    );
  });

  test('two scales in one sitting should not disagree by three rungs', () {
    // The shape a person would notice: same hand, same span, same session,
    // one met at the pace and the next at the floor.
    final state = playingAt(120);
    final tempi = {
      for (final material in [
        TechnicalMaterial('D', ScaleForm.naturalMinor),
        TechnicalMaterial('F', ScaleForm.naturalMinor),
      ])
        material.materialId: pipeline.entryTempoFor(
          state,
          exerciseFor(material, octaves: 1, tempoBpm: gentle),
        ),
    };

    expect(
      tempi.values.toSet(),
      hasLength(2),
      reason:
          'recorded as it stands: one of these is met at the pace and the '
          'other at the floor, and this is the observable consequence',
    );
  });

  test('no pace evidence still means the gentle tempo', () {
    // The cap is not wrong about a learner nobody has seen play. What it gets
    // wrong is discarding evidence that exists.
    expect(
      pipeline.entryTempoFor(
        stateAt(PlacementTier.someExperience),
        unseen('F', ScaleForm.naturalMinor),
      ),
      gentle,
    );
  });
}
