import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/practice_providers.dart';
import 'package:keyrecall/features/practice/home_screen.dart';

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

    await tester.runAsync(() => container.read(practiceLoopProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Taps [label] and lets the storage writes it starts actually finish.
  ///
  /// The tap has to happen inside [WidgetTester.runAsync] too: futures created
  /// under the fake clock do not complete on their own.
  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('launching reaches an exercise without asking anything first', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.text('Play this'), findsOneWidget);
    expect(find.text('What the model expected'), findsOneWidget);
    expect(find.text('Clean'), findsOneWidget);
  });

  testWidgets('reporting a result commits it and moves on', (tester) async {
    await pumpPanel(tester);

    await tapAndSettle(tester, 'Clean');

    expect(find.text('Last committed'), findsOneWidget);
    expect(
      find.text('Play this'),
      findsOneWidget,
      reason: 'the loop presents the next exercise rather than stopping',
    );
  });

  testWidgets('playing on the synthetic instrument shows up as live input', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(find.text('nothing yet'), findsNothing);

    await tester.tap(find.text('Play something'));
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.textContaining('NoteOn'),
      findsWidgets,
      reason: 'the panel reads the same stream a keyboard would feed',
    );
  });
}
