import 'package:meta/meta.dart';

import 'competency.dart';

/// A scale form supported by V1.
///
/// The catalog is deliberately open-ended: forms are an initial catalog rather
/// than a closed set, and each new form needs its own topology competency.
enum ScaleForm {
  major('MAJOR', Competency.majorScaleTopology),
  naturalMinor('NATURAL_MINOR', Competency.naturalMinorTopology),
  harmonicMinor('HARMONIC_MINOR', Competency.harmonicMinorTopology),

  /// Fixed-form melodic minor: the same ascending form in both directions.
  melodicMinor('MELODIC_MINOR', Competency.melodicMinorTopology);

  const ScaleForm(this.id, this.topologyCompetency);

  /// Stable identifier used in [TechnicalMaterial.materialId] and traces.
  final String id;

  /// The topology competency this form loads on.
  final Competency topologyCompetency;

  /// The form with the given [id].
  ///
  /// Throws [ArgumentError] when no form matches.
  static ScaleForm fromId(String id) => values.firstWhere(
    (form) => form.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown scale form'),
  );
}

/// What is being played, independent of how it is played.
///
/// Material identity deliberately excludes hand, tempo, octaves, direction,
/// and guidance, so one scale has a single memory state while its right-hand,
/// left-hand, and hands-together performances carry separate execution state.
@immutable
class TechnicalMaterial {
  /// The tonic's letter name, such as `C` or `F#`.
  final String tonic;

  /// The scale form built on [tonic].
  final ScaleForm form;

  const TechnicalMaterial(this.tonic, this.form);

  /// Stable identifier for this material, such as `F#_HARMONIC_MINOR`.
  String get materialId => '${tonic}_${form.id}';

  @override
  bool operator ==(Object other) =>
      other is TechnicalMaterial && other.tonic == tonic && other.form == form;

  @override
  int get hashCode => Object.hash(tonic, form);

  @override
  String toString() => materialId;
}
