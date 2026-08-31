import 'package:meta/meta.dart';

import 'exercise.dart';
import 'pitch_spelling.dart';
import 'realization.dart';
import 'technical_material.dart';

/// Which fingers play a scale, as a pattern that generates any octave span.
///
/// A flat one-octave string cannot say this on its own: the finger that starts
/// a traversal, the one that takes an internal octave boundary, and the one
/// that ends it are three independent boundary conditions. C major right hand
/// runs `1 2 3 1 2 3 4 5` over one octave, but its internal upper tonic takes
/// the thumb so the scale can continue, and only the final one takes the
/// fifth finger.
///
/// See `docs/domain-model/fingering-taxonomy.md` for the research this encodes
/// and for the sources behind each pattern.
@immutable
class ScaleFingering {
  /// How the traversal begins, at the initial tonic.
  final List<int> entry;

  /// The repeating continuation from one tonic to the next internal tonic.
  final List<int> cycle;

  /// What the final tonic takes instead, when an endpoint differs from an
  /// internal octave boundary.
  final int? terminalFinger;

  const ScaleFingering({
    required this.entry,
    required this.cycle,
    this.terminalFinger,
  });

  /// The fingers for an ascending traversal of [octaves] octaves.
  List<int> ascending(int octaves) {
    final fingers = [
      ...entry,
      for (var octave = 0; octave < octaves; octave++) ...cycle,
    ];
    final terminal = terminalFinger;
    if (terminal != null) fingers[fingers.length - 1] = terminal;
    return fingers;
  }
}

// The conventional families, named for what they are rather than for one key.
// Right hand, thumb on the tonic, fourth finger on the seventh degree; the
// internal tonic continues on the thumb and only the last one takes five.
const _rhThumbTonic = ScaleFingering(
  entry: [1],
  cycle: [2, 3, 1, 2, 3, 4, 1],
  terminalFinger: 5,
);

/// Right hand with the thumb on the fourth degree as well, which is F major's
/// exception and is reused by the F minors.
const _rhThumbOnFour = ScaleFingering(
  entry: [1],
  cycle: [2, 3, 4, 1, 2, 3, 1],
  terminalFinger: 4,
);

const _rh23123412 = ScaleFingering(entry: [2], cycle: [3, 1, 2, 3, 4, 1, 2]);
const _rh23412312 = ScaleFingering(entry: [2], cycle: [3, 4, 1, 2, 3, 1, 2]);
const _rh21231234 = ScaleFingering(entry: [2], cycle: [1, 2, 3, 1, 2, 3, 4]);
const _rh31234123 = ScaleFingering(entry: [3], cycle: [1, 2, 3, 4, 1, 2, 3]);
const _rh21234123 = ScaleFingering(entry: [2], cycle: [1, 2, 3, 4, 1, 2, 3]);
const _rh34123123 = ScaleFingering(entry: [3], cycle: [4, 1, 2, 3, 1, 2, 3]);

const _lh54321321 = ScaleFingering(entry: [5], cycle: [4, 3, 2, 1, 3, 2, 1]);
const _lh43214321 = ScaleFingering(entry: [4], cycle: [3, 2, 1, 4, 3, 2, 1]);
const _lh32143213 = ScaleFingering(entry: [3], cycle: [2, 1, 4, 3, 2, 1, 3]);
const _lh43213214 = ScaleFingering(entry: [4], cycle: [3, 2, 1, 3, 2, 1, 4]);
const _lh21432132 = ScaleFingering(entry: [2], cycle: [1, 4, 3, 2, 1, 3, 2]);
const _lh21321432 = ScaleFingering(entry: [2], cycle: [1, 3, 2, 1, 4, 3, 2]);

