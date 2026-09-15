import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

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
}
