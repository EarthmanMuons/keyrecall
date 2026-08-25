import 'package:keyrecall_domain/keyrecall_domain.dart';

/// Which finger plays which degree of a scale.
///
/// Display data, and only that. It never reaches measurement or evidence: the
/// domain has no fingering model yet, and inventing one here would put a
/// pedagogical claim in the presentation layer. When the domain gains a
/// canonical fingering, this table is deleted rather than promoted.
///
/// Eight entries per hand, ascending: one per degree, then the finger the
/// upper tonic takes. Descending uses the same fingers in reverse, which is
/// true of every scale in the catalog.
///
/// Only the scales whose standard fingering is not in doubt are here. A
/// missing one shows nothing rather than a guess, since a learner who does not
/// know the fingering is exactly who would be misled by a wrong one.
const Map<String, Map<Hand, List<int>>> _fingerings = {
  'C_MAJOR': {
    Hand.right: [1, 2, 3, 1, 2, 3, 4, 5],
    Hand.left: [5, 4, 3, 2, 1, 3, 2, 1],
  },
  'G_MAJOR': {
    Hand.right: [1, 2, 3, 1, 2, 3, 4, 5],
    Hand.left: [5, 4, 3, 2, 1, 3, 2, 1],
  },
  'F_MAJOR': {
    // The thumb takes F and C, so the fourth finger lands on the B flat.
    Hand.right: [1, 2, 3, 4, 1, 2, 3, 4],
    Hand.left: [5, 4, 3, 2, 1, 3, 2, 1],
  },
  'A_NATURAL_MINOR': {
    Hand.right: [1, 2, 3, 1, 2, 3, 4, 5],
    Hand.left: [5, 4, 3, 2, 1, 3, 2, 1],
  },
  'D_HARMONIC_MINOR': {
    Hand.right: [1, 2, 3, 1, 2, 3, 4, 5],
    Hand.left: [5, 4, 3, 2, 1, 3, 2, 1],
  },
  'E_MELODIC_MINOR': {
    Hand.right: [1, 2, 3, 1, 2, 3, 4, 5],
    Hand.left: [5, 4, 3, 2, 1, 3, 2, 1],
  },
  // F#_HARMONIC_MINOR is deliberately absent. Its standard fingering starts
  // away from the thumb and is not something to guess at.
};

/// The finger for each moment of [exercise], for [hand], or null where the
/// scale has no fingering to show.
List<int>? fingeringFor(Exercise exercise, Hand hand) {
  final pattern = _fingerings[exercise.material.materialId]?[hand];
  if (pattern == null) return null;

  final degrees = pattern.length - 1;
  final octaves = exercise.conditions.octaves;
  final top = degrees * octaves;
  final ascending = [
    for (var degree = 0; degree <= top; degree++)
      degree == top ? pattern[degrees] : pattern[degree % degrees],
  ];

  return switch (exercise.conditions.direction) {
    ScaleDirection.up => ascending,
    ScaleDirection.upDown => [...ascending, ...ascending.reversed.skip(1)],
  };
}

/// The finger each key takes, for a diagram that marks keys rather than notes.
Map<int, int> fingeringByKeyFor(Exercise exercise, Hand hand) {
  final fingers = fingeringFor(exercise, hand);
  if (fingers == null) return const {};

  final realization = realize(exercise);
  return {
    for (final (position, moment) in realization.moments.indexed)
      if (moment.noteFor(hand) case final note?)
        note.midiNote: fingers[position],
  };
}
