import 'package:meta/meta.dart';

import 'execution_conditions.dart';
import 'hand_path.dart';
import 'technical_material.dart';

/// The authoritative fingering for one material and hand.
///
/// A flat one-octave string cannot say this on its own: the finger that starts
/// a traversal, the one that takes an internal octave boundary, and the one
/// that ends it are independent boundary conditions.
@immutable
class CanonicalFingering {
  /// The material this record realizes.
  final String materialId;

  /// The hand this record applies to.
  final Hand hand;

  /// How the traversal begins, at the initial tonic.
  final List<int> entry;

  /// The repeating continuation from one tonic to the next internal tonic.
  final List<int> cycle;

  /// What the final tonic takes instead, when an endpoint differs from an
  /// internal octave boundary.
  final int? terminalFinger;

  /// Whether descent uses the reversed ascending stream.
  final bool reversesForDescending;

  /// Where this canonical choice came from.
  final FingeringProvenance provenance;

  factory CanonicalFingering({
    required String materialId,
    required Hand hand,
    required List<int> entry,
    required List<int> cycle,
    int? terminalFinger,
    required bool reversesForDescending,
    required FingeringProvenance provenance,
  }) {
    if (materialId.isEmpty) {
      throw ArgumentError.value(materialId, 'materialId', 'must not be empty');
    }
    if (entry.isEmpty || cycle.isEmpty) {
      throw ArgumentError('entry and cycle must not be empty');
    }
    for (final finger in [...entry, ...cycle, ?terminalFinger]) {
      if (finger < 1 || finger > 5) {
        throw ArgumentError.value(finger, 'finger', 'must be between 1 and 5');
      }
    }
    return CanonicalFingering._(
      materialId: materialId,
      hand: hand,
      entry: List.unmodifiable(entry),
      cycle: List.unmodifiable(cycle),
      terminalFinger: terminalFinger,
      reversesForDescending: reversesForDescending,
      provenance: provenance,
    );
  }

  const CanonicalFingering._({
    required this.materialId,
    required this.hand,
    required this.entry,
    required this.cycle,
    this.terminalFinger,
    required this.reversesForDescending,
    required this.provenance,
  });

  /// The fingers for an ascending traversal of [octaves] octaves.
  List<int> ascending(int octaves) {
    if (octaves < 1) {
      throw ArgumentError.value(octaves, 'octaves', 'must be at least 1');
    }
    final fingers = [
      ...entry,
      for (var octave = 0; octave < octaves; octave++) ...cycle,
    ];
    final terminal = terminalFinger;
    if (terminal != null) fingers[fingers.length - 1] = terminal;
    return fingers;
  }

  /// The descending traversal, or null when reversal is not authoritative.
  List<int>? descending(int octaves) => reversesForDescending
      ? ascending(octaves).reversed.toList(growable: false)
      : null;
}

/// Research provenance for one canonical fingering choice.
@immutable
class FingeringProvenance {
  /// The work or dataset supporting the choice.
  final String source;

  /// The dated or named edition consulted.
  final String sourceEdition;

  /// The chapter, section, page, or record inside the source.
  final String sourceLocation;

  /// How the source participates in the canonical choice.
  final CanonicalFingeringStatus status;

  factory FingeringProvenance({
    required String source,
    required String sourceEdition,
    required String sourceLocation,
    required CanonicalFingeringStatus status,
  }) {
    if (source.isEmpty || sourceEdition.isEmpty || sourceLocation.isEmpty) {
      throw ArgumentError('fingering provenance fields must not be empty');
    }
    return FingeringProvenance._(
      source: source,
      sourceEdition: sourceEdition,
      sourceLocation: sourceLocation,
      status: status,
    );
  }

  const FingeringProvenance._({
    required this.source,
    required this.sourceEdition,
    required this.sourceLocation,
    required this.status,
  });
}

/// How firmly the cited source supports a canonical fingering.
enum CanonicalFingeringStatus {
  /// The cited source states the pattern directly.
  established,

  /// KeyRecall selected the pattern after reconciling its research sources.
  canonicalSelected,
}

@immutable
class _FingeringShape {
  final List<int> entry;
  final List<int> cycle;
  final int? terminalFinger;
  final bool reversesForDescending;

  const _FingeringShape._({
    required this.entry,
    required this.cycle,
    this.terminalFinger,
    required this.reversesForDescending,
  });
}

