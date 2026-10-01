import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

/// What the fluency report knows about one material.
///
/// The one source the key map and the detail sheet both read, so a cell and
/// the sheet it opens cannot disagree.
@immutable
class MaterialFluency {
  final TechnicalMaterial material;

  /// The strongest demonstration ever reached, or null when there is none.
  final Demonstration? demonstration;

  /// The fastest qualifying pace in each context this material was played in.
  final Map<TempoContext, double> demonstratedTempos;

  const MaterialFluency({
    required this.material,
    required this.demonstration,
    required this.demonstratedTempos,
  });

  DemonstrationLevel? get level => demonstration?.level;

  /// The demonstrated tempo for [hands] at [octaves] in parallel motion, read
  /// from the most independent rung that has one.
  RungTempo? tempoFor(HandConfiguration hands, {int octaves = 1}) {
    for (var rung = 2; rung >= 0; rung--) {
      final tempo =
          demonstratedTempos[(
            materialId: material.materialId,
            hands: hands,
            handMotion: HandMotion.parallel,
            octaves: octaves,
            guidanceIndependence: rung,
          )];
      if (tempo != null) return (tempoBpm: tempo, guidanceIndependence: rung);
    }
    return null;
  }

  /// The demonstrated tempo from memory for [hands] at one octave, which is
  /// what the key map's tempo lens shows.
  double? unguidedTempo(HandConfiguration hands) => switch (tempoFor(hands)) {
    (:final tempoBpm, guidanceIndependence: 2) => tempoBpm,
    _ => null,
  };
}

/// A demonstrated tempo and the rung it was demonstrated at.
typedef RungTempo = ({double tempoBpm, int guidanceIndependence});

/// One material as the detail sheet shows it: its fluency, and a tempo table
/// with a row per hand configuration and a column per octave span.
///
/// The spans are the ones the material's progression offers, so the table has
/// no cell for a realization the material is never played in, which would read
/// as not yet learned.
@immutable
class MaterialDetail {
  final MaterialFluency fluency;
  final List<int> octaveSpans;
  final List<TempoRow> rows;

  const MaterialDetail._(this.fluency, this.octaveSpans, this.rows);

  factory MaterialDetail.of(MaterialFluency fluency) {
    final spans = fluency.material.progression.octaveSpans;
    return MaterialDetail._(fluency, spans, [
      for (final hands in HandConfiguration.values)
        (
          hands: hands,
          tempos: [
            for (final octaves in spans)
              fluency.tempoFor(hands, octaves: octaves),
          ],
        ),
    ]);
  }

  TechnicalMaterial get material => fluency.material;

  /// Whether any cell of the table holds a tempo.
  bool get hasTempo =>
      rows.any((row) => row.tempos.any((tempo) => tempo != null));
}

/// One hand configuration's demonstrated tempos, a column per octave span.
typedef TempoRow = ({HandConfiguration hands, List<RungTempo?> tempos});

/// The fluency report's view of a whole catalog.
@immutable
class FluencySummary {
  final Map<String, MaterialFluency> _byMaterialId;

  const FluencySummary._(this._byMaterialId);

  /// What [days] show about each material in [catalog].
  factory FluencySummary.of(
    List<FluencyDay> days, {
    required List<TechnicalMaterial> catalog,
    TempoQualification qualification = TempoQualification.v1,
  }) {
    final best = bestDemonstrations(days);
    final tempos = <String, Map<TempoContext, double>>{};
    for (final MapEntry(key: context, value: tempo) in demonstratedTempos(
      days,
      qualification: qualification,
    ).entries) {
      tempos.putIfAbsent(context.materialId, () => {})[context] = tempo;
    }
    return FluencySummary._({
      for (final material in catalog)
        material.materialId: MaterialFluency(
          material: material,
          demonstration: best[material.materialId],
          demonstratedTempos: Map.unmodifiable(
            tempos[material.materialId] ?? const {},
          ),
        ),
    });
  }

  /// What is known about [material].
  ///
  /// Throws [ArgumentError] for a material outside the catalog this summary
  /// was built over.
  MaterialFluency operator [](TechnicalMaterial material) =>
      _byMaterialId[material.materialId] ??
      (throw ArgumentError.value(
        material.materialId,
        'material',
        'not in this summary',
      ));

