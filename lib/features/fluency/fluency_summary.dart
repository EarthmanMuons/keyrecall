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

/// One key on the wheel: a tonic pitch class and its scale in each form.
@immutable
class KeySector {
  /// Semitones above C.
  final int pitchClass;

  final Map<ScaleForm, ScaleMaterial> forms;

  KeySector({
    required this.pitchClass,
    required Map<ScaleForm, ScaleMaterial> forms,
  }) : forms = Map.unmodifiable(forms);

  /// The tonic as the major scale spells it.
  String? get majorTonic => forms[ScaleForm.major]?.tonic;

  /// The tonic as the minor forms spell it, when that differs from the major.
  String? get minorTonic {
    final minor = [
      for (final form in ScaleForm.values)
        if (form != ScaleForm.major) ?forms[form]?.tonic,
    ].firstOrNull;
    return minor == majorTonic ? null : minor;
  }
}

/// The scales in [catalog] arranged around the circle of fifths from C.
///
/// Every pitch class has a sector, whether or not the catalog holds a scale on
/// it, so the wheel keeps its shape for a narrower catalog.
///
/// Throws [StateError] when the catalog spells one form on one pitch class two
/// ways, since a cell can hold one material.
List<KeySector> keySectors(Iterable<TechnicalMaterial> catalog) {
  final byPitchClass = <int, Map<ScaleForm, ScaleMaterial>>{};
  for (final material in catalog.whereType<ScaleMaterial>()) {
    final forms = byPitchClass.putIfAbsent(
      pitchClassOf(material.tonic),
      () => {},
    );
    if (forms.containsKey(material.form)) {
      throw StateError(
        '${material.materialId} shares a key and form with '
        '${forms[material.form]!.materialId}',
      );
    }
    forms[material.form] = material;
  }
  return [
    for (var step = 0; step < 12; step++)
      KeySector(
        pitchClass: step * 7 % 12,
        forms: byPitchClass[step * 7 % 12] ?? const {},
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

/// Where a point on the key map falls.
///
/// Rings run from the outside in, in [ScaleForm] order, so major is outermost.
typedef WheelCell = ({int sector, ScaleForm form});

/// The key map's shape, in the unit square it is drawn into.
@immutable
class KeyWheelGeometry {
  /// The outer edge of the rings, as a fraction of half the square's side.
  static const double outerRadius = 0.8;

  /// The inner edge of the innermost ring, likewise.
  static const double innerRadius = 0.24;

  const KeyWheelGeometry();

  double get ringWidth => (outerRadius - innerRadius) / ScaleForm.values.length;

  /// The outer and inner radius of [form]'s ring.
  (double outer, double inner) ringOf(ScaleForm form) {
    final outer = outerRadius - form.index * ringWidth;
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
      ScaleForm.values.length - 1,
    );
    final clockwise = (math.atan2(x, -y) + 2 * math.pi) % (2 * math.pi);
    final sector =
        ((clockwise + math.pi / 12) / (2 * math.pi / 12)).floor() % 12;
    return (sector: sector, form: ScaleForm.values[ring]);
  }
}

/// What a demonstration level is called on the key map.
String demonstrationName(DemonstrationLevel? level) => switch (level) {
  null => 'Not yet',
  DemonstrationLevel.cued => 'With cues',
  DemonstrationLevel.notesPreviewed => 'Notes previewed',
  DemonstrationLevel.fromMemory => 'From memory',
};

/// When something was last demonstrated, as a date a learner reads: the year
/// only when it is not the year of [now].
String demonstratedOn(DateTime at, {required DateTime now}) {
  const months = [
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
  ];
  final local = at.toLocal();
  final date = '${months[local.month - 1]} ${local.day}';
  return local.year == now.toLocal().year ? date : '$date, ${local.year}';
}

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
