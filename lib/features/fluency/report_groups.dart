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

  /// What a slice holds and how slices are ordered, for the help sheet.
  final String keysHelp;

  /// What the rings are, for the help sheet.
  final String ringsHelp;

  /// The line under the wheel: how the rings run, and how to open a cell.
  final String caption;

  const WheelView(
    this.rings, {
    required this.keysHelp,
    required this.ringsHelp,
    required this.caption,
  });
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

  /// What the group is called, as a title.
  final String name;

  /// What one of its materials is called inside a sentence.
  final String singular;

  /// What several of its materials are called inside a sentence.
  final String plural;

  final Set<String> familyIds;
  final PrimaryView view;

  /// The cohort the group's playing pace is read over, from its materials, or
  /// null when it has none yet.
  final PaceCohort Function(Iterable<TechnicalMaterial> materials)? paceCohort;

  const ReportGroup({
    required this.id,
    required this.name,
    required this.singular,
    required this.plural,
    required this.familyIds,
    required this.view,
    this.paceCohort,
  });
}

final ReportGroup scaleGroup = ReportGroup(
  id: 'SCALES',
  name: 'Scales',
  singular: 'scale',
  plural: 'scales',
  familyIds: const {TechnicalMaterial.scaleFamilyId},
  view: WheelView(
    [
      for (final form in ScaleForm.values)
        WheelRing(
          holds: (material) => material.scaleForm == form,
          spelling: form == ScaleForm.major
              ? KeySpelling.major
              : KeySpelling.minor,
        ),
    ],
    keysHelp:
        'Each slice holds the scales that start on the same piano key, such as '
        'D♭ major and C♯ minor. Slices follow the circle of fifths, so '
        'neighbors share all but one note, but you can simply read the names.',
    ringsHelp:
        'Major is the outer ring, then natural, harmonic, and melodic minor '
        'toward the middle.',
    caption:
        'Major on the outside, then natural, harmonic, and melodic minor. '
        'Tap a scale for its tempos, or hold and slide to choose.',
  ),
  paceCohort: PaceCohort.scales,
);

/// Root-position arpeggios only. An inversion belongs in its root position's
/// detail sheet rather than in a ring of its own.
final ReportGroup arpeggioGroup = ReportGroup(
  id: 'ARPEGGIOS',
  name: 'Arpeggios',
  singular: 'arpeggio',
  plural: 'arpeggios',
  familyIds: const {TechnicalMaterial.arpeggioFamilyId},
  view: WheelView(
    [
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
    ],
    keysHelp:
        'Each slice holds the arpeggios that start on the same piano key, such '
        'as D♭ major and C♯ minor. Slices follow the circle of fifths, but you '
        'can simply read the names.',
    ringsHelp: 'Major is the outer ring and minor the inner one.',
    caption:
        'Major on the outside, minor inside. Tap an arpeggio for its tempos, '
        'or hold and slide to choose.',
  ),
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
        singular: 'material',
        plural: 'materials',
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
