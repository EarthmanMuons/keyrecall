import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Choosing between realizations of one material.
///
/// The material-level terms cannot tell them apart: retention and diversity
/// are facts about a scale, and information reads competencies. So every
/// tempo, span and hand configuration of one material carried an identical
/// key, and the winner was whichever generation listed first.
void main() {
  final material = materials.first;

  LearnerState playing({required double tempoBpm, int octaves = 1}) {
    final state = stateAt(PlacementTier.someExperience);
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = t0
      ..factualLastRetrievalAt = t0;
    state.materialExecutionFor(
        (material.materialId, HandConfiguration.right, HandMotion.parallel),
        t0,
        learnerParams,
      )
      ..demonstrate(octaves: octaves, tempoBpm: tempoBpm)
      ..readyForHandsTogether(octaves: octaves, tempoBpm: tempoBpm)
      ..paced(tempoBpm)
      ..lastEvidenceAt = t0;
    return state;
  }

  RealizationRank rankOf(
    LearnerState state,
    double tempoBpm, {
    int octaves = 1,
  }) => realizationRankFor(
    state,
    exerciseFor(material, octaves: octaves, tempoBpm: tempoBpm),
  );

  test('work already surpassed ranks last', () {
    final state = playing(tempoBpm: 126);

    expect(rankOf(state, 60), RealizationRank.surpassed);
    expect(rankOf(state, 126), RealizationRank.holding);
    expect(rankOf(state, tempoAfter(126)), RealizationRank.advancing);
  });

  test('the order is advancing, holding, unmeasured, surpassed', () {
    final byRank = RealizationRank.values.toList()
      ..sort((a, b) => b.index.compareTo(a.index));

    expect(byRank, [
      RealizationRank.advancing,
      RealizationRank.holding,
      RealizationRank.unmeasured,
      RealizationRank.surpassed,
    ]);
  });

  test('a first encounter is unmeasured, not surpassed', () {
    // Nothing to be past. Meeting material is ordinary work and should not
    // rank below the slowest thing somebody has already outgrown elsewhere.
    expect(
      rankOf(stateAt(PlacementTier.someExperience), 60),
      RealizationRank.unmeasured,
    );
  });

  test('it is read at the span being played', () {
    // The frontier is a lattice: managing one octave at 126 says nothing
    // about two, so two octaves at 60 is not work anybody has surpassed.
    final state = playing(tempoBpm: 126);

    expect(rankOf(state, 60, octaves: 2), RealizationRank.unmeasured);
  });

  test('the key breaks a tie the material terms leave', () {
    final key = RankKey(
      tier: EligibilityTier.fullyEligible,
      retention: 0.004,
      information: 0.585,
      diversity: 0,
      goals: 0,
      realization: RealizationRank.advancing,
    );
    final surpassed = RankKey(
      tier: key.tier,
      retention: key.retention,
      information: key.information,
      diversity: key.diversity,
      goals: key.goals,
      realization: RealizationRank.surpassed,
    );

    expect(key.compareTo(surpassed), greaterThan(0));
  });

  test('and never overrides which material to practise', () {
    // A scale that badly needs testing wins even at a tempo already
    // surpassed, because what to practise is settled before how.
    final due = RankKey(
      tier: EligibilityTier.fullyEligible,
      retention: 0.9,
      information: 0.1,
      diversity: 0,
      goals: 0,
      realization: RealizationRank.surpassed,
    );
    final fresh = RankKey(
      tier: EligibilityTier.fullyEligible,
      retention: 0.1,
      information: 0.1,
      diversity: 0,
      goals: 0,
      realization: RealizationRank.advancing,
    );

    expect(due.compareTo(fresh), greaterThan(0));
  });
}
