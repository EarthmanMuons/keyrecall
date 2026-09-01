import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall/features/demo_input/demo_input.dart';
import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/developer_screen.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keyrecall_widget_test');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  /// The panel is a tall stack of sections, and the default test window is
  /// short enough that the lower ones are never laid out.
  void useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Pumps the panel with its storage already opened.
  ///
  /// Opening a session is real file I/O, which the test binding's fake clock
  /// does not advance, so it has to happen in [WidgetTester.runAsync].
  Future<ProviderContainer> pumpPanel(WidgetTester tester) async {
    useTallWindow(tester);
    final container = ProviderContainer(
      overrides: [storageRootProvider.overrideWith((ref) async => root)],
    );
    addTearDown(container.dispose);

    // The panel sits behind the placement gate in the real app, so the install
    // is placed the way the first-run screen places it before it is pumped.
    // The synthetic instrument, rather than the MIDI stack a test has no
    // radio for.
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    await tester.runAsync(() async {
      await container
          .read(profileRosterProvider.notifier)
          .place(PlacementTier.someExperience);
      await container.read(practiceLoopProvider.future);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DeveloperScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('a placed install reaches an exercise without asking more', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.text('What the model expected'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
  });

  testWidgets('playing on the synthetic instrument shows up as live input', (
    tester,
  ) async {
    final container = await pumpPanel(tester);
    expect(find.text('nothing yet'), findsNothing);

    container.read(demoInputProvider.notifier).playSequence(const [60, 62, 64]);
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.textContaining('NoteOn'),
      findsWidgets,
      reason: 'the panel reads the same stream a keyboard would feed',
    );
  });
}