  /// How many of [materials] have been demonstrated at exactly [level].
  int countAt(
    DemonstrationLevel level,
    Iterable<TechnicalMaterial> materials,
  ) => materials.where((material) => this[material].level == level).length;
}

/// Which spelling of a key a ring's materials carry in the sector label.
enum KeySpelling { major, minor }

/// One ring of the key wheel: which materials it holds, and how they spell the
/// key.
@immutable
class WheelRing {
  final bool Function(TechnicalMaterial material) holds;
  final KeySpelling spelling;

  const WheelRing({required this.holds, required this.spelling});
}

/// One key on the wheel: a tonic pitch class and its material in each ring.
@immutable
class KeySector {
  /// Semitones above C.
  final int pitchClass;

  /// The material in each ring, outermost first, or null where there is none.
  final List<TechnicalMaterial?> cells;

  /// The tonic as the major-spelled rings write it.
  final String? majorTonic;

  /// The tonic as the minor-spelled rings write it, when that differs from
  /// [majorTonic].
  final String? minorTonic;

  KeySector._(
    this.pitchClass,
    List<TechnicalMaterial?> cells,
    List<WheelRing> rings,
  ) : cells = List.unmodifiable(cells),
      majorTonic = _tonicIn(cells, rings, KeySpelling.major),
      minorTonic = _distinct(
        _tonicIn(cells, rings, KeySpelling.minor),
        _tonicIn(cells, rings, KeySpelling.major),
      );

  /// The key's materials, outermost ring first.
  List<TechnicalMaterial> get materials => cells.nonNulls.toList();

  static String? _tonicIn(
    List<TechnicalMaterial?> cells,
    List<WheelRing> rings,
    KeySpelling spelling,
  ) => [
    for (final (ring, material) in cells.indexed)
      if (rings[ring].spelling == spelling) ?material?.tonic,
  ].firstOrNull;

  static String? _distinct(String? minor, String? major) =>
      minor == major ? null : minor;
}

/// [materials] arranged around the circle of fifths from C, one ring per entry
/// of [rings].
///
/// Every pitch class has a sector, whether or not there is a material on it,
/// so the wheel keeps its shape for a narrower catalog.
///
/// Throws [StateError] when a material belongs to no ring or to two, or when
/// two share a key and ring, since a cell can hold one material.
List<KeySector> keySectors(
  Iterable<TechnicalMaterial> materials,
  List<WheelRing> rings,
) {
  final byPitchClass = <int, List<TechnicalMaterial?>>{};
  for (final material in materials) {
    final matching = [
      for (final (index, ring) in rings.indexed)
        if (ring.holds(material)) index,
    ];
    if (matching.length != 1) {
      throw StateError(
        '${material.materialId} belongs to ${matching.length} rings',
      );
    }
    final cells = byPitchClass.putIfAbsent(
      pitchClassOf(material.tonic),
      () => List.filled(rings.length, null),
    );
    if (cells[matching.single] case final held?) {
      throw StateError(
        '${material.materialId} shares a key and ring with '
        '${held.materialId}',
      );
    }
    cells[matching.single] = material;
  }
  return [
    for (var step = 0; step < 12; step++)
      KeySector._(
        step * 7 % 12,
        byPitchClass[step * 7 % 12] ?? List.filled(rings.length, null),
        rings,
      ),
  ];
}

/// How the tempo lens shades a demonstrated tempo.
///
/// Coarse on purpose. The bands are a reading aid for a wheel of small cells,
/// and the exact tempo is one tap away.
enum TempoBand {
  none,
  under72,
  from72,
  from100;

  static TempoBand of(double? tempoBpm) => switch (tempoBpm) {
    null => none,
    < 72 => under72,
    < 100 => from72,
    _ => from100,
  };
}

/// Where a point on the key map falls, with rings counted from the outside in.
typedef WheelCell = ({int sector, int ring});

/// The key map's shape, in the unit square it is drawn into.
@immutable
class KeyWheelGeometry {
  /// The outer edge of the rings, as a fraction of half the square's side.
  static const double outerRadius = 0.8;

