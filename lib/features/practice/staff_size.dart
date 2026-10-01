import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The shortest side, in logical pixels, from which a screen is a tablet's.
const double _tabletShortestSide = 600;

const double _millimetersPerInch = 25.4;

/// Logical pixels to the millimeter on a screen of [size] on [platform].
///
/// Flutter reports no physical density, and iOS has none to report, so this
/// goes by device class: an iPhone point is about 1/153 inch, an iPad point
/// about 1/132, and an Android dp nominally 1/160. An iPad mini's points are
/// smaller than other iPads', so a size drawn there runs about a fifth small.
double logicalPixelsPerMillimeter(TargetPlatform platform, Size size) {
  final perInch = switch (platform) {
    TargetPlatform.iOS when size.shortestSide >= _tabletShortestSide => 132.0,
    TargetPlatform.iOS => 153.0,
    _ => 160.0,
  };
  return perInch / _millimetersPerInch;
}

/// The staff space, in logical pixels, of a five-line staff [millimeters]
/// tall.
double staffSpaceOf(
  double millimeters, {
  required double pixelsPerMillimeter,
}) => millimeters * pixelsPerMillimeter / 4;
