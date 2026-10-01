import 'package:flutter/foundation.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'fluency_summary.dart';

/// How a report group lays out its materials.
sealed class PrimaryView {
  const PrimaryView();
}

/// The key wheel, with [rings] from the outside in.
final class WheelView extends PrimaryView {
  final List<WheelRing> rings;

  const WheelView(this.rings);
}

/// A plain list of the group's materials, which any group can be shown as.
final class MaterialListView extends PrimaryView {
  const MaterialListView();
}

/// A learner-facing grouping in the fluency report.
///
/// Assembled from the catalog when the report is read, never stored, so a
/// group can change without touching any history.
@immutable
class ReportGroup {
  final String id;

  /// What the group is called, as a plural.
  final String name;

  final Set<String> familyIds;
  final PrimaryView view;

  /// The cohort the group's playing pace is read over, from its materials, or
  /// null when it has none yet.
  final PaceCohort Function(Iterable<TechnicalMaterial> materials)? paceCohort;

  const ReportGroup({
    required this.id,
    required this.name,
    required this.familyIds,
    required this.view,
    this.paceCohort,
  });
}

final ReportGroup scaleGroup = ReportGroup(
  id: 'SCALES',
  name: 'Scales',
  familyIds: const {TechnicalMaterial.scaleFamilyId},
  view: WheelView([
    for (final form in ScaleForm.values)
      WheelRing(
        holds: (material) => material.scaleForm == form,
        spelling: form == ScaleForm.major
            ? KeySpelling.major
            : KeySpelling.minor,
      ),
  ]),
  paceCohort: PaceCohort.scales,
);

/// Root-position arpeggios only. An inversion belongs in its root position's
/// detail sheet rather than in a ring of its own.
final ReportGroup arpeggioGroup = ReportGroup(
  id: 'ARPEGGIOS',
  name: 'Arpeggios',
  familyIds: const {TechnicalMaterial.arpeggioFamilyId},
  view: WheelView([
    for (final quality in ArpeggioQuality.values)
      WheelRing(
        holds: (material) =>
            material is ArpeggioMaterial &&
            material.quality == quality &&
            material.inversion == ArpeggioInversion.root,
        spelling: quality == ArpeggioQuality.major
            ? KeySpelling.major
            : KeySpelling.minor,
      ),
  ]),
);

final List<ReportGroup> reportGroups = List.unmodifiable([
  scaleGroup,
  arpeggioGroup,
]);

/// A report group and the catalog materials it holds, in catalog order.
@immutable
class ResolvedGroup {
  final ReportGroup group;
  final List<TechnicalMaterial> materials;

  ResolvedGroup(this.group, Iterable<TechnicalMaterial> materials)
    : materials = List.unmodifiable(materials);
}

/// [catalog] organized into [groups], each holding at least one material.
///
/// A material family no group claims gets a group of its own, shown as a list
/// and named by its family id, so no material is left out of the report. The
/// declared groups come first, then those, in catalog order.
///
/// Throws [StateError] when two groups claim one family.
List<ResolvedGroup> resolveReportGroups(
  Iterable<TechnicalMaterial> catalog, {
  List<ReportGroup>? groups,
}) {
  final declared = groups ?? reportGroups;
  final claims = <String, ReportGroup>{};
  for (final group in declared) {
    for (final familyId in group.familyIds) {
      if (claims[familyId] case final other?) {
        throw StateError('${group.id} and ${other.id} both claim $familyId');
      }
      claims[familyId] = group;
    }
  }

  final held = <ReportGroup, List<TechnicalMaterial>>{
    for (final group in declared) group: [],
  };
  for (final material in catalog) {
    final group = claims.putIfAbsent(
      material.familyId,
      () => ReportGroup(
        id: material.familyId,
        name: material.familyId,
        familyIds: {material.familyId},
        view: const MaterialListView(),
      ),
    );
    held.putIfAbsent(group, () => []).add(material);
  }
  return [
    for (final MapEntry(key: group, value: materials) in held.entries)
      if (materials.isNotEmpty) ResolvedGroup(group, materials),
  ];
}