  /// The inner edge of the innermost ring, likewise.
  static const double innerRadius = 0.24;

  final int rings;

  const KeyWheelGeometry({required this.rings}) : assert(rings > 0);

  double get ringWidth => (outerRadius - innerRadius) / rings;

  /// The outer and inner radius of [ring], counted from the outside in.
  (double outer, double inner) ringOf(int ring) {
    final outer = outerRadius - ring * ringWidth;
    return (outer, outer - ringWidth);
  }

  /// The angle [sector] is centered on, clockwise from twelve o'clock.
  double centerAngleOf(int sector) => sector * 2 * math.pi / 12;

  /// Where assistive technology finds [sector]: a square centered on the
  /// sector's outer edge, in the same coordinates as [cellAt].
  ///
  /// One target a key rather than one a cell. The innermost ring is too narrow
  /// for cell-sized targets anyone can hit, so the key is the button and its
  /// sheet lists the forms. The side is the largest that keeps every target
  /// clear of its neighbors.
  ({double x, double y, double side}) semanticTargetOf(int sector) {
    final angle = centerAngleOf(sector);
    return (
      x: outerRadius * math.sin(angle),
      y: -outerRadius * math.cos(angle),
      side: _semanticSide,
    );
  }

  /// The side every semantic target shares, bounded by the closest pair of
  /// neighboring sector centers along either axis.
  static final double _semanticSide = [
    for (var sector = 0; sector < 12; sector++)
      math.max(
        (outerRadius *
                (math.sin((sector + 1) * math.pi / 6) -
                    math.sin(sector * math.pi / 6)))
            .abs(),
        (outerRadius *
                (math.cos((sector + 1) * math.pi / 6) -
                    math.cos(sector * math.pi / 6)))
            .abs(),
      ),
  ].reduce(math.min);

  /// The cell at ([x], [y]), where both run from -1 to 1 across the square with
  /// y increasing downward, or null outside the rings.
  WheelCell? cellAt(double x, double y) {
    final radius = math.sqrt(x * x + y * y);
    if (radius > outerRadius || radius < innerRadius) return null;
    final ring = ((outerRadius - radius) / ringWidth).floor().clamp(
      0,
      rings - 1,
    );
    final clockwise = (math.atan2(x, -y) + 2 * math.pi) % (2 * math.pi);
    final sector =
        ((clockwise + math.pi / 12) / (2 * math.pi / 12)).floor() % 12;
    return (sector: sector, ring: ring);
  }
}

/// What a demonstration level is called on the key map.
String demonstrationName(DemonstrationLevel? level) => switch (level) {
  null => 'Not yet',
  DemonstrationLevel.cued => 'With cues',
  DemonstrationLevel.notesPreviewed => 'Notes previewed',
  DemonstrationLevel.fromMemory => 'From memory',
};

/// What a hand configuration is called in the report.
String handsLabel(HandConfiguration hands) => switch (hands) {
  HandConfiguration.right => 'Right hand',
  HandConfiguration.left => 'Left hand',
  HandConfiguration.together => 'Together',
};

/// When something was last demonstrated, as a date a learner reads: the year
/// only when it is not the year of [now].
String demonstratedOn(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  return _dateName(local.year, local.month, local.day, now.toLocal().year);
}

/// A calendar day as a learner reads it, with the year only when it is not the
/// year of [today].
String dayName(CalendarDay day, {required CalendarDay today}) =>
    _dateName(day.year, day.month, day.day, today.year);

String _dateName(int year, int month, int day, int currentYear) {
  final date = '${monthName(month)} $day';
  return year == currentYear ? date : '$date, $year';
}

/// A month as a learner reads it on a date, such as `Sep`.
String monthName(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

/// A demonstrated tempo as a table cell, naming the support it was shown with
/// when that was not from memory.
String rungTempoName(RungTempo tempo) {
  final bpm = tempo.tempoBpm.round();
  return switch (tempo.guidanceIndependence) {
    2 => '$bpm',
    1 => '$bpm previewed',
    _ => '$bpm with cues',
  };
}
