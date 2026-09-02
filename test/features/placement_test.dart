import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_screen.dart';
import 'package:keyrecall/features/practice/onboarding.dart';
import 'package:keyrecall/features/practice/placement.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';
import 'package:keyrecall/features/practice/profiles_screen.dart';

/// The one question a first launch asks, and what it must not do before it is
/// answered.
///
/// Placement is the prior every attempt in a history is interpreted against
/// and nothing can change it afterwards, so a profile that exists before
/// somebody has chosen is a learner started from a tier nobody picked.
void main() {
  late InMemoryProfileRepository profiles;
  late InMemoryPracticeStore practice;

  setUp(() {
    profiles = InMemoryProfileRepository();
    practice = InMemoryPracticeStore();
  });

  ProviderContainer containerOn() {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        practiceStoreProvider.overrideWith((ref) async => practice),
      ],
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

    // The synthetic instrument, rather than the MIDI stack a test has no
    // radio for.
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    await container.read(profileRosterProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingGate()),
      ),
    );
    await tester.pump();
  }

  Future<List<Profile>> profilesIn(ProviderContainer container) async =>
      (await container.read(profileRepositoryProvider.future)).list();

  testWidgets('an install with nobody on it opens on the question', (
    tester,
  ) async {
    final container = containerOn();
    await pumpGate(tester, container);

    expect(find.text('Where should we start?'), findsOneWidget);
    expect(find.byType(AttemptScreen), findsNothing);
    for (final tier in PlacementTier.values) {
      expect(find.text(tier.headline), findsOneWidget);
    }
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'there is nothing to continue to until a tier is chosen',
    );
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
      await profilesIn(container),
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

    await tester.tap(find.text(PlacementTier.beginner.headline));
    await tester.pumpAndSettle();
    expect(
      await profilesIn(container),
      isEmpty,
      reason: 'selecting is not answering; the answer is confirmed',
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      await profilesIn(container),
      isEmpty,
      reason:
          'the instrument step is still part of the first launch, and '
          'quitting during it leaves the install unplaced',
    );

    await tester.tap(find.text('Start practicing'));
    await tester.pumpAndSettle();

    final created = (await profilesIn(container)).single;
    expect(created.placement, PlacementTier.beginner);
    expect(
      created.displayName,
      defaultProfileName,
      reason:
          'one person on one instrument stays the ordinary case, so the '
          'name is implicit and only the prior is asked for',
    );
  });

  group('an install emptied of profiles', () {
    /// Seeds one profile, opens the app on it, and pushes the profiles screen
    /// over it, which is the only way the roster is emptied by hand.
    Future<GlobalKey<NavigatorState>> openProfiles(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
      final repository = await container.read(profileRepositoryProvider.future);
      await repository.create(
        displayName: 'Alice',
        placement: PlacementTier.advanced,
      );
      await container.read(profileRosterProvider.future);

      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigator,
            home: const OnboardingGate(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AttemptScreen), findsOneWidget);

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (context) => const ProfilesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return navigator;
    }

    Future<void> deleteAlice(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('leaves the way back at the first launch', (tester) async {
      final container = containerOn();
      final navigator = await openProfiles(tester, container);
      await deleteAlice(tester);
      expect(find.text('Nobody practices here yet'), findsOneWidget);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byType(AttemptScreen), findsNothing);
      expect(
        find.text(placementQuestion),
        findsOneWidget,
        reason:
            'an install with nobody on it is unplaced however it got that '
            'way, and the next learner is placed by the person who will be it',
      );
    });

    testWidgets('is practicing again as soon as somebody is added', (
      tester,
    ) async {
      final container = containerOn();
      final navigator = await openProfiles(tester, container);
      await deleteAlice(tester);

      await tester.tap(find.text('Add profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bo');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(PlacementTier.someExperience.headline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      navigator.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byType(AttemptScreen), findsOneWidget);
      expect(
        find.text(placementQuestion),
        findsNothing,
        reason:
            'a profile added by name carries its own answer, so the first '
            'launch has nothing left to ask',
      );
    });
  });

  testWidgets('an install that has been placed goes straight to practice', (
    tester,
  ) async {
    final container = containerOn();
    final repository = await container.read(profileRepositoryProvider.future);
    await repository.create(
      displayName: 'Alice',
      placement: PlacementTier.advanced,
    );
    await pumpGate(tester, container);

    expect(find.text('Where should we start?'), findsNothing);
    expect(find.byType(AttemptScreen), findsOneWidget);
  });
}