/// The canonical fingering for every scale V1 supports, by material id.
///
/// One fingering per scale and hand, deliberately: documented alternatives
/// exist and are research provenance rather than runtime behavior. Spellings
/// follow the catalog's, so D flat major and C sharp minor are separate
/// entries rather than one enharmonic pair.
const Map<String, Map<Hand, ScaleFingering>> _canonical = {
  // Major.
  'C_MAJOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'G_MAJOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'D_MAJOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'A_MAJOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'E_MAJOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'F_MAJOR': {Hand.right: _rhThumbOnFour, Hand.left: _lh54321321},
  'B_MAJOR': {Hand.right: _rhThumbTonic, Hand.left: _lh43214321},
  'Db_MAJOR': {Hand.right: _rh23123412, Hand.left: _lh32143213},
  'F#_MAJOR': {Hand.right: _rh23412312, Hand.left: _lh43213214},
  'Bb_MAJOR': {Hand.right: _rh21231234, Hand.left: _lh32143213},
  'Eb_MAJOR': {Hand.right: _rh31234123, Hand.left: _lh32143213},
  'Ab_MAJOR': {Hand.right: _rh34123123, Hand.left: _lh32143213},

  // Natural minor.
  'C_NATURAL_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'D_NATURAL_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'E_NATURAL_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'G_NATURAL_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'A_NATURAL_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'F_NATURAL_MINOR': {Hand.right: _rhThumbOnFour, Hand.left: _lh54321321},
  'B_NATURAL_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh43214321},
  'C#_NATURAL_MINOR': {Hand.right: _rh34123123, Hand.left: _lh32143213},
  'G#_NATURAL_MINOR': {Hand.right: _rh34123123, Hand.left: _lh32143213},
  'Eb_NATURAL_MINOR': {Hand.right: _rh31234123, Hand.left: _lh21432132},
  'F#_NATURAL_MINOR': {Hand.right: _rh34123123, Hand.left: _lh43213214},
  'Bb_NATURAL_MINOR': {Hand.right: _rh21231234, Hand.left: _lh21321432},

  // Harmonic minor.
  'C_HARMONIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'D_HARMONIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'E_HARMONIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'G_HARMONIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'A_HARMONIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'F_HARMONIC_MINOR': {Hand.right: _rhThumbOnFour, Hand.left: _lh54321321},
  'B_HARMONIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh43214321},
  'C#_HARMONIC_MINOR': {Hand.right: _rh34123123, Hand.left: _lh32143213},
  'G#_HARMONIC_MINOR': {Hand.right: _rh34123123, Hand.left: _lh32143213},
  'F#_HARMONIC_MINOR': {Hand.right: _rh34123123, Hand.left: _lh43213214},
  'Eb_HARMONIC_MINOR': {Hand.right: _rh21234123, Hand.left: _lh21432132},
  'Bb_HARMONIC_MINOR': {Hand.right: _rh21231234, Hand.left: _lh21321432},

  // Fixed-form melodic minor: the harmonic-minor fingering, except the two
  // right hands the raised sixth changes.
  'C_MELODIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'D_MELODIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'E_MELODIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'G_MELODIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'A_MELODIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh54321321},
  'F_MELODIC_MINOR': {Hand.right: _rhThumbOnFour, Hand.left: _lh54321321},
  'B_MELODIC_MINOR': {Hand.right: _rhThumbTonic, Hand.left: _lh43214321},
  'C#_MELODIC_MINOR': {Hand.right: _rh23123412, Hand.left: _lh32143213},
  'F#_MELODIC_MINOR': {Hand.right: _rh23123412, Hand.left: _lh43213214},
  'G#_MELODIC_MINOR': {Hand.right: _rh34123123, Hand.left: _lh32143213},
  'Eb_MELODIC_MINOR': {Hand.right: _rh21234123, Hand.left: _lh21432132},
  'Bb_MELODIC_MINOR': {Hand.right: _rh21231234, Hand.left: _lh21321432},
};

/// The canonical fingering for [material] in [hand], or null when the catalog
/// does not cover that scale.
ScaleFingering? canonicalFingering(TechnicalMaterial material, Hand hand) =>
    _canonical[material.materialId]?[hand];

/// The finger for each moment of [exercise], for [hand], or null when the
/// scale has no canonical fingering or [hand] does not play it.
///
/// Read off the same degree path the notes are, so the fingers follow wherever
/// the hand goes rather than re-deriving the traversal here. A descent reverses
/// the ascending stream, which holds for every scale in the catalog and is a
/// property of this dataset rather than a rule about fingering in general.
///
/// A hand whose line runs below its tonic is indexed from the far end: the
/// thumb it starts on is the finger that would have ended an ascent. That is
/// the same reversal, taken per degree instead of per sequence, and it is what
/// makes the return leg of a contrary traversal fall out unaided.
List<int>? fingeringFor(Exercise exercise, Hand hand) {
  final pattern = canonicalFingering(exercise.material, hand);
  if (pattern == null) return null;

  final intervals = scaleFormIntervals[exercise.material.form]!;
  final path = handPathsFor(
    exercise.conditions,
    degreesPerOctave: intervals.length,
  )[hand];
  if (path == null) return null;

  final ascending = pattern.ascending(exercise.conditions.octaves);
  final topDegree = ascending.length - 1;
  final descends = path.any((degree) => degree < 0);
  return [
    for (final degree in path)
      ascending[descends ? topDegree + degree : degree],
  ];
}
