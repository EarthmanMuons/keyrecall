import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'player_archetypes.dart';
import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// One cohort member, with the unit coordinates it was drawn at.
class CohortProfile {
  final SyntheticPlayer player;

  /// Each [PlausibilityCohort.dimensions] entry's position in `[0, 1)`.
  final List<double> unit;

  const CohortProfile(this.player, this.unit);
}

/// Moderately varied players around [PlayerArchetypes.developing], for
/// asking whether a scheduler behavior holds across plausible learners or
/// only at the archetypes' extremes.
///
/// A sensitivity cohort, not a sample: the ranges are documented assumptions,
/// and no population distribution stands behind them. Players transfer nothing
/// between families, as every [SyntheticPlayer] does.
///
/// Drawn once, as the most spread of [_candidates] Latin hypercubes from a
/// fixed seed, so every stratum of every dimension holds one player and no two
/// players sit close together.
abstract final class PlausibilityCohort {
  static const size = 24;
  static const _seed = 20261012;
  static const _candidates = 200;

  /// What each unit coordinate sets, in order.
  static const dimensions = [
    'ability',
    'family asymmetry',
    'noise',
    'durability',
    'learning rate',
    'tempo',
    'tempo compliance',
  ];

  static final List<CohortProfile> profiles = _draw();

  static List<CohortProfile> _draw() {
    final random = PythonCompatibleRandom(_seed);
    List<List<double>>? best;
    var bestSpread = -1.0;
    for (var c = 0; c < _candidates; c++) {
      final design = _latinHypercube(random);
      final spread = _minimumDistance(design);
      if (spread > bestSpread) {
        bestSpread = spread;
        best = design;
      }
    }
    return [
      for (final (index, unit) in best!.indexed)
        CohortProfile(
          playerAt(unit, 'cohort_${'${index + 1}'.padLeft(2, '0')}'),
          unit,
        ),
    ];
  }

  /// The player at [unit], one coordinate per [dimensions] entry.
  ///
  /// Ability shifts all three hand abilities by up to half a logit either way
  /// and moves natural tempo and scale familiarity with it, since faster and
  /// more familiar go together in every archetype. Family asymmetry splits up
  /// to 0.6 logits between the families, against 2.0 for the asymmetric
  /// archetypes. Noise runs from the advanced archetype's 0.07 to 0.14.
  /// Durability is a familiarity half-life of 60 to 720 days, with execution
  /// kept twice as long, where the developing archetype forgets nothing.
  /// Learning rate runs from half to double the default. Tempo varies natural
  /// pace 10% either way beyond what ability sets, and compliance runs from
  /// 0.55 to 0.85.
  static SyntheticPlayer playerAt(List<double> unit, String id) {
    final [ability, asymmetry, noise, durability, learning, tempo, compliance] =
        unit;
    final base = PlayerArchetypes.developing;
    final shift = ability - 0.5;
    final split = (asymmetry - 0.5) * 0.6;
    final familiarityHalfLife = 60 * math.pow(12, durability).toDouble();
    final pace = math.exp(0.25 * shift + 0.2 * (tempo - 0.5));
    return base.copyWith(
      id: id,
      rightHandAbility: base.rightHandAbility + shift,
      leftHandAbility: base.leftHandAbility + shift,
      handsTogetherAbility: base.handsTogetherAbility + shift,
      familyAbility: {
        TechnicalMaterial.scaleFamilyId: split,
        TechnicalMaterial.arpeggioFamilyId: -split,
      },
      familiarity: base.familiarity + 0.2 * shift,
      noise: 0.07 + 0.07 * noise,
      familiarityHalfLifeDays: familiarityHalfLife,
      retentionHalfLifeDays: 2 * familiarityHalfLife,
      learningRate: 0.005 * math.pow(4, learning).toDouble(),
      naturalTempoRightBpm: base.naturalTempoRightBpm * pace,
      naturalTempoLeftBpm: base.naturalTempoLeftBpm * pace,
      tempoCompliance: 0.55 + 0.3 * compliance,
    );
  }

  static List<List<double>> _latinHypercube(PythonCompatibleRandom random) {
    final columns = [
      for (var d = 0; d < dimensions.length; d++)
        [
          for (final stratum in _shuffled(random))
            (stratum + random.nextDouble()) / size,
        ],
    ];
    return [
      for (var i = 0; i < size; i++) [for (final column in columns) column[i]],
    ];
  }

  static List<int> _shuffled(PythonCompatibleRandom random) {
    final strata = [for (var i = 0; i < size; i++) i];
    for (var i = size - 1; i > 0; i--) {
      final j = random.nextIntBelow(i + 1);
      final swapped = strata[i];
      strata[i] = strata[j];
      strata[j] = swapped;
    }
    return strata;
  }

  static double _minimumDistance(List<List<double>> design) {
    var minimum = double.infinity;
    for (var i = 0; i < design.length; i++) {
      for (var j = i + 1; j < design.length; j++) {
        var squared = 0.0;
        for (var d = 0; d < dimensions.length; d++) {
          final delta = design[i][d] - design[j][d];
          squared += delta * delta;
        }
        minimum = math.min(minimum, squared);
      }
    }
    return math.sqrt(minimum);
  }
}
