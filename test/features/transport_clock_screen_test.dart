import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/transport_clock_trace.dart';

import '../support/silent_midi_transport.dart';

void main() {
  Future<Rect> pumpScreen(WidgetTester tester, Size physicalSize) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [silentMidiTransport],
        child: const MaterialApp(home: TransportClockScreen()),
      ),
    );
    await tester.pump();

    final list =
        find.byType(ListView).evaluate().single.renderObject! as RenderBox;
    return list.localToGlobal(Offset.zero) & list.size;
  }

  Rect rectOf(WidgetTester tester, Finder finder) {
    final box = finder.evaluate().single.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // The take protocols were six paragraphs in six radio tiles, which made the
  // picker 1148 logical pixels tall on a 788 pixel viewport and put every
  // control, including the one that starts a take, below the fold. Somebody
  // holding a phone at an instrument has to be able to see the button.
  for (final (label, physicalSize) in [
    ('a small phone', const Size(750, 1334)),
    ('a large phone', const Size(1170, 2532)),
  ]) {
    testWidgets('the controls are on screen without scrolling on $label', (
      tester,
    ) async {
      final viewport = await pumpScreen(tester, physicalSize);

      for (final control in ['Start take', 'Discard']) {
        final rect = rectOf(tester, find.text(control));
        expect(
          rect.bottom,
          lessThanOrEqualTo(viewport.bottom),
          reason: '$control is below the fold on $label',
        );
      }
    });
  }

  testWidgets('the protocol shown is the one for the chosen take', (
    tester,
  ) async {
    await pumpScreen(tester, const Size(750, 1334));

    expect(find.text(TransportTake.pulse.protocol), findsOneWidget);
    expect(find.text(TransportTake.chords.protocol), findsNothing);

    await tester.tap(find.byType(DropdownButton<TransportTake>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TransportTake.chords.label).last);
    await tester.pumpAndSettle();

    expect(find.text(TransportTake.chords.protocol), findsOneWidget);
  });

  // Which take this is belongs to the file, so it cannot change halfway.
  testWidgets('a running take locks what it is labeled as', (tester) async {
    await pumpScreen(tester, const Size(750, 1334));

    await tester.tap(find.text('Start take'));
    await tester.pump();

    expect(find.text('Stop'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<TransportTake>>(
            find.byType(DropdownButton<TransportTake>),
          )
          .onChanged,
      isNull,
      reason: 'a disabled dropdown is what locks it',
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });
}
