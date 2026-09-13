import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is built on `material_ui`, which is a Material implementation of
/// its own rather than a layer over Flutter's.
///
/// A screen written against `package:flutter/material.dart` still compiles,
/// because both libraries define the same widget names. It just cannot find
/// the app's theme or an ancestor to paint on, so it reaches a device drawing
/// gray boxes where its controls should be. That is a whole class of failure
/// nothing else here catches: it looks like a layout bug, it survives a widget
/// test pumped under a bare `MaterialApp`, and it is invisible in review.
void main() {
  test('no app source imports Flutter Material instead of material_ui', () {
    final offenders = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          if (entity.readAsStringSync().contains(
            "import 'package:flutter/material.dart'",
          ))
            entity.path,
    ]..sort();

    expect(
      offenders,
      isEmpty,
      reason:
          'import package:material_ui/material_ui.dart instead, or these '
          'widgets will not find the app they are running in',
    );
  });
}
