import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/developer_screen.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';
import 'package:keyrecall/layout.dart';
import 'package:keyrecall/theme.dart';

import '../support/scheduler_override.dart';

void main() {
  for (final width in [320.0, 393.0]) {
    testWidgets('scheduling fits a $width pixel phone and either override '
        'can be chosen and cleared', (tester) async {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith(
            (ref) async => InMemoryProfileRepository(),
          ),
          inProcessScheduling,
          practiceStoreProvider.overrideWith(
            (ref) async => InMemoryPracticeStore(),
          ),
          practiceCatalogProvider.overrideWithValue([
            ScaleMaterial('C', ScaleForm.major),
            ScaleMaterial('G', ScaleForm.major),
          ]),
        ],
      );
      addTearDown(container.dispose);
      container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
      await container
          .read(profileRosterProvider.notifier)
          .place(PlacementTier.someExperience);
      final before = await container.read(practiceLoopProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: keyRecallTheme(lightColorScheme),
            builder: (context, child) => LayoutScope(child: child!),
            home: const DeveloperScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final dropdown = find.byType(DropdownButton<SchedulingAssignment?>);
      for (final chosen in [...SchedulingAssignment.values, null]) {
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        final label =
            chosen?.id ?? 'Production (${SchedulingAssignment.production.id})';
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final after = container.read(practiceLoopProvider).requireValue;
        expect(after.profile.schedulingOverride, chosen);
        expect(after.pending!.attemptId, before.presented!.decision.attemptId);
      }

      await tester.pumpWidget(const SizedBox());
    });
  }
}
