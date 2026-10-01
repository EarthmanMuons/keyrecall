import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/staff_size.dart';

void main() {
  const iPhone = Size(402, 874);
  const iPad = Size(820, 1180);

  test('an iPad point is larger than an iPhone point', () {
    expect(
      logicalPixelsPerMillimeter(TargetPlatform.iOS, iPad),
      lessThan(logicalPixelsPerMillimeter(TargetPlatform.iOS, iPhone)),
    );
  });

  test('an iPad on its side is still an iPad', () {
    expect(
      logicalPixelsPerMillimeter(TargetPlatform.iOS, iPad.flipped),
      logicalPixelsPerMillimeter(TargetPlatform.iOS, iPad),
    );
  });

  test('a 7 mm staff on an iPhone is about 10.5 points a space', () {
    final space = staffSpaceOf(
      7,
      pixelsPerMillimeter: logicalPixelsPerMillimeter(
        TargetPlatform.iOS,
        iPhone,
      ),
    );

    expect(space, closeTo(10.5, 0.1));
  });

  test('an Android dp is a 160th of an inch', () {
    expect(
      logicalPixelsPerMillimeter(TargetPlatform.android, iPad),
      closeTo(160 / 25.4, 1e-9),
    );
  });
}