// The conventional families, named for what they are rather than for one key.
// Right hand, thumb on the tonic, fourth finger on the seventh degree; the
// internal tonic continues on the thumb and only the last one takes five.
const _rhThumbTonic = _FingeringShape._(
  entry: [1],
  cycle: [2, 3, 1, 2, 3, 4, 1],
  terminalFinger: 5,
  reversesForDescending: true,
);

/// Right hand with the thumb on the fourth degree as well, which is F major's
/// exception and is reused by the F minors.
const _rhThumbOnFour = _FingeringShape._(
  entry: [1],
  cycle: [2, 3, 4, 1, 2, 3, 1],
  terminalFinger: 4,
  reversesForDescending: true,
);

const _rh23123412 = _FingeringShape._(
  entry: [2],
  cycle: [3, 1, 2, 3, 4, 1, 2],
  reversesForDescending: true,
);
const _rh23412312 = _FingeringShape._(
  entry: [2],
  cycle: [3, 4, 1, 2, 3, 1, 2],
  reversesForDescending: true,
);
const _rh21231234 = _FingeringShape._(
  entry: [2],
  cycle: [1, 2, 3, 1, 2, 3, 4],
  reversesForDescending: true,
);
const _rh31234123 = _FingeringShape._(
  entry: [3],
  cycle: [1, 2, 3, 4, 1, 2, 3],
  reversesForDescending: true,
);
const _rh21234123 = _FingeringShape._(
  entry: [2],
  cycle: [1, 2, 3, 4, 1, 2, 3],
  reversesForDescending: true,
);
const _rh34123123 = _FingeringShape._(
  entry: [3],
  cycle: [4, 1, 2, 3, 1, 2, 3],
  reversesForDescending: true,
);

const _lh54321321 = _FingeringShape._(
  entry: [5],
  cycle: [4, 3, 2, 1, 3, 2, 1],
  reversesForDescending: true,
);
const _lh43214321 = _FingeringShape._(
  entry: [4],
  cycle: [3, 2, 1, 4, 3, 2, 1],
  reversesForDescending: true,
);
const _lh32143213 = _FingeringShape._(
  entry: [3],
  cycle: [2, 1, 4, 3, 2, 1, 3],
  reversesForDescending: true,
);
const _lh43213214 = _FingeringShape._(
  entry: [4],
  cycle: [3, 2, 1, 3, 2, 1, 4],
  reversesForDescending: true,
);
const _lh21432132 = _FingeringShape._(
  entry: [2],
  cycle: [1, 4, 3, 2, 1, 3, 2],
  reversesForDescending: true,
);
const _lh21321432 = _FingeringShape._(
  entry: [2],
  cycle: [1, 3, 2, 1, 4, 3, 2],
  reversesForDescending: true,
);

/// The canonical fingering for every scale V1 supports, by material id.
///
/// One fingering per scale and hand, deliberately: documented alternatives
/// exist and are research provenance rather than runtime behavior. Spellings
/// follow the catalog's, so D flat major and C sharp minor are separate
/// entries rather than one enharmonic pair.
const Map<String, Map<Hand, _FingeringShape>> _scaleFingeringShapes = {
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

const _rhArpeggio1235 = _FingeringShape._(
  entry: [1],
  cycle: [2, 3, 1],
  terminalFinger: 5,
  reversesForDescending: true,
);
const _lhArpeggio5421 = _FingeringShape._(
  entry: [5],
  cycle: [4, 2, 1],
  reversesForDescending: true,
);
const _lhArpeggio5321 = _FingeringShape._(
  entry: [5],
  cycle: [3, 2, 1],
  reversesForDescending: true,
);
const _rhArpeggio2124 = _FingeringShape._(
  entry: [2],
  cycle: [1, 2, 4],
  reversesForDescending: true,
);
const _lhArpeggio2142 = _FingeringShape._(
  entry: [2],
  cycle: [1, 4, 2],
  reversesForDescending: true,
);
const _rhArpeggio2312 = _FingeringShape._(
  entry: [2],
  cycle: [3, 1, 2],
  reversesForDescending: true,
);
const _lhArpeggio3213 = _FingeringShape._(
  entry: [3],
  cycle: [2, 1, 3],
  reversesForDescending: true,
);

const Map<String, Map<Hand, _FingeringShape>>
_establishedArpeggioFingeringShapes = {
  'C_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'Db_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio2124,
    Hand.left: _lhArpeggio2142,
  },
  'D_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5321,
  },
  'Eb_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio2124,
    Hand.left: _lhArpeggio2142,
  },
  'E_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5321,
  },
  'F_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'G_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'Ab_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio2124,
    Hand.left: _lhArpeggio2142,
  },
  'A_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5321,
  },
  'B_MAJOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5321,
  },
  'C_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'C#_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio2124,
    Hand.left: _lhArpeggio2142,
  },
  'D_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'Eb_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'E_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'F_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'F#_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio2124,
    Hand.left: _lhArpeggio2142,
  },
  'G_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'G#_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio2124,
    Hand.left: _lhArpeggio2142,
  },
  'A_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
  'B_MINOR_ROOT_ARPEGGIO': {
    Hand.right: _rhArpeggio1235,
    Hand.left: _lhArpeggio5421,
  },
};

