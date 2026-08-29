import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/home_screen.dart';
import 'package:keyrecall/features/practice/placement.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

/// The one question a first launch asks, and what it must not do before it is
/// answered.
///
/// Placement is the prior every attempt in a history is interpreted against
/// and nothing can change it afterwards, so a profile that exists before
/// somebody has chosen is a learner started from a tier nobody picked.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_placement_ui_test');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  ProviderContainer containerOn() {
    final container = ProviderContainer(
      overrides: [storageRootProvider.overrideWith((ref) async => root)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpGate(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => container.read(profileRosterProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlacementGate()),
      ),
    );
    await tester.pump();
  }

  Future<List<Profile>> profilesIn(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final repository = await tester.runAsync(
      () => container.read(profileRepositoryProvider.future),
    );
    return (await tester.runAsync(() => repository!.list()))!;
  }

  testWidgets('an install with nobody on it opens on the question', (
    tester,
  ) async {
    final container = containerOn();
    await pumpGate(tester, container);

    expect(find.text('Where should we start?'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    for (final tier in PlacementTier.values) {
      expect(find.text(tier.headline), findsOneWidget);
    }
    expect(
      find.byType(TextField),
      findsNothing,
      reason:
          'a first launch is not profile administration, and the name is '
          'not the part that cannot be changed later',
    );
  });

  testWidgets('nothing is written until somebody chooses', (tester) async {
    final container = containerOn();
    await pumpGate(tester, container);

    // The screen has been built, the roster read, and the loop is behind the
    // gate. None of that may have brought a learner into existence.
    expect(
      await profilesIn(tester, container),
      isEmpty,
      reason:
          'a profile written before the answer carries a placement nobody '
          'chose, which is exactly what cannot be corrected afterwards',
    );
  });

  testWidgets('choosing creates the learner it was asked about', (
    tester,
  ) async {
    final container = containerOn();
    await pumpGate(tester, container);

    await tester.runAsync(() async {
      await tester.tap(find.text(PlacementTier.beginner.headline));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final created = (await profilesIn(tester, container)).single;
    expect(created.placement, PlacementTier.beginner);
    expect(
      created.displayName,
      defaultProfileName,
      reason:
          'one person on one instrument stays the ordinary case, so the '
          'name is implicit and only the prior is asked for',
    );
  });

  testWidgets('an install that has been placed goes straight to practice', (
    tester,
  ) async {
    final container = containerOn();
    await tester.runAsync(() async {
      final repository = await container.read(profileRepositoryProvider.future);
      await repository.create(
        displayName: 'Alice',
        placement: PlacementTier.advanced,
      );
    });
    await pumpGate(tester, container);

    expect(find.text('Where should we start?'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
