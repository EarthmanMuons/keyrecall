import 'dart:async';

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

  group('when the presentation changes while a report is in flight', () {
    /// Pumps a gate over [presentation] whose owner does not answer until
    /// [answering] completes, recording what each report was about.
    Future<void> pumpGate(
      WidgetTester tester,
      Object presentation, {
      required Completer<bool> answering,
      required List<Object> asked,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExposureGate(
            presentation: presentation,
            onExposed: () {
              asked.add(presentation);
              return answering.isCompleted
                  ? Future.value(true)
                  : answering.future;
            },
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      ),
    );

    testWidgets('reports the one that replaced it, once the first is taken', (
      tester,
    ) async {
      final answering = Completer<bool>();
      final asked = <Object>[];

      await pumpGate(tester, 'first', answering: answering, asked: asked);
      expect(asked, ['first']);

      // The second arrives while the owner is still deciding about the first.
      await pumpGate(tester, 'second', answering: answering, asked: asked);
      answering.complete(true);
      await tester.pump(const Duration(seconds: 1));

      expect(
        asked,
        contains('second'),
        reason:
            'taking the first settles nothing about the second, which has '
            'not been reported at all',
      );
    });

    testWidgets('reports the replacement when the first was refused too', (
      tester,
    ) async {
      final answering = Completer<bool>();
      final asked = <Object>[];

      await pumpGate(tester, 'first', answering: answering, asked: asked);
      await pumpGate(tester, 'second', answering: answering, asked: asked);
      answering.complete(false);
      await tester.pump(const Duration(seconds: 1));

      expect(asked, contains('second'));
    });

    testWidgets('does not mark the replacement reported by the first', (
      tester,
    ) async {
      final answering = Completer<bool>();
      final asked = <Object>[];

      await pumpGate(tester, 'first', answering: answering, asked: asked);
      await pumpGate(tester, 'second', answering: answering, asked: asked);
      answering.complete(true);
      await tester.pump(const Duration(seconds: 1));

      expect(asked.where((one) => one == 'second'), hasLength(1));
    });
  });

  group('content clipped by the scroll it sits in', () {
    /// A viewport 100 tall at the top of the window, with the gate 300 into
    /// its content: well inside the window, and clipped out of the box it
    /// actually scrolls in.
    Future<ScrollController> pumpClipped(
      WidgetTester tester,
      List<int> asked,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 100,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      const SizedBox(width: 400, height: 300),
                      ExposureGate(
                        presentation: 'below the fold',
                        onExposed: () async {
                          asked.add(asked.length);
                          return true;
                        },
                        child: const SizedBox(width: 400, height: 50),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return scroll;
    }

    testWidgets('is not reported while it is clipped', (tester) async {
      final asked = <int>[];
      await pumpClipped(tester, asked);
      await tester.pump(const Duration(seconds: 1));

      expect(
        asked,
        isEmpty,
        reason:
            'it has real bounds inside the window and is painted in none of '
            'them, so reporting it claims a section nobody scrolled to',
      );
    });

    testWidgets('is reported once scrolling brings it into view', (
      tester,
    ) async {
      final asked = <int>[];
      final scroll = await pumpClipped(tester, asked);
      await tester.pump(const Duration(seconds: 1));
      expect(asked, isEmpty);

      scroll.jumpTo(300);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(asked, hasLength(1));
    });
  });

  group('when the report itself fails', () {
    Future<List<int>> pumpThrowing(
      WidgetTester tester, {
      required bool synchronously,
    }) async {
      final asked = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExposureGate(
              presentation: 'one presentation',
              onExposed: () {
                asked.add(asked.length);
                if (synchronously) throw StateError('no store');
                return Future<bool>.error(StateError('no store'));
              },
              child: const SizedBox(width: 200, height: 200),
            ),
          ),
        ),
      );
      return asked;
    }

    for (final (name, synchronously) in [
      ('a failed future', false),
      ('a callback that throws before returning one', true),
    ]) {
      testWidgets('$name is a refusal, and is asked again', (tester) async {
        final asked = await pumpThrowing(tester, synchronously: synchronously);

        final askedAtFirst = asked.length;
        expect(askedAtFirst, greaterThan(0));
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a failed report must not escape into the frame that asked '
              'for it',
        );
        await tester.pump(const Duration(seconds: 1));
        expect(asked.length, greaterThan(askedAtFirst));
      });
    }
  });
}