const Map<String, Map<Hand, _FingeringShape>> _selectedArpeggioFingeringShapes =
    {
      'F#_MAJOR_ROOT_ARPEGGIO': {
        Hand.right: _rhArpeggio1235,
        Hand.left: _lhArpeggio5321,
      },
      'Bb_MAJOR_ROOT_ARPEGGIO': {
        Hand.right: _rhArpeggio2124,
        Hand.left: _lhArpeggio3213,
      },
      'Bb_MINOR_ROOT_ARPEGGIO': {
        Hand.right: _rhArpeggio2312,
        Hand.left: _lhArpeggio3213,
      },
    };

const _scaleFingeringProvenance = FingeringProvenance._(
  source: 'KeyRecall Scale Fingering Taxonomy and Research',
  sourceEdition: '2026-08-18',
  sourceLocation: 'docs/domain-model/fingering-taxonomy.md §13',
  status: CanonicalFingeringStatus.canonicalSelected,
);

const _establishedArpeggioFingeringProvenance = FingeringProvenance._(
  source: 'St. Olaf College, Keyboard Proficiency Requirements Level III',
  sourceEdition: 'Revision 052720',
  sourceLocation: 'Appendix 2: Arpeggio Fingerings, pp. 15–16',
  status: CanonicalFingeringStatus.established,
);

const _selectedArpeggioFingeringProvenance = FingeringProvenance._(
  source: 'KeyRecall Root-Position Arpeggio Fingering Research',
  sourceEdition: '2026-09-04',
  sourceLocation: 'docs/domain-model/arpeggio-domain-research.md §6',
  status: CanonicalFingeringStatus.canonicalSelected,
);

Map<String, Map<Hand, CanonicalFingering>> _canonicalRecords(
  Map<String, Map<Hand, _FingeringShape>> shapes,
  FingeringProvenance provenance,
) => {
  for (final material in shapes.entries)
    material.key: {
      for (final fingering in material.value.entries)
        fingering.key: CanonicalFingering(
          materialId: material.key,
          hand: fingering.key,
          entry: fingering.value.entry,
          cycle: fingering.value.cycle,
          terminalFinger: fingering.value.terminalFinger,
          reversesForDescending: fingering.value.reversesForDescending,
          provenance: provenance,
        ),
    },
};

final Map<String, Map<Hand, CanonicalFingering>> _canonicalFingerings = {
  ..._canonicalRecords(_scaleFingeringShapes, _scaleFingeringProvenance),
  ..._canonicalRecords(
    _establishedArpeggioFingeringShapes,
    _establishedArpeggioFingeringProvenance,
  ),
  ..._canonicalRecords(
    _selectedArpeggioFingeringShapes,
    _selectedArpeggioFingeringProvenance,
  ),
};

/// The canonical fingering for [material] in [hand], or null when unsupported.
CanonicalFingering? canonicalFingering(TechnicalMaterial material, Hand hand) =>
    _canonicalFingerings[material.materialId]?[hand];

/// The finger for each moment under [conditions], for [hand], or null when the
/// material has no canonical fingering or [hand] does not play it.
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
List<int>? fingeringForConditions({
  required TechnicalMaterial material,
  required ExecutionConditions conditions,
  required Hand hand,
}) {
  final pattern = canonicalFingering(material, hand);
  if (pattern == null) return null;
  if (!pattern.reversesForDescending &&
      (conditions.direction == ExerciseDirection.upDown ||
          conditions.handMotion == HandMotion.contrary)) {
    return null;
  }

  final path = handPathsFor(
    conditions,
    degreesPerOctave: material.topology.degreesPerOctave,
  )[hand];
  if (path == null) return null;

  final ascending = pattern.ascending(conditions.octaves);
  final topDegree = ascending.length - 1;
  final descends = path.any((degree) => degree < 0);
  return [
    for (final degree in path)
      ascending[descends ? topDegree + degree : degree],
  ];
}
