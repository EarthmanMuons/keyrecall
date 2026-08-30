import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Choosing between realizations at a span nobody has reached.
///
/// `unmeasured` says nothing has been demonstrated *here*, which is true of
/// every tempo at that span at once. So the realization term, which exists to
/// stop generation order deciding tempo, had nothing to say in exactly the
/// state a learner enters whenever they widen a scale: a sweep found an
/// advanced player choosing sixty over a hundred and twenty on two octaves of
/// B flat major, with identical rank keys, while playing at ninety-five.
void main() {
  const gentle = 60.0;
  final material = TechnicalMaterial('Bb', ScaleForm.major);

  /// A learner who owns one octave of B flat major in the right hand at
  /// [tempoBpm], and has never played two.
  LearnerState owningOneOctave({double tempoBpm = 120}) {
    final state = stateAt(PlacementTier.advanced);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = t0
      ..factualLastRetrievalAt = t0;
    state.materialExecutionFor(
        (material.materialId, HandConfiguration.right),
        t0,
        learnerParams,
      )
      ..demonstrate(octaves: 1, tempoBpm: tempoBpm)
      ..readyForHandsTogether(octaves: 1, tempoBpm: tempoBpm)
      ..paced(tempoBpm)
      ..lastEvidenceAt = t0;
    return state;
  }

  Exercise wider(double tempoBpm) =>
      exerciseFor(material, octaves: 2, tempoBpm: tempoBpm);

  test('the target is the tempo the narrower span was managed at', () {
    final state = owningOneOctave();

    expect(
      unmeasuredEntryTempo(state, wider(60), gentleTempoBpm: gentle),
      120,
      reason: 'the fingering is one they play; the octave is the new ask',
    );
  });

  test('which is the span step, so both agree about the same realization', () {
    // Carrying the narrower tempo across is already an adjacent step, and it
    // outranks every unmeasured sibling on the realization term alone.
    final state = owningOneOctave();

    expect(executionAdvanceFor(state, wider(120)), ExecutionAdvance.span);
    expect(realizationRankFor(state, wider(120)), RealizationRank.advancing);
  });

  test('every other tempo there is unmeasured', () {
    final state = owningOneOctave();

    for (final tempoBpm in [60.0, 100.0, 116.0]) {
      expect(
        realizationRankFor(state, wider(tempoBpm)),
        RealizationRank.unmeasured,
      );
    }
  });

  test('so the fit is what separates them', () {
    final state = owningOneOctave();
    double fitOf(double tempoBpm) =>
        realizationFitFor(state, wider(tempoBpm), gentleTempoBpm: gentle);

    expect(fitOf(116), greaterThan(fitOf(100)));
    expect(fitOf(100), greaterThan(fitOf(60)));
  });

  test('the gentlest realization no longer wins by being listed first', () {
    // The census that found this, reconstructed: the same rank key on every
    // tempo, and sixty first in the list.
    final state = owningOneOctave();
    final key = (Exercise exercise) => RankKey(
      tier: EligibilityTier.fullyEligible,
      retention: 0.002,
      information: 1.604,
      diversity: 0,
      goals: 0,
      realization: realizationRankFor(state, exercise),
      realizationFit: realizationFitFor(
        state,
        exercise,
        gentleTempoBpm: gentle,
      ),
    );

    final ordered = [60.0, 80.0, 100.0, 116.0, 120.0]
      ..sort((a, b) => key(wider(b)).compareTo(key(wider(a))));

    expect(
      ordered.first,
      120,
      reason: 'the span step, which is advancing rather than unmeasured',
    );
    expect(
      ordered[1],
      116,
      reason: 'and the nearest unmeasured realization to it comes next',
    );
    expect(ordered.last, 60);
  });

  test('a hand with no evidence here falls back to its pace', () {
    // Nothing at the narrower span for this material, so the question becomes
    // the more distant one an unseen scale asks.
    final state = stateAt(PlacementTier.advanced);
    for (final tonic in ['C', 'G', 'F']) {
      state.materialExecutionFor(
          ('${tonic}_MAJOR', HandConfiguration.right),
          t0,
          learnerParams,
        )
        ..paced(104)
        ..lastEvidenceAt = t0;
    }

    expect(unmeasuredEntryTempo(state, wider(60), gentleTempoBpm: gentle), 104);
  });

  test('and a learner nobody has seen play still starts gently', () {
    expect(
      unmeasuredEntryTempo(
        stateAt(PlacementTier.advanced),
        wider(60),
        gentleTempoBpm: gentle,
      ),
      gentle,
    );
  });
}
