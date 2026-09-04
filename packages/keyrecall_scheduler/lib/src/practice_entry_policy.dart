import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// Entry tempi resolved for the material families in one practice scope.
@immutable
class PracticeEntryPolicy {
  final double defaultTempoBpm;
  final Map<String, double> _tempoByFamilyId;

  const PracticeEntryPolicy.uniform(this.defaultTempoBpm)
    : assert(defaultTempoBpm > 0),
      assert(defaultTempoBpm < double.infinity),
      _tempoByFamilyId = const {};

  PracticeEntryPolicy.byFamily(
    Map<String, double> tempoByFamilyId, {
    required this.defaultTempoBpm,
  }) : _tempoByFamilyId = Map.unmodifiable(tempoByFamilyId) {
    _validate(defaultTempoBpm, 'defaultTempoBpm');
    for (final entry in _tempoByFamilyId.entries) {
      _validate(entry.value, 'tempoByFamilyId[${entry.key}]');
    }
  }

  double tempoFor(TechnicalMaterial material) =>
      _tempoByFamilyId[material.familyId] ?? defaultTempoBpm;

  static void _validate(double tempoBpm, String name) {
    if (!tempoBpm.isFinite || tempoBpm <= 0) {
      throw ArgumentError.value(
        tempoBpm,
        name,
        'must be finite and greater than zero',
      );
    }
  }
}
