import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/presentation_exposure.dart';

void main() {
  ExposureConditions conditions({
    bool mounted = true,
    bool routeCurrent = true,
    bool foreground = true,
    bool onScreen = true,
  }) => ExposureConditions(
    isMounted: mounted,
    isRouteCurrent: routeCurrent,
    isForeground: foreground,
    isOnScreen: onScreen,
  );

  group('what counts as having reached the learner', () {
    test('everything out of the way', () {
      expect(conditions().isExposed, isTrue);
    });

    test('a mounted widget is not on its own an exposure', () {
      expect(conditions(routeCurrent: false).isExposed, isFalse);
      expect(conditions(foreground: false).isExposed, isFalse);
      expect(conditions(onScreen: false).isExposed, isFalse);
      expect(conditions(mounted: false).isExposed, isFalse);
    });
  });

  group('whether content is inside the viewport', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 800);

    test('content on screen is', () {
      expect(
        isWithinViewport(const Rect.fromLTWH(0, 100, 400, 60), viewport),
        isTrue,
      );
    });

    test('content partly scrolled in is', () {
      expect(
        isWithinViewport(const Rect.fromLTWH(0, 760, 400, 200), viewport),
        isTrue,
        reason: 'it could have been seen, which is all this decides',
      );
    });

    test('content below the fold is not', () {
      expect(
        isWithinViewport(const Rect.fromLTWH(0, 900, 400, 60), viewport),
        isFalse,
      );
    });

    test('a sheet still below the screen is not', () {
      expect(
        isWithinViewport(const Rect.fromLTWH(0, 800, 400, 400), viewport),
        isFalse,
      );
    });

    test('something laid out to nothing is not', () {
      expect(
        isWithinViewport(const Rect.fromLTWH(0, 100, 400, 0), viewport),
        isFalse,
      );
    });
  });

  group('when the owner refuses the report', () {
    /// Pumps a visible gate whose owner answers [accepts], and returns how
    /// many times it has been asked.
    Future<List<int>> pumpGate(
      WidgetTester tester, {
      required bool accepts,
    }) async {
      final asked = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExposureGate(
              presentation: 'one presentation',
              onExposed: () async {
                asked.add(asked.length);
                return accepts;
              },
              child: const SizedBox(width: 200, height: 200),
            ),
          ),
        ),
      );
      return asked;
    }

    testWidgets('asks again with nothing else on screen moving', (
      tester,
    ) async {
      final asked = await pumpGate(tester, accepts: false);

      expect(asked, hasLength(1));
      // No scroll, no route change, no lifecycle change, and nothing asking
      // for a frame. A settled screen produces no frames at all, so a gate
      // that waited for the next one would wait for activity that never comes.
      await tester.pump(const Duration(seconds: 1));
      final askedAgain = asked.length;
      expect(askedAgain, greaterThan(1));

      await tester.pump(const Duration(minutes: 1));
      expect(
        asked.length,
        greaterThan(askedAgain),
        reason: 'a refusal is still an exposure nobody has recorded',
      );
    });

    testWidgets('waits longer after each refusal', (tester) async {
      final asked = await pumpGate(tester, accepts: false);
      for (var second = 0; second < 8; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(
        asked.length,
        lessThan(8),
        reason:
            'a write that is not going to succeed must not be retried at '
            'speed for as long as the screen is up',
      );
      expect(asked.length, greaterThan(2));
    });

    testWidgets('stops once the owner takes it', (tester) async {
      final asked = await pumpGate(tester, accepts: true);

      expect(asked, hasLength(1));
      await tester.pump(const Duration(seconds: 30));
      expect(asked, hasLength(1));
    });
  });
}
