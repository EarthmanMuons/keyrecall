import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// What a probe about guidance is allowed to change.
///
/// One axis. A guidance probe that also dropped a learner from a hundred and
/// twenty-six to sixty changed two, and the slower one then read as
/// underchallenged and drew a tempo probe along behind it. Nothing in ranking
/// reads tempo, so which tempo a probe landed on was decided by the order of a
/// constant.
void main() {
  final material = materials.first;

  /// A learner established at the previewed rung, with [tempoBpm] managed on
  /// this material at one octave in the right hand.
  LearnerState established({double? tempoBpm}) {
    final state = stateAt(PlacementTier.someExperience);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = t0
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0
      ..establishedIndependence =
          GuidanceContext.notesPreviewedOnly.independence
      ..establishedIndependenceAt = t0;
    if (tempoBpm != null) {
      state.materialExecutionFor(
          (material.materialId, HandConfiguration.right),
          t0,
          learnerParams,
        )
        ..demonstrate(octaves: 1, tempoBpm: tempoBpm)
        ..readyForHandsTogether(octaves: 1, tempoBpm: tempoBpm)
        ..paced(tempoBpm)
        ..lastEvidenceAt = t0;
    }
    return state;
  }

  Exercise at(double tempoBpm) =>
      exerciseFor(material, octaves: 1, tempoBpm: tempoBpm);

  final later = t0.plusDays(config.probe.minDaysSinceSupportEstablished + 1.0);

  test('a guidance probe is asked at the tempo the learner is at', () {
    final state = established(tempoBpm: 126);

    expect(pipeline.isGuidanceProbe(state, at(126), later), isTrue);
    expect(
      pipeline.isGuidanceProbe(state, at(60), later),
      isFalse,
      reason:
          'stepping back on support while also stepping back three rungs of '
          'tempo asks two questions and answers neither',
    );
  });

  test('it holds the frontier for this span, not the widest one', () {
    final state = established(tempoBpm: 126);
    state.materialExecution[(material.materialId, HandConfiguration.right)]!
        .demonstrate(octaves: 2, tempoBpm: 96);

    expect(
      pipeline.isGuidanceProbe(
        state,
        exerciseFor(material, octaves: 2, tempoBpm: 96),
        later,
      ),
      isTrue,
    );
    expect(
      pipeline.isGuidanceProbe(
        state,
        exerciseFor(material, octaves: 2, tempoBpm: 126),
        later,
      ),
      isFalse,
      reason: 'two octaves has been managed at ninety-six, not at that',
    );
  });

  test('with no frontier at that span it holds the entry tempo', () {
    final state = established();

    expect(
      pipeline.heldTempoFor(state, at(60)),
      pipeline.entryTempoFor(state, at(60)),
      reason:
          'a material can have an established rung without having been played '
          'this wide, and the pace is the best answer there',
    );
  });

  test('one hand does not set the other hand tempo', () {
    final state = established(tempoBpm: 126);

    expect(
      pipeline.isGuidanceProbe(
        state,
        exerciseFor(material, hands: HandConfiguration.left, tempoBpm: 126),
        later,
      ),
      isFalse,
      reason: 'the left hand has managed nothing on this material',
    );
  });
}
