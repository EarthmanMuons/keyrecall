import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'package:keyrecall/features/fluency/fluency_summary.dart';
import 'package:keyrecall/features/fluency/report_groups.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

final _catalog = [...allScales, ...allRootPositionArpeggios];

void main() {
  group('report groups', () {
    test('hold each claimed family in its declared group', () {
      final groups = resolveReportGroups(_catalog);

      expect(
        [for (final resolved in groups) resolved.group],
        [scaleGroup, arpeggioGroup],
      );
      expect(groups[0].materials, allScales);
      expect(groups[1].materials, allRootPositionArpeggios);
    });

    test('give an unclaimed family a list of its own', () {
      final groups = resolveReportGroups(_catalog, groups: [scaleGroup]);

      expect(groups, hasLength(2));
      final fallback = groups[1].group;
      expect(fallback.id, TechnicalMaterial.arpeggioFamilyId);
      expect(fallback.familyIds, {TechnicalMaterial.arpeggioFamilyId});
      expect(fallback.view, isA<MaterialListView>());
      expect(groups[1].materials, allRootPositionArpeggios);
    });

    test('place every material in exactly one group', () {
      for (final declared in [
        reportGroups,
        [scaleGroup],
        [arpeggioGroup],
        <ReportGroup>[],
      ]) {
        final placed = [
          for (final resolved in resolveReportGroups(
            _catalog,
            groups: declared,
          ))
            ...resolved.materials,
        ];
        expect(placed, unorderedEquals(_catalog));
      }
    });

    test('leave out a group with nothing in the catalog', () {
      expect(
        [for (final resolved in resolveReportGroups(allScales)) resolved.group],
        [scaleGroup],
      );
    });

    test('refuse two groups claiming one family', () {
      expect(
        () => resolveReportGroups(_catalog, groups: [scaleGroup, scaleGroup]),
        throwsStateError,
      );
    });

    test('put every material of the app catalog in a cell of its wheel', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final catalog = container.read(practiceCatalogProvider);

      for (final resolved in resolveReportGroups(catalog)) {
        if (resolved.group.view case WheelView(:final rings)) {
          final placed = keySectors(
            resolved.materials,
            rings,
          ).expand((sector) => sector.materials);
          expect(placed, unorderedEquals(resolved.materials));
        }
      }
    });
  });

  group('the arpeggio wheel', () {
    final sectors = keySectors(
      allRootPositionArpeggios,
      (arpeggioGroup.view as WheelView).rings,
    );

    test('rings major outside minor in each key', () {
      expect(sectors[0].cells, [
        ArpeggioMaterial('C', ArpeggioQuality.major),
        ArpeggioMaterial('C', ArpeggioQuality.minor),
      ]);
    });

    test('labels a key with each quality spelling', () {
      expect(sectors[7].majorTonic, 'Db');
      expect(sectors[7].minorTonic, 'C#');
      expect(sectors[0].minorTonic, isNull);
    });

    test('holds no inversion in a ring', () {
      expect(
        () => keySectors([
          ArpeggioMaterial(
            'C',
            ArpeggioQuality.major,
            inversion: ArpeggioInversion.first,
          ),
        ], (arpeggioGroup.view as WheelView).rings),
        throwsStateError,
      );
    });
  });
}
