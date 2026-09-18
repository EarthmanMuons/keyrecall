import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/fluency/fluency_screen.dart';
import 'package:keyrecall/features/fluency/fluency_summary.dart';
import 'package:keyrecall/features/practice/hands_icon.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

void main() {
  Future<void> pumpReport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceCatalogProvider.overrideWithValue(allScales),
          fluencyReportProvider.overrideWith(
            (ref) async => (
              summary: FluencySummary.of(const [], catalog: allScales),
              days: const <FluencyDay>[],
            ),
          ),
        ],
        child: const MaterialApp(home: FluencyScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset point(WidgetTester tester, double x, double y) {
    final wheel = tester.getRect(find.byType(KeyWheel));
    return wheel.center + Offset(x, y) * (wheel.width / 2);
  }

  testWidgets('holding previews and scrubbing opens the released scale', (
    tester,
  ) async {
    await pumpReport(tester);
    final gesture = await tester.startGesture(point(tester, 0, -0.73));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('C major'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('C major'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await gesture.moveTo(point(tester, 0.45, 0));
    await tester.pump();
    expect(find.text('C major'), findsNothing);
    expect(find.text('A harmonic minor'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'A harmonic minor'),
    );
    expect(row.selected, isTrue);
    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('releasing outside the rings cancels the selection', (
    tester,
  ) async {
    await pumpReport(tester);
    final gesture = await tester.startGesture(point(tester, 0, -0.73));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.moveTo(point(tester, 0, 0));
    await tester.pump();
    expect(find.text('Release to cancel'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Release to cancel'), findsNothing);
  });

  testWidgets('a canceled pointer clears the preview without opening a sheet', (
    tester,
  ) async {
    await pumpReport(tester);
    final gesture = await tester.startGesture(point(tester, 0, -0.73));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('C major'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a drag before holding still scrolls the report', (tester) async {
    await pumpReport(tester);
    final before = tester.getTopLeft(find.byType(KeyWheel));
    await tester.dragFrom(point(tester, 0, -0.73), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(KeyWheel)).dy, lessThan(before.dy));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('C major'), findsNothing);
  });

  testWidgets('tapping an expanded form collapses it and allows reopening', (
    tester,
  ) async {
    await pumpReport(tester);
    await tester.tapAt(point(tester, 0, -0.73));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'C major'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'C major'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'C natural minor'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'C major'))
          .selected,
      isFalse,
    );
  });

  testWidgets(
    'tempo hand icons are ordered left, right, together at phone width',
    (tester) async {
      await pumpReport(tester);
      await tester.tap(find.text('Tempo'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<HandsIcon>(find.byType(HandsIcon))
            .map((icon) => icon.hands),
        [
          HandConfiguration.left,
          HandConfiguration.right,
          HandConfiguration.together,
        ],
      );
      final selector = find.byType(SegmentedButton<HandConfiguration>);
      expect(
        tester
            .widget<SegmentedButton<HandConfiguration>>(selector)
            .showSelectedIcon,
        isFalse,
      );
      for (final hands in HandConfiguration.values) {
        await tester.tap(
          find.ancestor(
            of: find.byWidgetPredicate(
              (widget) => widget is HandsIcon && widget.hands == hands,
            ),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<SegmentedButton<HandConfiguration>>(selector).selected,
          {hands},
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
